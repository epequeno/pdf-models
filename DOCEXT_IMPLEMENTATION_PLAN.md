# docext (Nanonets-OCR) Implementation Plan

**Date:** 2026-01-14
**Status:** Planning

## Overview

docext is NanoNets' document intelligence toolkit featuring Nanonets-OCR-s, a 3B parameter vision-language model for PDF/image to Markdown conversion with semantic understanding.

**GitHub:** https://github.com/NanoNets/docext
**Model:** https://huggingface.co/nanonets/Nanonets-OCR-s
**License:** Apache 2.0

## Key Features

- PDF/image to structured Markdown conversion
- LaTeX equation recognition (inline and display)
- Table extraction with structure preservation
- Signature and watermark detection
- Intelligent image descriptions via `<img>` tags
- Semantic tagging for LLM downstream processing

## Model Details

| Attribute | Value |
|-----------|-------|
| Model | Nanonets-OCR-s |
| Parameters | ~4B (based on Qwen2.5-VL-3B-Instruct) |
| Architecture | Vision-Language Model |
| Inference | vLLM or Transformers |
| HuggingFace | nanonets/Nanonets-OCR-s |

**Alternative:** Nanonets-OCR2-3B (newer version)

## Hardware Requirements

- **GPU:** CUDA-compatible GPU (similar to DeepSeek-OCR 3B)
- **VRAM:** ~8-12GB expected (3B model, similar to DeepSeek-OCR)
- **Instance:** g4dn.xlarge should be sufficient (T4 16GB)

## Proposed Configuration

```python
"docext": ModelConfig(
    name="docext",
    cpu=4096,  # 4 vCPU on g4dn.xlarge
    memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
    container_path="docext",
    output_formats=("markdown",),
    timeout_minutes=30,
    use_gpu=True,
    gpu_count=1,
    instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
    spot_enabled=True,
    min_capacity=0,
    max_capacity=2,
    ebs_volume_size_gb=80,  # 3B model + vLLM/transformers
),
```

## Architecture Options

### Option A: Use docext Package (Gradio Server)
```python
# docext runs as a Gradio web server
# pip install docext
# python -m docext.app.app --model_name hosted_vllm/nanonets/Nanonets-OCR-s

# Would need to:
# 1. Start server in background
# 2. Call API endpoints
# 3. More complex container setup
```

**Pros:** Official supported path
**Cons:** Extra complexity, Gradio overhead, reported vLLM issues

### Option B: Use Model Directly via Transformers (Recommended)
```python
# Load model directly like DeepSeek-OCR
from transformers import AutoModel, AutoTokenizer
import torch

model = AutoModel.from_pretrained(
    "nanonets/Nanonets-OCR-s",
    trust_remote_code=True,
    torch_dtype=torch.bfloat16
).cuda()
```

**Pros:** Simpler, consistent with other models, no server overhead
**Cons:** May miss docext-specific preprocessing

## Implementation Steps

### 1. Create Container Files

Create `backend/containers/docext/`:
- `Dockerfile` - CUDA base with transformers/vLLM
- `task.py` - Processing script
- `buildspec.yml` - CodeBuild specification

### 2. Dockerfile Pattern

```dockerfile
# Similar to deepseek-ocr container
FROM nvcr.io/nvidia/cuda:12.1.0-devel-ubuntu22.04 AS builder
# ... flash-attention build ...

FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04
# Install transformers, torch, etc.
# Pre-download nanonets/Nanonets-OCR-s model
```

### 3. Task Script Pattern

```python
# Based on Qwen2.5-VL architecture
from transformers import AutoProcessor, AutoModelForVision2Seq

processor = AutoProcessor.from_pretrained("nanonets/Nanonets-OCR-s")
model = AutoModelForVision2Seq.from_pretrained(
    "nanonets/Nanonets-OCR-s",
    torch_dtype=torch.bfloat16,
    device_map="cuda"
)

# Process PDF pages as images
# Generate markdown output
```

### 4. Deploy Infrastructure

```bash
make cdk-deploy STACK=FoundationStack  # ECR repo
make cdk-deploy STACK=CiCdStack        # CodeBuild project
make cdk-deploy STACK=DocextStack      # ECS + Step Functions
```

### 5. Build and Test

```bash
make container-build MODEL=docext
make test-integration-cloud MODEL=docext
```

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| vLLM compatibility issues | High | Use transformers directly instead |
| Model loading differences from DeepSeek | Medium | Test Qwen2.5-VL loading pattern |
| Preprocessing requirements | Medium | Review docext source for image prep |

## Known Issues

- vLLM compatibility issues reported on HuggingFace discussions
- Model is based on Qwen2.5-VL, may need specific processor

## Questions to Resolve

1. **Transformers vs vLLM:** Can we use transformers directly or is vLLM required?
2. **Image preprocessing:** What preprocessing does docext apply before model inference?
3. **Prompt format:** What system/user prompt format does the model expect?
4. **OCR2 vs OCR-s:** Should we use the newer Nanonets-OCR2-3B instead?

## References

- [Nanonets-OCR-s on HuggingFace](https://huggingface.co/nanonets/Nanonets-OCR-s)
- [Nanonets-OCR2-3B on HuggingFace](https://huggingface.co/nanonets/Nanonets-OCR2-3B)
- [vLLM Issues Discussion](https://huggingface.co/nanonets/Nanonets-OCR-s/discussions/22)
- [HuggingFace OCR Blog](https://huggingface.co/blog/ocr-open-models)

## Comparison with Existing Models

| Model | Params | Backend | Instance | Notes |
|-------|--------|---------|----------|-------|
| DeepSeek-OCR | 3B | Transformers | g4dn.xlarge | Working, flash-attn |
| Dolphin | VLM | Transformers | g4dn.xlarge | Working, prompts |
| docext | 3B | Transformers? | g4dn.xlarge | Qwen2.5-VL based |
| olmocr | 7B | vLLM | g4dn.xlarge | Larger model |
