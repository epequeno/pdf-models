# Implementation Plan: LightOnOCR-2-1B Model

## Overview

**Model**: [lightonai/LightOnOCR-2-1B](https://huggingface.co/lightonai/LightOnOCR-2-1B)

LightOnOCR-2 is an efficient end-to-end 1B-parameter vision-language model for converting documents (PDFs, scans, images) into clean, naturally ordered text. It achieves SOTA performance on OlmOCR-Bench while being ~9× smaller and significantly faster than competing approaches.

**Key Characteristics**:
- 1B parameters (very efficient)
- End-to-end OCR (no external pipeline)
- Handles tables, receipts, forms, multi-column layouts, math notation
- 5.71 pages/s on H100 (~493k pages/day)
- Apache 2.0 license
- Requires transformers from source (custom model class)

## Resource Requirements

| Resource | Value | Notes |
|----------|-------|-------|
| GPU | Required | T4 (g4dn.xlarge) or better |
| VRAM | ~4GB | 1B model in bfloat16 |
| Instance Type | g4dn.xlarge | 1x T4 GPU, 4 vCPU, 16GB RAM |
| EBS Volume | 60GB | ~2GB model + container overhead |
| Timeout | 30 min | Very fast inference |

## Implementation Steps

### Step 1: Add Model Configuration to stack_config.py

Add to `MODELS` dict in `backend/backend/stack_config.py`:

```python
"lightonocr": ModelConfig(
    name="lightonocr",
    cpu=4096,  # 4 vCPU on g4dn.xlarge
    memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
    container_path="lightonocr",
    output_formats=("markdown",),  # Clean text output
    timeout_minutes=30,
    supports_prompt=False,  # OCR-focused, no custom prompts
    use_gpu=True,
    gpu_count=1,
    instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
    spot_enabled=True,
    min_capacity=0,  # Scale to zero when idle
    max_capacity=2,
    ebs_volume_size_gb=60,  # 1B model is small
),
```

### Step 2: Create Container Directory

Create `backend/containers/lightonocr/` with three files:

#### 2.1 Dockerfile

```dockerfile
# LightOnOCR-2 PDF Processing Container
#
# Uses LightOnOCR-2-1B (1B parameter VLM) for efficient document OCR.
# Requires GPU for optimal performance.
#
# Model: lightonai/LightOnOCR-2-1B (pre-downloaded at build time)

# Use NVIDIA CUDA base image from NGC (avoids Docker Hub rate limits)
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and runtime dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
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

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories for model cache
RUN mkdir -p /app/models /app/cache && \
    chown -R appuser:appuser /app

# Install PyTorch with CUDA support
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu121

# Install transformers from source (LightOnOCR-2 requires unreleased features)
# This is per the model's documentation
RUN pip3 install --no-cache-dir \
    git+https://github.com/huggingface/transformers

# Install other dependencies
RUN pip3 install --no-cache-dir \
    pillow \
    pypdfium2 \
    boto3 \
    accelerate

# Copy task script
COPY task.py /app/task.py
WORKDIR /app

# Set environment variables for Hugging Face cache
ENV HF_HOME=/app/cache
ENV TRANSFORMERS_CACHE=/app/cache

# Switch to appuser for model download
USER appuser

# Pre-download LightOnOCR-2 model
# This downloads ~2GB of model weights
RUN python3 -c "\
from transformers import LightOnOcrForConditionalGeneration, LightOnOcrProcessor; \
import torch; \
print('Downloading LightOnOCR-2 model...'); \
model = LightOnOcrForConditionalGeneration.from_pretrained('lightonai/LightOnOCR-2-1B', torch_dtype=torch.bfloat16); \
processor = LightOnOcrProcessor.from_pretrained('lightonai/LightOnOCR-2-1B'); \
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
LightOnOCR-2 PDF Processing Task

This script runs inside an ECS container to process PDFs using LightOnOCR-2-1B model.
It converts PDF pages to images, processes with the 1B parameter VLM, and outputs
clean Markdown text.

GPU required (g4dn.xlarge or better). Very efficient - processes ~5.7 pages/s on H100.

Environment Variables:
    JOB_ID: Unique job identifier
    S3_BUCKET: S3 bucket name
    S3_INPUT_KEY: S3 key for input PDF
    DYNAMODB_TABLE: DynamoDB table name for job tracking
"""

import os
import sys
import tempfile
import logging
from pathlib import Path
from datetime import datetime, timezone

# Force offline mode - model is pre-downloaded
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import boto3
import pypdfium2 as pdfium
from PIL import Image
import torch
from transformers import LightOnOcrForConditionalGeneration, LightOnOcrProcessor

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


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


def load_lightonocr_model():
    """Load the LightOnOCR-2 model and processor with GPU support.

    Returns:
        tuple: (model, processor, device, dtype)
    """
    if not torch.cuda.is_available():
        raise RuntimeError("LightOnOCR-2 requires CUDA GPU support")

    device = "cuda"
    dtype = torch.bfloat16

    gpu_name = torch.cuda.get_device_name(0)
    gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
    logger.info(f"GPU: {gpu_name}")
    logger.info(f"GPU Memory: {gpu_memory:.1f} GB")

    logger.info("Loading LightOnOCR-2 model...")

    model = LightOnOcrForConditionalGeneration.from_pretrained(
        "lightonai/LightOnOCR-2-1B",
        torch_dtype=dtype,
        local_files_only=True
    ).to(device)

    processor = LightOnOcrProcessor.from_pretrained(
        "lightonai/LightOnOCR-2-1B",
        local_files_only=True
    )

    logger.info("LightOnOCR-2 model loaded successfully")
    return model, processor, device, dtype


def pdf_to_images(pdf_path: Path) -> list[Image.Image]:
    """Convert PDF to list of PIL Images using pypdfium2.

    Args:
        pdf_path: Path to PDF file

    Returns:
        List of PIL Images, one per page
    """
    pdf = pdfium.PdfDocument(pdf_path)
    images = []

    for page_num in range(len(pdf)):
        page = pdf[page_num]
        # Render at 200 DPI (scale factor = 200/72 ≈ 2.77)
        pil_image = page.render(scale=2.77).to_pil()
        images.append(pil_image)

    return images


def process_page_with_lightonocr(model, processor, device, dtype, image: Image.Image, page_num: int) -> str:
    """Process a single page image with LightOnOCR-2 model.

    Args:
        model: The LightOnOCR-2 model
        processor: The processor
        device: Device to run on
        dtype: Data type for tensors
        image: PIL Image of the page
        page_num: Page number (1-indexed)

    Returns:
        str: OCR text output
    """
    logger.info(f"Processing page {page_num}...")

    # Build conversation format expected by LightOnOCR-2
    conversation = [{"role": "user", "content": [{"type": "image", "image": image}]}]

    # Process inputs
    inputs = processor.apply_chat_template(
        conversation,
        add_generation_prompt=True,
        tokenize=True,
        return_dict=True,
        return_tensors="pt",
    )

    # Move to device with correct dtype
    inputs = {
        k: v.to(device=device, dtype=dtype) if v.is_floating_point() else v.to(device)
        for k, v in inputs.items()
    }

    # Generate output
    output_ids = model.generate(**inputs, max_new_tokens=4096)
    generated_ids = output_ids[0, inputs["input_ids"].shape[1]:]
    output_text = processor.decode(generated_ids, skip_special_tokens=True)

    logger.info(f"Page {page_num} processed ({len(output_text)} chars)")
    return output_text


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    logger.info(f"Starting LightOnOCR-2 job {job_id}")
    logger.info(f"Input: s3://{bucket_name}/{input_key}")

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
            images = pdf_to_images(input_pdf)
            logger.info(f"Converted {len(images)} pages to images")

            # Update substatus - loading models
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="loading_models")

            # Load LightOnOCR-2 model
            model, processor, device, dtype = load_lightonocr_model()

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process each page
            markdown_parts = []

            for i, image in enumerate(images, start=1):
                page_text = process_page_with_lightonocr(model, processor, device, dtype, image, i)

                # Add page separator for multi-page documents
                if i > 1:
                    markdown_parts.append("\n---\n")

                markdown_parts.append(f"<!-- Page {i} -->\n")
                markdown_parts.append(page_text)
                markdown_parts.append("\n")

                logger.info(f"Page {i}/{len(images)} completed")

            # Combine all pages into final markdown
            markdown_content = "\n".join(markdown_parts)

            # Generate result S3 key
            user_id = input_key.split("/")[0]
            md_result_key = f"{user_id}/{job_id}-result.md"

            # Update substatus - uploading
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="uploading")

            # Write and upload Markdown result
            md_file = temp_path / "output.md"
            md_file.write_text(markdown_content, encoding="utf-8")
            logger.info(f"Uploading Markdown result to s3://{bucket_name}/{md_result_key}")
            s3.upload_file(str(md_file), bucket_name, md_result_key)

            logger.info("Upload complete")

            # Update job status to completed
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

# CodeBuild specification for building and pushing LightOnOCR-2 container to ECR

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
      - cd backend/containers/lightonocr
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
      - aws ssm put-parameter --name "/pdf-models/cicd/lightonocr-image-tag" --value "$IMAGE_TAG" --type String --overwrite
      - echo "SSM parameter /pdf-models/cicd/lightonocr-image-tag updated to $IMAGE_TAG"
      # Update ECS task definition with new image
      - echo "Updating ECS task definition..."
      - TASK_DEF_FAMILY="pdf-models-lightonocr"
      - |
        CURRENT_TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_FAMILY --query 'taskDefinition' --output json)
        NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) | .containerDefinitions[0].image = "'"$ECR_REPOSITORY_URI:$IMAGE_TAG"'"')
        NEW_ARN=$(aws ecs register-task-definition --cli-input-json "$NEW_TASK_DEF" --query 'taskDefinition.taskDefinitionArn' --output text)
        echo "Registered new task definition: $NEW_ARN"
        aws ssm put-parameter --name "/pdf-models/lightonocr/task-definition-arn" --value "$NEW_ARN" --type String --overwrite
        echo "Updated /pdf-models/lightonocr/task-definition-arn to $NEW_ARN"
```

### Step 3: Create Model Stack in app.py

Add to `backend/app.py`:

```python
from backend.stack_config import MODELS

# Create LightOnOcrStack using generic ModelStack
LightOnOcrStack = ModelStack(
    app,
    "LightOnOcrStack",
    model_config=MODELS["lightonocr"],
    env=env,
)
```

### Step 4: Create Integration Test

Create `backend/tests/integration/test_lightonocr_e2e.py` following the pattern of existing tests.

### Step 5: Deployment Steps

1. Add model config to `stack_config.py`
2. Create container files
3. Commit and push to CodeCommit
4. Deploy FoundationStack (creates ECR repo): `make cdk-deploy STACK=FoundationStack`
5. Deploy CiCdStack (creates CodeBuild project): `make cdk-deploy STACK=CiCdStack`
6. Build container: `make container-build MODEL=lightonocr`
7. Deploy model stack: `make cdk-deploy STACK=LightOnOcrStack`
8. Update ApiV2Stack if needed
9. Run integration tests: `make test-integration-cloud MODEL=lightonocr`

## Notes

- LightOnOCR-2 requires transformers installed from source (not PyPI release)
- Uses pypdfium2 for PDF rendering (same as the model's examples)
- Very efficient model - good for high-volume processing
- No custom prompt support - it's a pure OCR model
- Consider using the bbox variant (LightOnOCR-2-1B-bbox) if image detection is needed

## Comparison with dots.ocr

| Feature | LightOnOCR-2 | dots.ocr |
|---------|--------------|----------|
| Parameters | 1B | 1.7B |
| Speed | 5.7 pages/s (H100) | Slower |
| Output | Clean text | Structured JSON + text |
| Layout detection | No (bbox variant available) | Yes |
| Custom prompts | No | Yes |
| Best for | High-volume OCR | Layout-aware parsing |
