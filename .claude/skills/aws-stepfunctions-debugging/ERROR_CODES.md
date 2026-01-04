# Step Functions Error Codes

Common error codes and their meanings.

## States.* errors (Step Functions errors)

### States.Timeout

**Meaning**: Task exceeded configured timeout

**Causes**:
- Lambda function took too long (max 15 minutes)
- ECS task exceeded timeout
- Network issues preventing completion

**Solution**:
- Increase timeout in state machine definition
- Optimize slow operations
- Check for infinite loops or deadlocks

### States.TaskFailed

**Meaning**: Generic task failure

**Causes**: Various - check `cause` field for details

**Diagnosis**: Look at execution history for specific error

### States.Permissions

**Meaning**: IAM permission denied

**Causes**:
- Execution role lacks required permissions
- Resource policy denies access
- Service role not trusted

**Solution**: Check IAM policies on:
- Step Functions execution role
- Task execution role (for ECS)
- Resource policies (Lambda, ECS, etc.)

### States.Runtime

**Meaning**: Runtime error in state machine

**Causes**:
- Invalid JsonPath expression
- Type mismatch in parameters
- Malformed state definition

**Example**:
```json
"TaskDefinition.$": "$.nonexistent"  // Field doesn't exist
```

## ECS.* errors (ECS task errors)

### ECS.InvalidParameterException

**Meaning**: Invalid parameter passed to ECS

**Common causes**:

**1. Task definition not found**
```json
{
  "error": "ECS.InvalidParameterException",
  "cause": "Task definition does not exist: arn:aws:ecs:...:task-definition/pdf-models-marker:99"
}
```

**Solution**: Check task definition exists:
```bash
AWS_PROFILE=arch aws ecs describe-task-definition \
  --task-definition pdf-models-marker:99
```

**2. Invalid cluster**
```json
{
  "cause": "Cluster does not exist: pdf-models-marker-cluster"
}
```

**Solution**: Verify cluster name and region

**3. Invalid network configuration**
```json
{
  "cause": "Network configuration is required for task definitions with network mode 'awsvpc'"
}
```

**Solution**: Add network configuration:
```json
{
  "NetworkConfiguration": {
    "AwsvpcConfiguration": {
      "Subnets": ["subnet-123"],
      "SecurityGroups": ["sg-456"]
    }
  }
}
```

### ECS.AccessDeniedException

**Meaning**: Permission denied for ECS operation

**Common causes**:

**1. Execution role lacks ecs:RunTask**
```json
{
  "error": "ECS.AccessDeniedException",
  "cause": "User: arn:aws:sts::123:assumed-role/StepFunctionsRole is not authorized to perform: ecs:RunTask"
}
```

**Solution**: Add to execution role:
```python
execution_role.add_to_policy(
    iam.PolicyStatement(
        actions=["ecs:RunTask", "ecs:DescribeTasks"],
        resources=["*"],  # Or specific task definition ARN
    )
)
```

**2. Cannot pass task role**
```json
{
  "cause": "is not authorized to perform: iam:PassRole on resource: arn:aws:iam::123:role/TaskRole"
}
```

**Solution**: Add PassRole permission:
```python
execution_role.add_to_policy(
    iam.PolicyStatement(
        actions=["iam:PassRole"],
        resources=[task_role.role_arn],
    )
)
```

### ECS.CapacityError

**Meaning**: No capacity available to run task

**Causes**:
- No container instances in cluster (EC2 launch type)
- Fargate capacity unavailable (rare)
- Resource constraints (CPU/memory)

**Solution**:
- For EC2: Add container instances
- For Fargate: Retry or reduce resource requirements
- Check service quotas

### ECS.ServiceNotActiveException

**Meaning**: ECS service in wrong state

**Causes**:
- Service being deleted
- Service stopped

**Solution**: Wait for service to become active or recreate

## Lambda errors

### Lambda.Unknown

**Meaning**: Lambda function error

**Causes**: Various - check CloudWatch logs

**Diagnosis**:
```bash
AWS_PROFILE=arch aws logs tail \
  /aws/lambda/pdf-models-marker-resolver --since 10m
```

**Common Lambda errors**:
- Import error (module not found)
- Unhandled exception
- Timeout
- Out of memory

### Lambda.ServiceException

**Meaning**: Lambda service error

**Causes**:
- Concurrent execution limit reached
- Service temporarily unavailable

**Solution**: Retry or increase Lambda concurrency limits

### Lambda.ResourceNotFound

**Meaning**: Lambda function not found

**Causes**:
- Function deleted
- Wrong function name/ARN
- Wrong region

**Solution**: Verify function exists:
```bash
AWS_PROFILE=arch aws lambda get-function \
  --function-name pdf-models-marker-resolver
```

## Application exit codes (from ECS container)

These appear in task output, not as Step Functions errors.

### Exit code 0

**Meaning**: Success

Container completed successfully.

### Exit code 1

**Meaning**: General application error

**Diagnosis**: Check container logs:
```bash
AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m
```

**Common causes**:
- Python exception
- Missing environment variable
- S3 access denied
- Invalid input

### Exit code 137

**Meaning**: Killed by OOM (Out of Memory)

**Diagnosis**: Check task memory limit vs usage

**Solution**:
- Increase task memory in task definition
- Optimize application memory usage
- Process data in smaller chunks

### Exit code 139

**Meaning**: Segmentation fault

**Diagnosis**: Application crashed (C/C++ error)

**Solution**:
- Update dependencies
- Report bug to library maintainer
- Add error handling

## DynamoDB errors

### DynamoDB.ConditionalCheckFailedException

**Meaning**: Conditional update failed

**Cause**: Item doesn't exist or condition not met

**Example**: Trying to update job that doesn't exist

**Solution**: Check item exists before conditional update

### DynamoDB.ProvisionedThroughputExceededException

**Meaning**: Too many requests to DynamoDB

**Causes**:
- Exceeded provisioned capacity
- Hot partition

**Solution**:
- Use on-demand billing mode
- Increase provisioned capacity
- Add exponential backoff retry logic

## S3 errors

### S3.AccessDenied

**Meaning**: Permission denied for S3 operation

**Causes**:
- Task role lacks S3 permissions
- Bucket policy denies access
- Object ACL restrictive

**Solution**: Add S3 permissions to task role:
```python
task_role.add_to_policy(
    iam.PolicyStatement(
        actions=["s3:GetObject", "s3:PutObject"],
        resources=[f"arn:aws:s3:::{bucket_name}/*"],
    )
)

# Also add ListBucket for some operations
task_role.add_to_policy(
    iam.PolicyStatement(
        actions=["s3:ListBucket"],
        resources=[f"arn:aws:s3:::{bucket_name}"],
    )
)
```

### S3.NoSuchKey

**Meaning**: Object doesn't exist

**Causes**:
- Wrong key/path
- Object not uploaded yet
- Object deleted

**Solution**: Verify object exists:
```bash
AWS_PROFILE=arch aws s3 ls s3://bucket-name/path/to/file
```

## Troubleshooting workflow

1. **Get error code and cause** from execution history
2. **Match to error type** above
3. **Check specific logs**:
   - Lambda: `/aws/lambda/<function-name>`
   - ECS: `/ecs/<service-name>`
   - Step Functions: Execution history
4. **Verify permissions** for the operation
5. **Check resource exists** (task definition, function, etc.)
6. **Fix and retry** execution
