# Integration Tests

End-to-end integration tests for the pdf-models API. These tests validate the complete workflow from PDF upload through processing to result download.

## Overview

The integration test suite validates:
- **Authentication**: Cognito user pool and identity pool integration
- **API Endpoints**: Job submission, status polling, and listing
- **S3 Operations**: Upload input PDFs and download results
- **Processing Pipeline**: Step Functions orchestration and Fargate task execution
- **Authorization**: User-scoped access control

## Quick Start

### 1. Install Dependencies

```bash
cd backend
uv sync
```

This installs all required dependencies including:
- `boto3` - AWS SDK for Python
- `requests` - HTTP client for API calls
- `pytest` - Testing framework

### 2. Create Test User

Run the setup script to create a Cognito test user:

```bash
make test-integration-setup
```

This will prompt you for:
- Test user email address
- Password (minimum 8 characters)

The script will:
- Create the user in Cognito User Pool
- Set a permanent password
- Verify authentication works
- Generate a `.env.test` template file

### 3. Set Environment Variables

Export the test user credentials:

```bash
export TEST_USER_EMAIL="test@example.com"
export TEST_USER_PASSWORD="your-password"
```

Or edit and source the generated `.env.test` file:

```bash
# Edit the file first to add your password
source backend/tests/integration/.env.test
```

### 4. Run Tests

```bash
make test-integration
```

## Test Files

### Core Test Suite

- **`test_marker_e2e.py`** - End-to-end workflow tests
  - `test_submit_and_process_pdf` - Complete PDF processing workflow
  - `test_list_jobs` - Job listing functionality
  - `test_unauthorized_access_to_other_user_job` - Authorization checks
  - `test_invalid_s3_key_rejected` - Input validation

### Test Infrastructure

- **`conftest.py`** - Pytest fixtures and configuration
  - Authentication fixtures (tokens, credentials)
  - AWS client fixtures (S3, DynamoDB, Step Functions)
  - Cleanup fixtures (auto-cleanup S3/DynamoDB)

- **`auth_helper.py`** - API client and utilities
  - `APIClient` - Type-safe API client with authentication
  - `wait_for_job_completion()` - Poll job status until completion

- **`setup_test_user.py`** - One-time setup script
  - Creates Cognito test user
  - Verifies authentication
  - Generates environment template

### Test Fixtures

- **`fixtures/test.pdf`** - Sample PDF for testing

## Test Workflow

The main end-to-end test (`test_submit_and_process_pdf`) executes this workflow:

```
1. Upload PDF to S3
   ↓
2. Submit job via API (POST /v1/models/marker/jobs)
   ↓
3. Verify job created (status: pending)
   ↓
4. Poll for completion (GET /v1/models/marker/jobs/{job_id})
   ↓
5. Download result from S3
   ↓
6. Validate markdown output
   ↓
7. Cleanup (delete S3 files and DynamoDB records)
```

## Configuration

Default configuration (can be overridden with environment variables):

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region |
| `COGNITO_USER_POOL_ID` | `us-east-1_0Puc2vOAn` | Cognito User Pool ID |
| `COGNITO_CLIENT_ID` | `3a9qpq5sb48plnt6eg52t26ula` | Cognito App Client ID |
| `COGNITO_IDENTITY_POOL_ID` | `us-east-1:725ee04f-7250-4862-9158-de9fa49ef895` | Cognito Identity Pool ID |
| `API_BASE_URL` | `https://ivd1t6g04g.execute-api.us-east-1.amazonaws.com/v1` | API Gateway URL |
| `S3_BUCKET` | `pdf-models-docs-496830984285` | S3 bucket name |
| `DYNAMODB_TABLE` | `pdf-models-jobs` | DynamoDB table name |
| `TEST_USER_EMAIL` | *(required)* | Test user email |
| `TEST_USER_PASSWORD` | *(required)* | Test user password |

## Running Individual Tests

Run a specific test:

```bash
cd backend
uv run pytest tests/integration/test_marker_e2e.py::TestMarkerEndToEnd::test_submit_and_process_pdf -v -s
```

Run with verbose output:

```bash
make test-integration
```

The `-s` flag shows print statements in real-time, useful for monitoring job progress.

## Cleanup

The test suite automatically cleans up resources after each test:

- **S3 objects**: Input PDFs and result files are deleted
- **DynamoDB records**: Test job records are removed

Cleanup is registered using pytest fixtures:
- `cleanup_s3_keys` - Tracks S3 keys to delete
- `cleanup_dynamodb_jobs` - Tracks job IDs to delete

If a test fails, cleanup still runs to prevent resource leaks.

## Troubleshooting

### Authentication Errors

**Error**: `User not found` or `Authentication failed`

**Solution**:
1. Verify test user exists: Run `make test-integration-setup`
2. Check credentials are set: `echo $TEST_USER_EMAIL`
3. Verify password is correct

### Permission Errors

**Error**: `Access Denied` when accessing S3 or DynamoDB

**Solution**:
1. Ensure `AWS_PROFILE=arch` is set (Makefile handles this)
2. Verify your AWS credentials have necessary permissions
3. Check that Identity Pool is configured correctly

### Job Timeout

**Error**: `TimeoutError: Job did not complete within 600 seconds`

**Solution**:
1. Check CloudWatch logs for Fargate task failures
2. Verify Step Functions execution: `make aws-stepfunctions-list`
3. Increase timeout in `wait_for_job_completion()` if needed

### Missing Test PDF

**Error**: `Test PDF not found at fixtures/test.pdf`

**Solution**:
```bash
cp test.pdf backend/tests/integration/fixtures/
```

## CI/CD Integration

These tests can be run in CodeBuild for automated testing.

### Local CodeBuild Simulation

Run tests with same environment as CodeBuild:

```bash
cd backend
AWS_PROFILE=arch uv run pytest tests/integration/ -v -s
```

### Future: CodeBuild Project

Create a CodeBuild project that:
1. Triggers on API stack deployments
2. Runs integration tests
3. Reports results to CloudWatch
4. Fails deployment if tests fail

## Adding New Tests

To add a new integration test:

1. **Create test file** in `tests/integration/`
2. **Use fixtures** from `conftest.py` for authentication and clients
3. **Register cleanup** using `cleanup_s3_keys` and `cleanup_dynamodb_jobs`
4. **Follow naming convention**: `test_*.py` for files, `test_*` for functions

Example:

```python
def test_my_feature(
    config,
    auth_tokens,
    s3_client,
    cleanup_s3_keys,
    cleanup_dynamodb_jobs,
):
    # Setup
    api_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

    # Test logic
    result = api_client.submit_job("marker", "my-file.pdf")

    # Register cleanup
    cleanup_dynamodb_jobs.append(result["job_id"])

    # Assertions
    assert result["status"] == "pending"
```

## Test Coverage

Current test coverage:

- ✅ User authentication (Cognito User Pool)
- ✅ AWS credential exchange (Identity Pool)
- ✅ S3 upload with scoped credentials
- ✅ Job submission via API
- ✅ Job status polling
- ✅ Job listing
- ✅ Result download from S3
- ✅ Authorization (user-scoped access)
- ✅ Input validation
- ⏳ Error handling (partial)
- ⏳ Rate limiting (not implemented)
- ⏳ Large file handling (not implemented)

## Performance

Expected test durations:
- **Full E2E test**: 5-10 minutes (includes Fargate cold start)
- **List jobs test**: < 5 seconds
- **Authorization tests**: < 5 seconds

Total suite runtime: ~10-15 minutes

## Security Notes

- Test user has same permissions as production users (scoped to their S3 prefix)
- Credentials should be stored securely (use environment variables, not committed files)
- `.env.test` is git-ignored to prevent credential leaks
- Test cleanup ensures no data persists between runs

## Related Documentation

- [Architecture Documentation](../../docs/architecture.md) - System design and patterns
- [API Documentation](../../docs/api.md) - API endpoint specifications (if exists)
- [AGENTS.md](../../../AGENTS.md) - AI agent development guide
