# Development Progress

Last Updated: 2025-12-31

## Phase 1: Core Infrastructure - DEPLOYED ✅

### Implementation Summary

Phase 1 implementation is **100% complete** with all code written, tested, and **DEPLOYED TO AWS**.

### Files Created

1. **`backend/backend/stack_config.py`**
   - Centralized configuration constants
   - NO hardcoded account IDs or regions (critical requirement met)
   - SSM parameter name definitions
   - Resource naming conventions

2. **`backend/backend/foundation_stack.py`**
   - ECR repository for Marker container
   - Image scanning enabled
   - Lifecycle policy (keep last 5 images)
   - SSM parameter export for ECR URI
   - Placeholders for future Route53/ACM

3. **`backend/backend/core_infrastructure_stack.py`**
   - S3 bucket with 7-day lifecycle, CORS, encryption
   - DynamoDB table with GSI for user queries
   - Cognito User Pool (authentication)
   - Cognito Identity Pool (AWS credentials)
   - IAM role with scoped S3 permissions (CRITICAL SECURITY)
   - 5 SSM parameter exports

4. **`backend/tests/unit/test_foundation_stack.py`**
   - 4 unit tests covering FoundationStack
   - Tests ECR config, SSM exports, scanning settings

5. **`backend/tests/unit/test_core_infrastructure_stack.py`**
   - 10 unit tests covering CoreInfrastructureStack
   - Tests S3, DynamoDB, Cognito, IAM policies
   - Validates scoped S3 access (security-critical)

### Files Modified

1. **`backend/app.py`**
   - Removed BackendStack
   - Added FoundationStack and CoreInfrastructureStack
   - No env= parameter (AWS_PROFILE handles everything)
   - No shebang (uses venv)

2. **`Makefile`**
   - Added `make test` and `make test-watch` commands
   - Fixed CDK command paths (backend/ not backend/cdk/)
   - Hardcoded AWS_PROFILE=arch in all commands (not variable)
   - Updated setup command

### Test Results

```
14 passed in 1.72s
```

All tests passing:
- ✅ Stack synthesis (both stacks)
- ✅ ECR repository configuration
- ✅ S3 bucket lifecycle and CORS
- ✅ DynamoDB schema and GSI
- ✅ Cognito User Pool settings
- ✅ Cognito Identity Pool configuration
- ✅ **IAM scoped S3 access (SECURITY CRITICAL)** ✅
- ✅ SSM parameter exports (all 6 parameters)

### Key Architectural Decisions Implemented

1. **NO Hardcoded Account/Region**
   - Never use account IDs in code or configuration
   - AWS_PROFILE=arch handles all account/region determination
   - Use `Aws.ACCOUNT_ID` for S3 bucket naming only

2. **SSM Parameter Store (NOT CloudFormation Exports)**
   - All cross-stack communication via SSM
   - Enables independent stack updates/deletion
   - No export dependency chains

3. **Makefile Enforces AWS_PROFILE=arch**
   - All commands explicitly use AWS_PROFILE=arch
   - No reliance on environment variables
   - Consistent, repeatable deployments

4. **Scoped S3 Access via Cognito**
   - Users can only access `${cognito-identity.amazonaws.com:sub}/*`
   - IAM policy enforces path-based isolation
   - Tested and validated in unit tests

### What's Ready

- [x] All code written
- [x] All tests passing
- [x] Makefile configured
- [x] Documentation updated
- [x] **FoundationStack DEPLOYED** ✅
- [x] **CoreInfrastructureStack DEPLOYED** ✅

### Deployment Results

**Deployment Date**: 2025-12-31

#### FoundationStack - Deployed ✅

**Resources Created**:
- ECR Repository: `496830984285.dkr.ecr.us-east-1.amazonaws.com/pdf-models/marker`
- Image Scanning: Enabled (scan on push)
- SSM Parameter: `/pdf-models/foundation/ecr-repo-uri-marker`

**Validation**:
```bash
✅ ECR repository verified
✅ SSM parameter verified
```

#### CoreInfrastructureStack - Deployed ✅

**Resources Created**:
- S3 Bucket: `pdf-models-docs-496830984285`
- DynamoDB Table: `pdf-models-jobs` (ACTIVE)
- DynamoDB GSI: `user_id-created_at-index`
- Cognito User Pool: `pdf-models-users` (ID: `us-east-1_0Puc2vOAn`)
- Cognito User Pool Client: `3a9qpq5sb48plnt6eg52t26ula`
- Cognito Identity Pool: `us-east-1:725ee04f-7250-4862-9158-de9fa49ef895`
- IAM Authenticated Role with scoped S3 access
- 5 SSM Parameters:
  - `/pdf-models/core/s3-bucket-name`
  - `/pdf-models/core/dynamodb-table-name`
  - `/pdf-models/core/cognito-user-pool-id`
  - `/pdf-models/core/cognito-user-pool-client-id`
  - `/pdf-models/core/cognito-identity-pool-id`

**Validation**:
```bash
✅ S3 bucket verified
✅ DynamoDB table and GSI verified
✅ Cognito User Pool verified
✅ All 5 SSM parameters verified
```

#### Files Modified During Deployment

1. **`Makefile`**
   - Added `--require-approval never` flag to `cdk-deploy` target
   - Enables automatic deployment without manual approval prompts

### Known Issues / Notes

None - Phase 1 fully deployed and validated.

### Next Steps

**Optional: Create Test User**
```bash
USER_POOL_ID=$(AWS_PROFILE=arch aws ssm get-parameter \
  --name /pdf-models/core/cognito-user-pool-id \
  --query 'Parameter.Value' --output text)

AWS_PROFILE=arch aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username your-email@example.com \
  --user-attributes Name=email,Value=your-email@example.com \
  --temporary-password TempPass123!

AWS_PROFILE=arch aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username your-email@example.com \
  --password YourPassword123! \
  --permanent
```

**Ready for Phase 2**: MarkerStack Implementation

## Phase 1.5: CI/CD Infrastructure - DEPLOYED ✅

### Implementation Summary

CI/CD stack deployed successfully with container build infrastructure.

### Files Created

1. **`backend/backend/cicd_stack.py`**
   - CodeCommit repository for source code
   - CodeBuild project for Marker container builds
   - IAM roles with ECR push permissions
   - SSM parameter exports for clone URLs

2. **`backend/containers/marker/Dockerfile`**
   - Python 3.11-slim base image
   - Marker PDF library and boto3
   - Non-root user security
   - Optimized for Fargate

3. **`backend/containers/marker/buildspec.yml`**
   - CodeBuild specification
   - ECR login and image tagging
   - Multi-stage build and push

4. **`backend/containers/marker/task.py`**
   - Complete Fargate task implementation
   - S3 download/upload logic
   - DynamoDB job status tracking
   - Marker PDF-to-Markdown conversion
   - Error handling and logging

### Deployment Results

**Deployment Date**: 2025-12-31

**Resources Created**:
- CodeCommit Repository: `pdf-models`
  - HTTP Clone URL: `https://git-codecommit.us-east-1.amazonaws.com/v1/repos/pdf-models`
- CodeBuild Project: `pdf-models-marker-container-build`
- SSM Parameters:
  - `/pdf-models/cicd/codecommit-clone-url-http`
  - `/pdf-models/cicd/codecommit-clone-url-ssh`

**Validation**:
```bash
✅ CodeCommit repository verified
✅ CodeBuild project verified
✅ SSM parameters verified
```

### What's Ready

- [x] CiCdStack code written
- [x] CiCdStack deployed
- [x] Marker Dockerfile complete
- [x] Marker task.py complete
- [x] CodeBuild buildspec complete
- [ ] Marker container built and pushed to ECR (pending)

### Next Steps

**Build Marker Container**:
```bash
# Trigger CodeBuild to build and push container
AWS_PROFILE=arch aws codebuild start-build \
  --project-name pdf-models-marker-container-build
```

**Ready for Phase 2**: MarkerStack Implementation (ECS cluster, Fargate task definition, Step Functions)

## Phase 3: API Stack - IN PROGRESS 🚧

### Implementation Summary (Partial)

Phase 3 implementation is **in progress**. Rust Lambda functions are complete but not yet built or deployed.

### Files Created

1. **`backend/lambdas/submit-job/Cargo.toml`**
   - Rust dependencies: lambda_runtime, AWS SDK (DynamoDB, Step Functions), serde, uuid, chrono
   - Optimized release profile (strip, LTO, opt-level "z")

2. **`backend/lambdas/submit-job/src/main.rs`** (185 lines)
   - Handles POST /v1/models/{model}/jobs
   - Extracts user ID from Cognito JWT claims
   - Validates S3 input key matches user prefix
   - Creates DynamoDB job record
   - Triggers Step Functions execution
   - Returns 201 with job details

3. **`backend/lambdas/get-job/Cargo.toml`**
   - Rust dependencies: lambda_runtime, AWS SDK (DynamoDB), serde
   - Optimized release profile

4. **`backend/lambdas/get-job/src/main.rs`** (193 lines)
   - Handles GET /v1/models/{model}/jobs/{job_id} (single job)
   - Handles GET /v1/models/{model}/jobs (list jobs)
   - User isolation: only returns jobs belonging to authenticated user
   - Uses DynamoDB GSI (user_id-created_at-index) for listing
   - Returns 404 if job not found or belongs to different user

### What's Pending

- [ ] Add CodeBuild project to CiCdStack for Rust Lambda builds
- [ ] Create ApiStack CDK code (API Gateway, Lambda functions, Cognito authorizer)
- [ ] Write unit tests for ApiStack
- [ ] Build Lambdas via CodeBuild
- [ ] Deploy ApiStack to AWS
- [ ] End-to-end testing

### Key Architecture Decisions

1. **Rust Lambdas**: Chosen over Python to avoid dependency conflicts with CDK (Python)
2. **cargo-lambda build output**: `target/lambda/{function-name}/bootstrap` (not `target/release`)
3. **CodeBuild for Lambda builds**: Follows AWS-only CI/CD principle (no local cross-compilation)
4. **User isolation**: S3 keys must start with `{user_id}/`, enforced in Lambda
5. **Cognito integration**: User ID extracted from `requestContext.authorizer.claims.sub`

**Ready for Phase 2**: MarkerStack Implementation (ECS cluster, Fargate task definition, Step Functions)

## Phase 2: MarkerStack - DEPLOYED ✅

### Implementation Summary

Phase 2 implementation is **100% complete** with all code written, tested, and **DEPLOYED TO AWS**.

### Files Created

1. **`backend/backend/marker_stack.py`**
   - ECS Cluster with container insights
   - Fargate Task Definition (2 vCPU, 8GB RAM)
   - Task Execution Role (for ECS to pull images, write logs)
   - Task Role (for container to access S3, DynamoDB)
   - CloudWatch Log Group (7-day retention)
   - Step Functions State Machine for orchestration
   - VPC with public/private subnets and NAT gateways
   - 3 SSM parameter exports

2. **`backend/tests/unit/test_marker_stack.py`**
   - 11 unit tests covering MarkerStack
   - Tests ECS cluster, task definition, IAM permissions
   - Tests Step Functions state machine
   - Validates SSM exports

### Files Modified

1. **`backend/app.py`**
   - Added MarkerStack instantiation
   - Added dependency comments

### Test Results

```
23 passed in 1.99s
```

All tests passing including 11 new MarkerStack tests:
- ✅ ECS cluster configuration
- ✅ Fargate task definition (CPU/memory)
- ✅ Container environment variables
- ✅ Task role S3 permissions
- ✅ Task role DynamoDB permissions
- ✅ CloudWatch log group
- ✅ Step Functions state machine
- ✅ Step Functions role permissions
- ✅ SSM parameter exports

### Deployment Results

**Deployment Date**: 2025-12-31

**Resources Created**:
- ECS Cluster: `pdf-models-marker-cluster`
- Task Definition: `pdf-models-marker:1` (2 vCPU, 8GB)
- Step Functions State Machine: `pdf-models-marker`
- VPC with 2 public subnets, 2 private subnets, 2 NAT gateways
- CloudWatch Log Group: `/ecs/pdf-models-marker`
- SSM Parameters:
  - `/pdf-models/marker/task-definition-arn`
  - `/pdf-models/marker/cluster-arn`
  - `/pdf-models/marker/state-machine-arn`
- Marker Container Image: `496830984285.dkr.ecr.us-east-1.amazonaws.com/pdf-models/marker:latest`

**Validation**:
```bash
✅ ECS cluster verified
✅ Task definition verified
✅ Step Functions state machine verified
✅ All 3 SSM parameters verified
✅ Marker container image pushed to ECR
```

### What's Ready

- [x] MarkerStack code written
- [x] MarkerStack tests passing (11 tests)
- [x] Marker container built and pushed to ECR
- [x] MarkerStack deployed to AWS
- [x] All resources validated

### Known Issues / Notes

**NAT Gateways Created**: The MarkerStack creates a VPC with NAT gateways for private subnet internet access. This incurs ongoing costs (~$0.045/hour per NAT gateway = ~$65/month for 2 NAT gateways). This is required for Fargate tasks in private subnets to pull container images from ECR.

**Future Optimization**: Consider using VPC endpoints for ECR to eliminate NAT gateway costs.

### Next Steps

**Phase 3**: API Stack (API Gateway, Lambda functions, Cognito authorizer)
- Rust Lambda for job submission
- Rust Lambda for job status queries
- API Gateway with routes
- Cognito User Pool authorizer

## Commands Reference

### Testing
```bash
make test              # Run all unit tests
make test-watch        # Run tests in watch mode
```

### CDK Operations
```bash
make cdk-synth                              # Synthesize all stacks
make cdk-diff STACK=FoundationStack         # Preview changes
make cdk-deploy STACK=FoundationStack       # Deploy stack
make cdk-destroy STACK=CoreInfrastructureStack  # Destroy stack
```

### AWS Operations
```bash
make aws-s3-ls                                        # List S3 buckets
make aws-logs LOGGROUP=/aws/lambda/function-name      # Tail logs
make aws-stepfunctions-list                           # List state machines
```

## Important Reminders for Future Sessions

1. **ALWAYS use AWS_PROFILE=arch** - Makefile handles this automatically
2. **NEVER hardcode account IDs or regions** in code
3. **Use SSM parameters** for cross-stack references, not CloudFormation exports
4. **Run tests before deployment**: `make test`
5. **Stack deployment order**:
   1. FoundationStack (Phase 1)
   2. CoreInfrastructureStack (Phase 1)
   3. CiCdStack (Phase 1.5) - independent
   4. MarkerStack (Phase 2)
   5. ApiStack (Phase 3)

## Route53 Configuration

**Domain**: `epequeno.app`
**Hosted Zone ID**: `Z04774573K4OEWVFBEMS5`

**IMPORTANT**: The Route53 hosted zone ALREADY EXISTS in the AWS account. DO NOT create a new hosted zone in CDK. Use `HostedZone.from_hosted_zone_attributes()` to reference the existing zone when setting up DNS records for the API Gateway custom domain (future phase).

## Session Notes

### Session 1: Planning & Implementation
**Date**: 2025-12-31
**Agent**: Claude Sonnet 4.5
**Summary**:
- Planned and implemented complete Phase 1 infrastructure
- Created 5 new files, modified 2 existing files
- Wrote 14 unit tests (all passing)
- Updated Makefile with proper AWS_PROFILE enforcement
- Architecture fully documented in [backend/docs/architecture.md](backend/docs/architecture.md)

### Session 2: Deployment
**Date**: 2025-12-31
**Agent**: Claude Sonnet 4.5
**Summary**:
- Deployed FoundationStack successfully (ECR repository + SSM parameters)
- Deployed CoreInfrastructureStack successfully (S3, DynamoDB, Cognito, IAM)
- Validated all resources in AWS
- Updated Makefile to add `--require-approval never` for automated deployments
- Phase 1 fully deployed and ready for Phase 2

### Session 3: CI/CD Stack & Phase 2 Implementation
**Date**: 2025-12-31
**Agent**: Claude Sonnet 4.5
**Summary**:
- Discovered CiCdStack already deployed (not documented in progress)
- Updated PROGRESS.md to reflect actual state (Phase 1.5)
- Implemented MarkerStack (ECS cluster, Fargate task, Step Functions)
- Wrote 11 unit tests for MarkerStack (all passing)
- Built and pushed Marker container to ECR via CodeBuild
- Deployed MarkerStack to AWS successfully
- Validated all resources in AWS
- Phase 2 fully deployed and ready for Phase 3

### Session 4: Phase 3 - API Stack & Rust Lambdas (IN PROGRESS)
**Date**: 2025-12-31
**Agent**: Claude Sonnet 4.5
**Summary**:
- Started Phase 3: API Stack implementation
- Created Rust Lambda project structure in backend/lambdas/
- Implemented submit-job Lambda function
  - POST /v1/models/{model}/jobs endpoint handler
  - DynamoDB job creation with user_id, job_id, status, timestamps
  - Step Functions execution trigger
  - Cognito user authentication via request context
  - S3 key validation for user isolation (must start with user_id/)
  - Error handling with proper HTTP status codes
- Implemented get-job Lambda function
  - GET /v1/models/{model}/jobs/{job_id} - single job query
  - GET /v1/models/{model}/jobs - list user's jobs (uses GSI)
  - User isolation (can only see own jobs)
  - DynamoDB queries with proper filtering
- Both Lambdas:
  - Use lambda_runtime 1.0.2 (upgraded from 0.13.0), AWS SDK v1
  - Rust 2021 edition with optimized release builds
  - Environment variables: DYNAMODB_TABLE_NAME, STATE_MACHINE_ARN (submit-job only)
  - CORS headers, JSON responses, structured error handling
- Build output: `target/lambda/{function-name}/bootstrap` (cargo-lambda structure)
- **IMPORTANT**: Avoided installing Zig locally (follows AWS-only CI/CD principle)
- **CodeBuild for Rust Lambdas** ✅:
  - Created backend/lambdas/buildspec.yml for building both lambdas
  - Updated CiCdStack to include RustLambdaBuild CodeBuild project
  - Configured S3 artifact output to pdf-models bucket
  - Added SSM parameter export: `/pdf-models/cicd/rust-lambda-build-project`
  - Updated Makefile with `lambda-build` command
- **Deprecation Fixes** ✅:
  - Fixed MarkerStack: `container_insights` deprecated → `container_insights_v2=ecs.ContainerInsights.ENHANCED`
  - Updated test to expect "enhanced" instead of "enabled"
  - All 23 tests passing
  - CDK synth produces no deprecation warnings
- **ApiStack Implementation** ✅:
  - Created backend/backend/api_stack.py with complete API Gateway configuration
  - REST API Gateway with Cognito User Pool Authorizer
  - 2 Lambda functions: submit-job (POST) and get-job (GET single + list)
  - 3 API routes: POST /v1/models/{model}/jobs, GET /v1/models/{model}/jobs, GET /v1/models/{model}/jobs/{job_id}
  - CORS configuration for browser access
  - CloudWatch log groups with 7-day retention
  - IAM roles with scoped permissions (DynamoDB PutItem/GetItem/Query, Step Functions StartExecution)
  - Lambda asset paths: lambdas/{function}/target/lambda/{function}/bootstrap (cargo-lambda output)
  - SSM parameter exports: /pdf-models/api/endpoint, /pdf-models/api/id
  - Created placeholder bootstrap files to enable CDK synthesis before actual builds
  - Wrote 11 comprehensive unit tests in backend/tests/unit/test_api_stack.py
  - All 34 tests passing (11 ApiStack + 23 existing)
- **NEXT STEPS**:
  1. ~~Add CodeBuild project to CiCdStack for building Rust Lambdas~~ ✅
  2. ~~Complete ApiStack CDK implementation with correct Lambda asset paths~~ ✅
  3. ~~Write unit tests for ApiStack~~ ✅
  4. Deploy CiCdStack updates to AWS (RustLambdaBuild project)
  5. Build Lambdas via CodeBuild (replace placeholder bootstrap files)
  6. Deploy ApiStack to AWS
