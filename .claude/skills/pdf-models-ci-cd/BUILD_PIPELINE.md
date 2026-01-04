# Build Pipeline Details

Detailed diagrams and flow for all build pipelines.

## Container build pipeline

```
Developer
  ↓
Edit Dockerfile/task.py
  ↓
git commit && git push
  ↓
CodeCommit Repository (main branch)
  ↓ (manual trigger: make container-build MODEL=marker)
CodeBuild Project: pdf-models-marker-container-build
  ├─ Phase: PRE_BUILD
  │   ├─ Login to ECR
  │   ├─ Get commit hash
  │   └─ Set IMAGE_TAG
  ├─ Phase: BUILD
  │   ├─ cd backend/containers/marker
  │   ├─ docker build -t $ECR_URI:latest .
  │   └─ docker tag $ECR_URI:latest $ECR_URI:$IMAGE_TAG
  └─ Phase: POST_BUILD
      ├─ docker push $ECR_URI:latest
      ├─ docker push $ECR_URI:$IMAGE_TAG
      └─ aws ssm put-parameter --name /pdf-models/cicd/marker-image-tag --value $IMAGE_TAG
  ↓
ECR Repository: pdf-models/marker
  ├─ Image: latest (digest: sha256:abc...)
  └─ Image: 3994348 (digest: sha256:abc...)
  ↓
SSM Parameter Updated
  └─ /pdf-models/cicd/marker-image-tag = "3994348"
  ↓
Next ECS Task Uses New Image
  └─ Step Functions → Resolve task def → ECS RunTask → Pull latest image
```

**Build time breakdown**:
- PRE_BUILD: ~30 seconds
- BUILD: 5-15 minutes (depends on Docker cache and model downloads)
- POST_BUILD: 2-5 minutes (image push)

**Total**: 8-20 minutes

## Lambda build pipeline

```
Developer
  ↓
Edit Rust Lambda code
  ↓
git commit && git push
  ↓
CodeCommit Repository
  ↓ (manual trigger: make lambda-build)
CodeBuild Project: pdf-models-rust-lambda-build
  ├─ Uses custom ECR image: rust-lambda-builder
  │   (Pre-installed: Rust, cargo-lambda, build tools)
  ├─ Phase: BUILD
  │   ├─ cd backend/lambdas
  │   ├─ For each Lambda directory:
  │   │   ├─ cargo lambda build --release
  │   │   └─ zip bootstrap → <function-name>.zip
  │   └─ Upload to S3
  └─ Phase: POST_BUILD
      ├─ For each Lambda:
      │   ├─ aws lambda update-function-code
      │   └─ --s3-bucket <bucket> --s3-key lambda-artifacts/<name>.zip
      └─ Publish new version
  ↓
S3 Bucket
  └─ lambda-artifacts/
      ├─ submit-job.zip
      ├─ get-job.zip
      └─ list-jobs.zip
  ↓
Lambda Functions Updated
  ├─ pdf-models-submit-job
  ├─ pdf-models-get-job
  └─ pdf-models-list-jobs
```

**Build time breakdown**:
- BUILD: 8-12 minutes (Rust compilation)
- POST_BUILD: 1-2 minutes (upload + update functions)

**Total**: 10-15 minutes

## Base image build pipeline (one-time)

```
Developer
  ↓
(First-time setup)
  ↓
make base-image-build
  ↓
CodeBuild Project: pdf-models-rust-lambda-builder-build
  ├─ Uses: aws/codebuild/standard:7.0
  ├─ Phase: BUILD (~30 minutes)
  │   ├─ Install Rust toolchain
  │   ├─ Install cargo-lambda
  │   ├─ Install build dependencies
  │   └─ docker build -t rust-lambda-builder
  └─ Phase: POST_BUILD
      └─ docker push to ECR
  ↓
ECR Repository: pdf-models/rust-lambda-builder
  └─ Image: latest (includes Rust + cargo-lambda)
  ↓
Used by Lambda Build Pipeline
  └─ CodeBuild pulls this as build environment
```

**Build time**: ~30 minutes (first time only)

**Frequency**: Once, or when updating Rust version

## CDK deployment pipeline

```
Developer
  ↓
Edit CDK stack code (backend/backend/*_stack.py)
  ↓
make cdk-synth  (Optional: check for errors)
  ↓
make cdk-diff STACK=MarkerStack  (Optional: preview changes)
  ↓
make cdk-deploy STACK=MarkerStack
  ↓
CDK (runs locally)
  ├─ Synthesize CloudFormation template
  │   ├─ Read SSM parameters (cached at synth time)
  │   ├─ Generate template JSON
  │   └─ Write to cdk.out/
  ├─ Upload assets to S3 (if needed)
  │   └─ Lambda code, Docker images, etc.
  └─ Deploy via CloudFormation
      ├─ Create changeset
      ├─ Execute changeset
      └─ Wait for completion
  ↓
CloudFormation Stack
  ├─ Resources created/updated
  ├─ Outputs exported
  └─ SSM parameters created
  ↓
Infrastructure Live
```

**Deploy time**: 1-5 minutes per stack

**No build process** - runs directly from local machine

## Integration test pipeline

```
Developer
  ↓
make test-integration-auto
  ↓
Test Setup Script
  ├─ Create Cognito test user
  │   ├─ Email: integration-test@pdf-models.local
  │   └─ Password: TestPass123!
  └─ Set environment variables
  ↓
Pytest (backend/tests/integration/)
  ├─ Test: Unauthenticated access → 401
  ├─ Test: List jobs (empty) → 200
  ├─ Test: Submit job
  │   ├─ Upload PDF to S3
  │   ├─ POST /models/marker/jobs
  │   ├─ Verify job created in DynamoDB
  │   └─ Verify Step Functions execution started
  ├─ Test: Get job status
  │   └─ GET /models/marker/jobs/{id}
  └─ Test: Wait for completion
      ├─ Poll job status
      ├─ Wait for "completed" status
      └─ Verify output in S3
  ↓
Test Results
  ├─ Pass: All tests succeeded
  └─ Fail: Show which test failed + logs
```

**Test time**: 2-3 minutes (plus job processing time if testing end-to-end)

## Dependency flow between pipelines

```
Base Image Build (once)
  ↓
  ├─→ Lambda Build (uses base image)
  │     ↓
  │     └─→ API Stack Deploy (uses Lambda .zip files)
  │           ↓
  │           └─→ Integration Tests
  │
  └─→ Container Build (independent)
        ↓
        └─→ Marker Stack uses new image (automatic via SSM)
              ↓
              └─→ Integration Tests
```

## Caching strategies

### Docker layer caching

CodeBuild caches Docker layers between builds:
- Base image layers (python:3.11-slim): Always cached
- Dependency layers (pip install): Cached if requirements.txt unchanged
- Application layers: Rebuilt every time

**Optimization**: Order Dockerfile to maximize cache hits:
```dockerfile
# Rarely changes - good cache
FROM python:3.11-slim

# Changes occasionally - okay cache
COPY requirements.txt .
RUN pip install -r requirements.txt

# Changes frequently - poor cache
COPY . .
```

### Rust compilation caching

Lambda builds cache Rust compilation artifacts:
- `target/` directory cached between builds
- Only changed crates recompiled
- Significantly faster second build

**First build**: 12-15 minutes
**Subsequent builds**: 2-5 minutes (if minor changes)

### CDK asset caching

CDK caches assets in S3:
- Lambda `.zip` files
- Docker images
- CloudFormation templates

Only uploads if hash changed.

## Parallel vs sequential builds

### Can run in parallel:
- Container build + Lambda build (independent)
- Multiple Lambda builds (if we had multiple Lambda build projects)
- CDK synth for multiple stacks

### Must run sequentially:
- Base image build → Lambda build (Lambda needs base image)
- Build → Deploy → Test (each depends on previous)
- Stack deploys with dependencies (Foundation → Core → Marker)

## Rollback strategies

### Container rollback

**Option 1**: Redeploy previous image tag
```bash
# Update SSM parameter to previous commit hash
AWS_PROFILE=arch aws ssm put-parameter \
  --name /pdf-models/cicd/marker-image-tag \
  --value "abc1234" \
  --overwrite

# Next task uses old image
```

**Option 2**: Revert code and rebuild
```bash
git revert HEAD
git push
make container-build MODEL=marker
```

### Lambda rollback

**Option 1**: Revert to previous version
```bash
AWS_PROFILE=arch aws lambda update-function-code \
  --function-name pdf-models-submit-job \
  --s3-bucket <bucket> \
  --s3-key lambda-artifacts/submit-job.zip \
  --version-id <previous-version-id>
```

**Option 2**: Revert code and rebuild
```bash
git revert HEAD
git push
make lambda-build
```

### Infrastructure rollback

**Option 1**: Revert CDK code
```bash
git revert HEAD
make cdk-deploy STACK=MarkerStack
```

**Option 2**: CloudFormation rollback
```bash
AWS_PROFILE=arch aws cloudformation cancel-update-stack \
  --stack-name MarkerStack
```

**Note**: Some resources can't be rolled back (data loss risk).

## Build notifications (future enhancement)

Potential improvements:
- SNS topic for build failures
- Slack notifications on build completion
- CloudWatch alarms for failed builds
- Email on integration test failures

**Example CDK**:
```python
build_project.on_build_failed("BuildFailed",
    target=targets.SnsTopic(build_alerts_topic)
)
```
