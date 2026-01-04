# SSM Parameters Reference

Complete reference of all SSM parameters used in the pdf-models project.

## Parameter organization

Parameters organized by namespace:

- `/pdf-models/s3/*` - S3 resources
- `/pdf-models/dynamodb/*` - DynamoDB resources
- `/pdf-models/cognito/*` - Cognito resources
- `/pdf-models/ecr/*` - ECR repositories
- `/pdf-models/marker/*` - Marker service
- `/pdf-models/api-v2/*` - API Gateway v2
- `/pdf-models/cicd/*` - CI/CD resources

## All parameters

### S3 parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/s3/bucket-name` | String | CoreInfrastructureStack | `pdf-models-data-abc123` | Main S3 bucket name |

**Usage**:
```bash
AWS_PROFILE=arch aws ssm get-parameter --name /pdf-models/s3/bucket-name --query 'Parameter.Value' --output text
```

### DynamoDB parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/dynamodb/table-name` | String | CoreInfrastructureStack | `pdf-models-jobs` | Job tracking table |

### Cognito parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/cognito/user-pool-id` | String | CoreInfrastructureStack | `us-east-1_AbCdEfGhI` | User authentication |
| `/pdf-models/cognito/user-pool-client-id` | String | CoreInfrastructureStack | `1abc2def3ghi4jkl` | User Pool client ID |
| `/pdf-models/cognito/identity-pool-id` | String | CoreInfrastructureStack | `us-east-1:12345678-abcd-efgh` | Identity Pool for AWS credentials |

### ECR parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/ecr/marker-uri` | String | FoundationStack | `123456789.dkr.ecr.us-east-1.amazonaws.com/pdf-models/marker` | Marker container repo |
| `/pdf-models/ecr/rust-lambda-builder-uri` | String | FoundationStack | `123456789.dkr.ecr.us-east-1.amazonaws.com/pdf-models/rust-lambda-builder` | Builder image repo |

### Marker service parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/marker/task-definition-arn` | String | MarkerStack | `arn:aws:ecs:us-east-1:123:task-definition/pdf-models-marker:11` | Current task definition |
| `/pdf-models/marker/state-machine-arn` | String | MarkerStack | `arn:aws:states:us-east-1:123:stateMachine:pdf-models-marker` | Step Functions state machine |

**Note**: Task definition ARN includes revision number (`:11`) which changes when task definition is updated.

### API Gateway parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/api-v2/id` | String | ApiV2Stack | `abc123defg` | API Gateway ID |
| `/pdf-models/api-v2/endpoint` | String | ApiV2Stack | `https://abc123.execute-api.us-east-1.amazonaws.com` | API base URL |

### CI/CD parameters

| Parameter | Type | Created By | Example Value | Purpose |
|-----------|------|------------|---------------|---------|
| `/pdf-models/cicd/codecommit-clone-url-http` | String | CiCdStack | `https://git-codecommit.us-east-1.amazonaws.com/v1/repos/pdf-models` | Repo clone URL |
| `/pdf-models/cicd/codecommit-clone-url-ssh` | String | CiCdStack | `ssh://git-codecommit.us-east-1.amazonaws.com/v1/repos/pdf-models` | SSH clone URL |
| `/pdf-models/cicd/marker-image-tag` | String | CodeBuild | `3994348` | Latest container image tag |
| `/pdf-models/cicd/base-image-build-project` | String | CiCdStack | `pdf-models-rust-lambda-builder-build` | Base image build project |
| `/pdf-models/cicd/rust-lambda-build-project` | String | CiCdStack | `pdf-models-rust-lambda-build` | Lambda build project |

**Note**: `marker-image-tag` is updated by CodeBuild during container builds.

## Dynamic vs static parameters

### Static parameters (set at deploy)

Most parameters are static - created during stack deployment and don't change unless stack is redeployed.

Example:
```python
ssm.StringParameter(
    self, "BucketName",
    parameter_name="/pdf-models/s3/bucket-name",
    string_value=bucket.bucket_name,  # Set once at deploy
)
```

### Dynamic parameters (updated at runtime)

Some parameters are updated by running services:

1. **`/pdf-models/cicd/marker-image-tag`**
   - Updated by CodeBuild after each container build
   - Contains git commit hash (e.g., `3994348`)

2. **`/pdf-models/marker/task-definition-arn`**
   - Updated when new task definition registered
   - Includes revision number that increments

## Reading parameters

### In CDK (synthesis time)

```python
value = ssm.StringParameter.value_for_string_parameter(
    self, "/pdf-models/s3/bucket-name"
)
```

**Gotcha**: Value is cached at `cdk synth` time. If parameter changes, you must redeploy.

### At runtime (Lambda, ECS)

```python
import boto3

ssm = boto3.client('ssm')
response = ssm.get_parameter(Name='/pdf-models/s3/bucket-name')
value = response['Parameter']['Value']
```

This always gets current value.

### From command line

```bash
# Get single parameter
AWS_PROFILE=arch aws ssm get-parameter \
  --name /pdf-models/s3/bucket-name \
  --query 'Parameter.Value' --output text

# Get all parameters for project
AWS_PROFILE=arch aws ssm get-parameters-by-path \
  --path /pdf-models \
  --recursive \
  --query 'Parameters[*].[Name,Value]' \
  --output table
```

## Updating parameters

### Via CDK (redeploy stack)

Modify stack code and redeploy:
```bash
make cdk-deploy STACK=CoreInfrastructureStack
```

### Manually (not recommended)

```bash
AWS_PROFILE=arch aws ssm put-parameter \
  --name /pdf-models/cicd/marker-image-tag \
  --value "new-value" \
  --type String \
  --overwrite
```

**Warning**: Manual changes may be overwritten by stack updates.

### Via CodeBuild (automatic)

Container image tag updated automatically:
```yaml
# In buildspec.yml
post_build:
  commands:
    - aws ssm put-parameter \
        --name /pdf-models/cicd/marker-image-tag \
        --value $IMAGE_TAG \
        --overwrite
```

## Parameter naming conventions

Follow these patterns:

**Good**:
- `/pdf-models/service/resource-type`
- Kebab-case for multi-word names
- Hierarchical structure

**Examples**:
- `/pdf-models/s3/bucket-name` ✓
- `/pdf-models/marker/task-definition-arn` ✓

**Bad**:
- `/pdfModels/camelCase` ✗
- `/pdf-models-bucket-name` ✗ (flat structure)

## Troubleshooting

### Parameter not found

**Error**: `ParameterNotFound: Parameter /pdf-models/... does not exist`

**Diagnosis**: Check if parameter exists:
```bash
AWS_PROFILE=arch aws ssm get-parameter --name /pdf-models/s3/bucket-name
```

**Causes**:
1. Dependency stack not deployed
2. Typo in parameter name
3. Wrong AWS region

**Solution**: Deploy the stack that creates the parameter.

### Stale parameter value

**Symptom**: Parameter has old value, recent changes not reflected

**Diagnosis**: Check when parameter was last modified:
```bash
AWS_PROFILE=arch aws ssm get-parameter \
  --name /pdf-models/cicd/marker-image-tag \
  --query 'Parameter.LastModifiedDate' --output text
```

**Causes**:
1. CodeBuild didn't update parameter (build failed)
2. CDK cached old value at synthesis
3. Looking at wrong region/account

**Solution**:
1. Rebuild container: `make container-build MODEL=marker`
2. Redeploy stack: `make cdk-deploy STACK=MarkerStack`
3. Verify region: `echo $AWS_DEFAULT_REGION`

### Permission denied reading parameter

**Error**: `AccessDeniedException: User is not authorized to perform: ssm:GetParameter`

**Cause**: IAM role/user lacks SSM permissions

**Solution**: Add policy:
```python
role.add_to_policy(
    iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        actions=["ssm:GetParameter"],
        resources=[f"arn:aws:ssm:{region}:{account}:parameter/pdf-models/*"],
    )
)
```
