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
