---
name: aws-stepfunctions-debugging
description: Debug AWS Step Functions state machines, trace execution failures, and diagnose ECS task integration issues. Use when troubleshooting job failures, Step Functions errors, or ECS tasks not starting from Step Functions.
---

# AWS Step Functions Debugging

Debug Step Functions state machines and ECS task integration issues.

## Quick diagnostics

**List recent executions**:
```bash
AWS_PROFILE=arch aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker \
  --max-results 10 \
  --query 'executions[*].[name,status,startDate]' \
  --output table
```

**Get execution details**:
```bash
python .claude/skills/aws-stepfunctions-debugging/scripts/get_execution.py <execution-name>
```

**Check failed executions**:
```bash
python .claude/skills/aws-stepfunctions-debugging/scripts/list_failed.py
```

## Understanding execution flow

### pdf-models-marker state machine

The Marker state machine has two steps:

1. **ResolveTaskDefinition** (Lambda)
   - Reads current task definition ARN from SSM
   - Returns ARN with revision number
   - Purpose: Dynamic resolution avoids caching issues

2. **RunMarkerTask** (ECS RunTask)
   - Uses resolved task definition ARN
   - Launches ECS task in Fargate
   - Waits for task completion
   - Returns task result

**Normal flow**:
```
Start
  ↓
ResolveTaskDefinition (Lambda)
  ↓
RunMarkerTask (ECS)
  ↓
Task completes
  ↓
SUCCEEDED
```

## Common issues

### Execution shows SUCCEEDED but job failed

**Symptom**: Step Functions execution status is SUCCEEDED, but job shows failed in DynamoDB

**Cause**: Step Functions tracks state machine completion, not task success

**Diagnosis**: Check ECS task exit code:
```bash
python .claude/skills/aws-stepfunctions-debugging/scripts/get_execution.py <execution-name>
```

Look for `exitCode` in RunMarkerTask output:
- `0` = Success
- `1` = Error (check logs)
- `137` = Out of memory

**Solution**: Error handling logic should check task exit code, not just execution status.

### ResolveTaskDefinition fails

**Symptom**: Execution fails at first step

**Common errors**:

**1. SSM parameter not found**
```json
{
  "error": "ParameterNotFound",
  "cause": "Parameter /pdf-models/marker/task-definition-arn does not exist"
}
```

**Cause**: MarkerStack not deployed or task definition not registered

**Solution**: Deploy MarkerStack: `make cdk-deploy STACK=MarkerStack`

**2. Lambda timeout**
```json
{
  "error": "States.Timeout"
}
```

**Cause**: Lambda function not responding

**Solution**: Check Lambda logs:
```bash
AWS_PROFILE=arch aws logs tail /aws/lambda/pdf-models-marker-resolver --since 10m
```

### RunMarkerTask fails to start

**Symptom**: Execution fails at RunMarkerTask, task never launches

**Common errors**:

**1. Task definition not found**
```json
{
  "error": "ECS.InvalidParameterException",
  "cause": "Task definition does not exist"
}
```

**Cause**: Resolved ARN points to non-existent task definition

**Solution**: Check SSM parameter has valid value:
```bash
AWS_PROFILE=arch aws ssm get-parameter \
  --name /pdf-models/marker/task-definition-arn \
  --query 'Parameter.Value' --output text
```

**2. Insufficient permissions**
```json
{
  "error": "ECS.AccessDeniedException",
  "cause": "User is not authorized to perform: ecs:RunTask"
}
```

**Cause**: Step Functions execution role lacks ECS permissions

**Solution**: Check IAM policies on execution role. Should allow:
- `ecs:RunTask`
- `ecs:DescribeTasks`
- `iam:PassRole` (for task role)

**3. No capacity**
```json
{
  "error": "ECS.CapacityError",
  "cause": "No container instances available"
}
```

**Cause**: ECS cluster has no capacity (Fargate should not have this issue)

**Solution**: Verify cluster exists and has capacity:
```bash
AWS_PROFILE=arch aws ecs describe-clusters --clusters pdf-models-marker-cluster
```

### Task starts but fails immediately

**Symptom**: ECS task starts, exits with code 1

**Diagnosis**: Check task logs:
```bash
AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m
```

**Common causes**:
- Missing environment variables
- S3 access denied
- Container entrypoint error
- Python import error

See [aws-container-debugging](../aws-container-debugging/SKILL.md) for container troubleshooting.

### Execution stuck in RUNNING

**Symptom**: Execution shows RUNNING for extended period

**Diagnosis**: Check which step it's on:
```bash
python .claude/skills/aws-stepfunctions-debugging/scripts/get_execution.py <execution-name>
```

**Causes**:

**1. ECS task taking too long**
- Check task logs to see progress
- Task may be legitimately processing large PDF
- Consider increasing timeout if needed

**2. Task hung/deadlocked**
- Task not outputting logs
- No CPU activity
- Solution: Stop task manually or wait for timeout

**3. Step Functions timeout not set**
- Execution runs indefinitely
- Set timeout in state machine definition

## Workflow: Debugging a failed execution

1. **Get execution ARN from job record**:
   ```bash
   # Job record contains Step Functions execution ARN
   AWS_PROFILE=arch aws dynamodb get-item \
     --table-name pdf-models-jobs \
     --key '{"job_id": {"S": "job-123"}}'
   ```

2. **Get execution details**:
   ```bash
   python .claude/skills/aws-stepfunctions-debugging/scripts/get_execution.py <execution-name>
   ```

3. **Identify failed step**:
   - ResolveTaskDefinition: Lambda issue
   - RunMarkerTask: ECS task issue

4. **Check specific logs**:
   - Lambda: `/aws/lambda/pdf-models-marker-resolver`
   - ECS: `/ecs/pdf-models-marker`

5. **Look for error patterns**:
   - Permission denied: IAM issue
   - Not found: Resource doesn't exist
   - Timeout: Increase limits
   - Exit code 1: Application error

6. **Fix and retry**:
   - Fix underlying issue
   - Re-run job or start new execution

## Advanced: State machine definition

### Current definition (simplified)

```json
{
  "StartAt": "ResolveTaskDefinition",
  "States": {
    "ResolveTaskDefinition": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:task-def-resolver",
      "Next": "RunMarkerTask",
      "ResultPath": "$.taskDefArn"
    },
    "RunMarkerTask": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "TaskDefinition.$": "$.taskDefArn",
        "Cluster": "pdf-models-marker-cluster",
        "Overrides": {
          "ContainerOverrides": [{
            "Name": "marker-container",
            "Environment": [
              {"Name": "S3_INPUT_KEY", "Value.$": "$.s3_input_key"},
              {"Name": "JOB_ID", "Value.$": "$.job_id"}
            ]
          }]
        }
      },
      "End": true
    }
  }
}
```

### Key patterns

**`.sync` suffix on ECS resource**:
```json
"Resource": "arn:aws:states:::ecs:runTask.sync"
```

This makes Step Functions wait for task completion. Without `.sync`, it would start task and immediately proceed.

**ResultPath for Lambda output**:
```json
"ResultPath": "$.taskDefArn"
```

Adds Lambda result to input, making it available to next state.

**Parameters with `.$` (JsonPath)**:
```json
"TaskDefinition.$": "$.taskDefArn"
```

The `.$` suffix means use JsonPath to extract value from input, not literal string.

## Dynamic task definition pattern

### Problem

Hard-coding task definition ARN in state machine:
```json
"TaskDefinition": "arn:aws:ecs:...:task-definition/pdf-models-marker:11"
```

**Issues**:
- Revision number (`:11`) changes when container updated
- Must redeploy Step Functions after every container build
- Creates circular dependency: CodeBuild → SSM → CDK → Step Functions

### Solution

Two-step pattern with Lambda resolver:

**Step 1**: Lambda reads SSM at runtime
```python
def handler(event, context):
    ssm = boto3.client('ssm')
    param = ssm.get_parameter(Name='/pdf-models/marker/task-definition-arn')
    return param['Parameter']['Value']
```

**Step 2**: Use resolved value
```json
{
  "TaskDefinition.$": "$.taskDefArn",  // From Lambda result
  "LaunchType": "FARGATE",
  ...
}
```

**Benefits**:
- Container updates immediately available
- No CDK redeployment needed
- Breaks circular dependency

## Monitoring

### CloudWatch metrics

**Execution metrics**:
- `ExecutionsStarted`
- `ExecutionsSucceeded`
- `ExecutionsFailed`
- `ExecutionTime`

**View in console**: CloudWatch → Metrics → Step Functions

### Setting up alarms

```python
# In MonitoringStack
alarm = cloudwatch.Alarm(
    self, "StepFunctionsFailures",
    metric=state_machine.metric_failed(),
    threshold=1,
    evaluation_periods=1,
    alarm_description="Step Functions execution failed",
)
```

## Reference

- See [EXECUTION_PATTERNS.md](EXECUTION_PATTERNS.md) for common execution patterns
- See [ERROR_CODES.md](ERROR_CODES.md) for error code reference
