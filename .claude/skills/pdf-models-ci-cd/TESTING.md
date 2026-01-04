# Testing Strategy

Testing approaches for the pdf-models project.

## Test types

### Unit tests

**Location**: `backend/tests/`

**Run**:
```bash
make test
```

**Coverage**: Individual functions and classes

**Example**:
```python
def test_job_id_validation():
    assert is_valid_job_id("job-abc123")
    assert not is_valid_job_id("invalid")
```

**Characteristics**:
- Fast (< 1 second)
- No AWS dependencies
- Mock external services
- Run locally

### Integration tests

**Location**: `backend/tests/integration/`

**Run**:
```bash
make test-integration-auto
```

**Coverage**: Full API → Step Functions → ECS → S3 flow

**Characteristics**:
- Slower (2-3 minutes)
- Requires deployed AWS infrastructure
- Uses real AWS services
- Tests end-to-end workflows

**Test scenarios**:
1. **Unauthorized access**: Verify 401 for missing auth
2. **List jobs** (empty): Verify user can list their jobs
3. **Submit job**: Upload PDF, submit job, verify created
4. **Get job status**: Retrieve job details
5. **Wait for completion**: Poll until job completes
6. **Verify output**: Check output file in S3

### Manual tests

**When**: After major changes or before releases

**Checklist**:
- [ ] Upload various PDF types (text, scanned, mixed)
- [ ] Test large PDFs (>100 pages)
- [ ] Test concurrent job submissions
- [ ] Verify error handling (invalid inputs)
- [ ] Check CloudWatch logs for warnings
- [ ] Monitor resource usage (CPU, memory)

## Integration test setup

### Prerequisites

1. **Deployed infrastructure**: All stacks deployed
2. **Cognito user pool**: Created by CoreInfrastructureStack
3. **Test user**: Created by test setup script

### Creating test user

**Automatic** (recommended):
```bash
make test-integration-setup
```

This creates:
- Email: `integration-test@pdf-models.local`
- Password: `TestPass123!`
- Confirmed: Yes

**Manual**:
```bash
cd backend
AWS_PROFILE=arch uv run python tests/integration/setup_test_user.py
# Enter email and password when prompted
```

### Environment variables

Set before running tests:
```bash
export TEST_USER_EMAIL="integration-test@pdf-models.local"
export TEST_USER_PASSWORD="TestPass123!"
```

Or use `make test-integration-auto` which sets them automatically.

## Test execution flow

### Integration test flow

```
1. Setup
   ├─ Create test user (if not exists)
   ├─ Set environment variables
   └─ Initialize pytest

2. Test: Unauthenticated access
   ├─ GET /models/marker/jobs (no auth header)
   ├─ Expect: 401 Unauthorized
   └─ Pass/Fail

3. Test: Authenticate
   ├─ Call Cognito InitiateAuth
   ├─ Get access token
   └─ Store for subsequent requests

4. Test: List jobs (empty)
   ├─ GET /models/marker/jobs (with auth)
   ├─ Expect: 200, empty array
   └─ Pass/Fail

5. Test: Submit job
   ├─ Create test PDF file
   ├─ Upload to S3
   ├─ POST /models/marker/jobs (s3_input_key=...)
   ├─ Expect: 201, job_id returned
   ├─ Verify job in DynamoDB
   ├─ Verify Step Functions execution started
   └─ Pass/Fail

6. Test: Get job status
   ├─ GET /models/marker/jobs/{job_id}
   ├─ Expect: 200, job details
   ├─ Verify status (processing or completed)
   └─ Pass/Fail

7. Test: Wait for completion (optional)
   ├─ Poll GET /models/marker/jobs/{job_id}
   ├─ Wait until status = "completed"
   ├─ Max wait: 10 minutes
   ├─ Verify output in S3
   └─ Pass/Fail

8. Cleanup
   ├─ Delete test files from S3
   ├─ Delete test job from DynamoDB (optional)
   └─ Report results
```

## Test data

### Test PDF files

**Location**: `backend/tests/integration/test-files/`

**Types**:
- `simple.pdf` - Text-based, 1 page
- `multi-page.pdf` - Multiple pages
- `scanned.pdf` - Scanned document (requires OCR)

**Create test PDF programmatically**:
```python
from reportlab.pdfgen import canvas

def create_test_pdf(filename, text):
    c = canvas.Canvas(filename)
    c.drawString(100, 750, text)
    c.save()
```

### Test user credentials

**Email**: Must be valid format but doesn't need real inbox

**Password**: Must meet Cognito requirements:
- Minimum 8 characters
- Contains uppercase
- Contains lowercase
- Contains number

**Example**: `TestPass123!`

## Debugging failing tests

### Test fails: Unauthenticated access

**Symptom**: Expected 401, got 500 or other

**Diagnosis**:
- Check Lambda authorizer logs
- Verify Cognito User Pool exists
- Check API Gateway integration

### Test fails: Submit job returns 500

**Symptom**: POST /jobs returns 500 error

**Diagnosis**:
1. Check Lambda logs:
   ```bash
   AWS_PROFILE=arch aws logs tail /aws/lambda/pdf-models-submit-job --since 5m
   ```

2. Common causes:
   - DynamoDB table not found
   - S3 access denied
   - Step Functions state machine not found
   - Invalid input validation

### Test fails: Job never completes

**Symptom**: Test times out waiting for completion

**Diagnosis**:
1. Check job status manually:
   ```bash
   AWS_PROFILE=arch aws dynamodb get-item \
     --table-name pdf-models-jobs \
     --key '{"job_id": {"S": "job-xxx"}}'
   ```

2. Check Step Functions execution:
   ```bash
   python .claude/skills/aws-stepfunctions-debugging/scripts/get_execution.py <exec-name>
   ```

3. Check ECS task logs:
   ```bash
   AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m
   ```

4. Common causes:
   - Container crashed
   - S3 access denied
   - Task definition not found
   - Insufficient memory/CPU

### Test fails: Access denied

**Symptom**: 403 errors during test

**Diagnosis**:
- Check API Gateway authorizer
- Verify test user has valid token
- Check IAM roles for Lambda/ECS
- Verify S3 bucket policies

## Continuous testing strategy

### When to run tests

**Unit tests**:
- Before every commit (pre-commit hook)
- On every push (CI pipeline)
- During development (watch mode)

**Integration tests**:
- After infrastructure changes
- After container/Lambda builds
- Before releases
- Nightly (automated)

### Test environment

**Options**:

**1. Single environment (current)**
- Pros: Simple, cost-effective
- Cons: Tests affect production data

**2. Separate test environment**
- Pros: Isolated testing, safe
- Cons: Higher cost, maintenance overhead

**3. Per-branch environments**
- Pros: Parallel testing, no conflicts
- Cons: Complex setup, high cost

**Recommendation**: Start with single environment, add separate test environment when team grows.

## Test coverage goals

**Unit tests**: 70%+ coverage
- Core business logic: 90%+
- Utils and helpers: 80%+
- Integration code: 50%+

**Integration tests**: Critical paths
- Submit job → completion
- List jobs
- Get job status
- Error scenarios (auth, permissions)

**Manual tests**: Edge cases
- Large files
- Concurrent requests
- Error recovery
- Performance testing

## Test assertions

### API response assertions

```python
# Status code
assert response.status_code == 200

# Response structure
data = response.json()
assert "job_id" in data
assert data["status"] in ["pending", "processing", "completed", "failed"]

# Type validation
assert isinstance(data["job_id"], str)
assert data["job_id"].startswith("job-")
```

### AWS resource assertions

```python
# DynamoDB item exists
item = dynamodb.get_item(Key={"job_id": job_id})
assert "Item" in item

# S3 object exists
s3.head_object(Bucket=bucket, Key=key)

# Step Functions execution started
executions = sfn.list_executions(stateMachineArn=arn)
assert len(executions["executions"]) > 0
```

### Log assertions

```python
# Check logs for specific message
logs = cloudwatch_logs.filter_log_events(
    logGroupName="/ecs/pdf-models-marker",
    startTime=start_time,
    filterPattern="Successfully processed"
)
assert len(logs["events"]) > 0
```

## Performance testing

### Load testing

**Tool**: Locust, k6, or Apache Bench

**Scenarios**:
1. **Sustained load**: 10 req/sec for 5 minutes
2. **Spike**: 100 req/sec for 1 minute
3. **Gradual increase**: Ramp from 1 to 50 req/sec

**Metrics to monitor**:
- Response time (p50, p95, p99)
- Error rate
- Throughput
- Resource utilization (CPU, memory)

### Example load test

```python
# Using Locust
from locust import HttpUser, task, between

class PdfModelsUser(HttpUser):
    wait_time = between(1, 3)

    @task
    def list_jobs(self):
        self.client.get("/models/marker/jobs",
            headers={"Authorization": f"Bearer {self.token}"})

    @task(3)  # 3x more frequent
    def submit_job(self):
        self.client.post("/models/marker/jobs",
            json={"s3_input_key": "test.pdf"},
            headers={"Authorization": f"Bearer {self.token}"})
```

Run:
```bash
locust -f loadtest.py --host=https://api.example.com
```

## Test reporting

### Pytest output

```bash
# Verbose output
make test -v

# With coverage
cd backend && uv run pytest --cov=. --cov-report=html

# JUnit XML for CI
cd backend && uv run pytest --junitxml=test-results.xml
```

### Integration test report

```bash
# Run with output capture
make test-integration-auto 2>&1 | tee test-results.log

# Check results
echo $?  # 0 = passed, non-zero = failed
```

### CI integration (future)

```yaml
# GitHub Actions example
- name: Run integration tests
  run: make test-integration-auto
  env:
    AWS_PROFILE: arch
    TEST_USER_EMAIL: ${{ secrets.TEST_USER_EMAIL }}
    TEST_USER_PASSWORD: ${{ secrets.TEST_USER_PASSWORD }}
```
