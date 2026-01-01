# AI Agent Guide

This document contains **critical requirements** for AI agents working on this project. Failure to follow these will result in errors or operations against the wrong AWS account.

## 🚨 Critical Requirements

### 1. AWS Profile Requirement

**ALL AWS and CDK commands MUST be prefixed with `AWS_PROFILE=arch`**

This sets the correct AWS credentials, account, and region automatically.

❌ **WRONG**:
```bash
cdk deploy FoundationStack
aws s3 ls
aws logs tail /aws/lambda/my-function
```

✅ **CORRECT**:
```bash
AWS_PROFILE=arch cdk deploy FoundationStack
AWS_PROFILE=arch aws s3 ls
AWS_PROFILE=arch aws logs tail /aws/lambda/my-function
```

**Why**: Without this prefix, commands will fail or operate against the wrong AWS account, potentially causing serious issues.

**Better approach**: Use the provided Makefile which automatically includes the AWS_PROFILE prefix.

### 2. Python/CDK Commands Must Use uv

This project uses `uv` for Python dependency management. Running bare `python` or `cdk` commands will fail because they won't use the correct virtual environment.

❌ **WRONG**:
```bash
python -m pytest
cdk synth
pip install boto3
```

✅ **CORRECT**:
```bash
uv run python -m pytest
uv run cdk synth
uv add boto3
```

**Why**: `uv` manages the virtual environment and dependencies. Bare commands won't have access to installed packages.

**Better approach**: Use the provided Makefile which automatically uses `uv run` for all commands.

## Recommended Workflow: Use the Makefile

To avoid manually prefixing commands, use the Makefile:

```bash
# CDK operations
make cdk-synth
make cdk-diff STACK=FoundationStack
make cdk-deploy STACK=FoundationStack
make cdk-destroy STACK=FoundationStack

# AWS operations
make aws-logs LOGGROUP=/aws/lambda/my-function
make aws-s3-ls

# Container operations
make container-build MODEL=marker
```

See `Makefile` for all available commands.

## Project-Specific Patterns

### Stack Communication
- Stacks communicate via **SSM Parameter Store** (not CloudFormation exports)
- Never use `Fn::ImportValue` or CloudFormation exports
- Always write to SSM and read from SSM for cross-stack references

**Example**:
```python
# Writing (in CoreInfrastructureStack)
ssm.StringParameter(self, "S3BucketParam",
    parameter_name="/pdf-models/core/s3-bucket-name",
    string_value=bucket.bucket_name
)

# Reading (in MarkerStack)
bucket_name = ssm.StringParameter.value_from_lookup(
    self, "/pdf-models/core/s3-bucket-name"
)
```

### No Local AWS Operations
- All container builds happen in CodeBuild (not locally)
- All deployments eventually happen in CodePipeline
- Local development is for code editing and CDK synthesis only

### Step Functions Use JSONata
- Set `"QueryLanguage": "JSONata"` in all state machines
- Prefer JSONata over JSONPath for better readability

### Lambda Functions in Rust
- If Lambda is needed, use Rust (not Python)
- Avoid Python Lambda to prevent dependency conflicts with CDK
- Keep Lambda handlers thin - just orchestration

## Common Pitfalls

### ❌ Forgetting AWS_PROFILE
**Symptom**: "Unable to locate credentials" or operations on wrong account
**Solution**: Always use `AWS_PROFILE=arch` or the Makefile

### ❌ Running bare CDK commands
**Symptom**: "cdk: command not found" or wrong Python environment
**Solution**: Use `uv run cdk` or the Makefile

### ❌ Using CloudFormation exports
**Symptom**: Can't delete stacks due to export dependencies
**Solution**: Use SSM Parameter Store instead

### ❌ Creating nested/monolithic stacks
**Symptom**: Hard to update individual components
**Solution**: Keep stacks separate, deploy independently

## Quick Reference

| Task | Command |
|------|---------|
| Synth all stacks | `make cdk-synth` |
| Deploy a stack | `make cdk-deploy STACK=FoundationStack` |
| Check what will change | `make cdk-diff STACK=CoreInfrastructureStack` |
| View logs | `make aws-logs LOGGROUP=/aws/lambda/function-name` |
| List S3 buckets | `make aws-s3-ls` |
| Build container | `make container-build MODEL=marker` |

## Stack Deployment Order

Always deploy in this order to satisfy dependencies:

1. `FoundationStack` - ECR, certificates, Route53
2. `CoreInfrastructureStack` - Cognito, S3, DynamoDB
3. `MarkerStack` - Model-specific resources
4. `ApiStack` - API Gateway, Lambda handlers
5. `CiCdStack` - CodeBuild (can be deployed anytime)

## Getting Help

- **Architecture details**: See [backend/docs/architecture.md](backend/docs/architecture.md)
- **Project overview**: See [README.md](README.md)
- **Common tasks**: Run `make help`

## For New Agents Starting a Session

1. Read this file first
2. Check current implementation status in README.md
3. Review architecture.md for system design
4. Use Makefile for all AWS/CDK operations
5. Remember: AWS_PROFILE=arch and uv are non-negotiable
