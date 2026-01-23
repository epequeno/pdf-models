# pdf-models

## Overview
A serverless platform for hosting open-source document processing models as API services. Users submit documents, get structured results back. No infrastructure management required.

## Documentation

**Backend:**
- **[Architecture Documentation](backend/docs/architecture.md)** - Detailed technical design, patterns, and implementation guide
- **[AI Agent Guide (AGENTS.md)](AGENTS.md)** - Critical requirements for AI agents (AWS_PROFILE, uv usage, common pitfalls)

**Frontend:**
- **[Design Brief (DESIGN_BRIEF.md)](DESIGN_BRIEF.md)** - Visual design system and component specifications
- **[Implementation Plan (frontend/IMPLEMENTATION_PLAN.md)](frontend/IMPLEMENTATION_PLAN.md)** - Complete frontend redesign implementation status
- **[Browser Testing (frontend/docs/BROWSER_TESTING.md)](frontend/docs/BROWSER_TESTING.md)** - Using agent-browser for UI testing
- **[Deployment (frontend/docs/DEPLOYMENT.md)](frontend/docs/DEPLOYMENT.md)** - S3/CloudFront deployment guide

## Key Concepts

**Serverless First**
- Pay-per-use compute only (no persistent resources like EC2, RDS, NAT gateways)
- Keeps costs minimal during development while enabling scale later
- SageMaker is explicitly avoided (requires persistent compute)

**Transparency**
- Return model outputs as-is, minimal transformation
- Users should experience models similarly to self-hosting
- We're infrastructure, not a custom processing pipeline

**AWS-Native CI/CD**
- Nothing runs locally except code editing
- All builds, deployments, and AWS operations happen in CodeBuild/CodePipeline
- Ensures hermetic, reproducible environments from day one
- 🚨 **CRITICAL**: CodeBuild pulls from CodeCommit - Lambda code changes must be committed & pushed before rebuilding

**Clean Separation**
- Infrastructure split into independent stacks by lifecycle (stable vs frequently changing)
- Stacks communicate via SSM Parameter Store (not CloudFormation exports)
- Enables independent updates without coupling

## Getting Started

**Prerequisites**: AWS CLI, CDK CLI, uv (Python), Rust toolchain

**Quick commands** (see `Makefile` for all options):
```bash
make help                              # Show all available commands
make cdk-deploy STACK=FoundationStack  # Deploy a stack
make cdk-diff STACK=CoreInfra          # Preview changes
make aws-logs LOGGROUP=/aws/lambda/... # Tail logs
```

**Deploy stacks in order**:
1. Foundation (long-lived resources: ECR, certificates)
2. Core Infrastructure (Cognito, S3, DynamoDB)
3. Model stacks (per-model: task definitions, Step Functions)
4. API (Gateway + Lambda handlers)
5. CI/CD (CodeBuild automation)

## Integration Testing

**Run integration tests:**
```bash
make test-integration-auto  # Sets up test user and runs all tests
```

**Test user credentials:**
- Email: `integration-test@pdf-models.local`
- Password: `TestPass123!`

## Quick Start - Using the API

**Identity Pool Workflow (Recommended):**
```bash
# 1. Get Cognito tokens
TOKEN_RESPONSE=$(AWS_PROFILE=arch aws cognito-idp initiate-auth \
  --client-id 4tmf8s58738hrbrp4ff2utqg5 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=integration-test@pdf-models.local,PASSWORD=TestPass123!)

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.AuthenticationResult.AccessToken')
ID_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.AuthenticationResult.IdToken')

# 2. Get Identity Pool credentials for S3 access
IDENTITY_ID=$(AWS_PROFILE=arch aws cognito-identity get-id \
  --identity-pool-id us-east-1:1fd26b6e-8a1c-4dd7-940d-60ec7884f384 \
  --logins cognito-idp.us-east-1.amazonaws.com/us-east-1_wslqPOxQd=$ID_TOKEN \
  --query 'IdentityId' --output text)

# 3. Upload PDF to S3 using Identity Pool credentials
aws s3 cp your-file.pdf s3://pdf-models-docs-496830984285/$IDENTITY_ID/your-job-id.pdf

# 4. Submit job with S3 key
curl -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"s3_input_key":"'$IDENTITY_ID'/your-job-id.pdf","start_processing":true}' \
  https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/v1/models/marker/jobs

# 5. Check job status
curl -H "Authorization: Bearer $ACCESS_TOKEN" \
  https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/v1/models/marker/jobs/your-job-id
```

