# olmocr Implementation Plan

**Date:** 2026-01-14
**Status:** Planning

## Overview

olmocr is Allen AI's PDF-to-Markdown conversion toolkit using a 7B parameter vision-language model. It's designed for creating clean LLM training datasets from PDFs.

**GitHub:** https://github.com/allenai/olmocr
**License:** Apache 2.0

## Key Features

- Converts PDFs to clean Markdown
- Handles equations, tables, handwriting, and complex formatting
- Removes headers/footers automatically
- Preserves natural reading order in multi-column layouts
- Uses vLLM for GPU inference

## Hardware Requirements

- **GPU:** NVIDIA GPU with 12GB+ VRAM (T4 has 16GB - should work)
- **Disk:** ~30GB free space for model weights
- **Model Size:** 7B parameters (larger than DeepSeek-OCR's 3B)

## Proposed Configuration

```python
"olmocr": ModelConfig(
    name="olmocr",
    cpu=4096,  # 4 vCPU on g4dn.xlarge
    memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
    container_path="olmocr",
    output_formats=("markdown",),
    timeout_minutes=30,
    use_gpu=True,
    gpu_count=1,
    instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
    spot_enabled=True,
    min_capacity=0,
    max_capacity=2,
    ebs_volume_size_gb=100,  # 7B model + vLLM + headroom
),
```

## Implementation Steps

### 1. Create Container Files

Create `backend/containers/olmocr/`:
- `Dockerfile` - CUDA base image with vLLM and olmocr
- `task.py` - Processing script
- `buildspec.yml` - CodeBuild specification

### 2. Dockerfile Considerations

```dockerfile
# Key dependencies:
# - CUDA 12.x base image (for vLLM)
# - vLLM for GPU inference
# - olmocr[gpu] package
# - poppler-utils for PDF rendering
# - System fonts for text rendering

# Installation:
pip install olmocr[gpu] --extra-index-url https://download.pytorch.org/whl/cu128
```

**Challenges:**
- vLLM requires specific CUDA version compatibility
- Model pre-download during build (~15GB+ with vLLM cache)
- May need larger build instance (BUILD_GENERAL1_2XLARGE)

### 3. Task Script Pattern

```python
# olmocr provides a pipeline CLI, but we may need to use Python API
# Check: python -m olmocr.pipeline --help

# Expected flow:
# 1. Download PDF from S3
# 2. Run olmocr pipeline on PDF
# 3. Read generated Markdown output
# 4. Upload to S3
# 5. Update DynamoDB status
```

### 4. Deploy Infrastructure

```bash
# Add model config to stack_config.py
# Deploy stacks:
make cdk-deploy STACK=FoundationStack  # ECR repo
make cdk-deploy STACK=CiCdStack        # CodeBuild project
make cdk-deploy STACK=OlmocrStack      # ECS + Step Functions
```

### 5. Build and Test

```bash
make container-build MODEL=olmocr
make test-integration-cloud MODEL=olmocr
```

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| T4 GPU insufficient (16GB vs 12GB req) | Low | Model claims 12GB min, T4 has 16GB |
| vLLM compatibility issues | Medium | Pin specific vLLM version, test locally first |
| Large container build time | High | Use larger CodeBuild instance, optimize layers |
| Model download fails in isolated subnet | Medium | Pre-download in Dockerfile, set offline mode |

## Questions to Resolve

1. **vLLM vs Transformers:** Does olmocr require vLLM or can it use transformers directly?
2. **Python API:** Is there a programmatic API or only CLI?
3. **Output format:** Does it output to stdout or files?
4. **Memory usage:** Actual VRAM usage with 7B model on T4?

## Next Steps

1. Research olmocr Python API usage (vs CLI)
2. Create Dockerfile with vLLM + olmocr
3. Test locally if possible
4. Create task.py processing script
5. Deploy and run integration tests

## Reference: Existing GPU Models

- `dolphin` - VLM with transformers, g4dn.xlarge
- `deepseek-ocr` - 3B VLM with flash-attention, g4dn.xlarge
- Both use similar patterns for GPU container setup
