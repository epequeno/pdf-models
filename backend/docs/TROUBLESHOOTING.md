# Troubleshooting Guide

This document contains solutions to common issues encountered during development and deployment of the pdf-models system.

## Table of Contents

- [Lambda Build Issues](#lambda-build-issues)
- [API Gateway & Authentication](#api-gateway--authentication)
- [Integration Testing](#integration-testing)
- [S3 Access Control](#s3-access-control)
- [Step Functions & Job Processing](#step-functions--job-processing)
- [General AWS Issues](#general-aws-issues)

## Lambda Build Issues

### CodeBuild Fails with "jq: command not found"

**Symptom**: CodeBuild fails during POST_BUILD phase with `exit status 127` and `jq: command not found`.

**Root Cause**: The buildspec was trying to parse JSON using `jq` which isn't available in the CodeBuild environment.

**Solution**: Use Python's built-in JSON parsing instead:
```yaml
# ❌ WRONG - jq not available
- SUBMIT_JOB_VERSION=$(echo $SUBMIT_JOB_UPLOAD | jq -r '.VersionId')

# ✅ CORRECT - use Python
- SUBMIT_JOB_VERSION=$(echo "$SUBMIT_JOB_UPLOAD" | python3 -c "import sys, json; print(json.load(sys.stdin)['VersionId'])")
```

### CodeBuild Fails with "AccessDeniedException" for SSM

**Symptom**: CodeBuild fails when trying to write SSM parameters with `AccessDeniedException`.

**Root Cause**: The CodeBuild role doesn't have `ssm:PutParameter` permissions.

**Solution**: Make SSM parameter updates non-fatal:
```yaml
- aws ssm put-parameter --name /pdf-models/lambda/submit-job-version --value ${VERSION} --type String --overwrite || echo "Warning Could not update SSM parameter"
```

### Lambda Deployment Fails with "Invalid version id specified"

**Symptom**: CDK deployment fails with S3 error about invalid version ID.

**Root Cause**: SSM parameters contain timestamps instead of actual S3 version IDs.

**Solution**: 
1. Get actual S3 version IDs:
   ```bash
   aws s3api list-object-versions --bucket BUCKET --prefix lambda-artifacts/submit-job.zip --query 'Versions[0].VersionId' --output text
   ```
2. Update SSM parameters with real version IDs:
   ```bash
   aws ssm put-parameter --name /pdf-models/lambda/submit-job-version --value ACTUAL_VERSION_ID --type String --overwrite
   ```

### YAML Syntax Errors in buildspec.yml

**Symptom**: CodeBuild fails immediately with "YAML_FILE_ERROR" and mentions unexpected subkeys.

**Root Cause**: YAML syntax issues, often caused by special characters in strings.

**Solution**: 
- Avoid colons in echo messages: `echo "Warning Could not update"` instead of `echo "Warning: Could not update"`
- Validate YAML syntax locally before committing
- Use simple strings without special characters in command outputs

## API Gateway & Authentication

### 403 Forbidden Errors from API

**Symptom**: API returns 403 even with valid JWT tokens.

**Root Cause**: Usually one of:
1. Cognito User ID vs Identity Pool ID mismatch
2. Lambda validation logic too strict
3. JWT token format issues

**Debugging Steps**:
1. Decode JWT token to check claims:
   ```python
   import base64, json
   parts = token.split('.')
   payload = json.loads(base64.b64decode(parts[1] + '==').decode())
   print("User ID (sub):", payload['sub'])
   ```

2. Check Lambda logs:
   ```bash
   AWS_PROFILE=arch aws logs tail /aws/lambda/pdf-models-submit-job-v2 --follow
   ```

3. Verify API Gateway authorizer configuration in CDK

**Solution**: Ensure Lambda validation logic matches the authentication flow. For Identity Pool workflow, don't validate S3 key prefixes in Lambda - let S3 IAM permissions handle access control.

### JWT Token Expiration

**Symptom**: API works initially but starts returning 401/403 after an hour.

**Root Cause**: Cognito access tokens expire after 1 hour by default.

**Solution**: Implement token refresh logic using the refresh token:
```python
response = cognito_client.initiate_auth(
    ClientId=client_id,
    AuthFlow='REFRESH_TOKEN_AUTH',
    AuthParameters={'REFRESH_TOKEN': refresh_token}
)
```

## Integration Testing

### Tests Fail with "TEST_USER_EMAIL environment variable not set"

**Symptom**: Integration tests skip with missing environment variable message.

**Solution**: Use the automated test setup:
```bash
make test-integration-auto  # Creates user and runs tests automatically
```

Or set environment variables manually:
```bash
export TEST_USER_EMAIL="integration-test@pdf-models.local"
export TEST_USER_PASSWORD="TestPass123!"
make test-integration
```

### Tests Timeout Waiting for Job Completion

**Symptom**: Tests fail with `TimeoutError: Job did not complete within 600 seconds`.

**Root Cause**: 
1. Job not started (missing `start_processing: true`)
2. Step Functions execution failed
3. ECS task failed to start or process the file

**Debugging Steps**:
1. Check if job status progresses from "created" to "processing":
   ```python
   job_response = api_client.submit_job(model, s3_key, start_processing=True)
   print("Initial status:", job_response['status'])  # Should be "processing"
   ```

2. Check Step Functions execution:
   ```bash
   AWS_PROFILE=arch aws stepfunctions list-executions --state-machine-arn STATE_MACHINE_ARN
   ```

3. Check ECS task logs:
   ```bash
   AWS_PROFILE=arch aws logs tail /aws/ecs/pdf-models-marker --follow
   ```

### S3 Access Denied During Tests

**Symptom**: Tests fail when trying to upload files to S3.

**Root Cause**: Identity Pool credentials don't have access to the expected S3 prefix.

**Solution**: Verify the S3 key format matches the Identity Pool ID:
```python
# ✅ CORRECT - use Identity Pool ID as prefix
s3_key = f"{identity_id}/{job_id}.pdf"

# ❌ WRONG - using Cognito User ID
s3_key = f"{cognito_user_id}/{job_id}.pdf"
```

## S3 Access Control

### Users Can Access Files Outside Their Prefix

**Symptom**: Security concern - users might access other users' files.

**Root Cause**: Lambda removed S3 key validation, relying only on S3 IAM permissions.

**Verification**: Check Identity Pool IAM role policy:
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::bucket-name/${cognito-identity.amazonaws.com:sub}/*"
}
```

This policy ensures users can only access files with their Identity Pool ID as prefix.

### Cognito User ID vs Identity Pool ID Confusion

**Key Insight**: These are different identifiers:
- **Cognito User ID** (`sub` claim in JWT): Used for API authentication
- **Identity Pool ID**: Used for S3 access permissions

**Best Practice**: Use Identity Pool ID for S3 key prefixes since that's what controls S3 access.

## Step Functions & Job Processing

### Jobs Stuck in "created" Status

**Symptom**: Jobs are created but never start processing.

**Root Cause**: Lambda not starting Step Functions execution.

**Solution**: Ensure `start_processing: true` in job submission:
```json
{
  "s3_input_key": "identity-id/job-id.pdf",
  "start_processing": true
}
```

### Container Permission Issues - Marker Font Downloads

**Symptom**: Jobs fail with `PermissionError: [Errno 13] Permission denied: '/usr/local/lib/python3.11/site-packages/static'`

**Root Cause**: The marker-pdf library's `download_font()` function doesn't respect the `MARKER_DATA_DIR` environment variable and tries to write to read-only package directories (`/usr/local/lib/python3.11/site-packages/static`) even when environment variables are set.

**Solution**: Monkey-patch the `download_font()` function to catch permission errors gracefully:

```python
# Import marker settings and configure paths before importing other marker modules
from marker import settings
settings.FONT_PATH = '/app/marker_data/static/GoNotoCurrent.ttf'
settings.MARKER_DATA_DIR = '/app/marker_data'

# Monkey-patch the download_font function to prevent permission errors
import marker.util
_original_download_font = marker.util.download_font

def patched_download_font():
    """Patched version that uses writable directory."""
    import os
    font_path = '/app/marker_data/static/GoNotoCurrent.ttf'
    font_dir = os.path.dirname(font_path)

    # Create directory if it doesn't exist
    os.makedirs(font_dir, exist_ok=True)

    # Download if not exists
    if not os.path.exists(font_path):
        try:
            # Try to download from the marker package's expected location
            _original_download_font()
        except (PermissionError, OSError):
            # If that fails due to permissions, skip - font might be pre-downloaded
            # or we'll handle the error gracefully
            pass

# Replace the function
marker.util.download_font = patched_download_font

# Now safe to import marker components
from marker.converters.pdf import PdfConverter
```

Also ensure the Dockerfile creates writable directories:
```dockerfile
# Create writable directories for marker data
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

# Set environment variables to redirect marker data to writable locations
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static
```

**Why environment variables alone don't work**: The marker library reads `settings.FONT_PATH` at import time and hardcodes the directory path. Setting `MARKER_DATA_DIR` after the module loads doesn't affect the font download logic. The monkey-patch ensures permission errors are caught and handled gracefully.

### ECS Task Definition Updates Not Propagating

**Symptom**: New container images built successfully but ECS tasks still use old images.

**Root Cause**: ECS caches container images and Step Functions references specific task definition revisions.

**Solution**: 
1. Create new task definition revision:
   ```bash
   make aws-ecs-force-new-deployment
   ```

2. Update SSM parameter with new revision:
   ```bash
   AWS_PROFILE=arch aws ssm put-parameter --name "/pdf-models/marker/task-definition-arn" \
     --value "arn:aws:ecs:us-east-1:ACCOUNT:task-definition/pdf-models-marker:NEW_REVISION" \
     --type String --overwrite
   ```

3. Force CDK to detect changes and redeploy:
   ```bash
   # Modify MarkerStack (add comment or change description)
   make cdk-deploy STACK=MarkerStack
   ```

### Step Functions SUCCEEDED but Job Marked as Failed

**Symptom**: Step Functions execution shows SUCCEEDED status but DynamoDB job record shows failed status.

**Root Cause**: The ECS task completes (exits) but with a non-zero exit code due to application errors. Step Functions considers the task "completed" even if it failed.

**Debugging Steps**:
1. Check ECS task logs for the specific job:
   ```bash
   AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 30m --format short
   ```

2. Check Step Functions execution details:
   ```bash
   AWS_PROFILE=arch aws stepfunctions describe-execution \
     --execution-arn arn:aws:states:us-east-1:ACCOUNT:execution:pdf-models-marker:JOB_ID
   ```

3. Verify task exit codes in the execution history

**Solution**: Review the Step Functions error handling logic to properly catch and handle ECS task failures.

## General AWS Issues

### "Unable to locate credentials" Errors

**Symptom**: AWS CLI commands fail with credential errors.

**Root Cause**: Missing `AWS_PROFILE=arch` prefix.

**Solution**: Always use the Makefile or add the prefix:
```bash
# ✅ CORRECT
AWS_PROFILE=arch aws s3 ls
make aws-s3-ls

# ❌ WRONG
aws s3 ls
```

### CDK Commands Fail with "cdk: command not found"

**Symptom**: CDK commands fail even though CDK is installed.

**Root Cause**: Not using `uv run` to access the virtual environment.

**Solution**: Use the Makefile or `uv run`:
```bash
# ✅ CORRECT
make cdk-synth
uv run cdk synth

# ❌ WRONG
cdk synth
```

### Stack Deployment Fails with Missing Parameters

**Symptom**: CDK deployment fails with "Unable to fetch parameters from parameter store".

**Root Cause**: SSM parameters don't exist or have wrong values.

**Solution**: 
1. Check if parameters exist:
   ```bash
   AWS_PROFILE=arch aws ssm get-parameter --name /pdf-models/lambda/submit-job-version
   ```

2. Create missing parameters:
   ```bash
   AWS_PROFILE=arch aws ssm put-parameter --name PARAM_NAME --value VALUE --type String
   ```

## Best Practices for Debugging

1. **Always check logs first**: Lambda, Step Functions, and ECS all have CloudWatch logs
2. **Use AWS_PAGER=""**: Prevents CLI commands from getting stuck waiting for input
3. **Test incrementally**: Use small test scripts to isolate issues
4. **Verify IAM permissions**: Many issues are permission-related
5. **Check SSM parameters**: Stacks communicate via SSM, ensure values are correct
6. **Follow the data flow**: Request → API Gateway → Lambda → Step Functions → ECS → S3

## Getting Help

- **Architecture details**: See [architecture.md](architecture.md)
- **Agent requirements**: See [../AGENTS.md](../AGENTS.md)
- **Available commands**: Run `make help`
- **AWS logs**: Use `make aws-logs LOGGROUP=/aws/lambda/function-name`