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

**Infrastructure Deployed - Auth Working with HTTP API v2** ✅

- [x] Phase 1: Core Infrastructure - **DEPLOYED & SIMPLIFIED**
  - FoundationStack (ECR repositories)
  - CoreInfrastructureStack (S3, DynamoDB, Cognito User Pool)
  - ✅ Cognito Identity Pool removed (simplified auth)
- [x] Phase 1.5: CI/CD Infrastructure - **DEPLOYED**
  - CiCdStack (CodeCommit, CodeBuild)
  - Custom Rust Lambda builder base image
- [x] Phase 2: Marker Model - **DEPLOYED**
  - MarkerStack (ECS, Fargate, Step Functions)
  - Marker container image
- [x] Phase 3: API Layer - **HTTP API v2 WORKING** ✅
  - ApiV2Stack (HTTP API Gateway, Cognito JWT authorizer)
  - Rust Lambda functions with S3 pre-signed URLs
  - API Endpoint: `https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/`
  - ⚠️ ApiStack (legacy REST API) - has auth issues, use v2 instead

## Quick Start - Testing API v2

```bash
# Get JWT token
TOKEN=$(AWS_PROFILE=arch aws cognito-idp initiate-auth \
  --client-id 4tmf8s58738hrbrp4ff2utqg5 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=integration-test@pdf-models.local,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.AccessToken' --output text)

# Submit a job (get upload URL)
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  https://eykwwhrt16.execute-api.us-east-1.amazonaws.com/v1/models/marker/jobs

# Response includes upload_url for S3 upload and job_id for tracking
```

## Next Steps to Complete

⚠️ **Lambda code needs to be updated** - See [HANDOVER.md](backend/docs/HANDOVER.md)

1. Commit all local changes to CodeCommit
2. Rebuild Lambda functions via CodeBuild
3. Redeploy ApiV2Stack
4. Test end-to-end workflow

See [backend/docs/HANDOVER.md](backend/docs/HANDOVER.md) for complete instructions.
