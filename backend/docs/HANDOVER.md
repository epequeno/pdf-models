# PDF Models - Project Handover

**Date**: January 2, 2026
**Status**: Infrastructure deployed, authentication working with HTTP API v2

## Current State

### ✅ What's Working

1. **Core Infrastructure** (CoreInfrastructureStack)
   - S3 bucket for document storage
   - DynamoDB table for job tracking
   - Cognito User Pool for authentication
   - ✅ **Cognito Identity Pool removed** - simplified to JWT-only auth

2. **CI/CD** (CiCdStack)
   - CodeCommit repository
   - CodeBuild for Rust Lambda functions
   - Automated build pipeline

3. **Marker Processing** (MarkerStack)
   - ECS Fargate tasks for PDF processing
   - Step Functions orchestration
   - Full end-to-end processing pipeline

4. **API v2** (ApiV2Stack) - **RECOMMENDED**
   - HTTP API Gateway (v2) with Cognito JWT authorizer
   - ✅ **Authentication working** - passed JWT validation
   - Lambda functions support both REST and HTTP API formats
   - Pre-signed URLs for S3 uploads/downloads
   - Endpoint: `https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/`

5. **API v1** (ApiStack) - Legacy REST API
   - ⚠️ Has persistent authentication issues
   - Should be deprecated in favor of ApiV2Stack

### ⚠️ Current Issue

**Lambda Code Not Updated**: The Lambda functions in ApiV2Stack are running old code because:
- Local changes to support HTTP API v2 format haven't been committed to CodeCommit
- CodeBuild pulls from CodeCommit, not local files
- Need to commit + push to trigger proper rebuild

**Files with uncommitted changes**:
- `backend/lambdas/submit-job/src/main.rs` - Added HTTP API v2 support
- `backend/lambdas/get-job/src/main.rs` - Added HTTP API v2 support
- `backend/backend/api_v2_stack.py` - New HTTP API stack
- `backend/app.py` - Added ApiV2Stack
- `backend/backend/core_infrastructure_stack.py` - Removed Identity Pool
- Other CDK and buildspec updates

## Architecture Changes Made

### Before: Complex Dual-Auth System
```
User → Cognito User Pool (JWT) → Identity Pool → AWS Credentials → S3
                                              ↘ API Gateway (confused!)
```
**Problem**: API Gateway couldn't decide between JWT and AWS SigV4 auth

### After: Simplified JWT + Pre-signed URLs
```
User → Cognito User Pool (JWT) → HTTP API v2 → Lambda → Pre-signed S3 URLs
```
**Benefits**:
- Single authentication mechanism (JWT only)
- HTTP API v2 has better Cognito integration
- Lambda controls S3 access via pre-signed URLs
- No AWS credential confusion

## How to Complete the Fix

### Step 1: Commit Changes to CodeCommit

```bash
# Check what needs to be committed
git status

# Add all changes
git add .

# Commit with descriptive message
git commit -m "Fix auth: Migrate to HTTP API v2 with pre-signed URLs

- Remove Cognito Identity Pool (eliminates JWT/SigV4 confusion)
- Add ApiV2Stack with HTTP API Gateway
- Update Lambda functions to support both REST and HTTP API formats
- Implement S3 pre-signed URLs for uploads/downloads
- Update buildspec to auto-upload Lambda artifacts to S3"

# Push to CodeCommit
git push
```

### Step 2: Rebuild Lambda Functions

```bash
# Trigger CodeBuild (it will now use updated code from CodeCommit)
AWS_PROFILE=arch aws codebuild start-build \
  --project-name pdf-models-rust-lambda-build

# Wait for build to complete (or check CloudWatch logs)
# The post_build phase will automatically upload to S3
```

### Step 3: Deploy Updated Lambdas

```bash
# The Lambda artifacts are now in S3, redeploy the stack
AWS_PROFILE=arch make cdk-deploy STACK=ApiV2Stack
```

### Step 4: Test End-to-End

```bash
# Get JWT token
TOKEN=$(AWS_PROFILE=arch aws cognito-idp initiate-auth \
  --client-id 4tmf8s58738hrbrp4ff2utqg5 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=integration-test@pdf-models.local,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.AccessToken' --output text)

# Test API
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/v1/models/marker/jobs

# Expected response:
# {
#   "job_id": "uuid",
#   "model": "marker",
#   "status": "created",
#   "s3_input_key": "user-id/job-id.pdf",
#   "upload_url": "https://s3...presigned-url",
#   "created_at": "timestamp"
# }
```

## API Usage

### Submit Job (Returns Upload URL)

```bash
POST /v1/models/marker/jobs
Authorization: Bearer {JWT_TOKEN}

Response:
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "model": "marker",
  "status": "created",
  "s3_input_key": "74f87488-6071-7034-6f34-e23c3bca23fa/550e8400-e29b-41d4-a716-446655440000.pdf",
  "upload_url": "https://pdf-models-docs-496830984285.s3.amazonaws.com/...",
  "created_at": "2026-01-02T05:00:00Z"
}
```

### Upload PDF to S3

```bash
# Use the upload_url from above
curl -X PUT \
  -H "Content-Type: application/pdf" \
  --data-binary @your-file.pdf \
  "{upload_url}"
```

### Start Processing

```bash
POST /v1/models/marker/jobs
Authorization: Bearer {JWT_TOKEN}
Content-Type: application/json

{
  "start_processing": true
}
```

### Check Job Status

```bash
GET /v1/models/marker/jobs/{job_id}
Authorization: Bearer {JWT_TOKEN}

Response (when complete):
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "download_url": "https://pdf-models-docs-496830984285.s3.amazonaws.com/...",
  ...
}
```

## Deployed Resources

### Stacks
- ✅ FoundationStack - ECR repositories
- ✅ CoreInfrastructureStack - S3, DynamoDB, Cognito (Identity Pool removed)
- ✅ CiCdStack - CodeCommit, CodeBuild
- ✅ MarkerStack - ECS, Step Functions
- ⚠️ ApiStack - Legacy REST API (has auth issues)
- ✅ ApiV2Stack - HTTP API (recommended)
- ⏸ MonitoringStack - Not yet deployed

### Key Parameters (SSM)
- `/pdf-models/core/s3-bucket-name` - Document storage
- `/pdf-models/core/dynamodb-table-name` - Job tracking
- `/pdf-models/core/cognito-user-pool-id` - Authentication
- `/pdf-models/api-v2/endpoint` - HTTP API endpoint
- `/pdf-models/marker/state-machine-arn` - Processing workflow

## Next Steps

### Immediate (Required to Fix Auth)
1. ✅ Commit all changes to CodeCommit
2. ✅ Rebuild Lambda functions via CodeBuild
3. ✅ Test authentication end-to-end

### Short-term (1-2 weeks)
1. **Deprecate ApiStack** - Remove REST API once HTTP API is validated
2. **Deploy MonitoringStack** - CloudWatch dashboards and alarms
3. **Add input validation** - File size limits, PDF validation
4. **Implement job cancellation** - DELETE endpoint
5. **Add structured logging** - JSON logs with correlation IDs

### Medium-term (1-2 months)
1. **Frontend Development** - Elm UI (scaffolded in `frontend/`)
2. **User tiers** - Implement Lambda Authorizer for admin/free/paid groups
3. **Webhook notifications** - Job completion callbacks
4. **Rate limiting** - Per-user quotas
5. **Multi-region deployment** - For better latency

## Known Issues

### 1. REST API Authorization Failure
**Symptom**: `Invalid key=value pair (missing equal-sign) in Authorization header`

**Root Cause**: API Gateway REST API has fundamental incompatibility with our Cognito setup. Even after complete recreation, the error persists.

**Solution**: Use HTTP API v2 (ApiV2Stack) instead. REST API should be deprecated.

### 2. Lambda Artifacts Not Auto-Updating
**Symptom**: Lambda code doesn't update when buildspec changes locally

**Root Cause**: CodeBuild pulls from CodeCommit, not local files

**Solution**: Always commit and push before rebuilding

### 3. Pre-signed URL Expiration
**Symptom**: Upload URLs expire after 15 minutes, download URLs after 1 hour

**Solution**: This is intentional for security. Frontend should request fresh URLs if expired.

## Important Notes

- **AWS Profile**: All commands require `AWS_PROFILE=arch` (Makefile handles this automatically)
- **CodeCommit**: Source of truth for CodeBuild - local changes must be committed
- **User Pool Client**: ID is `4tmf8s58738hrbrp4ff2utqg5`
- **Test User**: `integration-test@pdf-models.local` (password in secure storage)

## Questions for Next Developer

1. **Do you want to keep ApiStack (REST API)?**
   - Recommend: Delete it once ApiV2Stack is fully validated

2. **User tier implementation?**
   - Need: Lambda Authorizer with custom claims for admin/free/paid

3. **Frontend priority?**
   - Elm scaffolding exists in `frontend/` but not implemented

4. **Multi-model support?**
   - Architecture supports it, just need to add new MarkerStack-like stacks

## Support Resources

- **Architecture**: [architecture.md](architecture.md)
- **Next Steps**: [NEXT_STEPS.md](NEXT_STEPS.md)
- **Makefile**: `make help` for all available commands
- **CloudWatch Logs**: `/aws/lambda/pdf-models-submit-job-v2`

---

**Summary**: Infrastructure is solid, authentication works with HTTP API v2, just need to commit code changes and rebuild to complete the fix. The simplified architecture (JWT + pre-signed URLs) eliminates the previous auth confusion.
