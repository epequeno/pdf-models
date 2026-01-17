# AI Agent Guide

This document contains **critical requirements** for AI agents working on this project. Failure to follow these will result in errors or operations against the wrong AWS account.

## 🚨 Critical Requirements

### 1. AWS Profile Requirement

**ALL AWS and CDK commands MUST be prefixed with `AWS_PROFILE=arch`**

This sets the correct AWS credentials, account, and region automatically.

❌ **WRONG**:
```bash
cdk deploy FoundationStack
aws s3 ls
aws logs tail /aws/lambda/my-function
```

✅ **CORRECT**:
```bash
AWS_PROFILE=arch cdk deploy FoundationStack
AWS_PROFILE=arch aws s3 ls
AWS_PROFILE=arch aws logs tail /aws/lambda/my-function
```

**Why**: Without this prefix, commands will fail or operate against the wrong AWS account, potentially causing serious issues.

**Better approach**: Use the provided Makefile which automatically includes the AWS_PROFILE prefix.

### 2. Python/CDK Commands Must Use uv

This project uses `uv` for Python dependency management. Running bare `python` or `cdk` commands will fail because they won't use the correct virtual environment.

❌ **WRONG**:
```bash
python -m pytest
cdk synth
pip install boto3
```

✅ **CORRECT**:
```bash
uv run python -m pytest
uv run cdk synth
uv add boto3
```

**Why**: `uv` manages the virtual environment and dependencies. Bare commands won't have access to installed packages.

**Better approach**: Use the provided Makefile which automatically uses `uv run` for all commands.

## Recommended Workflow: Use the Makefile

To avoid manually prefixing commands, use the Makefile:

```bash
# Pipeline (primary deployment method)
make pipeline-start        # Deploy all stacks (runs tests first)
make pipeline-status       # Check current pipeline status
make pipeline-executions   # List recent executions

# CDK operations (for local dev/recovery only)
make cdk-synth
make cdk-diff STACK=FoundationStack
make cdk-deploy STACK=FoundationStack

# AWS operations
make aws-logs LOGGROUP=/aws/lambda/my-function
make aws-s3-ls

# Container operations
make container-build MODEL=marker
```

See `Makefile` for all available commands.

## Deployment Workflow

The CDK Pipeline is the **primary deployment method**. It does NOT auto-trigger on push.

**Standard workflow:**
1. Make changes locally
2. `git add . && git commit -m "message"`
3. `git push`
4. `make pipeline-start` (when ready to deploy)

The pipeline will:
1. Pull latest code from CodeCommit
2. Build the frontend
3. Run `cdk synth`
4. Run unit tests
5. Deploy all stacks in correct order

**When to use manual `make cdk-deploy`:**
- Deploying PipelineStack itself (bootstrap/updates)
- Quick iteration during development
- Recovery scenarios

## Project-Specific Patterns

### Stack Communication
- Stacks communicate via **SSM Parameter Store** (not CloudFormation exports)
- Never use `Fn::ImportValue` or CloudFormation exports
- Always write to SSM and read from SSM for cross-stack references

**Example**:
```python
# Writing (in CoreInfrastructureStack)
ssm.StringParameter(self, "S3BucketParam",
    parameter_name="/pdf-models/core/s3-bucket-name",
    string_value=bucket.bucket_name
)

# Reading (in MarkerStack)
bucket_name = ssm.StringParameter.value_from_lookup(
    self, "/pdf-models/core/s3-bucket-name"
)
```

### No Local AWS Operations
- All container builds happen in CodeBuild (not locally)
- All deployments go through the pipeline (`make pipeline-start`)
- Local development is for code editing and CDK synthesis only
- Exception: `make cdk-deploy STACK=PipelineStack` for pipeline updates

### 🚨 CodeCommit is Source of Truth for Lambda Builds

**CRITICAL**: CodeBuild pulls Lambda code from CodeCommit, NOT from local files.

If you modify Lambda code locally (in `backend/lambdas/`), the changes will NOT be deployed until you:
1. Commit the changes: `git add . && git commit -m "message"`
2. Push to CodeCommit: `git push`
3. Trigger rebuild: `AWS_PROFILE=arch aws codebuild start-build --project-name pdf-models-rust-lambda-build`
4. Redeploy the stack: `make cdk-deploy STACK=ApiV2Stack`

**Why this matters**: Local file changes are invisible to CodeBuild. You can rebuild 100 times locally, but Lambda will continue using old code until you push to CodeCommit.

**Common mistake**: Editing Lambda Rust code, running `make lambda-build` or CodeBuild manually, expecting Lambda to update - it won't update because CodeBuild is building from the old CodeCommit code, not your local edits.

### Identity Pool vs Cognito User ID

**CRITICAL DISTINCTION**: The system uses two different user identifiers:

- **Cognito User ID** (`sub` claim in JWT): Used for API authentication
- **Identity Pool ID**: Used for S3 access permissions (format: `us-east-1:uuid`)

**Key Insight**: S3 access is controlled by Identity Pool ID, not Cognito User ID. Users can only access S3 objects with their Identity Pool ID as the prefix due to IAM policies.

**Architecture Decision**: Lambda functions do NOT validate S3 key prefixes - this is handled by S3 IAM permissions. This prevents the mismatch between Cognito User ID and Identity Pool ID from causing issues.

### Integration Testing Workflow

The system uses an **Identity Pool workflow** where:
1. Users authenticate with Cognito to get JWT tokens
2. Users exchange JWT for Identity Pool credentials
3. Users upload files directly to S3 using Identity Pool credentials
4. Users submit jobs via API referencing the S3 keys
5. Lambda starts Step Functions execution for processing

**Test user credentials**:
- Email: `integration-test@pdf-models.local`
- Password: `TestPass123!`

**Running tests**:
- Local: `make test-integration-auto`
- Cloud (CodeBuild): `make test-integration-cloud` - runs in AWS, can close laptop
- Cloud for specific model: `make test-integration-cloud MODEL=marker`
- Check cloud test status: `make test-cloud-status`

### Step Functions Use JSONata
- Set `"QueryLanguage": "JSONata"` in all state machines
- Prefer JSONata over JSONPath for better readability

### Lambda Functions in Rust
- Lambda functions are written in rust, NOT python
- Avoid Python Lambda to prevent dependency conflicts with CDK
- Keep Lambda handlers thin - just orchestration

## Common Pitfalls

### ❌ Forgetting AWS_PROFILE
**Symptom**: "Unable to locate credentials" or operations on wrong account
**Solution 1**: Always use `AWS_PROFILE=arch` or the Makefile
**Solution 2**: Ask the user to refresh the AWS credentials

### ❌ Running bare CDK commands
**Symptom**: "cdk: command not found" or wrong Python environment
**Solution**: Use `uv run cdk` or the Makefile

### ❌ Using CloudFormation exports
**Symptom**: Can't delete stacks due to export dependencies
**Solution**: Use SSM Parameter Store instead

### ❌ Creating nested/monolithic stacks
**Symptom**: Hard to update individual components
**Solution**: Keep stacks separate, deploy independently

### ❌ Modifying Lambda code without pushing to CodeCommit
**Symptom**: Lambda continues using old code even after rebuilding in CodeBuild
**Root Cause**: CodeBuild pulls from CodeCommit repository, not local files
**Solution**: Always `git commit && git push` before triggering CodeBuild
**This is the #1 most common mistake** - it has come up repeatedly during debugging

### ❌ Using timestamps instead of S3 version IDs for Lambda deployment
**Symptom**: CDK deployment fails with "Invalid version id specified"
**Root Cause**: SSM parameters contain timestamps instead of actual S3 version IDs
**Solution**: Get real S3 version IDs and update SSM parameters before deployment

### ❌ Confusing Cognito User ID with Identity Pool ID
**Symptom**: 403 errors when submitting jobs, S3 access denied
**Root Cause**: Using Cognito User ID for S3 keys instead of Identity Pool ID
**Solution**: Use Identity Pool ID for S3 key prefixes, let IAM policies handle access control

### ❌ Missing start_processing parameter in job submission
**Symptom**: Jobs stay in "created" status and never start processing
**Root Cause**: Lambda defaults to `start_processing: false`
**Solution**: Include `"start_processing": true` in job submission payload

### ❌ Using jq or python3 in CodeBuild buildspec
**Symptom**: CodeBuild fails with "jq: command not found" or "python3: command not found" (exit status 127)
**Root Cause**: jq and python3 are not available in the CodeBuild environment
**Solution**: Use AWS CLI's built-in `--query` parameter for JSON parsing
**Example**: Replace `python3 -c "import sys, json; print(json.load(sys.stdin)['VersionId'])"` with `--query 'VersionId' --output text`

### ❌ Runtime model downloads in containers
**Symptom**: Container jobs take 10+ minutes, timeout frequently
**Root Cause**: Large ML models (1+ GB) downloading at runtime on every execution
**Solution**: Pre-download models during container build using RUN commands
**Example**: `RUN python -c "from marker.models import create_model_dict; create_model_dict()"`
**This pattern should be applied to all ML model containers**

### ❌ Using Docker Hub base images in Dockerfiles
**Symptom**: CodeBuild fails with "429 Too Many Requests" or "toomanyrequests: You have reached your unauthenticated pull rate limit"
**Root Cause**: Docker Hub has rate limits for unauthenticated pulls (100 pulls/6hr for anonymous, 200/6hr for free accounts)
**Solution**: Use AWS ECR Public Gallery instead of Docker Hub for base images
**Examples**:
```dockerfile
# ❌ WRONG - Docker Hub (will hit rate limits)
FROM python:3.11-slim
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

# ✅ CORRECT - AWS ECR Public Gallery
FROM public.ecr.aws/docker/library/python:3.11-slim
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04  # NVIDIA NGC for CUDA
```
**Note**: This happens consistently when adding new containers - always use ECR Public or NGC

### ❌ Manually editing frontend/elm.json
**Symptom**: Elm build fails with "dependencies elm.json in were edited by hand (or by a 3rd party tool) leaving them in an invalid state"
**Root Cause**: Elm's dependency resolver is strict about version consistency. Hand-editing elm.json often introduces invalid version combinations.
**Solution**: NEVER edit elm.json directly. ALWAYS use `elm install <package>` to add or update dependencies.
**Example**:
```bash
# ❌ WRONG - editing elm.json directly
# Manually changing "elm/html": "1.0.0" to "1.0.1"

# ✅ CORRECT - use elm install
cd frontend && yes | elm install elm/html
```
**Recovery**: If elm.json is corrupted, delete it and elm-stuff/, then reinstall all packages with `elm install`
**This is a critical requirement** - even minor version edits can break the build

## Quick Reference

| Task | Command |
|------|---------|
| **Deploy all stacks** | `make pipeline-start` |
| Check pipeline status | `make pipeline-status` |
| List pipeline executions | `make pipeline-executions` |
| Synth all stacks | `make cdk-synth` |
| Deploy a single stack | `make cdk-deploy STACK=FoundationStack` |
| Check what will change | `make cdk-diff STACK=CoreInfrastructureStack` |
| View logs | `make aws-logs LOGGROUP=/aws/lambda/function-name` |
| List S3 buckets | `make aws-s3-ls` |
| Build container | `make container-build MODEL=marker` |
| Run unit tests (local) | `make test` |
| Run unit tests (cloud) | `make test-unit-cloud` |
| Run integration tests (cloud) | `make test-integration-cloud` |
| Check cloud test status | `make test-cloud-status` |

## Stack Deployment Order

The pipeline (`make pipeline-start`) handles deployment order automatically. For manual deployments, use this order:

1. `FoundationStack` - ECR repositories, certificates, Route53
2. `NetworkingStack` - VPC, subnets, security groups
3. `CoreInfrastructureStack` - Cognito, S3, DynamoDB
4. `CiCdStack` - CodeBuild projects for containers, Lambda, and tests
5. Model stacks (MarkerStack, DoclingStack, etc.) - ECS tasks and Step Functions
6. `ApiV2Stack` - HTTP API Gateway, Lambda handlers
7. `MonitoringStack` - CloudWatch dashboards and alarms
8. `FrontendStack` - S3 static site, CloudFront distribution

## Frontend Testing with agent-browser

Use [agent-browser](https://github.com/vercel-labs/agent-browser) to test the frontend UI without manual browser interaction.

### Setup

agent-browser should already be installed globally. If not:
```bash
npm install -g agent-browser
agent-browser install  # Download Chromium
```

### Dev Mode (Recommended for UI Testing)

Add `?dev` to the URL to enable dev mode, which auto-authenticates with mock tokens:

```bash
cd frontend && ./build.sh
cd dst && uv run python -m http.server 8080 &
agent-browser open "http://localhost:8080/?dev"
```

**Dev mode features:**
- Auto-login on page load (no credentials needed)
- Access to all authenticated pages (Upload, Models, Jobs/Dashboard)
- Sign-in form accepts any credentials
- Mock tokens never expire

**Note:** API calls will fail in dev mode (no backend), but all UI pages and navigation work.

### Testing Workflow

1. **Start the frontend server**:
```bash
cd frontend && ./build.sh  # Build the Elm app
cd dst && uv run python -m http.server 8080 &
```

2. **Open the browser with dev mode**:
```bash
agent-browser open "http://localhost:8080/?dev"
```

3. **Take snapshots to see interactive elements**:
```bash
agent-browser snapshot -i  # Shows elements with refs like @e1, @e2
```

4. **Interact with elements**:
```bash
agent-browser fill @e1 "test@example.com"  # Fill text inputs
agent-browser click @e3                     # Click buttons
agent-browser press "Meta+k"                # Keyboard shortcuts (Cmd+K)
agent-browser press "Escape"                # Close modals
agent-browser press "ArrowDown"             # Navigate lists
```

5. **Take screenshots for visual verification**:
```bash
agent-browser screenshot /tmp/test-screenshot.png
```

6. **Close when done**:
```bash
agent-browser close
```

### Example: Testing the Model Palette

```bash
# Start server and open browser
agent-browser open http://localhost:8080/

# Open the model palette with Cmd+K
agent-browser press "Meta+k"

# Take screenshot to verify it opened
agent-browser screenshot /tmp/palette-test.png

# Test search functionality
agent-browser snapshot -i  # Find search input ref
agent-browser fill @e5 "docling"

# Test keyboard navigation
agent-browser press "ArrowDown"
agent-browser press "Enter"  # Select model

# Close palette with Escape
agent-browser press "Escape"

# Close browser
agent-browser close
```

### Useful Commands

| Task | Command |
|------|---------|
| Open URL | `agent-browser open <url>` |
| List elements | `agent-browser snapshot -i` |
| Click element | `agent-browser click @e1` |
| Fill input | `agent-browser fill @e1 "text"` |
| Press key | `agent-browser press "Enter"` |
| Key combo | `agent-browser press "Meta+k"` |
| Screenshot | `agent-browser screenshot <path>` |
| Get page title | `agent-browser get title` |
| Close browser | `agent-browser close` |

### Notes

- The frontend requires authentication for most pages. Without a backend, you can only test the login page and global features like the command palette (Cmd+K).
- Use `snapshot -i` after each interaction to get updated element refs.
- Screenshots are useful for visual verification of styling and layout.

## Getting Help

- **Architecture details**: See [backend/docs/architecture.md](backend/docs/architecture.md)
- **Project overview**: See [README.md](README.md)
- **Common tasks**: Run `make help`

## For New Agents Starting a Session

1. Read this file first
2. Review architecture.md for system design
3. Use Makefile for all AWS/CDK operations
4. Remember: AWS_PROFILE=arch and uv are non-negotiable
5. Deploy via `make pipeline-start` (not manual cdk-deploy)
6. Use agent-browser for frontend UI testing
