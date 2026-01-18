# Requirements Document

## Introduction

This document specifies the requirements for the User-Configurable Model Parameters feature. This feature enables users to create, save, and share custom model configurations that override both inference-level parameters (prompts, output formats) and infrastructure-level parameters (CPU, memory, GPU). All configurations require admin approval before use to ensure resource governance and prevent abuse.

## Glossary

- **Configuration**: A saved set of parameters that customize how a PDF processing model runs, including both inference parameters and infrastructure parameters.
- **Inference_Parameters**: Parameters passed to the model container at runtime via environment variables (prompts, output formats, language hints).
- **Infrastructure_Parameters**: Parameters that affect the ECS task definition (CPU, memory, GPU count, timeout, storage).
- **Approval_Status**: The state of a configuration in the admin approval workflow (pending_approval, approved, rejected).
- **Task_Definition**: An AWS ECS resource that defines how a container should run, including CPU, memory, and GPU requirements.
- **Config_CRUD_Lambda**: The Lambda function handling user configuration create, read, update, delete operations.
- **Config_Admin_Lambda**: The Lambda function handling admin approval, rejection, and revocation operations.
- **Register_Task_Def_Lambda**: The Lambda function that registers new ECS task definitions when configurations are approved.
- **Admin_User**: A user who belongs to the `pdf-models-admins` Cognito group and can approve/reject configurations.
- **Public_Configuration**: A configuration marked as visible to all users for discovery and forking.
- **Fork**: Creating a copy of an existing configuration for personal customization.

## Requirements

### Requirement 1: Configuration Data Storage

**User Story:** As a system architect, I want configurations stored in a dedicated DynamoDB table with appropriate indexes, so that configurations can be efficiently queried by user, model, and visibility.

#### Acceptance Criteria

1. THE System SHALL store configurations in a DynamoDB table named `pdf-models-configurations` with partition key `config_id`.
2. THE System SHALL provide a GSI `user_id-created_at-index` for querying a user's configurations sorted by creation date.
3. THE System SHALL provide a GSI `is_public-model-index` for discovering public approved configurations by model.
4. WHEN a configuration is created, THE System SHALL generate a UUID for `config_id` and record `created_at` timestamp.
5. THE System SHALL store inference parameters including `prompt`, `output_format`, and `custom_env_vars` as a nested object.
6. THE System SHALL store infrastructure parameters including `cpu`, `memory_mib`, `gpu_count`, `timeout_minutes`, `ephemeral_storage_gib`, `ebs_volume_size_gb`, and `spot_enabled` as a nested object.

### Requirement 2: User Configuration CRUD Operations

**User Story:** As a user, I want to create, view, update, and delete my custom model configurations, so that I can customize how models process my documents.

#### Acceptance Criteria

1. WHEN a user creates a configuration via `POST /v1/models/{model}/configs`, THE Config_CRUD_Lambda SHALL create a new configuration with `approval_status` set to `pending_approval`.
2. WHEN a user requests their configurations via `GET /v1/models/{model}/configs`, THE Config_CRUD_Lambda SHALL return only configurations owned by that user for the specified model.
3. WHEN a user requests a specific configuration via `GET /v1/models/{model}/configs/{config_id}`, THE Config_CRUD_Lambda SHALL return the configuration if the user owns it, it is shared with them, or it is public and approved.
4. WHEN a user updates a configuration via `PUT /v1/models/{model}/configs/{config_id}`, THE Config_CRUD_Lambda SHALL reset `approval_status` to `pending_approval` and clear `task_definition_arn`.
5. WHEN a user deletes a configuration via `DELETE /v1/models/{model}/configs/{config_id}`, THE Config_CRUD_Lambda SHALL remove the configuration if the user owns it.
6. WHEN a user attempts to modify a configuration they do not own, THE Config_CRUD_Lambda SHALL return a 403 Forbidden error.

### Requirement 3: Configuration Parameter Validation

**User Story:** As a system administrator, I want configuration parameters validated against allowed ranges, so that users cannot request invalid or excessive resources.

#### Acceptance Criteria

1. WHEN a configuration specifies `cpu`, THE Config_CRUD_Lambda SHALL validate it is a valid Fargate value (256, 512, 1024, 2048, 4096, 8192, or 16384) or valid EC2 vCPU count (1-96).
2. WHEN a configuration specifies `memory_mib`, THE Config_CRUD_Lambda SHALL validate it matches valid Fargate CPU/memory combinations or is within EC2 instance limits.
3. WHEN a configuration specifies `gpu_count`, THE Config_CRUD_Lambda SHALL validate it is between 0 and 4.
4. WHEN a configuration specifies `timeout_minutes`, THE Config_CRUD_Lambda SHALL validate it is between 1 and 180.
5. WHEN a configuration specifies `ephemeral_storage_gib`, THE Config_CRUD_Lambda SHALL validate it is between 21 and 200 for Fargate.
6. WHEN a configuration specifies `ebs_volume_size_gb`, THE Config_CRUD_Lambda SHALL validate it is between 30 and 500 for EC2.
7. IF a configuration contains invalid parameters, THEN THE Config_CRUD_Lambda SHALL return a 400 Bad Request with specific validation errors.

### Requirement 4: Admin Approval Workflow

**User Story:** As an administrator, I want to review and approve user configurations before they can be used, so that I can ensure resource governance and prevent abuse.

#### Acceptance Criteria

1. WHEN an admin requests pending configurations via `GET /v1/admin/configs/pending`, THE Config_Admin_Lambda SHALL return all configurations with `approval_status` of `pending_approval`.
2. WHEN an admin approves a configuration via `POST /v1/admin/configs/{config_id}/approve`, THE Config_Admin_Lambda SHALL set `approval_status` to `approved`, record `approved_by` and `approved_at`, and trigger task definition registration.
3. WHEN an admin rejects a configuration via `POST /v1/admin/configs/{config_id}/reject`, THE Config_Admin_Lambda SHALL set `approval_status` to `rejected` and record the `rejection_reason`.
4. WHEN an admin revokes a configuration via `POST /v1/admin/configs/{config_id}/revoke`, THE Config_Admin_Lambda SHALL set `approval_status` to `pending_approval` and clear `task_definition_arn`.
5. WHEN a non-admin user attempts to access admin endpoints, THE Config_Admin_Lambda SHALL return a 403 Forbidden error.
6. THE System SHALL verify admin status by checking membership in the `pdf-models-admins` Cognito group.

### Requirement 5: Task Definition Registration

**User Story:** As a system architect, I want ECS task definitions automatically registered when configurations are approved, so that approved configurations can be used for job processing.

#### Acceptance Criteria

1. WHEN a configuration is approved, THE Register_Task_Def_Lambda SHALL create a new ECS task definition based on the configuration's infrastructure parameters.
2. THE Register_Task_Def_Lambda SHALL derive the new task definition from the base model's task definition stored in SSM.
3. THE Register_Task_Def_Lambda SHALL name task definitions using the pattern `pdf-models-{model}-user-{config_id[:8]}`.
4. WHEN task definition registration succeeds, THE Register_Task_Def_Lambda SHALL update the configuration with `task_definition_arn` and set `task_definition_status` to `active`.
5. IF task definition registration fails, THEN THE Register_Task_Def_Lambda SHALL set `task_definition_status` to `failed` and record the error.
6. THE Register_Task_Def_Lambda SHALL have IAM permissions scoped to task definitions matching `pdf-models-*-user-*`.

### Requirement 6: Job Submission with Configuration

**User Story:** As a user, I want to submit jobs using my approved configurations, so that my documents are processed with my custom parameters.

#### Acceptance Criteria

1. WHEN a user submits a job with `config_id` via `POST /v1/models/{model}/jobs`, THE Submit_Job_Lambda SHALL validate the configuration exists and has `approval_status` of `approved`.
2. WHEN a user submits a job with `config_id`, THE Submit_Job_Lambda SHALL verify the user has access to the configuration (owner, shared, or public).
3. IF a user submits a job with a non-approved configuration, THEN THE Submit_Job_Lambda SHALL return a 400 Bad Request error.
4. WHEN a job is submitted with `config_id`, THE Submit_Job_Lambda SHALL pass the `config_id` to the Step Functions execution input.
5. THE ResolveTaskDef_Lambda SHALL use the configuration's `task_definition_arn` when `config_id` is present in the execution input.
6. THE ResolveTaskDef_Lambda SHALL merge the configuration's `inference_params` into the container environment overrides.

### Requirement 7: Configuration Discovery and Sharing

**User Story:** As a user, I want to discover and fork public configurations, so that I can benefit from configurations created by other users.

#### Acceptance Criteria

1. WHEN a user requests public configurations via `GET /v1/configs/discover`, THE Config_CRUD_Lambda SHALL return public configurations with `approval_status` of `approved`.
2. WHEN a user forks a configuration via `POST /v1/models/{model}/configs/{config_id}/fork`, THE Config_CRUD_Lambda SHALL create a copy owned by the user with `approval_status` of `pending_approval`.
3. WHEN a configuration is forked, THE Config_CRUD_Lambda SHALL record the `forked_from` field with the original configuration ID.
4. WHEN a configuration is used for a job, THE System SHALL increment the `usage_count` field.
5. THE System SHALL allow users to set `visibility` to `private` or `public` when creating or updating configurations.

### Requirement 8: User Configuration Limits

**User Story:** As a system administrator, I want to limit the number of configurations per user, so that the system remains manageable and resources are not exhausted.

#### Acceptance Criteria

1. WHEN a user creates a configuration, THE Config_CRUD_Lambda SHALL verify the user has fewer than 10 configurations for that model.
2. WHEN a user creates a configuration, THE Config_CRUD_Lambda SHALL verify the user has fewer than 50 total configurations across all models.
3. IF a user exceeds configuration limits, THEN THE Config_CRUD_Lambda SHALL return a 400 Bad Request with a message indicating the limit.
4. THE System SHALL count configurations with any `approval_status` toward the limits.

### Requirement 9: Admin Cognito Group

**User Story:** As a system administrator, I want admin users managed via a Cognito group, so that admin access can be controlled through standard IAM patterns.

#### Acceptance Criteria

1. THE System SHALL create a Cognito group named `pdf-models-admins` in the User Pool.
2. WHEN verifying admin access, THE Config_Admin_Lambda SHALL check the `cognito:groups` claim in the JWT token.
3. THE System SHALL allow multiple users to be members of the `pdf-models-admins` group.

### Requirement 10: Frontend Configuration Management

**User Story:** As a user, I want a user interface to manage my configurations, so that I can easily create, view, and select configurations for jobs.

#### Acceptance Criteria

1. THE Frontend SHALL provide a configuration list view showing the user's configurations with name, model, and approval status.
2. THE Frontend SHALL provide a configuration creation form with fields for name, description, inference parameters, and infrastructure parameters.
3. THE Frontend SHALL display validation errors when configuration parameters are invalid.
4. THE Frontend SHALL integrate a configuration selector into the upload flow for selecting approved configurations.
5. WHEN a configuration is pending approval, THE Frontend SHALL display a visual indicator and disable selection for job submission.

### Requirement 11: Frontend Admin Panel

**User Story:** As an administrator, I want a user interface to review and approve configurations, so that I can efficiently manage the approval workflow.

#### Acceptance Criteria

1. THE Frontend SHALL provide an admin panel accessible only to users in the `pdf-models-admins` group.
2. THE Frontend SHALL display pending configurations with user, model, and requested parameters.
3. THE Frontend SHALL provide approve and reject buttons with confirmation dialogs.
4. WHEN rejecting a configuration, THE Frontend SHALL require a rejection reason.
5. THE Frontend SHALL display the resource implications (estimated cost) of configurations before approval.
