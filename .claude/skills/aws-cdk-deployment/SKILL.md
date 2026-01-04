---
name: aws-cdk-deployment
description: Deploy and manage AWS CDK stacks for the pdf-models project. Use when deploying infrastructure, troubleshooting stack dependencies, fixing CDK synthesis issues, or managing SSM parameters.
---

# AWS CDK Deployment

Deploy and manage AWS infrastructure using CDK for the pdf-models project.

## Stack deployment order

**CRITICAL**: Stacks must be deployed in this exact order due to dependencies:

1. **FoundationStack** - ECR repositories, foundational resources
2. **CoreInfrastructureStack** - S3, DynamoDB, Cognito
3. **CiCdStack** - CodeBuild projects, CodeCommit
4. **MarkerStack** - ECS cluster, Step Functions for Marker
5. **ApiV2Stack** - API Gateway, Lambda functions
6. **MonitoringStack** - CloudWatch alarms, dashboards
7. **FrontendStack** - Frontend hosting

**Quick deploy all**:
```bash
make cdk-deploy-all
```

**Deploy single stack**:
```bash
make cdk-deploy STACK=FoundationStack
```

## Common commands

**Synthesize** (generate CloudFormation):
```bash
make cdk-synth
```

**Show diff** before deploying:
```bash
make cdk-diff STACK=MarkerStack
```

**Deploy with approval**:
```bash
cd backend && AWS_PROFILE=arch uv run cdk deploy MarkerStack
```

**Destroy stack**:
```bash
make cdk-destroy STACK=MonitoringStack
```

## SSM parameter dependencies

### Common pattern

Stacks share data via SSM parameters:

```python
# In FoundationStack (creates parameter)
ssm.StringParameter(
    self, "BucketName",
    parameter_name="/pdf-models/s3/bucket-name",
    string_value=bucket.bucket_name,
)

# In MarkerStack (reads parameter)
bucket_name = ssm.StringParameter.value_for_string_parameter(
    self, "/pdf-models/s3/bucket-name"
)
```

### Critical SSM parameters

| Parameter | Created By | Used By | Purpose |
|-----------|------------|---------|---------|
| `/pdf-models/s3/bucket-name` | Foundation | All | S3 bucket name |
| `/pdf-models/ecr/marker-uri` | Foundation | CiCd, Marker | ECR repository URI |
| `/pdf-models/api-v2/id` | ApiV2 | Monitoring | API Gateway ID |
| `/pdf-models/marker/task-definition-arn` | Marker | Marker (runtime) | ECS task definition |
| `/pdf-models/cicd/marker-image-tag` | CiCd (build) | Marker | Container image tag |

### SSM caching gotcha

**Problem**: SSM parameters cached at synthesis time, not runtime.

**Example**:
```python
# This caches the value when you run cdk synth
task_def_arn = ssm.StringParameter.value_for_string_parameter(
    self, "/pdf-models/marker/task-definition-arn"
)

# If parameter changes, you must re-run cdk deploy
```

**Solution for dynamic values**: Use Lambda to read SSM at runtime (see MarkerStack resolver pattern).

## Troubleshooting

### Stack dependency error

**Error**: "Stack X depends on Stack Y, please deploy Y first"

**Cause**: Deploying stacks out of order

**Solution**: Follow deployment order above, or use `make cdk-deploy-all`

### SSM parameter not found

**Error**: "Parameter /pdf-models/... does not exist"

**Cause**: Dependency stack not deployed yet

**Diagnosis**: Check if parameter exists:
```bash
AWS_PROFILE=arch aws ssm get-parameter --name /pdf-models/s3/bucket-name
```

**Solution**: Deploy dependency stack first (usually FoundationStack or CoreInfrastructureStack)

### Permission denied during deployment

**Error**: "User is not authorized to perform: iam:CreateRole"

**Cause**: Insufficient AWS permissions

**Solution**: Verify AWS profile has AdministratorAccess or equivalent

### Changes not reflected after deploy

**Symptom**: Deployed stack but behavior unchanged

**Causes**:
1. **SSM parameter caching** - Parameter read at synthesis, not runtime
2. **Resource not recreated** - CloudFormation updates in-place
3. **Code changes not deployed** - For Lambdas, need to rebuild

**Solutions**:
1. Re-run `cdk deploy` after parameter changes
2. Check CloudFormation changeset to see what actually changed
3. For Lambdas: `make lambda-build` then redeploy stack

### Stack stuck in UPDATE_ROLLBACK_FAILED

**Symptom**: Stack in failed state, can't update or delete

**Diagnosis**:
```bash
AWS_PROFILE=arch aws cloudformation describe-stack-events \
  --stack-name MarkerStack --max-items 20
```

**Solution**:
1. Fix underlying issue (check events for error)
2. Continue rollback: AWS Console → CloudFormation → Stack Actions → Continue Update Rollback
3. Or skip resources if necessary (advanced)

## Best practices

### Before deploying

- [ ] Run `make cdk-synth` to check for syntax errors
- [ ] Run `make cdk-diff STACK=<name>` to see what will change
- [ ] Verify dependency stacks are deployed
- [ ] Check AWS credentials: `AWS_PROFILE=arch aws sts get-caller-identity`

### After deploying

- [ ] Check CloudFormation events for warnings
- [ ] Verify resources created (check console or AWS CLI)
- [ ] Test critical paths (API, job submission, etc.)
- [ ] Check CloudWatch logs for errors

### Making changes

1. **Small iterations**: Deploy one stack at a time
2. **Test locally first**: Use `cdk synth` to catch errors early
3. **Review diffs**: Always check `cdk diff` before deploying
4. **Document parameters**: Update SSM parameter table when adding new ones

## IAM role patterns

### Cross-stack role assumptions

When resources in one stack need to assume roles in another:

```python
# In MarkerStack: Create role
task_role = iam.Role(
    self, "TaskRole",
    assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
)

# Export role ARN via SSM
ssm.StringParameter(
    self, "TaskRoleArn",
    parameter_name="/pdf-models/marker/task-role-arn",
    string_value=task_role.role_arn,
)

# In ApiV2Stack: Import and use
role_arn = ssm.StringParameter.value_for_string_parameter(
    self, "/pdf-models/marker/task-role-arn"
)

role = iam.Role.from_role_arn(self, "ImportedRole", role_arn)
```

### Wildcard permissions for dynamic resources

**Problem**: Task definition ARN includes revision number that changes.

**Bad** (too specific):
```python
resources=[f"arn:aws:ecs:{region}:{account}:task-definition/pdf-models-marker:11"]
```

**Good** (allows any revision):
```python
resources=[f"arn:aws:ecs:{region}:{account}:task-definition/pdf-models-marker:*"]
```

## Debugging techniques

### View synthesized CloudFormation

```bash
make cdk-synth
cat backend/cdk.out/MarkerStack.template.json | jq .
```

### Check what CDK thinks is deployed

```bash
cd backend && AWS_PROFILE=arch uv run cdk diff MarkerStack
```

### See CloudFormation events

```bash
AWS_PROFILE=arch aws cloudformation describe-stack-events \
  --stack-name MarkerStack \
  --max-items 20 \
  --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]' \
  --output table
```

### List all stacks

```bash
AWS_PROFILE=arch aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[*].[StackName,StackStatus]' \
  --output table
```

## Reference

- See [STACK_DEPENDENCIES.md](STACK_DEPENDENCIES.md) for detailed dependency graph
- See [SSM_PARAMETERS.md](SSM_PARAMETERS.md) for complete parameter reference
