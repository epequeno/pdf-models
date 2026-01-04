# Stack Dependencies

Visual dependency graph showing which stacks depend on others.

## Dependency graph

```
FoundationStack (ECR, base resources)
    ├── CoreInfrastructureStack (S3, DynamoDB, Cognito)
    │   ├── CiCdStack (CodeBuild, CodeCommit)
    │   ├── MarkerStack (ECS, Step Functions)
    │   └── ApiV2Stack (API Gateway, Lambdas)
    │       ├── MonitoringStack (CloudWatch)
    │       └── FrontendStack (Static hosting)
    └── CiCdStack
```

## Deployment order

1. **FoundationStack** → Creates ECR repositories
2. **CoreInfrastructureStack** → Creates S3, DynamoDB, Cognito
3. **CiCdStack** → Creates CodeBuild projects (needs ECR URIs)
4. **MarkerStack** → Creates ECS cluster, Step Functions (needs S3, ECR)
5. **ApiV2Stack** → Creates API, Lambdas (needs S3, DynamoDB, Cognito)
6. **MonitoringStack** → Creates alarms (needs API Gateway ID)
7. **FrontendStack** → Creates frontend hosting (needs API URL)

## Stack details

### FoundationStack

**Creates**:
- ECR repository: `pdf-models/marker`
- ECR repository: `pdf-models/rust-lambda-builder`
- SSM parameters for ECR URIs

**Dependencies**: None (deploy first)

**Exports via SSM**:
- `/pdf-models/ecr/marker-uri`
- `/pdf-models/ecr/rust-lambda-builder-uri`

### CoreInfrastructureStack

**Creates**:
- S3 bucket for PDFs and artifacts
- DynamoDB table for job tracking
- Cognito User Pool and Identity Pool

**Dependencies**: None

**Exports via SSM**:
- `/pdf-models/s3/bucket-name`
- `/pdf-models/dynamodb/table-name`
- `/pdf-models/cognito/user-pool-id`
- `/pdf-models/cognito/identity-pool-id`

### CiCdStack

**Creates**:
- CodeCommit repository
- CodeBuild project: `pdf-models-marker-container-build`
- CodeBuild project: `pdf-models-rust-lambda-builder-build`
- CodeBuild project: `pdf-models-rust-lambda-build`

**Dependencies**:
- FoundationStack (needs ECR URIs)
- CoreInfrastructureStack (needs S3 bucket)

**Reads from SSM**:
- `/pdf-models/ecr/marker-uri`
- `/pdf-models/ecr/rust-lambda-builder-uri`
- `/pdf-models/s3/bucket-name`

**Exports via SSM**:
- `/pdf-models/cicd/codecommit-clone-url-http`
- `/pdf-models/cicd/codecommit-clone-url-ssh`
- `/pdf-models/cicd/marker-image-tag` (updated by CodeBuild)

### MarkerStack

**Creates**:
- ECS cluster: `pdf-models-marker-cluster`
- ECS task definition: `pdf-models-marker`
- Step Functions state machine: `pdf-models-marker`
- Lambda: Task definition resolver
- IAM roles for ECS and Step Functions

**Dependencies**:
- FoundationStack (needs ECR URI)
- CoreInfrastructureStack (needs S3, DynamoDB)

**Reads from SSM**:
- `/pdf-models/ecr/marker-uri`
- `/pdf-models/s3/bucket-name`
- `/pdf-models/dynamodb/table-name`

**Exports via SSM**:
- `/pdf-models/marker/task-definition-arn` (updated by ECS)
- `/pdf-models/marker/state-machine-arn`

### ApiV2Stack

**Creates**:
- API Gateway HTTP API
- Lambda functions (Rust):
  - `submit-job` - Submit PDF processing job
  - `get-job` - Get job status
  - `list-jobs` - List user's jobs
- Lambda authorizer
- IAM roles for Lambdas

**Dependencies**:
- CoreInfrastructureStack (needs S3, DynamoDB, Cognito)
- MarkerStack (needs Step Functions ARN)

**Reads from SSM**:
- `/pdf-models/s3/bucket-name`
- `/pdf-models/dynamodb/table-name`
- `/pdf-models/cognito/user-pool-id`
- `/pdf-models/cognito/identity-pool-id`
- `/pdf-models/marker/state-machine-arn`

**Exports via SSM**:
- `/pdf-models/api-v2/id`
- `/pdf-models/api-v2/endpoint`

### MonitoringStack

**Creates**:
- CloudWatch dashboard
- CloudWatch alarms for:
  - API Gateway errors
  - Lambda errors
  - Step Functions failures
  - ECS task failures

**Dependencies**:
- ApiV2Stack (needs API Gateway ID)
- MarkerStack (needs Step Functions ARN)

**Reads from SSM**:
- `/pdf-models/api-v2/id`
- `/pdf-models/marker/state-machine-arn`

**Exports**: None

### FrontendStack

**Creates**:
- S3 bucket for static hosting
- CloudFront distribution
- Required bucket policies

**Dependencies**:
- ApiV2Stack (needs API endpoint URL)

**Reads from SSM**:
- `/pdf-models/api-v2/endpoint`

**Exports**:
- Frontend URL (CloudFront distribution)

## Circular dependency prevention

### Problem pattern

Don't do this:
```python
# In StackA
param_from_b = ssm.StringParameter.value_for_string_parameter(
    self, "/created/by/stack-b"
)

# In StackB
param_from_a = ssm.StringParameter.value_for_string_parameter(
    self, "/created/by/stack-a"
)
```

This creates circular dependency: A needs B, B needs A.

### Solution patterns

**Option 1**: One-way dependency
```python
# StackA creates, StackB consumes
# No circular dependency
```

**Option 2**: Runtime resolution
```python
# Use Lambda to read SSM at runtime, not synthesis time
# See MarkerStack task definition resolver example
```

**Option 3**: Third stack
```python
# Create StackC that both A and B depend on
# StackC creates shared resources
```

## Troubleshooting dependencies

### How to identify dependency issues

**Symptom**: `cdk deploy` fails with "depends on" error

**Diagnosis**:
1. Check error message for stack names
2. Find which SSM parameter is missing
3. Identify which stack creates that parameter
4. Deploy dependency stack first

**Example**:
```
Error: MarkerStack depends on CoreInfrastructureStack
```

This means MarkerStack reads an SSM parameter created by CoreInfrastructureStack.

### View dependency graph

```bash
cd backend && AWS_PROFILE=arch uv run cdk ls --long
```

### Force deployment order

Use `make cdk-deploy-all` which deploys in correct order automatically.
