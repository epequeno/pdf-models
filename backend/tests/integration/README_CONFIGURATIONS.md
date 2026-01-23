# Configuration System Integration Tests

These tests validate the complete configuration management system including user CRUD operations, admin approval workflow, task definition registration, and job execution with custom configurations.

## Prerequisites

### 1. Admin User Setup

The configuration tests require an admin user account in addition to the regular test user. Create an admin user and add them to the `pdf-models-admins` Cognito group:

```bash
# Set your AWS profile
export AWS_PROFILE=arch

# Create admin user (if not already created)
aws cognito-idp admin-create-user \
  --user-pool-id us-east-1_wslqPOxQd \
  --username admin-test@pdf-models.local \
  --user-attributes Name=email,Value=admin-test@pdf-models.local Name=email_verified,Value=true \
  --temporary-password "TempPassword123!" \
  --message-action SUPPRESS

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id us-east-1_wslqPOxQd \
  --username admin-test@pdf-models.local \
  --password "AdminTest123!" \
  --permanent

# Add user to pdf-models-admins group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id us-east-1_wslqPOxQd \
  --username admin-test@pdf-models.local \
  --group-name pdf-models-admins
```

### 2. Environment Variables

Set the following environment variables before running tests:

```bash
# Regular test user (for user operations)
export TEST_USER_EMAIL="integration-test@pdf-models.local"
export TEST_USER_PASSWORD="TestPass123!"

# Admin user (for admin operations)
export ADMIN_USER_EMAIL="admin-test@pdf-models.local"
export ADMIN_USER_PASSWORD="AdminTest123!"

# AWS profile (required for SSM parameter lookups)
export AWS_PROFILE=arch
```

## Running Tests

### Run all configuration tests:

```bash
cd backend
uv run python -m pytest tests/integration/test_configurations_e2e.py -v
```

### Run specific test:

```bash
# Test full approval and job execution workflow
uv run python -m pytest tests/integration/test_configurations_e2e.py::TestConfigurationsEndToEnd::test_configuration_approval_and_job_execution -v

# Test unapproved config rejection
uv run python -m pytest tests/integration/test_configurations_e2e.py::TestConfigurationsEndToEnd::test_unapproved_config_cannot_be_used -v

# Test admin rejection workflow
uv run python -m pytest tests/integration/test_configurations_e2e.py::TestConfigurationsEndToEnd::test_admin_rejection_workflow -v
```

### Run with detailed output:

```bash
uv run python -m pytest tests/integration/test_configurations_e2e.py -v -s
```

## Test Coverage

### Test 1: Configuration Approval and Job Execution
**File**: `test_configuration_approval_and_job_execution`

This test validates the complete end-to-end workflow:

1. **User creates configuration** - POST `/v1/models/{model}/configs`
   - Custom CPU/memory parameters
   - Verifies status is `pending_approval`

2. **Admin lists pending configurations** - GET `/v1/admin/configs/pending`
   - Verifies new configuration appears in pending list

3. **Admin approves configuration** - POST `/v1/admin/configs/{config_id}/approve`
   - Triggers `register-task-def` Lambda
   - Verifies status changes to `approved`

4. **Task definition registration** - Automatic via Lambda
   - Polls for `task_definition_arn` to be populated
   - Verifies ARN format and status

5. **User uploads PDF to S3** - Direct S3 upload with Identity Pool credentials

6. **User submits job with config_id** - POST `/v1/models/{model}/jobs`
   - Includes approved `config_id` in request
   - Verifies job is created and starts processing

7. **Job completes successfully** - Polls job status
   - Verifies job uses custom task definition
   - Downloads and validates result

8. **Cleanup** - DELETE `/v1/models/{model}/configs/{config_id}`

### Test 2: Unapproved Config Cannot Be Used
**File**: `test_unapproved_config_cannot_be_used`

This test validates authorization checks:

1. User creates configuration (status: `pending_approval`)
2. User attempts to submit job with unapproved `config_id`
3. Verifies request is rejected (400/403 error)
4. Cleanup: deletes configuration

### Test 3: Admin Rejection Workflow
**File**: `test_admin_rejection_workflow`

This test validates the rejection flow:

1. User creates configuration
2. Admin rejects configuration with reason
3. Verifies configuration status is `rejected`
4. Verifies user can see rejection reason
5. Cleanup: deletes configuration

## Expected Results

All tests should pass, demonstrating:
- ✅ Users can create configurations
- ✅ Configurations start in `pending_approval` status
- ✅ Admins can list pending configurations
- ✅ Admins can approve/reject configurations
- ✅ Task definitions are registered on approval
- ✅ Jobs can use approved configurations
- ✅ Unapproved configurations cannot be used for jobs
- ✅ Users can see rejection reasons

## Troubleshooting

### "Admin user not found"
- Verify admin user exists in Cognito
- Check admin user is in `pdf-models-admins` group
- Verify ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD are set correctly

### "Task definition ARN not registered"
- Check `register-task-def` Lambda logs
- Verify Lambda has permissions to register task definitions
- Check DynamoDB for task_definition_status field

### "Configuration not approved"
- Verify admin approval succeeded
- Check configuration status in DynamoDB
- Review `config-admin` Lambda logs

### "Job submission failed with config_id"
- Verify configuration is in `approved` status
- Check `submit-job` Lambda logs for validation errors
- Verify user has access to the configuration (owner or public)

## AWS Resources

The tests interact with:
- **DynamoDB**: `pdf-models-configurations` table
- **Lambda Functions**:
  - `pdf-models-config-crud` - User CRUD operations
  - `pdf-models-config-admin` - Admin approve/reject/revoke
  - `pdf-models-register-task-def` - Task definition registration
  - `pdf-models-submit-job` - Job submission with config validation
- **ECS**: Custom task definitions (family: `pdf-models-{model}-user-{config_id}`)
- **Step Functions**: Model-specific state machines
- **Cognito**: `pdf-models-admins` group for authorization
