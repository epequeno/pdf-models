# Lambda Build Optimization Plan

## Problem
Currently, each Lambda (submit-job, get-job, get-upload-url) is built separately, causing shared dependencies to be compiled 3 times:
- `aws-sdk-s3` (all 3)
- `aws-sdk-ssm` (all 3)
- `aws-sdk-dynamodb` (submit-job, get-job)
- `aws-config` (all 3)
- `lambda_runtime`, `tokio`, `serde`, `tracing` (all 3)

This results in ~15 minute builds with MEDIUM compute.

## Solution: Cargo Workspace + S3 Cache

### Part 1: Cargo Workspace

Convert the lambdas directory into a Cargo workspace so all dependencies compile once and are shared.

#### File Changes

**1. Create `backend/lambdas/Cargo.toml` (workspace root)**
```toml
[workspace]
resolver = "2"
members = [
    "submit-job",
    "get-job",
    "get-upload-url",
]

# Shared release profile for all workspace members
[profile.release]
strip = true
opt-level = "z"
lto = true
codegen-units = 1
```

**2. Update `backend/lambdas/submit-job/Cargo.toml`**
```toml
[package]
name = "submit-job"
version = "0.1.0"
edition = "2021"

[dependencies]
lambda_runtime = "1.0.2"
tokio = { version = "1", features = ["macros"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
aws-sdk-dynamodb = "1.60"
aws-sdk-sfn = "1.59"
aws-sdk-s3 = "1.60"
aws-sdk-ssm = "1.60"
aws-config = { version = "1.5", features = ["behavior-version-latest"] }
uuid = { version = "1.11", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Remove [profile.release] - now in workspace root
```

**3. Update `backend/lambdas/get-job/Cargo.toml`**
```toml
[package]
name = "get-job"
version = "0.1.0"
edition = "2021"

[dependencies]
lambda_runtime = "1.0.2"
tokio = { version = "1", features = ["macros"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
aws-sdk-dynamodb = "1.60"
aws-sdk-s3 = "1.60"
aws-sdk-ssm = "1.60"
aws-config = { version = "1.5", features = ["behavior-version-latest"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Remove [profile.release] - now in workspace root
```

**4. Update `backend/lambdas/get-upload-url/Cargo.toml`**
```toml
[package]
name = "get-upload-url"
version = "0.1.0"
edition = "2021"

[dependencies]
lambda_runtime = "1.0.2"
tokio = { version = "1", features = ["macros"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
aws-sdk-s3 = "1.60"
aws-sdk-ssm = "1.60"
aws-config = { version = "1.5", features = ["behavior-version-latest"] }
uuid = { version = "1.11", features = ["v4"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Remove [profile.release] - now in workspace root
```

**5. Update `backend/lambdas/buildspec.yml`**
```yaml
version: 0.2

phases:
  build:
    commands:
      - echo "Building Rust Lambda functions as workspace..."
      - cd backend/lambdas

      # Build all lambdas in one command - dependencies compile once
      - cargo lambda build --release --arm64 --workspace

      - echo "Lambda builds complete"

  post_build:
    commands:
      - echo "Creating individual Lambda deployment packages..."

      # Workspace builds output to: target/lambda/{package-name}/bootstrap
      # Create submit-job.zip
      - cd target/lambda/submit-job
      - zip submit-job.zip bootstrap
      - SUBMIT_JOB_VERSION=$(aws s3api put-object --bucket ${S3_BUCKET_NAME} --key lambda-artifacts/submit-job.zip --body submit-job.zip --query 'VersionId' --output text)
      - echo "submit-job.zip uploaded with version ${SUBMIT_JOB_VERSION}"
      - aws ssm put-parameter --name /pdf-models/lambda/submit-job-version --value ${SUBMIT_JOB_VERSION} --type String --overwrite
      - cd ..

      # Create get-job.zip
      - cd get-job
      - zip get-job.zip bootstrap
      - GET_JOB_VERSION=$(aws s3api put-object --bucket ${S3_BUCKET_NAME} --key lambda-artifacts/get-job.zip --body get-job.zip --query 'VersionId' --output text)
      - echo "get-job.zip uploaded with version ${GET_JOB_VERSION}"
      - aws ssm put-parameter --name /pdf-models/lambda/get-job-version --value ${GET_JOB_VERSION} --type String --overwrite
      - cd ..

      # Create get-upload-url.zip
      - cd get-upload-url
      - zip get-upload-url.zip bootstrap
      - GET_UPLOAD_URL_VERSION=$(aws s3api put-object --bucket ${S3_BUCKET_NAME} --key lambda-artifacts/get-upload-url.zip --body get-upload-url.zip --query 'VersionId' --output text)
      - echo "get-upload-url.zip uploaded with version ${GET_UPLOAD_URL_VERSION}"
      - aws ssm put-parameter --name /pdf-models/lambda/get-upload-url-version --value ${GET_UPLOAD_URL_VERSION} --type String --overwrite
      - cd ..

      - echo "Lambda artifacts uploaded to S3"

cache:
  paths:
    - backend/lambdas/target/**/*

artifacts:
  files:
    - backend/lambdas/target/lambda/submit-job/bootstrap
    - backend/lambdas/target/lambda/get-job/bootstrap
    - backend/lambdas/target/lambda/get-upload-url/bootstrap
  name: rust-lambda-builds
```

### Part 2: S3 Cache in CodeBuild

**6. Update `backend/backend/cicd_stack.py`**

Add S3 cache configuration to the Lambda build project:

```python
# In the lambda_build = codebuild.Project(...) definition, add:
cache=codebuild.Cache.bucket(
    artifacts_bucket,
    prefix="codebuild-cache/lambda-build",
),
```

Full change:
```python
# Create CodeBuild project for Rust Lambda functions
lambda_build = codebuild.Project(
    self,
    "RustLambdaBuild",
    project_name=f"{CONFIG.PROJECT_NAME}-rust-lambda-build",
    description="Build Rust Lambda functions for API",
    source=codebuild.Source.code_commit(
        repository=repo,
        branch_or_ref="main",
    ),
    environment=codebuild.BuildEnvironment(
        build_image=codebuild.LinuxBuildImage.from_ecr_repository(
            repository=ecr.Repository.from_repository_name(
                self,
                "RustBuilderRepo",
                CONFIG.ECR_RUST_LAMBDA_BUILDER_REPO_NAME,
            )
        ),
        compute_type=codebuild.ComputeType.MEDIUM,
        environment_variables={
            "S3_BUCKET_NAME": codebuild.BuildEnvironmentVariable(
                value=s3_bucket_name
            ),
        },
    ),
    build_spec=codebuild.BuildSpec.from_source_filename(
        "backend/lambdas/buildspec.yml"
    ),
    artifacts=codebuild.Artifacts.s3(
        bucket=artifacts_bucket,
        include_build_id=True,
        package_zip=True,
        name="rust-lambda-builds.zip",
    ),
    # ADD THIS: S3 cache for incremental builds
    cache=codebuild.Cache.bucket(
        artifacts_bucket,
        prefix="codebuild-cache/lambda-build",
    ),
)
```

### Part 3: Add Cargo.lock to Git

The workspace will generate a single `Cargo.lock` at the workspace root. This should be committed to ensure reproducible builds.

**7. Update `.gitignore` if needed**

Ensure `backend/lambdas/Cargo.lock` is NOT ignored. Cargo.lock should be committed for binary projects.

### Expected Results

| Metric | Before | After (First Build) | After (Cached Build) |
|--------|--------|---------------------|----------------------|
| Build Time | ~15 min | ~8-10 min | ~2-4 min |
| Dependencies Compiled | 3x | 1x | 0x (cached) |
| Memory Usage | High (3 parallel compiles) | Lower (shared target) | Same |

### Implementation Order

1. Create workspace `Cargo.toml`
2. Remove `[profile.release]` from individual Cargo.toml files
3. Update buildspec.yml with workspace commands
4. Test locally: `cd backend/lambdas && cargo lambda build --release --arm64 --workspace`
5. Commit changes and push
6. Update cicd_stack.py with S3 cache
7. Deploy CiCdStack
8. Trigger build and verify

### Rollback Plan

If issues occur:
1. Revert to individual builds by removing workspace Cargo.toml
2. Restore `[profile.release]` sections to individual Cargo.toml files
3. Revert buildspec.yml changes

### Future Improvements

- **sccache**: Use Mozilla's sccache for compilation caching (requires custom builder image update)
- **Shared library crate**: Extract common types/utilities into a shared `lambda-common` crate within the workspace
- **Parallel artifact upload**: Use `&` to upload zips in parallel in post_build
