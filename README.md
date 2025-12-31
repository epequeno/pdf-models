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

- [x] Architecture designed and documented
- [x] Phase 1: Core Infrastructure - **IMPLEMENTATION COMPLETE, READY FOR DEPLOYMENT**
  - [x] FoundationStack implemented (ECR repository)
  - [x] CoreInfrastructureStack implemented (S3, DynamoDB, Cognito)
  - [x] Unit tests written and passing (14/14 tests)
  - [x] Makefile updated with test commands
  - [ ] FoundationStack deployed to AWS
  - [ ] CoreInfrastructureStack deployed to AWS
- [ ] Phase 2: Marker model integration
- [ ] Phase 3: API Layer
- [ ] Phase 4: CI/CD automation

**Resume Point**: Phase 1 code is complete. Next step is deployment:
```bash
make cdk-deploy STACK=FoundationStack
make cdk-deploy STACK=CoreInfrastructureStack
```
