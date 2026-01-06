# Plan: Add Modular Multi-Model Support + Dolphin-v2

## Overview
Refactor from single-model (Marker) to modular multi-model architecture, then add ByteDance/Dolphin-v2 as second model.

**User Decisions:**
- GPU: Try CPU first (Fargate), upgrade later if needed
- Output: Both JSON and Markdown for Dolphin
- Approach: Refactor for modularity first

---

## Phase 1: Refactor for Modularity ✅ COMPLETED

**Status:** All tasks completed and tested on 2026-01-05

### 1.1 Model Registry (`backend/backend/stack_config.py`)
Add `ModelConfig` dataclass and `MODELS` registry:
```python
@dataclass(frozen=True)
class ModelConfig:
    name: str              # "marker", "dolphin"
    cpu: int               # Fargate vCPU
    memory_mib: int        # Fargate memory
    container_path: str    # Path under containers/
    output_formats: list   # ["markdown"] or ["json", "markdown"]
```

### 1.2 Generic Model Stack (`backend/backend/model_stack.py`) - NEW FILE
Extract from `marker_stack.py` into parameterized factory:
- Takes `ModelConfig` as input
- Creates ECS cluster, Fargate task, Step Functions
- Uses SSM parameter naming: `/pdf-models/{model}/*`

### 1.3 Foundation Stack Updates (`backend/backend/foundation_stack.py`)
- Loop over `CONFIG.MODELS` to create ECR repos
- SSM param: `/pdf-models/foundation/ecr-repo-uri-{model}`

### 1.4 Lambda Updates (remove hardcoded "marker")
**Files:**
- `backend/lambdas/submit-job/src/main.rs`
- `backend/lambdas/get-job/src/main.rs`
- `backend/lambdas/get-upload-url/src/main.rs`

Replace:
```rust
if model != "marker" { return error }
```
With SSM lookup:
```rust
let param = format!("/pdf-models/{}/state-machine-arn", model);
ssm_client.get_parameter().name(&param).send().await
```

### 1.5 API Stack Updates (`backend/backend/api_v2_stack.py`)
- Remove hardcoded state machine ARN
- Add SSM read permission: `/pdf-models/*/state-machine-arn`
- Add Step Functions permission for all models

### 1.6 CI/CD Stack Updates (`backend/backend/cicd_stack.py`)
- Loop over `CONFIG.MODELS` to create CodeBuild projects
- Each model has its own `buildspec.yml`

### 1.7 App Entry Point (`backend/app.py`)
Replace `MarkerStack()` with dynamic creation:
```python
for model_name, config in CONFIG.MODELS.items():
    ModelStack(app, f"{model_name.title()}Stack", model_config=config)
```

---

## Phase 2: Add Dolphin-v2 (CPU) ✅ COMPLETED

**Status:** All tasks completed and tested on 2026-01-06

### 2.1 Add to Registry (`backend/backend/stack_config.py`) ✅ DONE
```python
"dolphin": ModelConfig(
    name="dolphin",
    cpu=4096,           # Max for Fargate
    memory_mib=30720,   # 30GB - max for Fargate (4B model needs it)
    container_path="dolphin",
    output_formats=["json", "markdown"],
)
```

### 2.2 Container (`backend/containers/dolphin/`) ✅ DONE

**Dockerfile:**
- Base: `python:3.11-slim`
- Install: PyTorch (CPU), transformers, accelerate, pdf2image
- Pre-download: `ByteDance/Dolphin` model (~8GB)
- Offline environment variables set after model download

**task.py:**
- Convert PDF pages to images
- Process with Dolphin VLM
- Output structured JSON (elements, bounding boxes)
- Convert to Markdown
- Upload both to S3: `{job_id}-result.json`, `{job_id}-result.md`
- Update DynamoDB with both result keys
- **IMPORTANT:** Uses `local_files_only=True` in `from_pretrained()` calls + offline env vars to prevent runtime HuggingFace requests (container runs in isolated subnets)
- **IMPORTANT:** Uses `max_new_tokens=1024` (mbart decoder limit)

**buildspec.yml:**
- Build and push container
- Update SSM: `/pdf-models/cicd/dolphin-image-tag`

### 2.3 DynamoDB Schema Addition ✅ DONE
Add `s3_result_keys` map field for multiple output formats:
```
s3_result_keys: {"json": "...", "markdown": "..."}
```

### 2.4 Performance Notes
- CPU inference: ~1-2 minutes per page on Fargate (4 vCPU, 30GB RAM)
- 2-page test PDF: ~3 minutes total processing time
- Model load time: ~2 seconds (cached in container image)

---

## Phase 3: Upgrade Dolphin to EC2 Spot GPU ✅ COMPLETED

**Status:** All tasks completed and tested on 2026-01-06

### 3.1 Extend ModelConfig for GPU (`backend/backend/stack_config.py`) ✅ DONE
Added GPU/EC2 fields to ModelConfig:
```python
use_gpu: bool = False      # If True, use EC2 with GPU
gpu_count: int = 0         # Number of GPUs (typically 1)
instance_type: str = ""    # e.g., "g4dn.xlarge"
spot_enabled: bool = True  # Use Spot for cost savings
min_capacity: int = 0      # ASG min (0 = scale to zero)
max_capacity: int = 2      # ASG max
```

Updated dolphin config:
```python
"dolphin": ModelConfig(
    name="dolphin",
    cpu=4096,
    memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
    container_path="dolphin",
    output_formats=("json", "markdown"),
    timeout_minutes=30,  # Reduced from 120 - GPU is much faster
    use_gpu=True,
    gpu_count=1,
    instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
    spot_enabled=True,
    min_capacity=0,  # Scale to zero when idle
    max_capacity=2,
)
```

### 3.2 Update model_stack.py for EC2/GPU ✅ DONE
- Added conditional infrastructure based on `model_config.use_gpu`
- **GPU path:** EC2 Launch Template, Auto Scaling Group, ECS Capacity Provider
- **Fargate path:** Existing FargateTaskDefinition (unchanged)
- Updated Step Functions to use CapacityProviderStrategy for EC2 launch type
- Added ECS Drain Hook Lambda for graceful instance termination

### 3.3 Add VPC Endpoints for EC2 (`networking_stack.py`) ✅ DONE
Added interface endpoints required for EC2 in isolated subnets:
- `ecs-agent` endpoint (ECS agent communication)
- `ecs-telemetry` endpoint (container metrics)
- `ecs` endpoint (ECS API calls from instances)

### 3.4 Update Dockerfile for GPU PyTorch ✅ DONE
- Base image: `nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04` (NGC to avoid Docker Hub rate limits)
- PyTorch: `--index-url https://download.pytorch.org/whl/cu121`
- Model dtype: `torch.float16` (GPU-optimized)
- Added NVIDIA environment variables for GPU visibility

### 3.5 Update task.py for CUDA ✅ DONE
- Auto-detect CUDA device: `device = "cuda" if torch.cuda.is_available() else "cpu"`
- Use FP16 on GPU, FP32 on CPU
- Move model and inputs to GPU device
- Log GPU info (name, memory) for debugging

### 3.6 Deploy and Test ✅ DONE

**Deployed:**
- NetworkingStack (VPC endpoints) ✅
- Dolphin container built with GPU support ✅
- DolphinStack (ASG, Capacity Provider, EC2 Task Definition) ✅

**Bug fixes during testing:**
- Added `AWS_DEFAULT_REGION` env var to EC2 task definition (boto3 requires explicit region on EC2)
- Fixed dtype mismatch in task.py: convert inputs to float16 to match model on GPU

**Integration tests:** All 6 tests passed in 517s (8 min 37 sec)

### 3.7 Actual Performance Results

| Metric | Phase 2 (Fargate CPU) | Phase 3 (EC2 Spot GPU) |
|--------|----------------------|------------------------|
| Inference/page | 1-2 minutes | **8-9 seconds** |
| 2-page job | ~3 minutes | **~22 seconds** |
| Cost/hour | ~$0.26 | ~$0.16 (70% savings) |
| Cold start | ~30 seconds | 3-5 minutes (from 0) |
| End-to-end test | ~164 seconds | ~163 seconds (warm) |

**Note:** GPU processing time (~22s) is 8x faster than CPU. End-to-end time is similar due to task scheduling overhead.

---

## Implementation Order

```
Phase 1 (Refactor): ✅ COMPLETED
1. ✅ stack_config.py - Add ModelConfig, MODELS registry (marker only initially)
2. ✅ model_stack.py - Create generic stack factory
3. ✅ foundation_stack.py - Dynamic ECR repo creation
4. ✅ cicd_stack.py - Dynamic CodeBuild projects + SSM permissions + MEDIUM compute
5. ✅ Lambda changes - SSM-based model validation (added aws-sdk-ssm)
6. ✅ api_v2_stack.py - Multi-model permissions (wildcard Step Functions, SSM read)
7. ✅ app.py - Dynamic stack creation
8. ✅ Deploy & test marker still works (all 4 integration tests pass)

Phase 2 (Dolphin CPU): ✅ COMPLETED
9.  ✅ Add dolphin to CONFIG.MODELS
10. ✅ Create backend/containers/dolphin/
11. ✅ Deploy foundation (creates ECR)
12. ✅ Build container via CodeBuild (first build)
13. ✅ Deploy DolphinStack
14. ✅ Test end-to-end
    - Initial issue: container couldn't reach HuggingFace (isolated subnets)
    - Fix 1: Added HF_HUB_OFFLINE=1 env vars (not sufficient)
    - Fix 2: Added local_files_only=True to from_pretrained() calls
    - Fix 3: Reduced max_new_tokens from 4096 to 1024 (mbart decoder limit)
    - All 6 integration tests pass (2 Dolphin + 4 Marker)

Phase 3 (Dolphin GPU): ✅ COMPLETED
15. ✅ Extend ModelConfig with GPU fields (use_gpu, gpu_count, instance_type, spot_enabled)
16. ✅ Update model_stack.py with EC2 ASG + Capacity Provider
17. ✅ Add VPC endpoints for EC2 (ecs-agent, ecs-telemetry, ecs)
18. ✅ Update Dockerfile with NVIDIA CUDA base + GPU PyTorch
19. ✅ Update task.py with CUDA device detection + FP16
20. ✅ Deploy NetworkingStack (VPC endpoints)
21. ✅ Build GPU container via CodeBuild
22. ✅ Deploy DolphinStack (ASG, Capacity Provider, EC2 task def)
23. ✅ GPU quota approved (8 vCPU for G and VT instances)
24. ✅ Test end-to-end (6/6 tests passed)
```

---

## SSM Parameter Convention

```
/pdf-models/foundation/ecr-repo-uri-{model}
/pdf-models/cicd/{model}-image-tag
/pdf-models/{model}/cluster-arn
/pdf-models/{model}/task-definition-arn
/pdf-models/{model}/state-machine-arn
```

---

## Key Files Modified

| File | Phase | Change |
|------|-------|--------|
| `backend/backend/stack_config.py` | 1, 3 | Add ModelConfig, MODELS; Add GPU fields |
| `backend/backend/model_stack.py` | 1, 3 | Generic stack factory; EC2 ASG + Capacity Provider |
| `backend/backend/networking_stack.py` | 3 | VPC endpoints for EC2 (ecs-agent, ecs-telemetry, ecs) |
| `backend/backend/foundation_stack.py` | 1 | Dynamic ECR repos |
| `backend/backend/cicd_stack.py` | 1 | Dynamic CodeBuild |
| `backend/backend/api_v2_stack.py` | 1 | Multi-model permissions |
| `backend/app.py` | 1 | Dynamic stack instantiation |
| `backend/lambdas/submit-job/src/main.rs` | 1 | SSM model lookup |
| `backend/lambdas/get-job/src/main.rs` | 1 | SSM model lookup |
| `backend/lambdas/get-upload-url/src/main.rs` | 1 | Remove hardcoded check |
| `backend/containers/dolphin/Dockerfile` | 2, 3 | Dolphin container; NVIDIA CUDA + GPU PyTorch |
| `backend/containers/dolphin/task.py` | 2, 3 | Dolphin processing; CUDA + FP16 inference |
| `backend/containers/dolphin/buildspec.yml` | 2 | Container build spec |

---

## Dolphin-v2 Resource Requirements

### Option A: Fargate CPU (Phase 2 - deprecated)
- **CPU**: 4096 (4 vCPU) - max Fargate
- **Memory**: 30720 MiB (30 GB) - max Fargate for BF16 inference
- **Timeout**: 2 hours (CPU inference is slow)
- **Build**: X_LARGE CodeBuild (~8GB model download)
- **Status**: Superseded by GPU option in Phase 3

### Option B: EC2 Spot GPU ✅ DEPLOYED (Phase 3)
- **Instance**: g4dn.xlarge (1 T4 GPU, 4 vCPU, 16GB RAM)
- **Compute**: ECS Capacity Provider with Auto Scaling Group (min=0, max=2)
- **Cost**: ~$0.16/hr Spot vs $0.526/hr On-Demand (~70% savings)
- **Cold start**: ~3-5 minutes when scaling from zero
- **Timeout**: 30 minutes (GPU inference much faster)
- **Status**: Infrastructure deployed, awaiting GPU quota approval

---

## Testing Checkpoints

1. After Phase 1: ✅ Marker regression test PASSED
   - `test_submit_and_process_pdf` - Full E2E with Marker processing
   - `test_list_jobs` - List jobs for model
   - `test_unauthorized_access_to_other_user_job` - 404 for non-existent job
   - `test_s3_permissions_enforced` - S3 key validation

2. After Phase 2: ✅ ALL TESTS PASSED (2026-01-06)
   - `test_submit_and_process_pdf` (Dolphin) - Full E2E with Dolphin processing (~164s)
   - `test_list_jobs` (Dolphin) - List jobs for dolphin model
   - `test_submit_and_process_pdf` (Marker) - Regression test (~335s)
   - `test_list_jobs` (Marker) - Regression test
   - `test_unauthorized_access_to_other_user_job` (Marker) - Auth check
   - `test_s3_permissions_enforced` (Marker) - S3 key validation
   - Total: 6 tests in 507s (~8.5 min)

3. After Phase 3: ✅ ALL TESTS PASSED (2026-01-06)
   - `test_submit_and_process_pdf` (Dolphin) - Full E2E with GPU processing (~22s actual, 163s total)
   - `test_list_jobs` (Dolphin) - List jobs for dolphin model
   - `test_submit_and_process_pdf` (Marker) - Regression test (~345s)
   - `test_list_jobs` (Marker) - Regression test
   - `test_unauthorized_access_to_other_user_job` (Marker) - Auth check
   - `test_s3_permissions_enforced` (Marker) - S3 key validation
   - Total: 6 tests in 518s (~8.6 min)

---

## Future: Adding Model N+1

With this architecture, adding a new model requires:
1. Add entry to `CONFIG.MODELS` in stack_config.py
2. Create `backend/containers/{model}/` with Dockerfile, task.py, buildspec.yml
3. Deploy (foundation, model stack, API)

No Lambda or API changes needed.
