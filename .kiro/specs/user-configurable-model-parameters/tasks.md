# Implementation Plan: User-Configurable Model Parameters

## Overview

This implementation plan follows a phased approach:
1. **Phase 1**: Data model and infrastructure (DynamoDB table, Cognito group)
2. **Phase 2**: User configuration CRUD Lambda
3. **Phase 3**: Admin approval workflow Lambda
4. **Phase 4**: Task definition registration Lambda
5. **Phase 5**: Job submission integration
6. **Phase 6**: Frontend configuration management
7. **Phase 7**: Frontend admin panel

**CRITICAL**: Before starting any task, read `AGENTS.md` and `Makefile` to understand project conventions. All AWS commands require `AWS_PROFILE=arch` prefix.

## Tasks

- [x] 1. Set up data model and core infrastructure
  - [x] 1.1 Add configurations DynamoDB table to CoreInfrastructureStack
    - Add table `pdf-models-configurations` with partition key `config_id`
    - Add GSI `user_id-created_at-index` for user queries
    - Add GSI `visibility-model-index` for public config discovery
    - Export table name to SSM parameter `/pdf-models/core/configurations-table-name`
    - _Requirements: 1.1, 1.2, 1.3_
  
  - [x] 1.2 Add admin Cognito group to CoreInfrastructureStack
    - Create Cognito group `pdf-models-admins` in the User Pool
    - _Requirements: 9.1_
  
  - [x] 1.3 Deploy infrastructure changes
    - Run `AWS_PROFILE=arch uv run cdk synth` to verify
    - Run `make pipeline-start` to deploy
    - _Requirements: 1.1, 1.2, 1.3, 9.1_

- [x] 2. Implement config-crud Lambda (Rust)
  - [x] 2.1 Create config-crud Lambda project structure
    - Create `backend/lambdas/config-crud/` directory
    - Create `Cargo.toml` with dependencies (aws-sdk-dynamodb, serde, uuid, chrono)
    - Add to workspace `backend/lambdas/Cargo.toml`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_
  
  - [x] 2.2 Implement configuration data types and validation
    - Define `CreateConfigRequest`, `ConfigResponse`, `InferenceParams`, `InfraParams` structs
    - Implement Fargate CPU/memory validation matrix
    - Implement parameter range validation (gpu_count, timeout, storage)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
  
  - [ ]* 2.3 Write property tests for parameter validation
    - **Property 8: Parameter Validation**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
  
  - [x] 2.4 Implement create configuration handler
    - Generate UUID for config_id
    - Set approval_status to pending_approval
    - Validate parameters before saving
    - Check user limits (10 per model, 50 total)
    - _Requirements: 1.4, 2.1, 8.1, 8.2, 8.3, 8.4_
  
  - [ ]* 2.5 Write property tests for configuration creation
    - **Property 2: New Configurations Start Pending**
    - **Property 21: Configuration Limits Enforcement**
    - **Validates: Requirements 2.1, 8.1, 8.2, 8.3, 8.4**
  
  - [x] 2.6 Implement list configurations handler
    - Query GSI by user_id and model
    - Return only owned configurations
    - _Requirements: 2.2_
  
  - [ ]* 2.7 Write property test for user listing
    - **Property 3: User Listing Returns Only Owned Configurations**
    - **Validates: Requirements 2.2**
  
  - [x] 2.8 Implement get configuration handler
    - Fetch by config_id
    - Verify access (owner, shared, or public+approved)
    - _Requirements: 2.3_
  
  - [x] 2.9 Implement update configuration handler
    - Verify ownership
    - Reset approval_status to pending_approval
    - Clear task_definition_arn
    - _Requirements: 2.4, 2.6_
  
  - [ ]* 2.10 Write property test for update resets approval
    - **Property 5: Update Resets Approval Status**
    - **Validates: Requirements 2.4**
  
  - [x] 2.11 Implement delete configuration handler
    - Verify ownership before deletion
    - _Requirements: 2.5, 2.6_
  
  - [x] 2.12 Implement fork configuration handler
    - Create copy with new owner
    - Set approval_status to pending_approval
    - Record forked_from field
    - _Requirements: 7.2, 7.3_
  
  - [x] 2.13 Implement discover public configurations handler
    - Query visibility-model-index for public configs
    - Filter by approval_status = approved
    - _Requirements: 7.1_
  
  - [ ]* 2.14 Write property test for discover endpoint
    - **Property 17: Discover Returns Public Approved Configurations**
    - **Validates: Requirements 7.1**

- [x] 3. Checkpoint - Config CRUD Lambda complete
  - Ensure all tests pass, ask the user if questions arise.
  - Commit and push changes to CodeCommit
  - Trigger Lambda build: `AWS_PROFILE=arch aws codebuild start-build --project-name pdf-models-rust-lambda-build`

- [x] 4. Add config-crud API routes to ApiV2Stack
  - [x] 4.1 Create Lambda function resource for config-crud
    - Add SSM parameter for Lambda version
    - Create IAM role with DynamoDB permissions for configurations table
    - Create Lambda function resource
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_
  
  - [x] 4.2 Add API routes for config-crud
    - POST /v1/models/{model}/configs - create
    - GET /v1/models/{model}/configs - list
    - GET /v1/models/{model}/configs/{config_id} - get
    - PUT /v1/models/{model}/configs/{config_id} - update
    - DELETE /v1/models/{model}/configs/{config_id} - delete
    - POST /v1/models/{model}/configs/{config_id}/fork - fork
    - GET /v1/configs/discover - discover public
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 7.1, 7.2_

- [x] 5. Implement config-admin Lambda (Rust)
  - [x] 5.1 Create config-admin Lambda project structure
    - Create `backend/lambdas/config-admin/` directory
    - Create `Cargo.toml` with dependencies
    - Add to workspace
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  
  - [x] 5.2 Implement admin verification
    - Parse cognito:groups claim from JWT
    - Check for pdf-models-admins group membership
    - Return 403 if not admin
    - _Requirements: 4.5, 4.6, 9.2_
  
  - [ ]* 5.3 Write property test for admin authorization
    - **Property 11: Admin Authorization**
    - **Validates: Requirements 4.5, 9.2**
  
  - [x] 5.4 Implement list pending configurations handler
    - Query all configs with approval_status = pending_approval
    - _Requirements: 4.1_
  
  - [ ]* 5.5 Write property test for pending listing
    - **Property 9: Pending Configurations Listing**
    - **Validates: Requirements 4.1**
  
  - [x] 5.6 Implement approve configuration handler
    - Set approval_status to approved
    - Record approved_by and approved_at
    - Invoke register-task-def Lambda
    - _Requirements: 4.2_
  
  - [x] 5.7 Implement reject configuration handler
    - Set approval_status to rejected
    - Record rejection_reason
    - _Requirements: 4.3_
  
  - [x] 5.8 Implement revoke configuration handler
    - Set approval_status to pending_approval
    - Clear task_definition_arn
    - _Requirements: 4.4_
  
  - [ ]* 5.9 Write property tests for state transitions
    - **Property 10: Approval State Transitions**
    - **Validates: Requirements 4.2, 4.3, 4.4**

- [x] 6. Add config-admin API routes to ApiV2Stack
  - [x] 6.1 Create Lambda function resource for config-admin
    - Add SSM parameter for Lambda version
    - Create IAM role with DynamoDB permissions and Lambda invoke for register-task-def
    - Create Lambda function resource
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  
  - [x] 6.2 Add API routes for config-admin
    - GET /v1/admin/configs/pending - list pending
    - POST /v1/admin/configs/{config_id}/approve - approve
    - POST /v1/admin/configs/{config_id}/reject - reject
    - POST /v1/admin/configs/{config_id}/revoke - revoke
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [x] 7. Checkpoint - Admin Lambda complete
  - Ensure all tests pass, ask the user if questions arise.
  - Commit and push changes to CodeCommit
  - Trigger Lambda build

- [x] 8. Implement register-task-def Lambda (Python)
  - [x] 8.1 Create register-task-def Lambda project structure
    - Create `backend/lambdas/register-task-def/` directory
    - Create `handler.py` with boto3 ECS client
    - Create `requirements.txt`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
  
  - [x] 8.2 Implement task definition derivation logic
    - Read base task definition ARN from SSM
    - Describe base task definition via ECS API
    - Modify CPU, memory, GPU, storage based on config
    - _Requirements: 5.1, 5.2_
  
  - [x] 8.3 Implement task definition registration
    - Register new task definition with family pattern `pdf-models-{model}-user-{config_id[:8]}`
    - Update configuration with task_definition_arn
    - Set task_definition_status to active or failed
    - _Requirements: 5.3, 5.4, 5.5_
  
  - [ ]* 8.4 Write unit tests for task definition naming
    - **Property 12: Task Definition Naming Convention**
    - **Validates: Requirements 5.3**
  
  - [x] 8.5 Add register-task-def Lambda to CiCdStack or ApiV2Stack
    - Create IAM role with scoped ECS permissions (pdf-models-*-user-*)
    - Create Lambda function resource
    - _Requirements: 5.6_

- [x] 9. Modify submit-job Lambda for config support
  - [x] 9.1 Add config_id to SubmitJobBody struct
    - Add optional config_id field
    - _Requirements: 6.1_
  
  - [x] 9.2 Implement configuration validation in submit-job
    - Fetch configuration from DynamoDB if config_id provided
    - Verify approval_status is approved
    - Verify user has access to configuration
    - Return 400 if not approved, 403 if no access
    - _Requirements: 6.1, 6.2, 6.3_
  
  - [ ]* 9.3 Write property test for job submission with config
    - **Property 14: Job Submission Requires Approved Configuration**
    - **Validates: Requirements 6.1, 6.3**
  
  - [x] 9.4 Pass config_id to Step Functions execution input
    - Include config_id in execution input JSON
    - _Requirements: 6.4_
  
  - [x] 9.5 Increment usage_count when job submitted with config
    - Update configuration's usage_count atomically
    - _Requirements: 7.4_

- [x] 10. Modify ResolveTaskDef Lambda for config support
  - [x] 10.1 Update ResolveTaskDef Lambda in model_stack.py
    - Check for config_id in execution input
    - If present, fetch configuration from DynamoDB
    - Use configuration's task_definition_arn
    - Merge inference_params into environment overrides
    - _Requirements: 6.5, 6.6_
  
  - [ ]* 10.2 Write unit tests for ResolveTaskDef with config
    - **Property 16: ResolveTaskDef Uses Configuration**
    - **Validates: Requirements 6.5, 6.6**

- [-] 11. Checkpoint - Backend complete
  - Ensure all tests pass, ask the user if questions arise.
  - Commit and push all changes to CodeCommit
  - Run `make pipeline-start` to deploy all backend changes
  - Test end-to-end: create config → admin approve → submit job with config

- [ ] 12. Implement frontend configuration types
  - [ ] 12.1 Add Configuration types to Types.elm
    - Add Configuration record type
    - Add ApprovalStatus type (PendingApproval, Approved, Rejected)
    - Add InferenceParams and InfraParams record types
    - Add ConfigFilters type for filtering
    - _Requirements: 10.1, 10.2_
  
  - [ ] 12.2 Add configuration API functions to Api.elm
    - createConfig, getConfigs, getConfig, updateConfig, deleteConfig
    - forkConfig, discoverConfigs
    - Add JSON encoders and decoders
    - _Requirements: 10.1, 10.2, 10.3_

- [ ] 13. Implement frontend configuration management views
  - [ ] 13.1 Create Views/Configs.elm for configuration list
    - Display user's configurations with name, model, approval status
    - Show visual indicator for pending/rejected configs
    - Add create, edit, delete actions
    - _Requirements: 10.1, 10.5_
  
  - [ ] 13.2 Create configuration creation/edit form
    - Fields for name, description
    - Inference params: prompt, output_format, custom_env_vars
    - Infra params: cpu, memory, gpu, timeout, storage
    - Display validation errors
    - _Requirements: 10.2, 10.3_
  
  - [ ] 13.3 Integrate config selector into Upload view
    - Add dropdown to select approved configuration
    - Disable selection for pending/rejected configs
    - Pass config_id to job submission
    - _Requirements: 10.4, 10.5_

- [ ] 14. Implement frontend admin panel
  - [ ] 14.1 Add admin API functions to Api.elm
    - getPendingConfigs, approveConfig, rejectConfig, revokeConfig
    - Add JSON encoders and decoders
    - _Requirements: 11.1, 11.2, 11.3_
  
  - [ ] 14.2 Create Views/AdminConfigs.elm for admin panel
    - Display pending configurations with user, model, parameters
    - Show resource implications (estimated cost)
    - Add approve/reject buttons with confirmation
    - Require rejection reason input
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_
  
  - [ ] 14.3 Add admin route and navigation
    - Add AdminConfigs route to Types.elm
    - Add navigation link (visible only to admins)
    - Check admin status from JWT claims
    - _Requirements: 11.1_

- [ ] 15. Final checkpoint - Feature complete
  - Ensure all tests pass, ask the user if questions arise.
  - Build frontend: `cd frontend && ./build.sh`
  - Commit and push all changes
  - Run `make pipeline-start` for final deployment
  - Manual testing:
    - Create configuration via UI
    - Admin approve via admin panel
    - Submit job with approved configuration
    - Verify job uses custom parameters

## Notes

- **Warnings must be resolved**: Any compiler warnings that can be fixed should be addressed before marking a task as complete
- Tasks marked with `*` are optional property-based tests and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- All AWS commands require `AWS_PROFILE=arch` prefix
- Use `uv run` for Python/CDK commands
- Deploy via `make pipeline-start` (not manual cdk deploy)
