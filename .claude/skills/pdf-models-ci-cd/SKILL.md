---
name: pdf-models-ci-cd
description: Complete CI/CD workflow for the pdf-models project including code changes, builds, deployments, and testing. Use when planning deployments, troubleshooting build pipelines, or verifying changes are live.
---

# PDF Models CI/CD Workflow

Complete workflows for developing, building, and deploying the pdf-models project.

## Quick reference

**Build container**:
```bash
make container-build MODEL=marker
```

**Build Lambdas**:
```bash
make lambda-build
```

**Deploy infrastructure**:
```bash
make cdk-deploy STACK=MarkerStack
```

**Run integration tests**:
```bash
make test-integration-auto
```

## Complete workflows

### Workflow 1: Fixing a container issue

**Scenario**: Container fails, need to fix and redeploy

1. **Identify issue** from logs:
   ```bash
   AWS_PROFILE=arch aws logs tail /ecs/pdf-models-marker --since 10m
   ```

2. **Edit container files**:
   - `backend/containers/marker/Dockerfile`
   - `backend/containers/marker/task.py`
   - `backend/containers/marker/requirements.txt`

3. **Test locally** (optional):
   ```bash
   cd backend/containers/marker
   docker build -t marker-test .
   docker run marker-test
   ```

4. **Commit and push**:
   ```bash
   git add backend/containers/marker/
   git commit -m "Fix: [describe issue]"
   git push
   ```

5. **Trigger build**:
   ```bash
   make container-build MODEL=marker
   ```

6. **Monitor build** (~5-10 minutes):
   ```bash
   # Check status
   AWS_PROFILE=arch aws codebuild list-builds-for-project \
     --project-name pdf-models-marker-container-build \
     --max-items 1

   # Watch logs
   python .claude/skills/aws-container-debugging/scripts/get_build_logs.py
   ```

7. **Verify deployment**:
   - New image pushed to ECR (check digest)
   - SSM parameter updated
   - Next job uses new image

8. **Test**:
   ```bash
   make test-integration-auto
   ```

**Total time**: 10-15 minutes

### Workflow 2: Updating Lambda functions

**Scenario**: Need to modify API Lambda logic

1. **Edit Lambda code**:
   ```bash
   cd backend/lambdas/<lambda-name>/src
   # Edit Rust files
   ```

2. **Test locally**:
   ```bash
   cd backend/lambdas/<lambda-name>
   cargo test
   cargo build --release
   ```

3. **Commit and push**:
   ```bash
   git add backend/lambdas/
   git commit -m "Update: [describe change]"
   git push
   ```

4. **Trigger Lambda build**:
   ```bash
   make lambda-build
   ```

5. **Monitor build** (~10-15 minutes):
   ```bash
   AWS_PROFILE=arch aws codebuild list-builds-for-project \
     --project-name pdf-models-rust-lambda-build \
     --max-items 1
   ```

6. **Deploy updated stack**:
   ```bash
   make cdk-deploy STACK=ApiV2Stack
   ```

7. **Test**:
   ```bash
   make test-integration-auto
   ```

**Total time**: 20-30 minutes

### Workflow 3: Infrastructure changes

**Scenario**: Modify CDK stack (add resource, change config)

1. **Edit stack file**:
   ```bash
   cd backend/backend
   # Edit *_stack.py files
   ```

2. **Synthesize** to check for errors:
   ```bash
   make cdk-synth
   ```

3. **Review changes**:
   ```bash
   make cdk-diff STACK=MarkerStack
   ```

4. **Commit**:
   ```bash
   git add backend/backend/
   git commit -m "Infrastructure: [describe change]"
   git push
   ```

5. **Deploy**:
   ```bash
   make cdk-deploy STACK=MarkerStack
   ```

6. **Verify** resources created:
   - Check AWS Console
   - Test affected functionality

7. **Test**:
   ```bash
   make test-integration-auto
   ```

**Total time**: 5-10 minutes (depending on stack size)

### Workflow 4: Full deployment from scratch

**Scenario**: Deploy entire project to new AWS account

1. **Prerequisites**:
   - AWS account configured
   - AWS CLI with AdministratorAccess
   - uv installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

2. **Configure AWS profile**:
   ```bash
   aws configure --profile arch
   # Enter credentials
   ```

3. **Set up project**:
   ```bash
   git clone <repository>
   cd pdf-models
   ```

4. **Deploy all stacks**:
   ```bash
   make cdk-deploy-all
   ```

   This deploys in order:
   1. FoundationStack
   2. CoreInfrastructureStack
   3. CiCdStack
   4. MarkerStack
   5. ApiV2Stack
   6. MonitoringStack
   7. FrontendStack

5. **Build container base image** (one-time, ~30 min):
   ```bash
   make base-image-build
   ```

6. **Build Lambda builder** (uses base image):
   ```bash
   make lambda-build
   ```

7. **Build Marker container**:
   ```bash
   make container-build MODEL=marker
   ```

8. **Set up test user**:
   ```bash
   make test-integration-setup
   ```

9. **Run integration tests**:
   ```bash
   make test-integration-auto
   ```

**Total time**: 60-90 minutes

## Build systems

### Container builds (CodeBuild)

**Project**: `pdf-models-marker-container-build`

**Trigger**:
```bash
make container-build MODEL=marker
```

**Process**:
1. Pull from CodeCommit (main branch)
2. `cd backend/containers/marker/`
3. `docker build -t $ECR_URI:latest .`
4. Tag with commit hash (e.g., `:3994348`)
5. Push `:latest` and `:COMMIT_HASH` to ECR
6. Update SSM parameter with commit hash

**Duration**: 5-15 minutes (first build 15-20 min with model downloads)

**Compute type**: MEDIUM (7 GB RAM)

**Artifacts**:
- ECR image: `pdf-models/marker:latest`
- ECR image: `pdf-models/marker:<commit-hash>`
- SSM param: `/pdf-models/cicd/marker-image-tag`

### Lambda builds (CodeBuild)

**Project**: `pdf-models-rust-lambda-build`

**Trigger**:
```bash
make lambda-build
```

**Process**:
1. Pull from CodeCommit
2. Uses custom builder image (Rust + cargo-lambda pre-installed)
3. Builds each Lambda in `backend/lambdas/`
4. Uploads `.zip` files to S3
5. Updates function code via AWS API

**Duration**: 10-15 minutes

**Artifacts**:
- S3: `s3://<bucket>/lambda-artifacts/<function-name>.zip`
- Updated Lambda function code

### CDK deployments

**Not a build** - deployed directly from local machine

**Process**:
1. Local: `make cdk-deploy STACK=<name>`
2. CDK synthesizes CloudFormation template
3. CDK uploads assets to S3 (if needed)
4. CloudFormation creates/updates resources

**Duration**: 1-5 minutes per stack

## Verification checklist

After any deployment, verify:

### Container deployments

- [ ] CodeBuild succeeded
- [ ] Image in ECR with correct tag and digest
- [ ] SSM parameter `/pdf-models/cicd/marker-image-tag` updated
- [ ] Test job completes successfully
- [ ] ECS task logs show no errors

### Lambda deployments

- [ ] CodeBuild succeeded
- [ ] `.zip` files in S3 `lambda-artifacts/`
- [ ] Lambda function shows updated code
- [ ] Integration tests pass
- [ ] API returns expected responses

### Infrastructure deployments

- [ ] CloudFormation stack in UPDATE_COMPLETE status
- [ ] No CloudFormation errors in events
- [ ] Resources created (check console)
- [ ] SSM parameters created/updated
- [ ] Integration tests pass

## Common issues

### "No changes detected" in build

**Symptom**: Build runs but says "nothing to do"

**Cause**: Forgot to commit/push changes

**Solution**:
```bash
git status  # Check for uncommitted changes
git add <files>
git commit -m "Description"
git push
```

**Remember**: CodeBuild pulls from CodeCommit, not local files.

### Changes not reflected after deploy

**Symptom**: Deployed but behavior unchanged

**Diagnosis checklist**:
1. Did CodeBuild succeed?
2. Is new image in ECR?
3. Is SSM parameter updated?
4. Did CDK deploy complete?
5. Are you testing the right environment?

**Common causes**:
- Build failed silently (check logs)
- ECS using cached image
- CDK change didn't trigger resource update
- SSM parameter cached at synthesis

### Build fails immediately

**Symptom**: CodeBuild fails in seconds

**Common causes**:

**1. Source not found**
```
Error: Could not find buildspec file
```
**Solution**: Verify buildspec path in CDK:
```python
build_spec=codebuild.BuildSpec.from_source_filename(
    "backend/containers/marker/buildspec.yml"
)
```

**2. Permission denied**
```
Error: User is not authorized
```
**Solution**: Check CodeBuild service role has required permissions.

### Integration tests fail after deployment

**Symptom**: Deployment succeeded but tests fail

**Diagnosis**:
1. Check which test failed
2. Check CloudWatch logs for that service
3. Verify resource created (API endpoint, etc.)

**Common causes**:
- API Gateway not deployed
- Lambda function error
- DynamoDB table not ready
- Cognito user pool not configured

## Monitoring builds

### Real-time build monitoring

**CodeBuild console**:
- AWS Console → CodeBuild → Build projects → pdf-models-marker-container-build
- Click latest build → Phase details

**CLI**:
```bash
# Watch build status
watch -n 5 'AWS_PROFILE=arch aws codebuild list-builds-for-project \
  --project-name pdf-models-marker-container-build --max-items 1 \
  --query "ids[0]" --output text | xargs -I {} aws codebuild batch-get-builds \
  --ids {} --query "builds[0].[buildStatus,currentPhase]" --output json'
```

### Build history

```bash
# List last 10 builds
AWS_PROFILE=arch aws codebuild list-builds-for-project \
  --project-name pdf-models-marker-container-build \
  --max-items 10
```

## Environment variables

### Build environment (CodeBuild)

Set in CDK stack:
```python
environment_variables={
    "ECR_REPOSITORY_URI": codebuild.BuildEnvironmentVariable(
        value=ecr_marker_uri
    ),
}
```

Available in buildspec:
```yaml
commands:
  - echo $ECR_REPOSITORY_URI
```

### Runtime environment (ECS)

Set in task definition:
```python
environment={
    "S3_INPUT_KEY": input_key,
    "JOB_ID": job_id,
}
```

Available in container:
```python
import os
s3_key = os.environ['S3_INPUT_KEY']
```

## Reference

- See [BUILD_PIPELINE.md](BUILD_PIPELINE.md) for detailed pipeline diagrams
- See [TESTING.md](TESTING.md) for test strategies
