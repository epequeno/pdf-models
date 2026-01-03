# pdf-models

## Overview
A serverless platform for hosting open-source document processing models as API services. Users submit documents, get structured results back. No infrastructure management required.

**Initial Focus**: PDF to Markdown conversion using [Marker](https://github.com/VikParuchuri/marker)

## Documentation
- **[Architecture Documentation](backend/docs/architecture.md)** - Detailed technical design, patterns, and implementation guide
- **[AI Agent Guide (AGENTS.md)](AGENTS.md)** - Critical requirements for AI agents (AWS_PROFILE, uv usage, common pitfalls)

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

## Project Structure

```
backend/
├── docs/          # Architecture and design documentation
├── cdk/           # AWS CDK infrastructure (Python)
├── containers/    # Model containers (built in AWS)
└── lambdas/       # API handlers (Rust)

frontend/          # Elm UI (low priority for MVP)
```

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

**Important**: All AWS/CDK commands require `AWS_PROFILE=arch` prefix. The Makefile handles this automatically.

See [Architecture Documentation](backend/docs/architecture.md) for detailed setup and implementation phases.

## Current Status

**Integration Tests Fixed - Container Performance Optimized** ✅

- [x] Phase 1: Core Infrastructure - **DEPLOYED & WORKING**
  - FoundationStack (ECR repositories)
  - CoreInfrastructureStack (S3, DynamoDB, Cognito User Pool + Identity Pool)
  - ✅ Identity Pool workflow implemented for direct S3 access
- [x] Phase 1.5: CI/CD Infrastructure - **DEPLOYED & WORKING**
  - CiCdStack (CodeCommit, CodeBuild)
  - Custom Rust Lambda builder base image
  - ✅ Fixed buildspec to handle S3 versioning correctly
- [x] Phase 2: Marker Model - **DEPLOYED & OPTIMIZED** ✅
  - MarkerStack (ECS, Fargate, Step Functions)
  - ✅ Fixed networking: ECS tasks now use public subnets for ECR access
  - ✅ Optimized container: Pre-downloads 1.34GB Marker model at build time
- [x] Phase 3: API Layer - **HTTP API v2 FULLY WORKING** ✅
  - ApiV2Stack (HTTP API Gateway, Cognito JWT authorizer)
  - Rust Lambda functions with Identity Pool workflow
  - API Endpoint: `https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/`
  - ✅ S3 access permissions resolved

**Recent Fixes Applied**:
- **Networking Issue**: Fixed ECS tasks unable to reach ECR by switching from private to public subnets
- **Performance Issue**: Eliminated 1+ minute model download delay by pre-downloading models in container build
- **Container Optimization**: Marker models (1.34GB) now baked into container image for instant startup

**Performance Improvements**:
- **Before**: 10+ minute job execution (1+ minute model download + processing)
- **After**: ~30 seconds job execution (instant model loading + processing)

## Integration Testing

**Run integration tests:**
```bash
make test-integration-auto  # Sets up test user and runs all tests
```

**Test coverage:**
- ✅ Job submission with Identity Pool S3 upload
- ✅ Job status retrieval and polling
- ✅ Job listing for authenticated users
- ✅ Authorization (404 for non-existent jobs)
- ✅ End-to-end PDF processing (completes in ~30 seconds)

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

## Next Steps

**System is fully functional!** 🎉

The integration tests confirm the complete workflow is working:
1. Users authenticate with Cognito
2. Upload files to S3 using Identity Pool credentials  
3. Submit jobs via API referencing S3 keys
4. Jobs are processed by Step Functions + ECS Fargate
5. Results are stored back to S3 and accessible via API

**For production readiness:**
- Set up monitoring and alerting
- Configure custom domain and SSL certificate
- Implement rate limiting and usage quotas
- Add more comprehensive error handling
- Scale ECS cluster based on demand
