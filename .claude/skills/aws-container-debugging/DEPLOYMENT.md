# Container Deployment Pipeline

## Full pipeline flow

```
Local Code
    ↓ (git commit && git push)
CodeCommit Repository
    ↓ (triggered by make container-build)
CodeBuild Project
    ↓ (docker build)
Docker Image
    ↓ (docker push)
ECR Repository
    ↓ (SSM parameter update)
Task Definition ARN in SSM
    ↓ (Step Functions reads SSM)
ECS Task Definition
    ↓ (ECS RunTask)
Running Container
```

## Step-by-step deployment

### 1. Code changes

Edit files in `backend/containers/marker/`:
- `Dockerfile` - Container build instructions
- `task.py` - Task entry point
- `requirements.txt` - Python dependencies

### 2. Commit and push

**CRITICAL**: CodeBuild pulls from CodeCommit, not local files.

```bash
git add backend/containers/marker/
git commit -m "Fix container issue"
git push
```

### 3. Trigger build

```bash
make container-build MODEL=marker
```

This triggers CodeBuild project `pdf-models-marker-container-build`.

### 4. Monitor build

Check status:
```bash
AWS_PROFILE=arch aws codebuild list-builds-for-project \
  --project-name pdf-models-marker-container-build \
  --max-items 1
```

Watch logs:
```bash
python .claude/skills/aws-container-debugging/scripts/get_build_logs.py
```

### 5. Build process

CodeBuild performs:
1. Pulls code from CodeCommit (main branch)
2. Navigates to `backend/containers/marker/`
3. Runs `docker build -t $ECR_REPOSITORY_URI:latest .`
4. Tags image with commit hash (e.g., `3994348`)
5. Pushes both `:latest` and `:COMMIT_HASH` tags to ECR
6. Updates SSM parameter `/pdf-models/cicd/marker-image-tag`

### 6. ECS picks up new image

**Automatic** (for this project):
- Step Functions reads task definition ARN from SSM at runtime
- Task definition uses `:latest` tag (or specific tag)
- New tasks automatically use new image

**Verification**:
```bash
python .claude/skills/aws-container-debugging/scripts/check_task_image.py
```

## Deployment verification checklist

After rebuild, verify:

- [ ] CodeBuild succeeded: Check build status
- [ ] Image in ECR: Check digest and tags
- [ ] SSM parameter updated: Check `/pdf-models/cicd/marker-image-tag`
- [ ] New task uses new image: Run test job, check task image digest
- [ ] Task completes successfully: Check ECS logs

## Common deployment issues

### Issue: Build succeeded but tasks still fail

**Diagnosis**:
1. Check ECR image digest
2. Check what digest ECS task is using
3. Compare the two

**Causes**:
- Task definition cached old image
- Using specific tag instead of `:latest`
- SSM parameter not updated

### Issue: "No changes detected" in build

**Cause**: Forgot to commit and push changes

**Solution**:
```bash
git status  # Check what's modified
git add <files>
git commit -m "Description"
git push
```

Then rebuild.

### Issue: Build fails immediately

**Cause**: CodeCommit doesn't have latest code

**Verify**:
```bash
AWS_PROFILE=arch aws codecommit get-file \
  --repository-name pdf-models \
  --file-path backend/containers/marker/Dockerfile \
  --commit-specifier main \
  --query 'fileContent' --output text | base64 -d
```

Compare with local file.
