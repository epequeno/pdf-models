---
name: aws-container-debugging
description: Debug AWS CodeBuild container builds, ECR image issues, and ECS task failures. Use when troubleshooting Docker builds, container deployments, ECS tasks not starting, or permission errors in containers.
---

# AWS Container Debugging

Debug container build and deployment issues in the CodeBuild → ECR → ECS pipeline.

## Quick diagnostics

**Check latest CodeBuild status**:
```bash
AWS_PROFILE=arch aws codebuild list-builds-for-project \
  --project-name pdf-models-marker-container-build \
  --max-items 1 --query 'ids[0]' --output text | \
xargs -I {} aws codebuild batch-get-builds --ids {} \
  --query 'builds[0].[buildStatus,currentPhase]' --output json
```

**Get CodeBuild logs** (last 100 lines):
```bash
python .claude/skills/aws-container-debugging/scripts/get_build_logs.py
```

**Check latest ECR image**:
```bash
AWS_PROFILE=arch aws ecr describe-images \
  --repository-name pdf-models/marker \
  --query 'imageDetails | sort_by(@, &imagePushedAt) | [-1].[imageTags[0],imageDigest,imagePushedAt]' \
  --output table
```

**Check ECS task logs** (last 10 minutes):
```bash
AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m --format short
```

## Common issues

### Exit code 137 - Out of Memory

**Symptom**: Docker build killed during execution, CodeBuild shows exit code 137

**Cause**: Build instance ran out of memory (common with large model downloads)

**Solution**: Increase CodeBuild compute type in `backend/backend/cicd_stack.py`:
- SMALL (3 GB) → MEDIUM (7 GB)
- MEDIUM (7 GB) → LARGE (15 GB)

```python
compute_type=codebuild.ComputeType.MEDIUM,  # Or LARGE
```

Then deploy: `make cdk-deploy STACK=CiCdStack`

### ModuleNotFoundError in container

**Symptom**: ECS task logs show `ModuleNotFoundError` for Python packages

**Cause**: Missing dependency in Dockerfile or incorrect installation order

**Solution**:
1. Check Dockerfile for proper dependency installation
2. Some packages (like marker-pdf) require dependencies installed first:
   ```dockerfile
   RUN pip install pypdfium2  # Install first
   RUN pip install marker-pdf  # Then install marker
   ```
3. Rebuild: `make container-build MODEL=marker`

### Permission denied in container

**Symptom**: Container fails with "Permission denied" when writing to directories

**Cause**: Container user lacks write permissions to system directories

**Solution**: Redirect to writable directories using environment variables

Example from Marker container fix:
```dockerfile
# Create writable directories
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

# Set environment variables to redirect
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static
```

### ECS not using latest image

**Symptom**: Rebuilt container but ECS tasks still fail with old errors

**Cause**: ECS is using cached task definition or old image

**Diagnostic**: Check which image digest ECS task is using:
```bash
python .claude/skills/aws-container-debugging/scripts/check_task_image.py
```

**Solution**:
1. Verify image was pushed to ECR (check digest)
2. Check task definition references correct image
3. For this project: pipeline auto-updates via SSM parameter

See [DEPLOYMENT.md](DEPLOYMENT.md) for deployment pipeline details.

## Workflow: Debugging a failed container build

1. **Check build status**: Run quick diagnostics (above)
2. **Get full logs**: `python scripts/get_build_logs.py`
3. **Identify failure phase**: BUILD, POST_BUILD, or other
4. **Check error patterns**:
   - Exit code 137 → Memory issue
   - "command not found" → Missing dependency
   - "Permission denied" → File permissions
5. **Fix Dockerfile** in `backend/containers/marker/`
6. **Commit and push**: CodeBuild pulls from CodeCommit, not local files
7. **Rebuild**: `make container-build MODEL=marker`
8. **Monitor**: Watch logs in real-time or check status

## Workflow: Debugging ECS task failures

1. **Get recent task logs**: `AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m`
2. **Find error message**: Look for Python tracebacks, exit codes
3. **Check task stopped reason**:
   ```bash
   python .claude/skills/aws-container-debugging/scripts/get_stopped_tasks.py
   ```
4. **Common patterns**:
   - S3 access denied → Check IAM task role permissions
   - Module not found → Missing dependency in Dockerfile
   - Permission denied → Directory permissions issue
5. **Fix and rebuild** container if needed
6. **Verify fix**: Run integration test or trigger new job

## Critical reminders

- **CodeBuild pulls from CodeCommit**: Always commit and push before rebuilding
- **Image digests matter**: Same tag doesn't mean same image; check digest
- **Task definitions cache**: ECS may need explicit update to use new image
- **Memory requirements**: Model downloads need MEDIUM or LARGE instances
- **Log locations**: CodeBuild in `/aws/codebuild/`, ECS in `/ecs/`

## Reference files

- [DEPLOYMENT.md](DEPLOYMENT.md) - Full deployment pipeline flow
- [COMMON_ERRORS.md](COMMON_ERRORS.md) - Error patterns and solutions
