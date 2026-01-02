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

**All Infrastructure Deployed** ✅

- [x] Phase 1: Core Infrastructure - **DEPLOYED**
  - FoundationStack (ECR repositories)
  - CoreInfrastructureStack (S3, DynamoDB, Cognito)
- [x] Phase 1.5: CI/CD Infrastructure - **DEPLOYED**
  - CiCdStack (CodeCommit, CodeBuild)
  - Custom Rust Lambda builder base image
- [x] Phase 2: Marker Model - **DEPLOYED**
  - MarkerStack (ECS, Fargate, Step Functions)
  - Marker container image
- [x] Phase 3: API Layer - **DEPLOYED**
  - ApiStack (API Gateway, Cognito authorizer)
  - Rust Lambda functions (ARM64)
  - API Endpoint: `https://ivd1t6g04g.execute-api.us-east-1.amazonaws.com/v1/`

**Next Steps**: Create Cognito test user for API testing
