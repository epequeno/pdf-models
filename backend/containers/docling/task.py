#!/usr/bin/env python3
"""
Docling PDF Processing Task

This script runs inside an ECS container to process PDFs using IBM's Docling library.
Docling provides layout detection (11 types) and table structure recognition.

Outputs both JSON (structured document) and Markdown formats.

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

# Force offline mode - models are pre-downloaded
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import boto3

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

    if substatus:
        update_expr += ", substatus = :substatus"
        expr_attr_values[":substatus"] = substatus

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
    logger.info(f"Updated job {job_id} to status: {status}" + (f" ({substatus})" if substatus else ""))


def process_pdf_with_docling(input_path: str) -> dict:
    """Process a PDF file with Docling.

    Args:
        input_path: Path to the input PDF file

    Returns:
        dict with 'json' (structured document) and 'markdown' (text) content
    """
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions

    logger.info("Initializing Docling DocumentConverter...")

    # Use pre-downloaded models from DOCLING_ARTIFACTS_PATH
    artifacts_path = os.environ.get("DOCLING_ARTIFACTS_PATH")
    if artifacts_path:
        logger.info(f"Using artifacts from: {artifacts_path}")
        pipeline_options = PdfPipelineOptions(artifacts_path=artifacts_path)
        converter = DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            }
        )
    else:
        converter = DocumentConverter()

    logger.info(f"Converting PDF: {input_path}")
    result = converter.convert(input_path)

    # Get the document
    document = result.document

    # Export to markdown
    logger.info("Exporting to Markdown...")
    markdown_content = document.export_to_markdown()

    # Export to dict/JSON (structured format)
    logger.info("Exporting to JSON...")
    json_content = document.export_to_dict()

    # Add metadata
    json_content["_metadata"] = {
        "model": "docling",
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "page_count": len(document.pages) if hasattr(document, 'pages') else None,
    }

    return {
        "json": json_content,
        "markdown": markdown_content
    }


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    logger.info(f"Starting Docling job {job_id}")
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

            # Update substatus - loading models (Docling loads models internally)
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="loading_models")

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process with Docling
            results = process_pdf_with_docling(str(input_pdf))

            # Generate result S3 keys
            # Extract user_id from input_key (format: {user_id}/{job_id}.pdf)
            user_id = input_key.split("/")[0]
            json_result_key = f"{user_id}/{job_id}-result.json"
            md_result_key = f"{user_id}/{job_id}-result.md"

            # Update substatus - uploading
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="uploading")

            # Write and upload JSON result
            json_file = temp_path / "output.json"
            json_file.write_text(
                json.dumps(results["json"], indent=2, default=str),
                encoding="utf-8"
            )
            logger.info(f"Uploading JSON result to s3://{bucket_name}/{json_result_key}")
            s3.upload_file(str(json_file), bucket_name, json_result_key)

            # Write and upload Markdown result
            md_file = temp_path / "output.md"
            md_file.write_text(results["markdown"], encoding="utf-8")
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
