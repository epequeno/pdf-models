# Common Container Errors

## Python errors

### ModuleNotFoundError: No module named 'marker.convert'

**Symptom**: Container fails immediately on import

**Cause**: Missing dependency. `marker-pdf` requires `pypdfium2` installed first.

**Solution**:
```dockerfile
# Install dependencies first
RUN pip install pypdfium2

# Then install marker
RUN pip install marker-pdf
```

### ModuleNotFoundError: No module named 'X'

**Symptom**: Import error for any Python package

**Diagnosis**: Check if package is in `requirements.txt` or Dockerfile

**Solution**: Add to `requirements.txt` or Dockerfile:
```dockerfile
RUN pip install <package-name>
```

## Permission errors

### Permission denied: /usr/local/lib/python3.11/site-packages/static

**Symptom**: Container fails when library tries to create system directories

**Cause**: Non-root user lacks write permissions to system directories

**Solution**: Redirect to writable location with environment variables:
```dockerfile
# Create writable directory
RUN mkdir -p /app/data && chown -R appuser:appuser /app

# Set env var to redirect
ENV DATA_DIR=/app/data
```

**Real example** (Marker library):
```dockerfile
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static
```

### Permission denied: /var/log/

**Symptom**: Cannot write to log directory

**Solution**: Either:
1. Log to stdout (preferred for containers)
2. Create writable log directory

```python
# Log to stdout instead of file
import logging
logging.basicConfig(stream=sys.stdout, level=logging.INFO)
```

## Build errors

### exit code: 137

**Symptom**: Build killed during execution, no clear error

**Cause**: Out of memory

**Memory by compute type**:
- SMALL: 3 GB
- MEDIUM: 7 GB
- LARGE: 15 GB
- 2XLARGE: 145 GB

**Solution**: Increase compute type in `backend/backend/cicd_stack.py`:
```python
compute_type=codebuild.ComputeType.MEDIUM,
```

Deploy change: `make cdk-deploy STACK=CiCdStack`

### Command not found: docker

**Symptom**: Build fails with "docker: command not found"

**Cause**: Privileged mode not enabled

**Solution**: In buildspec or CDK:
```python
privileged=True,  # Required for Docker builds
```

### Cannot connect to Docker daemon

**Symptom**: "Cannot connect to the Docker daemon at unix:///var/run/docker.sock"

**Cause**: Same as above - privileged mode needed

## Runtime errors

### S3 access denied

**Symptom**: Task fails with `AccessDenied` when accessing S3

**Cause**: ECS task role lacks S3 permissions

**Solution**: Add IAM permissions to task role:
```python
task_role.add_to_policy(
    iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        actions=["s3:GetObject", "s3:PutObject"],
        resources=[f"arn:aws:s3:::{bucket_name}/*"],
    )
)

# Also need ListBucket for some operations
task_role.add_to_policy(
    iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        actions=["s3:ListBucket"],
        resources=[f"arn:aws:s3:::{bucket_name}"],
    )
)
```

### Task stopped: Essential container exited

**Symptom**: ECS task stops immediately, exit code 0 or 1

**Diagnosis**: Check container logs:
```bash
AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m
```

**Common causes**:
- Task completed too quickly (nothing to do)
- Task crashed on startup (check logs for traceback)
- Missing environment variables

## Image/deployment errors

### ECS using old image

**Symptom**: Rebuilt container but same errors occur

**Diagnosis**:
```bash
python .claude/skills/aws-container-debugging/scripts/check_task_image.py
```

**Causes**:
- Task definition cached
- Using specific tag that didn't get updated
- SSM parameter not refreshed

**Solution**: For this project, pipeline auto-updates. Check:
1. ECR has new image (check digest)
2. SSM parameter `/pdf-models/cicd/marker-image-tag` updated
3. Task definition references correct tag

### Image not found in ECR

**Symptom**: `CannotPullContainerError`

**Cause**: Image wasn't pushed or wrong repository

**Diagnosis**:
```bash
AWS_PROFILE=arch aws ecr describe-images \
  --repository-name pdf-models/marker
```

**Solution**: Check buildspec POST_BUILD phase succeeded.

## Model/data errors

### Downloading models at runtime (slow)

**Symptom**: Task takes minutes to start, downloads GBs of data

**Cause**: Models not pre-downloaded in Dockerfile

**Solution**: Download models during build:
```dockerfile
# Pre-download models to avoid runtime downloads
RUN python -c "from marker.models import create_model_dict; create_model_dict()"
```

**Note**: Requires sufficient build memory (MEDIUM or larger).

### Model download fails: Connection timeout

**Symptom**: Build fails downloading large files

**Cause**: Network timeout or insufficient build time

**Solution**: Increase build timeout in CDK:
```python
timeout=Duration.minutes(60),
```
