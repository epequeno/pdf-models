#!/usr/bin/env python3
"""
Marker PDF Processing Task

This script runs inside a Fargate container to process PDFs using the Marker model.
It downloads a PDF from S3, converts it to Markdown, uploads the result, and updates DynamoDB.

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

import pypdfium2  # Must be imported first to avoid warnings
import boto3
from marker.convert import convert_single_pdf
from marker.models import load_all_models

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
    logger.info(f"Updated job {job_id} to status: {status}")


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    logger.info(f"Starting job {job_id}")
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
            output_md = temp_path / "output.md"

            # Download PDF from S3
            logger.info("Downloading PDF from S3...")
            s3.download_file(bucket_name, input_key, str(input_pdf))
            logger.info(f"Downloaded PDF: {input_pdf.stat().st_size} bytes")

            # Load Marker models
            logger.info("Loading Marker models...")
            model_lst = load_all_models()
            logger.info("Models loaded successfully")

            # Convert PDF to Markdown
            logger.info("Converting PDF to Markdown...")
            full_text, images, out_meta = convert_single_pdf(
                str(input_pdf),
                model_lst
            )
            logger.info(f"Conversion complete. Output length: {len(full_text)} characters")

            # Write markdown to file
            output_md.write_text(full_text, encoding="utf-8")
            logger.info(f"Wrote markdown: {output_md.stat().st_size} bytes")

            # Generate result S3 key
            # Format: {user_id}/{job_id}-result.md
            # Extract user_id from input_key (format: {user_id}/{job_id}.pdf)
            user_id = input_key.split("/")[0]
            result_key = f"{user_id}/{job_id}-result.md"

            # Upload result to S3
            logger.info(f"Uploading result to s3://{bucket_name}/{result_key}")
            s3.upload_file(str(output_md), bucket_name, result_key)
            logger.info("Upload complete")

            # Update job status to completed
            update_job_status(
                dynamodb,
                table_name,
                job_id,
                "completed",
                s3_result_key=result_key
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
