# MinerU Implementation Status

**Date:** 2026-01-14
**Status:** Complete

## Summary

MinerU has been successfully integrated as a new PDF processing model. All infrastructure has been deployed and integration tests pass.

## Implementation Details

### Model Configuration
Added to `backend/backend/stack_config.py`:
```python
"mineru": ModelConfig(
    name="mineru",
    cpu=4096,  # 4 vCPU
    memory_mib=16384,  # 16GB
    container_path="mineru",
    output_formats=("markdown", "json"),
    timeout_minutes=30,
    ephemeral_storage_gib=50,  # ~5GB models + image layers
),
```

### Container Files
- `backend/containers/mineru/Dockerfile` - Container with MinerU 2.x and pre-downloaded models
- `backend/containers/mineru/task.py` - Processing script using `do_parse()` API
- `backend/containers/mineru/buildspec.yml` - CodeBuild specification

### Infrastructure Deployed
- ECR repository: `pdf-models/mineru`
- ECS cluster and task definition with 50GB ephemeral storage
- Step Functions state machine: `pdf-models-mineru`
- CloudWatch log group: `/ecs/pdf-models-mineru`

## Issues Resolved

### 1. MinerU 2.x API Changes
**Problem:** Package renamed from `magic_pdf` to `mineru`
**Fix:** Updated imports and switched to high-level `do_parse()` function

### 2. Model Download in Dockerfile
**Problem:** Interactive `mineru-models-download` command fails in Docker
**Fix:** Used `huggingface_hub.snapshot_download()` SDK directly

### 3. HuggingFace Cache Path
**Problem:** Models not found when `HF_HUB_OFFLINE=1`
**Fix:** Let HuggingFace Hub use its standard cache structure (removed `local_dir` parameter)

### 4. Fargate Ephemeral Storage
**Problem:** Container image (~5GB) exceeds Fargate's default 20GB ephemeral storage
**Fix:** Added `ephemeral_storage_gib` field to `ModelConfig` and set mineru to 50GB

## Test Results

Integration tests pass:
- `test_submit_and_process_pdf` - Verifies end-to-end PDF processing
- `test_list_jobs` - Verifies job listing API

## Files Modified/Created

| File | Status | Description |
|------|--------|-------------|
| `backend/backend/stack_config.py` | Modified | Added mineru config + ephemeral_storage_gib field |
| `backend/backend/model_stack.py` | Modified | Use ephemeral_storage_gib in FargateTaskDefinition |
| `backend/containers/mineru/Dockerfile` | Created | Container with MinerU 2.x |
| `backend/containers/mineru/task.py` | Created | Processing script |
| `backend/containers/mineru/buildspec.yml` | Created | CodeBuild spec |
| `backend/tests/integration/test_mineru_e2e.py` | Created | Integration tests |
| `Makefile` | Modified | Added pre-flight git checks to container-build |

## Relevant Commits

1. `0743316` - Fix MinerU imports for 2.x API
2. `dece086` - Fix boto3 scoping issue in conftest.py
3. `700a9d8` - Add ephemeral storage config for Fargate tasks
4. `f902000` - Fix MinerU model cache path

## Usage

```bash
# Deploy stack (if needed)
make cdk-deploy STACK=MineruStack

# Build container
make container-build MODEL=mineru

# Run integration tests
make test-integration-cloud MODEL=mineru
```
