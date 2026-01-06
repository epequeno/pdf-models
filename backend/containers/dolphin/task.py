#!/usr/bin/env python3
"""
Dolphin PDF Processing Task

This script runs inside a Fargate container to process PDFs using ByteDance's Dolphin model.
It converts PDF pages to images, processes with Dolphin VLM, and outputs both JSON and Markdown.

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
from pdf2image import convert_from_path
from PIL import Image

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
    s3_result_key: str = None,
    s3_result_keys: dict = None,
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

    # For backwards compatibility, set s3_result_key to markdown result
    if s3_result_key:
        update_expr += ", s3_result_key = :result_key"
        expr_attr_values[":result_key"] = s3_result_key

    # Also store multiple result keys for multi-format models
    if s3_result_keys:
        update_expr += ", s3_result_keys = :result_keys"
        expr_attr_values[":result_keys"] = s3_result_keys

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
    logger.info(f"Updated job {job_id} to status: {status}")


def load_dolphin_model():
    """Load the Dolphin model and processor."""
    from transformers import AutoModelForVision2Seq, AutoProcessor
    import torch

    logger.info("Loading Dolphin model...")
    processor = AutoProcessor.from_pretrained(
        'ByteDance/Dolphin',
        trust_remote_code=True
    )
    model = AutoModelForVision2Seq.from_pretrained(
        'ByteDance/Dolphin',
        trust_remote_code=True,
        torch_dtype=torch.float32  # CPU uses float32
    )
    logger.info("Dolphin model loaded successfully")
    return model, processor


def process_page_with_dolphin(model, processor, image: Image.Image, page_num: int) -> dict:
    """Process a single page image with Dolphin model."""
    import torch

    logger.info(f"Processing page {page_num}...")

    # Dolphin uses a specific prompt format for document understanding
    prompt = "Parse this document page and extract all text content with structure."

    # Process the image
    inputs = processor(
        text=prompt,
        images=image,
        return_tensors="pt"
    )

    # Generate output
    with torch.no_grad():
        generated_ids = model.generate(
            **inputs,
            max_new_tokens=4096,
            do_sample=False
        )

    # Decode the output
    generated_text = processor.batch_decode(
        generated_ids,
        skip_special_tokens=True
    )[0]

    # Remove the prompt from the output if present
    if prompt in generated_text:
        generated_text = generated_text.replace(prompt, "").strip()

    return {
        "page": page_num,
        "content": generated_text,
        "width": image.width,
        "height": image.height
    }


def convert_to_markdown(pages_data: list) -> str:
    """Convert structured page data to markdown."""
    markdown_parts = []

    for page_data in pages_data:
        page_num = page_data["page"]
        content = page_data["content"]

        # Add page separator for multi-page documents
        if page_num > 1:
            markdown_parts.append("\n---\n")

        markdown_parts.append(f"<!-- Page {page_num} -->\n")
        markdown_parts.append(content)
        markdown_parts.append("\n")

    return "\n".join(markdown_parts)


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    logger.info(f"Starting Dolphin job {job_id}")
    logger.info(f"Input: s3://{bucket_name}/{input_key}")

    # Initialize AWS clients
    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")

    try:
        # Update status to processing
        update_job_status(dynamodb, table_name, job_id, "processing")

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

            # Load Dolphin model
            model, processor = load_dolphin_model()

            # Process each page
            pages_data = []
            for i, image in enumerate(images, start=1):
                page_result = process_page_with_dolphin(model, processor, image, i)
                pages_data.append(page_result)
                logger.info(f"Page {i}/{len(images)} processed")

            # Generate result S3 keys
            # Extract user_id from input_key (format: {user_id}/{job_id}.pdf)
            user_id = input_key.split("/")[0]
            json_result_key = f"{user_id}/{job_id}-result.json"
            md_result_key = f"{user_id}/{job_id}-result.md"

            # Create JSON output
            json_output = {
                "job_id": job_id,
                "model": "dolphin",
                "pages": pages_data,
                "page_count": len(pages_data),
                "processed_at": datetime.now(timezone.utc).isoformat()
            }

            # Write and upload JSON result
            json_file = temp_path / "output.json"
            json_file.write_text(json.dumps(json_output, indent=2), encoding="utf-8")
            logger.info(f"Uploading JSON result to s3://{bucket_name}/{json_result_key}")
            s3.upload_file(str(json_file), bucket_name, json_result_key)

            # Convert to Markdown and upload
            markdown_content = convert_to_markdown(pages_data)
            md_file = temp_path / "output.md"
            md_file.write_text(markdown_content, encoding="utf-8")
            logger.info(f"Uploading Markdown result to s3://{bucket_name}/{md_result_key}")
            s3.upload_file(str(md_file), bucket_name, md_result_key)

            logger.info("Upload complete")

            # Update job status to completed with both result keys
            update_job_status(
                dynamodb,
                table_name,
                job_id,
                "completed",
                s3_result_key=md_result_key,  # Default to markdown for backwards compat
                s3_result_keys={
                    "json": json_result_key,
                    "markdown": md_result_key
                }
            )

            logger.info(f"Job {job_id} completed successfully")

    except Exception as e:
        logger.error(f"Job {job_id} failed: {str(e)}", exc_info=True)

        # Update job status to failed
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
