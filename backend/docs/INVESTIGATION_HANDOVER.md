# Investigation Handover - Marker Container Issues

**Date**: 2026-01-03
**Status**: In Progress - Container built but deployment issue remains
**Primary Issue**: ECS tasks not pulling updated container image

## Summary

Successfully deployed all 7 CDK stacks and identified the root cause of job failures. The Marker container was missing the `pypdfium2` dependency required by the `marker-pdf` package. The fix has been implemented and the container rebuilt, but there's a challenge getting ECS to use the new image.

## What Was Done

### 1. Initial Deployment ✅
- Added `make cdk-deploy-all` command to deploy all stacks in correct order
- Successfully deployed all 7 stacks:
  - FoundationStack
  - CoreInfrastructureStack
  - CiCdStack
  - MarkerStack
  - ApiV2Stack
  - MonitoringStack (fixed SSM parameter path from `/pdf-models/api/id` to `/pdf-models/api-v2/id`)
  - FrontendStack

### 2. Integration Testing ✅
- Ran integration tests to identify issues
- Tests showed jobs stuck in "processing" status, timing out after 10 minutes

### 3. Root Cause Analysis ✅
- Examined Step Functions executions - found ECS tasks failing with exit code 1
- Checked ECS task logs at `/ecs/pdf-models-marker`
- **Root cause identified**: `ModuleNotFoundError: No module named 'marker.convert'`
- The `marker-pdf` package requires `pypdfium2` to be installed first

### 4. Container Fix ✅
- Updated `backend/containers/marker/Dockerfile`:
  ```dockerfile
  RUN pip install --no-cache-dir \
      pypdfium2 \
      marker-pdf \
      boto3
  ```
- Updated `backend/containers/marker/task.py` to import pypdfium2 first
- Committed changes and pushed to CodeCommit
- Triggered CodeBuild: Build succeeded (build ID: `pdf-models-marker-container-build:dd8956d5-7381-4412-8150-786a8ff8999c`)
- New image pushed to ECR with digest: `sha256:ca1c790cc7c1bfc67389aa9c5e5608d07e7ca7c7effc94d4c3e5210fcebccd0b`

### 5. ECS Image Cache Issue ⚠️
**Current Blocker**: ECS is caching the old container image despite new build

**Problem**: The task definition uses `496830984285.dkr.ecr.us-east-1.amazonaws.com/pdf-models/marker:latest`, and ECS caches images by tag. Simply rebuilding with the `:latest` tag doesn't force ECS to pull the new image.

**Attempts Made**:
1. Created new task definition revision 2 (still used `:latest` tag)
2. Updated SSM parameter `/pdf-models/marker/task-definition-arn` to revision 2
3. Created task definition revision 4 with specific image digest
4. Updated SSM to revision 4
5. Attempted to redeploy MarkerStack - CDK shows "no changes" because it caches SSM lookups at synthesis time

**Added**: `make aws-ecs-force-new-deployment` command to create new task definition revisions

## Current State

### What's Working ✅
- All stacks deployed successfully
- API Gateway, Lambda functions, Cognito, S3, DynamoDB all functional
- Integration tests pass for: list jobs, unauthorized access, S3 permissions
- Step Functions executions are running (not stuck)
- One job (5dcc7581-258f-4c90-abda-9577448d69cc) shows Step Functions SUCCEEDED but job marked as failed in DynamoDB

### What's Not Working ❌
- ECS tasks still pulling old container image with missing pypdfium2
- Jobs fail because container can't import marker.convert module
- New task definition revisions not being used by Step Functions

## Key Files Modified

### Committed ✅
- `backend/containers/marker/Dockerfile` - Added pypdfium2 dependency
- `backend/containers/marker/task.py` - Import pypdfium2 first
- `backend/backend/monitoring_stack.py` - Fixed SSM parameter path
- `Makefile` - Added cdk-deploy-all and aws-ecs-force-new-deployment commands

### Not Committed ⚠️
None - all changes committed

## Environment Details

- **AWS Region**: us-east-1
- **AWS Profile**: arch
- **Current Task Definition**: pdf-models-marker:4 (using specific digest)
- **Latest Container Image**: sha256:ca1c790cc7c1bfc67389aa9c5e5608d07e7ca7c7effc94d4c3e5210fcebccd0b
- **SSM Task Def Parameter**: `/pdf-models/marker/task-definition-arn` = revision 4
- **Step Functions ARN**: arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker

## Next Steps

### Option 1: Force Step Functions Update (Recommended)
The Step Functions state machine was created by CDK and references the task definition object directly. Since CDK caches SSM lookups at synthesis time, we need to force an update.

**Steps**:
1. Modify `backend/backend/marker_stack.py` to add a dummy parameter or comment that forces CDK to detect a change
2. Run `make cdk-deploy STACK=MarkerStack`
3. This should update the Step Functions state machine to use the new task definition revision 4
4. Run integration tests again

### Option 2: Manually Update Step Functions (Quick Test)
1. Get the current Step Functions definition:
   ```bash
   AWS_PROFILE=arch aws stepfunctions describe-state-machine \
     --state-machine-arn arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker \
     --query 'definition' --output text > sfn-definition.json
   ```

2. Update the task definition ARN in the definition to use revision 4

3. Update the state machine:
   ```bash
   AWS_PROFILE=arch aws stepfunctions update-state-machine \
     --state-machine-arn arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker \
     --definition file://sfn-definition.json
   ```

4. Run integration tests

### Option 3: Use Image Digest in CDK (Long-term Solution)
Modify `backend/backend/marker_stack.py` to use a specific image digest or tag instead of `:latest` to avoid caching issues.

## Useful Commands

```bash
# Check latest container images
AWS_PROFILE=arch aws ecr describe-images --repository-name pdf-models/marker \
  --query 'imageDetails | sort_by(@, &imagePushedAt) | [-1]' --output json

# Check ECS task logs
AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m --format short

# Check Step Functions executions
AWS_PROFILE=arch aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker \
  --max-results 5

# Check current task definition
AWS_PROFILE=arch aws ecs describe-task-definition --task-definition pdf-models-marker:4

# Force new task definition revision
make aws-ecs-force-new-deployment

# Run integration tests
make test-integration-auto
```

## Architecture References

- See `backend/docs/architecture.md` for full system architecture
- See `backend/docs/TROUBLESHOOTING.md` for common issues and solutions
- Critical reminder: **CodeBuild pulls from CodeCommit, not local files**. Always commit and push before rebuilding containers.

## Investigation Insights

1. **ECS Image Caching**: When using `:latest` tag, ECS aggressively caches images. Using specific digests or unique tags forces image pulls.

2. **CDK SSM Caching**: CDK caches SSM parameter lookups at synthesis time, not deployment time. Changing SSM values doesn't automatically update deployed resources.

3. **Step Functions Integration**: The EcsRunTask integration in Step Functions directly references the task definition. The state machine definition needs to be updated to use new task revisions.

4. **pypdfium2 Requirement**: The marker-pdf package documentation states pypdfium2 must be imported first to avoid warnings, but it's actually a hard dependency that must be installed.

5. **Job Status Mismatch**: One execution showed Step Functions SUCCEEDED but DynamoDB marked job as failed - worth investigating the task.py error handling logic.

## Sources

- [marker-pdf PyPI](https://pypi.org/project/marker-pdf/)
- [marker-pdf Usage Documentation](https://github.com/VikParuchuri/marker)
