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
