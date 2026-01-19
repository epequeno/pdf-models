# User-Configurable Model Parameters

## Overview

Enable users to create, save, and share custom model configurations that override both inference-level parameters (prompts, output formats) and infrastructure-level parameters (CPU, memory, GPU). Task definitions are generated dynamically outside the CDK pipeline. **All configurations require admin approval before use.**

## Architecture Approach

### Two-Tier Parameter Model

1. **Inference Parameters** - Passed via container environment variables (no new task definition needed)
   - Custom prompts (VLM models)
   - Output format preferences
   - Language hints
   - Custom environment variables

2. **Infrastructure Parameters** - All customizable, require new ECS task definition
   - CPU allocation (Fargate units or EC2 vCPU)
   - Memory allocation
   - GPU count (for GPU models)
   - Timeout duration
   - Ephemeral storage (Fargate) / EBS volume size (EC2)
   - Spot vs on-demand (EC2)

### Admin Approval Workflow

```
User creates config → Status: "pending_approval"
                           ↓
              Admin reviews in admin panel
                           ↓
         ┌─────────────────┴─────────────────┐
         ↓                                   ↓
    Approved                             Rejected
         ↓                                   ↓
  Task def registered              Status: "rejected"
  Status: "active"                 (with reason)
```

- Users can only use "active" configurations for jobs
- Admins can revoke approval at any time
- Rejected configs can be edited and resubmitted

### Task Definition Generation

- Lambda function registers task definitions from user configs using AWS SDK
- Triggered by admin approval (not user creation)
- Derived from base model task definitions (stored in SSM)
- Naming convention: `pdf-models-{model}-user-{config_id[:8]}`
- Task definition ARN stored in configuration record in DynamoDB

## Data Model

### New DynamoDB Table: `pdf-models-configurations`

```
Partition Key: config_id (UUID)
GSI: user_id-created_at-index (list user's configs)
GSI: is_public-model-index (discover public configs)
```

**Schema:**
```json
{
  "config_id": "uuid",
  "user_id": "cognito-user-id",
  "model": "marker|dolphin|...",
  "name": "My Custom Config",
  "description": "Optional",
  "created_at": "ISO8601",
  "updated_at": "ISO8601",

  "inference_params": {
    "prompt": "Custom prompt",
    "output_format": "markdown|json",
    "custom_env_vars": {"KEY": "value"}
  },

  "infra_params": {
    "cpu": 4096,
    "memory_mib": 16384,
    "gpu_count": 1,
    "timeout_minutes": 60,
    "ephemeral_storage_gib": 50,
    "ebs_volume_size_gb": 100,
    "spot_enabled": true
  },

  "approval_status": "pending_approval|approved|rejected",
  "approved_by": "admin-user-id",
  "approved_at": "ISO8601",
  "rejection_reason": "Optional reason if rejected",

  "task_definition_arn": "arn:aws:ecs:...",
  "task_definition_status": "pending|active|failed",

  "visibility": "private|public",
  "org_id": "future-org-id",

  "usage_count": 42,
  "forked_from": "original-config-id"
}
```

## API Design

### User Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/models/{model}/configs` | Create config (status: pending_approval) |
| GET | `/v1/models/{model}/configs` | List user's configs |
| GET | `/v1/models/{model}/configs/{config_id}` | Get config |
| PUT | `/v1/models/{model}/configs/{config_id}` | Update config (resets to pending_approval) |
| DELETE | `/v1/models/{model}/configs/{config_id}` | Delete config |
| POST | `/v1/models/{model}/configs/{config_id}/fork` | Copy config |
| GET | `/v1/configs/discover` | Browse public approved configs |

### Admin Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/admin/configs/pending` | List all pending approval configs |
| POST | `/v1/admin/configs/{config_id}/approve` | Approve config (triggers task def creation) |
| POST | `/v1/admin/configs/{config_id}/reject` | Reject config with reason |
| POST | `/v1/admin/configs/{config_id}/revoke` | Revoke previously approved config |

**Admin Authorization**: Cognito group membership (e.g., `pdf-models-admins` group)

### Modified Job Submission

```json
POST /v1/models/{model}/jobs
{
  "s3_input_key": "...",
  "config_id": "abc123",
  "start_processing": true
}
```

## Integration Flow

1. **Job submission** with `config_id`:
   - Fetch configuration from DynamoDB
   - Verify user access (owner, shared_with, or public)
   - Pass `config_id` to Step Functions input

2. **Step Functions ResolveTaskDef Lambda** (enhanced):
   - If `config_id` present, check for custom `task_definition_arn`
   - Otherwise use base model task definition from SSM
   - Merge `inference_params` into container environment overrides

3. **ECS Task runs** with appropriate task definition and environment variables

## Security & Constraints

### Parameter Validation (enforced by API)
- CPU: Fargate valid values (256-16384) or EC2 limits based on instance type
- Memory: Must match CPU for Fargate combinations
- GPU count: 0-4 depending on model/instance type
- Timeout: 1-180 minutes
- Ephemeral storage: 21-200 GiB (Fargate)
- EBS volume: 30-500 GiB (EC2)

### Admin Approval
- **All configurations require admin approval before use**
- Admins can see resource implications (cost estimate) before approving
- Admins can revoke approval if config is being misused
- Rejection includes reason so user can fix and resubmit

### User Limits
- Max 10 configs per model
- Max 50 total configs
- Pending configs count toward limits

### IAM
- Task definition Lambda uses scoped permissions with condition:
  `ecs:task-definition-family: pdf-models-*-user-*`
- Admin endpoints require Cognito group: `pdf-models-admins`

## Files to Modify

### Backend CDK
- `backend/backend/core_infrastructure_stack.py` - Add configs DynamoDB table, admin Cognito group
- `backend/backend/api_v2_stack.py` - Add user + admin API routes
- `backend/backend/model_stack.py` - Enhance ResolveTaskDef Lambda for config support

### Backend Lambdas (new, Rust)
- `backend/lambdas/config-crud/` - User configuration CRUD
- `backend/lambdas/config-admin/` - Admin approve/reject/revoke
- `backend/lambdas/register-task-def/` - Task definition registration (Python, for boto3 simplicity)

### Existing Lambdas
- `backend/lambdas/submit-job/src/main.rs` - Accept `config_id`, verify approval status

### Frontend
- `frontend/src/Types.elm` - Add Configuration, ApprovalStatus types
- `frontend/src/Api.elm` - Add config + admin API calls
- `frontend/src/Views/Configs.elm` - User config management
- `frontend/src/Views/AdminConfigs.elm` - Admin approval panel
- `frontend/src/Views/Upload.elm` - Config selector integration

## Implementation Phases

### Phase 1: Data Model & User CRUD
- Create configs DynamoDB table with GSIs
- Create config-crud Lambda (Rust) for user operations
- Add user API routes for config management
- Frontend: basic config list/create views

### Phase 2: Admin Approval Workflow
- Create admin Lambda for approve/reject/revoke
- Add admin API routes with Cognito group authorization
- Create register-task-def Lambda (triggered by approval)
- Frontend: admin approval panel
- Parameter validation logic

### Phase 3: Job Integration
- Modify submit-job to accept config_id (only approved configs)
- Enhance ResolveTaskDef Lambda to use config's task definition
- Pass inference_params as container environment overrides
- Frontend: config selector in upload flow

### Phase 4: Public Gallery & Sharing
- Public config discovery endpoint
- Fork/copy functionality
- Usage tracking
- Frontend: discover/browse public configs page

## Verification

1. **Unit tests**: Config CRUD, parameter validation, approval state transitions
2. **Integration tests**:
   - End-to-end: create config → admin approve → submit job with config
   - Rejection flow: create → reject → edit → resubmit → approve
3. **Manual testing**:
   - Frontend config creation and admin approval
   - Job submission with approved config
   - Attempt to use pending/rejected config (should fail)
4. **Cloud tests**: `make test-integration-cloud`

## Future Considerations

### Org/Team Support (not in initial implementation)
- Add `org_id` field to configs (already in schema)
- Create organizations table
- Org-level visibility: `"visibility": "org"`
- Team admins can approve configs within their org
- Requires: org/team management UI, invitation flow
