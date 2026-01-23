# Implementation Plan: PaddleOCR Model

## Overview

**Library**: [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)

PaddleOCR is a practical ultra-lightweight OCR system developed by PaddlePaddle. It provides high-accuracy text detection and recognition for multiple languages with efficient inference speeds.

**Key Characteristics**:
- Multilingual support (80+ languages)
- Text detection + recognition in a single pipeline
- Angle classification for rotated text
- Structured layout output with bounding boxes and confidence scores
- Both CPU and GPU acceleration support
- Lightweight and production-ready

## Resource Requirements

| Resource | Value | Notes |
|----------|-------|-------|
| GPU | Optional but recommended | T4 (g4dn.xlarge) for better performance |
| VRAM | ~2GB | Small models |
| Instance Type | g4dn.xlarge | 1x T4 GPU, 4 vCPU, 16GB RAM |
| EBS Volume | 60GB | Models + container overhead |
| Timeout | 30 min | Fast inference |

## Implementation Steps

### Step 1: Add Model Configuration to stack_config.py

Add to `MODELS` dict in `backend/backend/stack_config.py`:

```python
"paddleocr": ModelConfig(
    name="paddleocr",
    cpu=4096,  # 4 vCPU
    memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
    container_path="paddleocr",
    output_formats=("markdown", "json"),  # Text + structured layout with bboxes
    timeout_minutes=30,
    supports_prompt=False,  # OCR-focused, no custom prompts
    use_gpu=True,  # PaddleOCR benefits from GPU acceleration
    gpu_count=1,
    instance_type="g4dn.xlarge",
    spot_enabled=True,
    min_capacity=0,  # Scale to zero when idle
    max_capacity=2,
    ebs_volume_size_gb=60,  # Models + container overhead
),
```

### Step 2: Create Container Directory

Create `backend/containers/paddleocr/` with three files:

#### 2.1 Dockerfile

```dockerfile
# PaddleOCR PDF Processing Container
#
# Uses PaddleOCR for multilingual text detection and recognition.
# Supports GPU acceleration for optimal performance.

# Use NVIDIA CUDA base image from NGC
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and system dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories
RUN mkdir -p /app/models /app/.paddleocr && chown -R appuser:appuser /app

# Install PaddlePaddle GPU version and PaddleOCR
RUN pip3 install --no-cache-dir \
    paddlepaddle-gpu \
    paddleocr \
    boto3 \
    pdf2image \
    Pillow

COPY task.py /app/task.py
WORKDIR /app

# Set PaddleOCR model directory
ENV HOME=/app

USER appuser

# Pre-download PaddleOCR models during build (detection, recognition, angle classification)
# This downloads models to avoid runtime downloads
RUN python3 -c "from paddleocr import PaddleOCR; PaddleOCR(use_angle_cls=True, lang='en', use_gpu=True)" && \
    echo "PaddleOCR models pre-downloaded successfully"

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
```

#### 2.2 task.py

```python
#!/usr/bin/env python3
"""
PaddleOCR PDF Processing Task

This script runs inside an ECS container to process PDFs using PaddleOCR.
It converts PDF pages to images, processes with PaddleOCR detection + recognition,
and outputs Markdown text and JSON with structured layout (bounding boxes, confidence).

GPU recommended for optimal performance (g4dn.xlarge or better).

Environment Variables:
    JOB_ID: Unique job identifier
    S3_BUCKET: S3 bucket name
    S3_INPUT_KEY: S3 key for input PDF
    DYNAMODB_TABLE: DynamoDB table name for job tracking
"""

import os
import sys
import json
import tempfile
import logging
from pathlib import Path
from datetime import datetime, timezone

import boto3
import numpy as np
from pdf2image import convert_from_path
from PIL import Image
from paddleocr import PaddleOCR

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


def load_paddleocr_model():
    """Load PaddleOCR model with GPU support.

    Returns:
        PaddleOCR instance
    """
    logger.info("Loading PaddleOCR model...")

    # Initialize PaddleOCR with angle classification and GPU support
    ocr = PaddleOCR(
        use_angle_cls=True,  # Enable angle classification for rotated text
        lang='en',  # English language models
        use_gpu=True,  # Enable GPU acceleration
        show_log=False  # Reduce log verbosity
    )

    logger.info("PaddleOCR model loaded successfully")
    return ocr


def process_page_with_paddleocr(ocr, image: Image.Image, page_num: int):
    """Process a single page with PaddleOCR.

    Args:
        ocr: PaddleOCR instance
        image: PIL Image of the page
        page_num: Page number (1-indexed)

    Returns:
        tuple: (markdown_text, layout_data)
    """
    logger.info(f"Processing page {page_num}...")

    # Convert PIL Image to numpy array for PaddleOCR
    img_array = np.array(image)

    # Run OCR with angle classification
    result = ocr.ocr(img_array, cls=True)

    page_text = []
    page_layout = []

    if result and result[0]:
        for line in result[0]:
            bbox, (text, confidence) = line
            page_text.append(text)
            page_layout.append({
                "text": text,
                "confidence": float(confidence),
                "bbox": [[float(x), float(y)] for x, y in bbox]
            })

    markdown_text = "\n".join(page_text)
    logger.info(f"Page {page_num} processed ({len(markdown_text)} chars, {len(page_layout)} text regions)")

    return markdown_text, page_layout


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    logger.info(f"Starting PaddleOCR job {job_id}")
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
            images = convert_from_path(str(input_pdf), dpi=150)
            logger.info(f"Converted {len(images)} pages to images")

            # Update substatus - loading models
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="loading_models")

            # Load PaddleOCR model
            ocr = load_paddleocr_model()

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process each page
            markdown_parts = []
            json_output = {"pages": []}

            for i, image in enumerate(images, start=1):
                text, layout = process_page_with_paddleocr(ocr, image, i)

                # Build markdown output
                if i > 1:
                    markdown_parts.append("\n---\n")
                markdown_parts.append(f"<!-- Page {i} -->\n")
                markdown_parts.append(text)
                markdown_parts.append("\n")

                # Build JSON output
                json_output["pages"].append({
                    "page_number": i,
                    "text": text,
                    "layout": layout
                })

                logger.info(f"Page {i}/{len(images)} completed")

            # Combine all pages into final outputs
            markdown_content = "\n".join(markdown_parts)

            # Generate result S3 keys
            user_id = input_key.split("/")[0]
            md_result_key = f"{user_id}/{job_id}-result.md"
            json_result_key = f"{user_id}/{job_id}-result.json"

            # Update substatus - uploading
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="uploading")

            # Write and upload Markdown result
            md_file = temp_path / "output.md"
            md_file.write_text(markdown_content, encoding="utf-8")
            logger.info(f"Uploading Markdown result to s3://{bucket_name}/{md_result_key}")
            s3.upload_file(str(md_file), bucket_name, md_result_key)

            # Write and upload JSON result (structured layout with bboxes)
            json_file = temp_path / "output.json"
            json_file.write_text(json.dumps(json_output, indent=2), encoding="utf-8")
            logger.info(f"Uploading JSON result to s3://{bucket_name}/{json_result_key}")
            s3.upload_file(str(json_file), bucket_name, json_result_key)

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

# CodeBuild specification for building and pushing PaddleOCR container to ECR

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
      - cd backend/containers/paddleocr
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
      - aws ssm put-parameter --name "/pdf-models/cicd/paddleocr-image-tag" --value "$IMAGE_TAG" --type String --overwrite
      - echo "SSM parameter /pdf-models/cicd/paddleocr-image-tag updated to $IMAGE_TAG"
      # Update ECS task definition with new image
      - echo "Updating ECS task definition..."
      - TASK_DEF_FAMILY="pdf-models-paddleocr"
      - |
        CURRENT_TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_FAMILY --query 'taskDefinition' --output json)
        NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) | .containerDefinitions[0].image = "'"$ECR_REPOSITORY_URI:$IMAGE_TAG"'"')
        NEW_ARN=$(aws ecs register-task-definition --cli-input-json "$NEW_TASK_DEF" --query 'taskDefinition.taskDefinitionArn' --output text)
        echo "Registered new task definition: $NEW_ARN"
        aws ssm put-parameter --name "/pdf-models/paddleocr/task-definition-arn" --value "$NEW_ARN" --type String --overwrite
        echo "Updated /pdf-models/paddleocr/task-definition-arn to $NEW_ARN"
```

### Step 3: Update CDK Stack Configuration

The model stack will be automatically created by the pipeline based on the ModelConfig in `stack_config.py`. The generic `ModelStack` handles all model deployments.

### Step 4: Create Integration Test

Create `backend/tests/integration/test_paddleocr_e2e.py` following the pattern of existing tests.

### Step 5: Deployment Steps

1. Add model config to `stack_config.py`
2. Create container files (Dockerfile, task.py, buildspec.yml)
3. Commit and push to CodeCommit
4. Deploy FoundationStack (creates ECR repo): `make cdk-deploy STACK=FoundationStack`
5. Deploy CiCdStack (creates CodeBuild project): `make cdk-deploy STACK=CiCdStack`
6. Build container: `make container-build MODEL=paddleocr`
7. Deploy model stack via pipeline: `make pipeline-start`
8. Run integration tests: `make test-integration-cloud MODEL=paddleocr`

## Notes

- PaddleOCR supports 80+ languages (can be configured in task.py by changing `lang` parameter)
- Angle classification helps with rotated documents (scanned PDFs)
- GPU version provides 3-5x speedup over CPU
- Both JSON (with bounding boxes) and Markdown outputs are generated
- Models are pre-downloaded during container build for faster cold starts
- Consider adding language as a parameter for multilingual support in future iterations

## Comparison with Other OCR Models

| Feature | PaddleOCR | dots.ocr | LightOnOCR-2 |
|---------|-----------|----------|--------------|
| Parameters | ~6M (detection) + ~6M (recognition) | 1.7B | 1B |
| Speed | Very fast | Moderate | Very fast |
| Layout detection | Bounding boxes only | Full layout + categories | No (text only) |
| Languages | 80+ | 100+ | Multilingual |
| Output | Text + bboxes | Structured JSON | Clean text |
| Best for | Fast multilingual OCR | Layout-aware parsing | Clean text extraction |

## References

- [PaddleOCR GitHub](https://github.com/PaddlePaddle/PaddleOCR)
- [PaddleOCR Documentation](https://paddlepaddle.github.io/PaddleOCR/)
- [PaddleOCR PyPI](https://pypi.org/project/paddleocr/)
- [PaddlePaddle](https://www.paddlepaddle.org.cn/)
