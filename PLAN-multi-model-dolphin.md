# Plan: Add Modular Multi-Model Support + Dolphin-v2

## Overview
Refactor from single-model (Marker) to modular multi-model architecture, then add ByteDance/Dolphin-v2 as second model.

**User Decisions:**
- GPU: Try CPU first (Fargate), upgrade later if needed
- Output: Both JSON and Markdown for Dolphin
- Approach: Refactor for modularity first

---

## Phase 1: Refactor for Modularity

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

## Phase 2: Add Dolphin-v2

### 2.1 Add to Registry (`backend/backend/stack_config.py`)
```python
"dolphin": ModelConfig(
    name="dolphin",
    cpu=4096,           # Max for Fargate
    memory_mib=30720,   # 30GB - max for Fargate (4B model needs it)
    container_path="dolphin",
    output_formats=["json", "markdown"],
)
```

### 2.2 Container (`backend/containers/dolphin/`) - NEW DIRECTORY

**Dockerfile:**
- Base: `python:3.11-slim`
- Install: PyTorch (CPU), transformers, accelerate, pdf2image
- Pre-download: `ByteDance/Dolphin-v2` model (~8GB)

**task.py:**
- Convert PDF pages to images
- Process with Dolphin-v2 VLM
- Output structured JSON (elements, bounding boxes)
- Convert to Markdown
- Upload both to S3: `{job_id}-result.json`, `{job_id}-result.md`
- Update DynamoDB with both result keys

**buildspec.yml:**
- Build and push container
- Update SSM: `/pdf-models/cicd/dolphin-image-tag`

### 2.3 DynamoDB Schema Addition
Add `s3_result_keys` map field for multiple output formats:
```
s3_result_keys: {"json": "...", "markdown": "..."}
```

---

## Implementation Order

```
Phase 1 (Refactor):
1. stack_config.py - Add ModelConfig, MODELS registry (marker only initially)
2. model_stack.py - Create generic stack factory
3. foundation_stack.py - Dynamic ECR repo creation
4. cicd_stack.py - Dynamic CodeBuild projects
5. Lambda changes - SSM-based model validation
6. api_v2_stack.py - Multi-model permissions
7. app.py - Dynamic stack creation
8. Deploy & test marker still works

Phase 2 (Dolphin):
9. Add dolphin to CONFIG.MODELS
10. Create backend/containers/dolphin/
11. Deploy foundation (creates ECR)
12. Build container via CodeBuild
13. Deploy DolphinStack
14. Test end-to-end
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

## Key Files to Modify

| File | Change |
|------|--------|
| `backend/backend/stack_config.py` | Add ModelConfig, MODELS |
| `backend/backend/model_stack.py` | NEW: Generic stack factory |
| `backend/backend/foundation_stack.py` | Dynamic ECR repos |
| `backend/backend/cicd_stack.py` | Dynamic CodeBuild |
| `backend/backend/api_v2_stack.py` | Multi-model permissions |
| `backend/app.py` | Dynamic stack instantiation |
| `backend/lambdas/submit-job/src/main.rs` | SSM model lookup |
| `backend/lambdas/get-job/src/main.rs` | SSM model lookup |
| `backend/lambdas/get-upload-url/src/main.rs` | Remove hardcoded check |
| `backend/containers/dolphin/*` | NEW: Dolphin container |

---

## Dolphin-v2 Resource Requirements

### Option A: Fargate CPU (Simple, slower)
- **CPU**: 4096 (4 vCPU) - max Fargate
- **Memory**: 30720 MiB (30 GB) - max Fargate for BF16 inference
- **Timeout**: 2 hours (CPU inference is slow)
- **Build**: X_LARGE CodeBuild (~8GB model download)

### Option B: EC2 Spot GPU (Recommended - faster, cost-effective)
- **Instance**: g4dn.xlarge (1 T4 GPU, 4 vCPU, 16GB RAM)
- **Compute**: ECS Capacity Provider with Auto Scaling Group (min=0, max=2)
- **Cost**: ~$0.16/hr Spot vs $0.526/hr On-Demand (~70% savings)
- **Cold start**: ~3-5 minutes when scaling from zero
- **Timeout**: 30 minutes (GPU inference much faster)
- **Note**: Requires model_stack.py changes to support EC2 launch type

---

## Testing Checkpoints

1. After Phase 1: Marker regression test (should work identically)
2. After Phase 2:
   - Submit job with `model=dolphin`
   - Verify both JSON and MD outputs in S3
   - Verify download URLs work for both formats

---

## Future: Adding Model N+1

With this architecture, adding a new model requires:
1. Add entry to `CONFIG.MODELS` in stack_config.py
2. Create `backend/containers/{model}/` with Dockerfile, task.py, buildspec.yml
3. Deploy (foundation, model stack, API)

No Lambda or API changes needed.
