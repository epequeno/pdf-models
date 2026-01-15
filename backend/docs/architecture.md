# PDF Models - Architecture Documentation

## Overview

PDF Models is a serverless models-as-a-service platform for hosting open-source document processing models. The platform provides API access to document processing capabilities, allowing developers to integrate ML models without managing infrastructure.

**Use Case**: Processing public sector RFI/RFO/RFQ documents
**Model Comparisons**: https://idp-leaderboard.org/

## Architecture Principles

### 1. Serverless First
- Prefer pay-per-use compute (Lambda, Fargate on-demand)
- Avoid persistent compute resources (RDS, EC2, ALB, NAT gateways)
- Cost optimization during development while maintaining scalability

### 2. SageMaker is Prohibited
- SageMaker requires persistent compute, violating serverless principle
- Production-grade features not required for MVP/POC
- Fargate provides sufficient model hosting capabilities

### 3. AWS-Only CI/CD
- **Nothing runs on developer's local machine** for AWS operations
- All builds, deployments, and AWS interactions happen in CodeBuild/CodePipeline
- Ensures hermetic, reproducible builds from day one
- Anti-patterns: local scripts modifying AWS resources, local container builds, local server processes

**🚨 CRITICAL: CodeCommit is Source of Truth**
- CodeBuild pulls code from CodeCommit repository, NOT from local files
- Lambda code changes MUST be committed and pushed to CodeCommit before rebuilding
- Local file edits are invisible to CodeBuild - you can rebuild 100 times and Lambda won't update
- Workflow: `git commit && git push` → trigger CodeBuild → redeploy stack
- This is the #1 most common mistake during development

### 4. Transparency Philosophy
- Behave as a thin infrastructure layer over models
- Return model outputs with minimal transformation
- Users should experience near-identical behavior to self-hosted models
- Avoid custom business logic that obscures model behavior

### 5. Clean Stack Separation
- Stacks separated by resource lifecycle and change frequency
- Use SSM Parameter Store (not CloudFormation exports) for cross-stack communication
- Enables independent stack updates and deletions

## System Architecture

### High-Level Flow

```
User Authentication & File Upload:
1. User authenticates with Cognito User Pool → JWT tokens
2. User exchanges JWT for Identity Pool credentials → AWS credentials
3. User uploads PDF to S3 using Identity Pool credentials → s3://bucket/identity-id/file.pdf

Job Processing:
4. User submits job via API with S3 key → Lambda validates & creates DynamoDB record
5. Lambda starts Step Functions execution → ECS Fargate task processes PDF
6. ECS task downloads from S3, runs Marker model, uploads result to S3
7. Step Functions updates DynamoDB with completion status
8. User polls API for status and downloads result from S3
```

### Authentication Architecture

**Two-Layer Authentication System:**

1. **API Authentication**: Cognito User Pool JWT tokens
   - Used for API Gateway authorization
   - User ID format: `74f87488-6071-7034-6f34-e23c3bca23fa` (UUID)

2. **S3 Access Control**: Cognito Identity Pool credentials  
   - Used for direct S3 access (upload/download)
   - Identity ID format: `us-east-1:73ad6f30-5d77-c234-4c31-379685de07c5`

**Key Insight**: These are different identifiers! S3 access is controlled by Identity Pool ID, not Cognito User ID. Lambda functions do NOT validate S3 key prefixes - this is handled by S3 IAM permissions.

**IAM Policy Example**:
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::bucket/${cognito-identity.amazonaws.com:sub}/*"
}
```

This ensures users can only access files with their Identity Pool ID as the prefix.
User Authentication
    ↓
[Cognito User Pool] → [Cognito Identity Pool] → Temporary AWS Credentials
    ↓
User Uploads PDF
    ↓
[S3: user-scoped prefix] ← Direct upload using temporary credentials
    ↓
User Submits Job
    ↓
[API Gateway] → [Rust Lambda: API Handler]
    ↓
[DynamoDB: Job metadata] + [Step Functions: Start execution]
    ↓
[Step Functions State Machine]
    ├─ Validate Job
    ├─ Launch Fargate Task (ECS RunTask)
    ├─ Wait for Completion
    └─ Update Job Status
    ↓
[Fargate Task: Marker Container]
    ├─ Download PDF from S3
    ├─ Run Marker (PDF → Markdown)
    ├─ Upload result to S3
    └─ Update DynamoDB
    ↓
User Polls Status
    ↓
[API Gateway] → [Rust Lambda] → [DynamoDB: Query]
    ↓
User Downloads Result
    ↓
[S3: Direct download using temporary credentials]
```

## Components

### Authentication & Authorization

**Cognito User Pool**
- Handles user authentication (username/password, JWT tokens)
- Provides identity for API Gateway authorizers

**Cognito Identity Pool**
- Exchanges User Pool JWT for temporary AWS credentials
- IAM role with scoped S3 permissions:
  ```json
  {
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject"],
    "Resource": ["arn:aws:s3:::pdf-models-docs/${cognito-identity.amazonaws.com:sub}/*"]
  }
  ```
- Users automatically isolated to their own S3 prefix

### Storage

**S3 Bucket Structure**
```
pdf-models-docs/
  ${user-id}/              # Cognito identity ID
    ${job-id}.pdf          # Input document
    ${job-id}-result.md    # Output markdown
```

**Lifecycle Policy**: Delete objects after 7 days

**DynamoDB Table: jobs**
```
Partition Key: job_id (String, UUID)
Attributes:
  - user_id (String)
  - model (String, e.g., "marker")
  - status (String: pending | processing | completed | failed)
  - s3_input_key (String)
  - s3_result_key (String)
  - created_at (String, ISO8601)
  - completed_at (String, ISO8601)
  - error (String, optional)

Global Secondary Index: user_id-created_at-index
  - Partition Key: user_id
  - Sort Key: created_at
  - Use: Query all jobs for a user
```

### API Layer

**API Gateway**
- REST API with Cognito User Pool authorizer
- Routes requests to Rust Lambda handlers
- Validates JWT tokens and extracts user identity

**Endpoints**
- `POST /v1/models/{model}/jobs` - Submit new job
- `GET /v1/models/{model}/jobs/{job_id}` - Get job status
- `GET /v1/models/{model}/jobs` - List user's jobs (optional)

**Rust Lambda Functions**
- Self-contained binaries (no runtime dependencies)
- Clean separation from CDK Python dependencies
- Handles:
  - Request validation
  - DynamoDB operations
  - Step Functions execution starts
  - Response formatting

**Why Rust over Python for Lambda?**
- Avoids dependency conflicts between Lambda runtime and CDK
- Self-contained binaries
- Fast cold starts
- Clean dependency boundaries

### Orchestration

**Step Functions State Machine (per model)**

**Query Language**: JSONata (preferred over JSONPath for better readability and expressiveness)

```json
{
  "QueryLanguage": "JSONata",
  "StartAt": "ValidateJob",
  "States": {
    "ValidateJob": {
      "Type": "Task",
      "Comment": "Verify S3 file exists and job is valid",
      "Next": "LaunchFargateTask"
    },
    "LaunchFargateTask": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "Cluster": "...",
        "TaskDefinition": "...",
        "LaunchType": "FARGATE",
        "Overrides": {
          "ContainerOverrides": [{
            "Name": "marker",
            "Environment": [
              {"Name": "JOB_ID", "Value": "{% $$.Execution.Input.job_id %}"},
              {"Name": "S3_INPUT_KEY", "Value": "{% $$.Execution.Input.s3_input_key %}"}
            ]
          }]
        }
      },
      "Next": "UpdateJobStatus"
    },
    "UpdateJobStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "End": true
    }
  }
}
```

**Benefits**
- Built-in retry logic
- Error handling
- Execution visibility
- Standard AWS pattern
- Prepares for more complex workflows
- **JSONata**: More expressive transformations, easier to read than JSONPath

### Parameterized Pipeline Design

**Key Innovation**: The system uses a parameterized approach to eliminate caching issues between container builds and deployments.

**Problem Solved**: Previously, Step Functions state machines had hardcoded task definition ARNs, causing new container images to be ignored until infrastructure was redeployed.

**Solution**: Dynamic task definition resolution at execution time:

1. **Lambda Resolver**: A Lambda function reads the current task definition ARN from SSM Parameter Store
2. **Two-Step Execution**: 
   - Step 1: Resolve current task definition ARN
   - Step 2: Use resolved ARN in ECS RunTask
3. **Wildcard IAM Permissions**: Policies allow any task definition revision:
   ```
   arn:aws:ecs:region:account:task-definition/pdf-models-marker:*
   ```

**Result**: Container updates are immediately available without redeploying Step Functions infrastructure.

### Compute

**Fargate Tasks (per model)**

**On-Demand Execution**
- No persistent running tasks
- Launch via Step Functions `ecs:runTask`
- Task runs, processes job, exits
- True pay-per-use model

**Trade-offs**
- Cold start: ~30 seconds (container start + model loading from pre-downloaded cache)
- Acceptable for async processing
- Network: Uses public subnets for ECR access (no NAT Gateway required)
- Container size: ~1.5GB (includes pre-downloaded ML models)
- Can optimize later with warm pools if needed

**Marker Task Configuration**
```
CPU: 2 vCPU
Memory: 8GB
Platform: Linux/x86_64
Network: awsvpc (Fargate requirement)
```

**Task IAM Role Permissions**
- S3: GetObject (input), PutObject (result)
- DynamoDB: UpdateItem (job status)
- CloudWatch Logs: PutLogEvents

**Container Structure**
```dockerfile
FROM python:3.11-slim

# Install system dependencies for Marker
RUN apt-get update && apt-get install -y \
    libgomp1 libglib2.0-0 libsm6 libxext6 \
    libxrender-dev libgl1 && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user and directories
RUN useradd -m -u 1000 appuser && \
    mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

# Install Python dependencies
RUN pip install --no-cache-dir pypdfium2 marker-pdf boto3

COPY task.py /app/task.py
WORKDIR /app

# Set environment variables for writable directories
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static

USER appuser

# 🚀 PERFORMANCE OPTIMIZATION: Pre-download models at build time
# This downloads ~1.34GB of Marker models during container build
# instead of downloading them at runtime, eliminating 1+ minute delay
RUN python -c "from marker.models import create_model_dict; create_model_dict()" && \
    echo "Models pre-downloaded successfully"

ENTRYPOINT ["python", "task.py"]
```

**Performance Optimization Details**:
- **Before**: Container downloaded 1.34GB of ML models at runtime (1+ minute delay per job)
- **After**: Models pre-downloaded during build and baked into container image
- **Result**: Jobs start processing immediately, reducing execution time from 10+ minutes to ~30 seconds
- **Trade-off**: Larger container image (~1.5GB) but much faster job execution

**task.py Responsibilities**
```python
# 1. Read environment variables
job_id = os.environ['JOB_ID']
s3_input_key = os.environ['S3_INPUT_KEY']
bucket = os.environ['S3_BUCKET']
table = os.environ['DYNAMODB_TABLE']

# 2. Download PDF from S3
# 3. Load pre-downloaded Marker models (instant - no download)
# 4. Run Marker: pdf → markdown
# 5. Upload result to S3
# 6. Update DynamoDB: status=completed, result_s3_key
```

### CI/CD

**CodeBuild Projects**

The system uses AWS CodeBuild for building containers and Lambda functions. Builds are **triggered manually** to avoid wasting build time on unrelated code changes (this is a monorepo).

**CodeBuild: pdf-models-marker-container-build**
- **Trigger**: Manual only
- **Source**: CodeCommit `backend/containers/marker/`
- **Build Spec**: `backend/containers/marker/buildspec.yml`
- **Purpose**: Build Marker container with pre-downloaded models
- **Compute**: X_LARGE (32GB) - required for downloading 1.34GB of ML models
- **Steps**:
  1. Build Docker image with model pre-downloading
  2. Tag: `pdf-models/marker:latest`
  3. Push to ECR
  4. Update SSM parameter with image digest
- **How to Trigger**:
  ```bash
  AWS_PROFILE=arch aws codebuild start-build --project-name pdf-models-marker-container-build
  ```
- **Monitor Build**:
  ```bash
  # Check status
  AWS_PROFILE=arch aws codebuild batch-get-builds \
    --ids pdf-models-marker-container-build:<build-id> \
    --query 'builds[0].[buildStatus,currentPhase]'

  # Tail logs
  AWS_PROFILE=arch aws logs tail /aws/codebuild/pdf-models-marker-container-build --follow
  ```

**CodeBuild: pdf-models-rust-lambda-builder-build**
- **Trigger**: Manual only
- **Source**: CodeCommit `backend/containers/rust-lambda-builder/`
- **Purpose**: Build base image with Rust and cargo-lambda pre-installed
- **Rarely needs rebuilding** (only when Rust/cargo-lambda versions change)

**CodeBuild: pdf-models-rust-lambda-build**
- **Trigger**: Manual only
- **Source**: CodeCommit `backend/lambdas/`
- **Purpose**: Build Rust Lambda functions using the builder base image
- **Outputs**: Uploads compiled Lambda .zip files to S3

**Why Manual Triggers?**
- Avoids wasting build resources on commits unrelated to containers/lambdas
- Container builds are expensive (X_LARGE instance, 10+ minute builds)
- Most commits change CDK infrastructure, not containers
- Explicit triggering makes intent clear

**Container Registry**
- ECR repositories (one per model)
- Repository: `pdf-models/marker`
- Images tagged with `:latest` and digest stored in SSM

## CDK Stack Organization

### Stack Separation by Lifecycle

**Stack 1: FoundationStack**
- **Change Frequency**: Rare
- **Replaceability**: Hard (DNS propagation, certificate validation)
- **Resources**:
  - Route53 Hosted Zone (if custom domain)
  - ACM Certificates
  - ECR Repositories
- **SSM Exports**:
  - `/pdf-models/foundation/ecr-repo-uri-marker`
  - `/pdf-models/foundation/hosted-zone-id`
  - `/pdf-models/foundation/certificate-arn`

**Stack 2: CoreInfrastructureStack**
- **Change Frequency**: Occasional
- **Replaceability**: Moderate (data loss risk)
- **Resources**:
  - Cognito User Pool
  - Cognito Identity Pool
  - S3 Bucket (documents + results)
  - DynamoDB Table (jobs)
  - Core IAM Roles
- **SSM Exports**:
  - `/pdf-models/core/s3-bucket-name`
  - `/pdf-models/core/dynamodb-table-name`
  - `/pdf-models/core/cognito-user-pool-id`
  - `/pdf-models/core/cognito-identity-pool-id`

**Stack 3: MarkerStack** (per-model pattern)
- **Change Frequency**: Frequent (model updates, tuning)
- **Replaceability**: Easy (stateless compute)
- **Resources**:
  - ECS Cluster (can be shared)
  - ECS Task Definition (Marker)
  - Step Functions State Machine
  - CloudWatch Log Groups
  - Task IAM Roles
- **SSM Exports**:
  - `/pdf-models/models/marker/task-definition-arn`
  - `/pdf-models/models/marker/step-function-arn`
  - `/pdf-models/models/marker/cluster-name`

**Stack 4: ApiStack**
- **Change Frequency**: Moderate
- **Replaceability**: Easy (stateless)
- **Resources**:
  - API Gateway REST API
  - Rust Lambda Functions (API handlers)
  - Lambda IAM Roles
  - API Gateway Cognito Authorizers
- **SSM Imports**:
  - DynamoDB table name
  - Step Functions ARNs
  - Cognito User Pool ID

**Stack 5: CiCdStack**
- **Change Frequency**: Rare
- **Replaceability**: Easy
- **Resources**:
  - CodeBuild Projects (per model container)
  - Build artifact S3 buckets
  - CodeBuild IAM Roles
- **SSM Imports**:
  - ECR repository URIs

### Stack Dependencies

```
FoundationStack
    ↓ (SSM)
CoreInfrastructureStack
    ↓ (SSM)
    ├─→ MarkerStack
    └─→ ApiStack

CiCdStack (independent, reads Foundation SSM)
```

**Deployment Order**
1. `cdk deploy FoundationStack`
2. `cdk deploy CoreInfrastructureStack`
3. `cdk deploy MarkerStack`
4. `cdk deploy ApiStack`
5. `cdk deploy CiCdStack` (anytime, independent)

**Key Principle**: Stacks read from SSM, never import CloudFormation exports. This allows independent updates and deletions.

## SSM Parameter Strategy

### Naming Convention

```
/pdf-models/{category}/{resource-identifier}
```

**Examples**
```
# Foundation
/pdf-models/foundation/ecr-repo-uri-marker
/pdf-models/foundation/hosted-zone-id
/pdf-models/foundation/certificate-arn

# Core
/pdf-models/core/s3-bucket-name
/pdf-models/core/dynamodb-table-name
/pdf-models/core/cognito-user-pool-id
/pdf-models/core/cognito-identity-pool-id

# Model-specific
/pdf-models/models/marker/task-definition-arn
/pdf-models/models/marker/step-function-arn
/pdf-models/models/marker/cluster-name
```

### Usage Pattern

**Writing to SSM (in CDK)**
```python
from aws_cdk import aws_ssm as ssm

# In CoreInfrastructureStack
ssm.StringParameter(self, "S3BucketParam",
    parameter_name="/pdf-models/core/s3-bucket-name",
    string_value=bucket.bucket_name
)
```

**Reading from SSM (in CDK)**
```python
# In MarkerStack
bucket_name = ssm.StringParameter.value_from_lookup(
    self, "/pdf-models/core/s3-bucket-name"
)
```

**Benefits**
- ✅ Loose coupling between stacks
- ✅ Can delete/recreate stacks independently
- ✅ Clear data flow
- ✅ No CloudFormation export/import dependencies

## Data Flow: End-to-End

### 1. User Authentication
```
User → Cognito User Pool
  ↓ (JWT token)
User → Cognito Identity Pool
  ↓ (temporary AWS credentials)
User has scoped S3 access: s3://bucket/${user-id}/*
```

### 2. Document Upload
```
User (with temp credentials) → S3
  Uploads: s3://pdf-models-docs/${user-id}/${job-id}.pdf
```

### 3. Job Submission
```
User → POST /v1/models/marker/jobs
  Headers: Authorization: Bearer ${jwt-token}
  Body: {
    "s3_key": "${user-id}/${job-id}.pdf",
    "config": {}
  }
  ↓
API Gateway (Cognito authorizer validates JWT)
  ↓
Rust Lambda Handler:
  1. Extract user_id from JWT claims
  2. Generate job_id (UUID)
  3. Validate s3_key starts with user_id (authorization)
  4. Write to DynamoDB:
     {
       "job_id": "...",
       "user_id": "...",
       "model": "marker",
       "status": "pending",
       "s3_input_key": "...",
       "created_at": "..."
     }
  5. Start Step Functions execution:
     Input: {job_id, s3_input_key, s3_bucket, dynamodb_table}
  ↓
Response: {"job_id": "...", "status": "pending"}
```

### 4. Processing
```
Step Functions State Machine
  ↓
State: LaunchFargateTask
  ECS RunTask (sync wait)
  ↓
Fargate Task Starts
  Container: marker:latest
  Environment: {JOB_ID, S3_INPUT_KEY, S3_BUCKET, DYNAMODB_TABLE}
  ↓
task.py:
  1. Download PDF from S3
  2. Run Marker: convert_single_pdf(pdf_path) → markdown
  3. Upload markdown to S3: ${user-id}/${job-id}-result.md
  4. Update DynamoDB:
     status = "completed"
     s3_result_key = "${user-id}/${job-id}-result.md"
     completed_at = now()
  5. Exit (task terminates)
  ↓
Step Functions: Task completion detected
  ↓
State: UpdateJobStatus (if needed)
  ↓
Execution Complete
```

### 5. Status Polling
```
User → GET /v1/models/marker/jobs/${job-id}
  Headers: Authorization: Bearer ${jwt-token}
  ↓
API Gateway → Rust Lambda
  ↓
Lambda:
  1. Query DynamoDB for job_id
  2. Verify user_id matches JWT claim (authorization)
  3. Return job metadata
  ↓
Response: {
  "job_id": "...",
  "status": "completed",
  "model": "marker",
  "s3_input_key": "...",
  "s3_result_key": "...",
  "created_at": "...",
  "completed_at": "..."
}
```

### 6. Result Download
```
User (with temp credentials) → S3
  Downloads: s3://pdf-models-docs/${user-id}/${job-id}-result.md

Receives: Raw Markdown output from Marker
```

## Model Integration Pattern

### Adding a New Model

Each model follows the same pattern as Marker:

**1. Create Container**
```
backend/containers/{model-name}/
  ├── Dockerfile
  ├── task.py
  └── requirements.txt
```

**2. Create CDK Stack**
```python
class NewModelStack(Stack):
    def __init__(self, ...):
        # ECS Task Definition
        # Step Functions State Machine
        # IAM Roles
        # Export to SSM
```

**3. Update API Stack**
- Add model endpoint: `/v1/models/{new-model}/jobs`
- Route to appropriate Step Function

**4. Create CodeBuild**
- Container build for new model
- Push to ECR: `pdf-models/{new-model}:latest`

**Isolation Benefits**
- ✅ Each model has independent resources
- ✅ Updates don't affect other models
- ✅ Different CPU/memory configurations
- ✅ Can deprecate models by deleting stack

## Implementation Phases

### Phase 1: Core Infrastructure
**Goal**: Establish foundational AWS resources

**Stacks**:
- FoundationStack (ECR repos)
- CoreInfrastructureStack (Cognito, S3, DynamoDB)

**Deliverables**:
- Users can authenticate and get S3 credentials
- S3 bucket ready for uploads
- DynamoDB table ready for job tracking

**Validation**:
- Manual test: Authenticate, upload PDF to S3
- Verify DynamoDB table exists and is queryable

---

### Phase 2: Model Stack (Marker)
**Goal**: Process documents end-to-end

**Stacks**:
- MarkerStack (Task Definition, Step Functions)

**Deliverables**:
- Marker container built and in ECR
- task.py script working
- Step Functions can launch Fargate task
- Task can process PDF → Markdown

**Validation**:
- Manual Step Functions execution
- Verify Markdown output in S3
- Check DynamoDB status updates

---

### Phase 3: API Layer
**Goal**: User-accessible API

**Stacks**:
- ApiStack (API Gateway, Rust Lambdas)

**Deliverables**:
- API endpoints functional
- Cognito authorization working
- End-to-end: Submit job via API, poll status, download result

**Validation**:
- API integration tests
- Full user workflow test

---

### Phase 4: CI/CD
**Goal**: Automated builds

**Stacks**:
- CiCdStack (CodeBuild projects)

**Deliverables**:
- CodeBuild for Marker container
- Automated image builds on trigger

**Validation**:
- Trigger build, verify new image in ECR
- Deploy updated task definition

---

## Security Considerations

### Authentication
- Cognito User Pool enforces password policies
- JWT tokens expire (configurable)
- MFA can be enabled later

### Authorization
- Identity Pool credentials scoped to user prefix
- API Gateway validates JWT before processing
- Rust Lambda validates user_id matches resource owner
- No cross-user data access possible

### Data Isolation
- S3: User-prefixed paths enforced by IAM
- DynamoDB: User_id verification in Lambda
- Fargate tasks have no user context (process specific job_id)

### Secrets Management
- No secrets in code or environment variables
- Use AWS Secrets Manager if third-party APIs needed
- Task roles use IAM (no credentials in container)

## Monitoring & Observability

### CloudWatch Logs
- API Gateway access logs
- Lambda function logs
- Fargate task logs (stdout/stderr)
- Step Functions execution history

### Metrics
- API Gateway: Request count, latency, errors
- Lambda: Invocations, duration, errors
- Step Functions: Executions, success/failure rate
- DynamoDB: Read/write capacity, throttles
- ECS: Task count, CPU/memory utilization

### Alarms (future)
- API error rate > threshold
- Step Functions failure rate > threshold
- DynamoDB throttling
- Fargate task failures

## Cost Optimization

### Current (MVP)
- **Cognito**: Free tier (50,000 MAUs)
- **S3**: Pay per GB stored (7-day lifecycle limits cost)
- **DynamoDB**: On-demand pricing (pay per request)
- **Fargate**: Pay per second (2 vCPU, 8GB) - only when processing
- **Step Functions**: $0.025 per 1,000 state transitions
- **Lambda**: Free tier covers initial usage
- **API Gateway**: Free tier (1M requests/month)

**Estimated Monthly Cost (low usage)**:
- 100 jobs/month × ~5 min/job = ~8.3 Fargate hours
- Fargate: ~$0.50
- Other services: Free tier
- **Total: < $1/month**

### Future Optimizations
- Reserved Fargate capacity if usage is predictable
- S3 Intelligent Tiering
- DynamoDB reserved capacity
- Compression for results

## Future Considerations

### Scaling
- API Gateway: 10,000 req/s limit (request increase if needed)
- DynamoDB: On-demand handles spikes automatically
- Fargate: Account limits (request increase)
- Step Functions: 1M executions/account/month (monitor)

### Multi-Model Enhancements
- Model versioning (v1, v2)
- A/B testing between models
- Model comparison API
- Batch processing (multiple docs, single job)

### Advanced Features
- Webhooks for job completion (avoid polling)
- Streaming results (large outputs)
- Custom fine-tuned models per user
- Result caching
- API rate limiting per user

## Appendix

### Technology Stack
- **Infrastructure as Code**: AWS CDK (Python)
- **API Handlers**: Rust (Lambda)
- **Task Orchestration**: Python (Fargate task.py)
- **Model**: Marker (Python)
- **Frontend**: Elm (separate)

### Useful Commands
```bash
# Deploy stacks in order
cdk deploy FoundationStack
cdk deploy CoreInfrastructureStack
cdk deploy MarkerStack
cdk deploy ApiStack

# Build Marker container (manual)
# (Will be automated in CodeBuild)
cd backend/containers/marker
docker build -t marker:latest .
docker tag marker:latest ${ECR_URI}:latest
docker push ${ECR_URI}:latest

# Trigger Step Functions manually (testing)
aws stepfunctions start-execution \
  --state-machine-arn ${SFN_ARN} \
  --input '{"job_id":"test","s3_input_key":"user/test.pdf"}'
```

### References
- [Marker GitHub](https://github.com/VikParuchuri/marker)
- [AWS CDK Python Docs](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [Cognito Identity Pools](https://docs.aws.amazon.com/cognito/latest/developerguide/identity-pools.html)
- [Step Functions ECS Integration](https://docs.aws.amazon.com/step-functions/latest/dg/connect-ecs.html)
