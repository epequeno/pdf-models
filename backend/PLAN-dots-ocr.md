# Implementation Plan: dots.ocr Model

## Overview

**Model**: [rednote-hilab/dots.ocr](https://huggingface.co/rednote-hilab/dots.ocr)

dots.ocr is a multilingual document parser that unifies layout detection and content recognition within a single vision-language model. It achieves SOTA performance on OmniDocBench while maintaining good reading order.

**Key Characteristics**:
- 1.7B parameter LLM foundation (compact but powerful)
- Multilingual support (100+ languages)
- Unified layout detection + content recognition
- Outputs structured JSON with bounding boxes, categories, and text
- Requires GPU with flash_attention_2 support
- Based on Qwen2.5-VL architecture

## Resource Requirements

| Resource | Value | Notes |
|----------|-------|-------|
| GPU | Required | T4 (g4dn.xlarge) or better |
| VRAM | ~8GB | 1.7B model in bfloat16 |
| Instance Type | g4dn.xlarge | 1x T4 GPU, 4 vCPU, 16GB RAM |
| EBS Volume | 80GB | ~5GB model + container overhead |
| Timeout | 30 min | GPU inference is fast |

## Implementation Steps

### Step 1: Add Model Configuration to stack_config.py

Add to `MODELS` dict in `backend/backend/stack_config.py`:

```python
"dots-ocr": ModelConfig(
    name="dots-ocr",
    cpu=4096,  # 4 vCPU on g4dn.xlarge
    memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
    container_path="dots-ocr",
    output_formats=("json", "markdown"),  # JSON with layout + markdown text
    timeout_minutes=30,
    supports_prompt=True,  # VLM model accepts custom prompts
    use_gpu=True,
    gpu_count=1,
    instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
    spot_enabled=True,
    min_capacity=0,  # Scale to zero when idle
    max_capacity=2,
    ebs_volume_size_gb=80,  # 1.7B model + transformers
),
```

### Step 2: Create Container Directory

Create `backend/containers/dots-ocr/` with three files:

#### 2.1 Dockerfile

```dockerfile
# dots.ocr PDF Processing Container
#
# Uses dots.ocr (1.7B parameter VLM) for document OCR with layout detection.
# Requires GPU with flash-attention support.
#
# Model: rednote-hilab/dots.ocr (pre-downloaded at build time)

# Use NVIDIA CUDA base image from NGC (avoids Docker Hub rate limits)
FROM nvcr.io/nvidia/cuda:12.1.0-devel-ubuntu22.04 AS builder

# Install Python and build dependencies
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    python3-pip \
    git \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Make python3.12 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install PyTorch with CUDA support first (required for flash-attn build)
RUN pip3 install --no-cache-dir \
    torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu121

# Install flash-attention (needs CUDA dev tools to build)
RUN pip3 install --no-cache-dir packaging wheel
RUN pip3 install flash-attn --no-build-isolation

# Runtime stage - smaller image without build tools
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and runtime dependencies
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3-pip \
    poppler-utils \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    git \
    && rm -rf /var/lib/apt/lists/*

# Make python3.12 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories for model cache
RUN mkdir -p /app/models /app/cache /app/weights && \
    chown -R appuser:appuser /app

# Copy flash-attn from builder
COPY --from=builder /usr/local/lib/python3.12/dist-packages /usr/local/lib/python3.12/dist-packages

# Install PyTorch with CUDA support
RUN pip3 install --no-cache-dir \
    torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu121

# Install dots.ocr from GitHub (includes qwen_vl_utils dependency)
RUN pip3 install --no-cache-dir \
    git+https://github.com/rednote-hilab/dots.ocr.git

# Install other dependencies
RUN pip3 install --no-cache-dir \
    transformers \
    accelerate \
    pdf2image \
    pillow \
    boto3

# Copy task script
COPY task.py /app/task.py
WORKDIR /app

# Set environment variables for Hugging Face cache
ENV HF_HOME=/app/cache
ENV TRANSFORMERS_CACHE=/app/cache

# Switch to appuser for model download
USER appuser

# Pre-download dots.ocr model using their download script
# Model is saved to /app/weights/DotsOCR (no periods in directory name per their docs)
RUN python3 -c "\
from huggingface_hub import snapshot_download; \
import os; \
print('Downloading dots.ocr model...'); \
snapshot_download(repo_id='rednote-hilab/dots.ocr', local_dir='/app/weights/DotsOCR'); \
print('Model pre-downloaded successfully')"

# Force offline mode AFTER model is downloaded
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
```

#### 2.2 task.py

```python
#!/usr/bin/env python3
"""
dots.ocr PDF Processing Task

This script runs inside an ECS container to process PDFs using dots.ocr model.
It converts PDF pages to images, processes with the 1.7B parameter VLM, and outputs
structured JSON with layout detection and Markdown text.

GPU required (g4dn.xlarge or better). Uses FlashAttention2 on Ampere+ GPUs.

Environment Variables:
    JOB_ID: Unique job identifier
    S3_BUCKET: S3 bucket name
    S3_INPUT_KEY: S3 key for input PDF
    DYNAMODB_TABLE: DynamoDB table name for job tracking
    PROMPT: Optional custom prompt (default: layout detection + OCR)
"""

import os
import sys
import tempfile
import logging
import json
from pathlib import Path
from datetime import datetime, timezone

# Force offline mode - model is pre-downloaded
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import boto3
from pdf2image import convert_from_path
from PIL import Image
import torch
from transformers import AutoModelForCausalLM, AutoProcessor
from qwen_vl_utils import process_vision_info

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Model path (pre-downloaded during container build)
MODEL_PATH = "/app/weights/DotsOCR"

# Default prompt for layout detection + OCR
DEFAULT_PROMPT = """Please output the layout information from the PDF image, including each layout element's bbox, its category, and the corresponding text content within the bbox.

1. Bbox format: [x1, y1, x2, y2]

2. Layout Categories: The possible categories are ['Caption', 'Footnote', 'Formula', 'List-item', 'Page-footer', 'Page-header', 'Picture', 'Section-header', 'Table', 'Text', 'Title'].

3. Text Extraction & Formatting Rules:
    - Picture: For the 'Picture' category, the text field should be omitted.
    - Formula: Format its text as LaTeX.
    - Table: Format its text as HTML.
    - All Others (Text, Title, etc.): Format their text as Markdown.

4. Constraints:
    - The output text must be the original text from the image, with no translation.
    - All layout elements must be sorted according to human reading order.

5. Final Output: The entire output must be a single JSON object.
"""


def get_required_env(key: str) -> str:
    """Get required environment variable or exit."""
    value = os.environ.get(key)
    if not value:
        logger.error(f"Missing required environment variable: {key}")
        sys.exit(1)
    return value


def update_job_status(
    dynamodb,
    table_name: str,
    job_id: str,
    status: str,
    substatus: str = None,
    s3_result_key: str = None,
    error: str = None
):
    """Update job status in DynamoDB."""
    table = dynamodb.Table(table_name)

    update_expr = "SET #status = :status, completed_at = :completed_at"
    expr_attr_names = {"#status": "status"}
    expr_attr_values = {
        ":status": status,
        ":completed_at": datetime.now(timezone.utc).isoformat()
    }

    if substatus:
        update_expr += ", substatus = :substatus"
        expr_attr_values[":substatus"] = substatus

    if s3_result_key:
        update_expr += ", s3_result_key = :result_key"
        expr_attr_values[":result_key"] = s3_result_key

    if error:
        update_expr += ", #error = :error"
        expr_attr_names["#error"] = "error"
        expr_attr_values[":error"] = error

    table.update_item(
        Key={"job_id": job_id},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_attr_names,
        ExpressionAttributeValues=expr_attr_values
    )
    logger.info(f"Updated job {job_id} to status: {status}" + (f" ({substatus})" if substatus else ""))


def load_dots_ocr_model():
    """Load the dots.ocr model and processor with GPU support.

    Returns:
        tuple: (model, processor)
    """
    if not torch.cuda.is_available():
        raise RuntimeError("dots.ocr requires CUDA GPU support")

    gpu_name = torch.cuda.get_device_name(0)
    gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
    logger.info(f"GPU: {gpu_name}")
    logger.info(f"GPU Memory: {gpu_memory:.1f} GB")

    logger.info("Loading dots.ocr model...")

    # Check GPU compute capability for attention implementation
    compute_capability = torch.cuda.get_device_capability(0)
    if compute_capability[0] >= 8:
        attn_impl = 'flash_attention_2'
        logger.info("Using FlashAttention2 (Ampere+ GPU detected)")
    else:
        attn_impl = 'eager'
        logger.info(f"Using eager attention (compute capability {compute_capability[0]}.{compute_capability[1]} < 8.0)")

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        attn_implementation=attn_impl,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
        local_files_only=True
    )

    processor = AutoProcessor.from_pretrained(
        MODEL_PATH,
        trust_remote_code=True,
        local_files_only=True
    )

    logger.info("dots.ocr model loaded successfully")
    return model, processor


def process_page_with_dots_ocr(model, processor, image: Image.Image, page_num: int, temp_dir: Path, custom_prompt: str = None) -> dict:
    """Process a single page image with dots.ocr model.

    Args:
        model: The dots.ocr model
        processor: The processor
        image: PIL Image of the page
        page_num: Page number (1-indexed)
        temp_dir: Temporary directory for intermediate files
        custom_prompt: Optional custom prompt from user

    Returns:
        dict: Parsed JSON output with layout information
    """
    logger.info(f"Processing page {page_num}...")

    # Save image to temp file
    image_path = temp_dir / f"page_{page_num}.png"
    image.save(str(image_path), "PNG")

    # Use custom prompt if provided, otherwise use default
    prompt = custom_prompt if custom_prompt else DEFAULT_PROMPT

    # Build messages for the model
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image", "image": str(image_path)},
                {"type": "text", "text": prompt}
            ]
        }
    ]

    # Prepare inputs
    text = processor.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True
    )
    image_inputs, video_inputs = process_vision_info(messages)
    inputs = processor(
        text=[text],
        images=image_inputs,
        videos=video_inputs,
        padding=True,
        return_tensors="pt",
    )
    inputs = inputs.to("cuda")

    # Generate output
    generated_ids = model.generate(**inputs, max_new_tokens=24000)
    generated_ids_trimmed = [
        out_ids[len(in_ids):] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
    ]
    output_text = processor.batch_decode(
        generated_ids_trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
    )[0]

    logger.info(f"Page {page_num} processed ({len(output_text)} chars)")

    # Try to parse as JSON
    try:
        result = json.loads(output_text)
    except json.JSONDecodeError:
        # If not valid JSON, wrap in a simple structure
        result = {"raw_output": output_text}

    return result


def extract_markdown_from_layout(layout_data: dict) -> str:
    """Extract markdown text from dots.ocr layout output.

    Args:
        layout_data: Parsed JSON from dots.ocr

    Returns:
        str: Concatenated markdown text in reading order
    """
    if "raw_output" in layout_data:
        return layout_data["raw_output"]

    # dots.ocr outputs elements in reading order
    # Extract text from each element
    markdown_parts = []

    elements = layout_data if isinstance(layout_data, list) else layout_data.get("elements", [])

    for element in elements:
        text = element.get("text", "")
        category = element.get("category", "")

        if category == "Picture":
            # Pictures don't have text
            markdown_parts.append("[Image]")
        elif category == "Title":
            markdown_parts.append(f"# {text}")
        elif category == "Section-header":
            markdown_parts.append(f"## {text}")
        else:
            markdown_parts.append(text)

    return "\n\n".join(markdown_parts)


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    # Get optional custom prompt
    custom_prompt = os.environ.get("PROMPT", "").strip() or None

    logger.info(f"Starting dots.ocr job {job_id}")
    logger.info(f"Input: s3://{bucket_name}/{input_key}")
    if custom_prompt:
        logger.info(f"Custom prompt provided")

    # Initialize AWS clients
    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")

    try:
        # Update status to processing - downloading
        update_job_status(dynamodb, table_name, job_id, "processing", substatus="downloading")

        # Create temporary directory for processing
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            input_pdf = temp_path / "input.pdf"

            # Download PDF from S3
            logger.info("Downloading PDF from S3...")
            s3.download_file(bucket_name, input_key, str(input_pdf))
            logger.info(f"Downloaded PDF: {input_pdf.stat().st_size} bytes")

            # Convert PDF pages to images
            logger.info("Converting PDF to images...")
            images = convert_from_path(str(input_pdf), dpi=150)
            logger.info(f"Converted {len(images)} pages to images")

            # Update substatus - loading models
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="loading_models")

            # Load dots.ocr model
            model, processor = load_dots_ocr_model()

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process each page
            all_layouts = []
            markdown_parts = []

            for i, image in enumerate(images, start=1):
                layout_data = process_page_with_dots_ocr(model, processor, image, i, temp_path, custom_prompt)
                all_layouts.append({"page": i, "layout": layout_data})

                # Extract markdown from layout
                page_markdown = extract_markdown_from_layout(layout_data)
                if i > 1:
                    markdown_parts.append("\n---\n")
                markdown_parts.append(f"<!-- Page {i} -->\n")
                markdown_parts.append(page_markdown)

                logger.info(f"Page {i}/{len(images)} completed")

            # Generate result S3 keys
            user_id = input_key.split("/")[0]
            json_result_key = f"{user_id}/{job_id}-result.json"
            md_result_key = f"{user_id}/{job_id}-result.md"

            # Update substatus - uploading
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="uploading")

            # Write and upload JSON result (full layout data)
            json_file = temp_path / "output.json"
            json_file.write_text(json.dumps({"pages": all_layouts}, indent=2), encoding="utf-8")
            logger.info(f"Uploading JSON result to s3://{bucket_name}/{json_result_key}")
            s3.upload_file(str(json_file), bucket_name, json_result_key)

            # Write and upload Markdown result
            markdown_content = "\n".join(markdown_parts)
            md_file = temp_path / "output.md"
            md_file.write_text(markdown_content, encoding="utf-8")
            logger.info(f"Uploading Markdown result to s3://{bucket_name}/{md_result_key}")
            s3.upload_file(str(md_file), bucket_name, md_result_key)

            logger.info("Upload complete")

            # Update job status to completed (use markdown as primary result)
            update_job_status(
                dynamodb,
                table_name,
                job_id,
                "completed",
                s3_result_key=md_result_key
            )

            logger.info(f"Job {job_id} completed successfully")

    except Exception as e:
        logger.error(f"Job {job_id} failed: {str(e)}", exc_info=True)

        try:
            update_job_status(
                dynamodb,
                table_name,
                job_id,
                "failed",
                error=str(e)
            )
        except Exception as update_error:
            logger.error(f"Failed to update job status: {str(update_error)}")

        sys.exit(1)


if __name__ == "__main__":
    main()
```

#### 2.3 buildspec.yml

```yaml
version: 0.2

# CodeBuild specification for building and pushing dots.ocr container to ECR
# NOTE: Requires X_LARGE compute type due to flash-attention compilation

phases:
  pre_build:
    commands:
      - echo "Logging in to Amazon ECR..."
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $(echo $ECR_REPOSITORY_URI | cut -d'/' -f1)
      - echo "ECR Repository URI:$ECR_REPOSITORY_URI"
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=${COMMIT_HASH:-latest}
      - echo "Image tag will be:$IMAGE_TAG"
      - echo "Pulling existing image for cache..."
      - docker pull $ECR_REPOSITORY_URI:latest || true

  build:
    commands:
      - echo "Build started on $(date)"
      - echo "Building the Docker image with BuildKit caching..."
      - cd backend/containers/dots-ocr
      - DOCKER_BUILDKIT=1 docker build --cache-from $ECR_REPOSITORY_URI:latest -t $ECR_REPOSITORY_URI:latest .
      - docker tag $ECR_REPOSITORY_URI:latest $ECR_REPOSITORY_URI:$IMAGE_TAG
      - echo "Build completed"

  post_build:
    commands:
      - echo "Build completed on $(date)"
      - echo "Pushing the Docker images..."
      - docker push $ECR_REPOSITORY_URI:latest
      - docker push $ECR_REPOSITORY_URI:$IMAGE_TAG
      - echo "Successfully pushed $ECR_REPOSITORY_URI:latest"
      - echo "Successfully pushed $ECR_REPOSITORY_URI:$IMAGE_TAG"
      - echo "Updating SSM parameter with image tag..."
      - aws ssm put-parameter --name "/pdf-models/cicd/dots-ocr-image-tag" --value "$IMAGE_TAG" --type String --overwrite
      - echo "SSM parameter /pdf-models/cicd/dots-ocr-image-tag updated to $IMAGE_TAG"
      # Update ECS task definition with new image
      - echo "Updating ECS task definition..."
      - TASK_DEF_FAMILY="pdf-models-dots-ocr"
      - |
        CURRENT_TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_FAMILY --query 'taskDefinition' --output json)
        NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) | .containerDefinitions[0].image = "'"$ECR_REPOSITORY_URI:$IMAGE_TAG"'"')
        NEW_ARN=$(aws ecs register-task-definition --cli-input-json "$NEW_TASK_DEF" --query 'taskDefinition.taskDefinitionArn' --output text)
        echo "Registered new task definition: $NEW_ARN"
        aws ssm put-parameter --name "/pdf-models/dots-ocr/task-definition-arn" --value "$NEW_ARN" --type String --overwrite
        echo "Updated /pdf-models/dots-ocr/task-definition-arn to $NEW_ARN"
```

### Step 3: Create Model Stack in app.py

Add to `backend/app.py`:

```python
from backend.stack_config import MODELS

# Create DotsOcrStack using generic ModelStack
DotsOcrStack = ModelStack(
    app,
    "DotsOcrStack",
    model_config=MODELS["dots-ocr"],
    env=env,
)
```

### Step 4: Create Integration Test

Create `backend/tests/integration/test_dots_ocr_e2e.py` following the pattern of existing tests.

### Step 5: Deployment Steps

1. Add model config to `stack_config.py`
2. Create container files
3. Commit and push to CodeCommit
4. Deploy FoundationStack (creates ECR repo): `make cdk-deploy STACK=FoundationStack`
5. Deploy CiCdStack (creates CodeBuild project): `make cdk-deploy STACK=CiCdStack`
6. Build container: `make container-build MODEL=dots-ocr`
7. Deploy model stack: `make cdk-deploy STACK=DotsOcrStack`
8. Update ApiV2Stack if needed
9. Run integration tests: `make test-integration-cloud MODEL=dots-ocr`

## Notes

- dots.ocr requires Python 3.12 (per their installation docs)
- Model directory name must not contain periods (use `DotsOCR` not `dots.ocr`)
- The model outputs structured JSON with bounding boxes - useful for downstream processing
- Consider adding a separate endpoint for layout-only detection (faster, no OCR)
