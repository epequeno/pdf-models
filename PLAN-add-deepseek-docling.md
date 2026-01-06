# Plan: Add DeepSeek-OCR and Docling Models

## Overview

Add two new document processing models to the platform:
1. **DeepSeek-OCR** - 3B parameter VLM for OCR with visual-text compression
2. **Docling** - 258M parameter model for layout detection and table structure

Both leverage the modular architecture built in the multi-model-dolphin work.

---

## Model Analysis

### DeepSeek-OCR
- **Source**: https://huggingface.co/deepseek-ai/DeepSeek-OCR
- **Parameters**: 3B (BF16/FP16)
- **Function**: OCR with visual-text compression, document to markdown
- **Hardware**: GPU required (flash-attention, ~8GB+ VRAM)
- **Dependencies**: torch, transformers, flash-attn, einops
- **Output**: Markdown text

**Recommendation**: EC2 Spot GPU (g4dn.xlarge) like Dolphin

### Docling
- **Source**: https://github.com/docling-project/docling
- **Parameters**: 258M (granite-docling model)
- **Function**: Layout detection (11 types), table structure recognition
- **Hardware**: CPU works (0.79 sec/page), GPU faster (0.49 sec/page)
- **Dependencies**: `pip install docling` (~9.74GB Docker image with PyTorch)
- **Output**: Markdown, HTML, JSON, DocTags

**Recommendation**: Start with Fargate CPU (smaller model), upgrade to GPU if needed

---

## Phase 1: Add Docling (CPU)

Docling is simpler to add - smaller model, works on CPU, pip-installable.

### 1.1 Add to Registry (`backend/backend/stack_config.py`)
```python
"docling": ModelConfig(
    name="docling",
    cpu=4096,           # 4 vCPU
    memory_mib=16384,   # 16GB (model + PyTorch overhead)
    container_path="docling",
    output_formats=("json", "markdown"),
    timeout_minutes=30,
    use_gpu=False,
)
```

### 1.2 Create Container (`backend/containers/docling/`)

**Dockerfile:**
```dockerfile
FROM python:3.11-slim

# Install system dependencies for PDF processing
RUN apt-get update && apt-get install -y \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Install docling (includes PyTorch CPU)
RUN pip install --no-cache-dir \
    docling \
    boto3

# Pre-download models at build time
RUN python -c "from docling.document_converter import DocumentConverter; DocumentConverter()"

WORKDIR /app
COPY task.py .

CMD ["python", "task.py"]
```

**task.py:**
- Download PDF from S3
- Convert using `DocumentConverter`
- Export to JSON and Markdown
- Upload results to S3
- Update DynamoDB status

**buildspec.yml:**
- Standard container build
- Update SSM: `/pdf-models/cicd/docling-image-tag`

### 1.3 Deploy & Test
```bash
make cdk-deploy STACK=FoundationStack  # Creates ECR repo
make container-build MODEL=docling     # Build container
make cdk-deploy STACK=DoclingStack     # Deploy stack
make test-integration-auto             # Run tests
```

---

## Phase 2: Add DeepSeek-OCR (GPU)

DeepSeek-OCR requires GPU for flash-attention and BF16 inference.

### 2.1 Add to Registry (`backend/backend/stack_config.py`)
```python
"deepseek-ocr": ModelConfig(
    name="deepseek-ocr",
    cpu=4096,
    memory_mib=15360,       # 15GB (leave headroom from 16GB instance)
    container_path="deepseek-ocr",
    output_formats=("markdown",),
    timeout_minutes=30,
    use_gpu=True,
    gpu_count=1,
    instance_type="g4dn.xlarge",  # 1 T4 GPU, 16GB VRAM
    spot_enabled=True,
    min_capacity=0,
    max_capacity=2,
)
```

### 2.2 Create Container (`backend/containers/deepseek-ocr/`)

**Dockerfile:**
```dockerfile
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and dependencies
RUN apt-get update && apt-get install -y \
    python3.11 python3-pip poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Install PyTorch with CUDA
RUN pip install --no-cache-dir \
    torch --index-url https://download.pytorch.org/whl/cu121

# Install transformers and flash-attention
RUN pip install --no-cache-dir \
    transformers \
    einops \
    addict \
    easydict \
    boto3

# Install flash-attention (requires build)
RUN pip install flash-attn --no-build-isolation

# Pre-download model (~6GB)
ENV HF_HOME=/app/hf_cache
RUN python3 -c "from transformers import AutoModel, AutoTokenizer; \
    AutoTokenizer.from_pretrained('deepseek-ai/DeepSeek-OCR', trust_remote_code=True); \
    AutoModel.from_pretrained('deepseek-ai/DeepSeek-OCR', trust_remote_code=True)"

# Set offline mode after download
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

WORKDIR /app
COPY task.py .

CMD ["python3", "task.py"]
```

**task.py:**
- Download PDF from S3
- Convert PDF pages to images
- Process with DeepSeek-OCR model
- Generate markdown output
- Upload to S3, update DynamoDB

**buildspec.yml:**
- X_LARGE compute (model download)
- Update SSM: `/pdf-models/cicd/deepseek-ocr-image-tag`

### 2.3 Deploy & Test
```bash
make cdk-deploy STACK=FoundationStack      # Creates ECR repo
make container-build MODEL=deepseek-ocr    # Build container (~20 min)
make cdk-deploy STACK=DeepseekOcrStack     # Deploy stack
make test-integration-auto                 # Run tests
```

---

## Phase 3: Add Integration Tests

### 3.1 Create Test Files
- `backend/tests/integration/test_docling_e2e.py`
- `backend/tests/integration/test_deepseek_ocr_e2e.py`

Mirror existing test structure from `test_dolphin_e2e.py`.

---

## Implementation Order

```
Phase 1 (Docling - CPU):
1. [ ] Add docling to CONFIG.MODELS
2. [ ] Create backend/containers/docling/
3. [ ] Deploy FoundationStack (creates ECR)
4. [ ] Build container via CodeBuild
5. [ ] Deploy DoclingStack
6. [ ] Create integration test
7. [ ] Test end-to-end

Phase 2 (DeepSeek-OCR - GPU):
8. [ ] Add deepseek-ocr to CONFIG.MODELS
9. [ ] Create backend/containers/deepseek-ocr/
10. [ ] Deploy FoundationStack (creates ECR)
11. [ ] Build container via CodeBuild
12. [ ] Deploy DeepseekOcrStack
13. [ ] Create integration test
14. [ ] Test end-to-end
```

---

## Resource Summary

| Model | Parameters | Compute | Memory | Est. Time/Page |
|-------|------------|---------|--------|----------------|
| Marker | ~1GB models | Fargate CPU | 8GB | ~15-30s |
| Dolphin | 4B | EC2 GPU (T4) | 15GB | ~8-9s |
| Docling | 258M | Fargate CPU | 16GB | ~0.8s |
| DeepSeek-OCR | 3B | EC2 GPU (T4) | 15GB | TBD |

---

## Notes

- Both models follow the existing pattern: pre-download at build time, offline mode at runtime
- Docling may need larger Docker image (~10GB) due to PyTorch
- DeepSeek-OCR requires flash-attention which needs CUDA at build time
- Consider sharing GPU ASG between Dolphin and DeepSeek-OCR (future optimization)
