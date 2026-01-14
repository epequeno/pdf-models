#!/usr/bin/env python3
"""
MinerU PDF Processing Task

This script runs inside an ECS container to process PDFs using OpenDataLab's MinerU library.
MinerU provides high-quality PDF to Markdown/JSON conversion with layout detection,
table extraction, and formula recognition.

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

# Ensure MinerU config is set
if "MINERU_TOOLS_CONFIG_JSON" not in os.environ:
    os.environ["MINERU_TOOLS_CONFIG_JSON"] = "/app/magic-pdf.json"

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


def process_pdf_with_mineru(input_path: str, output_dir: str) -> dict:
    """Process a PDF file with MinerU.

    Args:
        input_path: Path to the input PDF file
        output_dir: Directory to write output files

    Returns:
        dict with 'json' (structured document) and 'markdown' (text) content
    """
    # MinerU 2.x imports
    from mineru.cli.common import do_parse

    logger.info("Initializing MinerU processing...")

    # Read PDF bytes
    logger.info(f"Reading PDF: {input_path}")
    with open(input_path, "rb") as f:
        pdf_bytes = f.read()

    # Get PDF filename without extension for output naming
    pdf_name = os.path.splitext(os.path.basename(input_path))[0]

    # Process with MinerU using the high-level API
    # do_parse writes output files to disk
    logger.info("Processing document with MinerU...")
    do_parse(
        output_dir=output_dir,
        pdf_file_names=[pdf_name],
        pdf_bytes_list=[pdf_bytes],
        lang_list=['en'],
        backend='pipeline',  # CPU mode, no GPU required
        parse_method='auto',
        f_dump_middle_json=True,
        f_dump_content_list=True,
    )

    # Read the generated output files
    # MinerU outputs to: output_dir/pdf_name/auto/
    result_dir = os.path.join(output_dir, pdf_name, 'auto')

    # Read markdown output
    md_path = os.path.join(result_dir, f'{pdf_name}.md')
    if os.path.exists(md_path):
        with open(md_path, 'r', encoding='utf-8') as f:
            markdown_content = f.read()
    else:
        logger.warning(f"Markdown file not found at {md_path}")
        markdown_content = ""

    # Read middle JSON for structured content
    middle_json_path = os.path.join(result_dir, f'{pdf_name}_middle.json')
    if os.path.exists(middle_json_path):
        with open(middle_json_path, 'r', encoding='utf-8') as f:
            middle_json = json.load(f)
    else:
        logger.warning(f"Middle JSON not found at {middle_json_path}")
        middle_json = {}

    # Build structured JSON output
    json_content = {
        "content": middle_json.get("content_list", []),
        "pdf_info": middle_json.get("pdf_info", {}),
        "_metadata": {
            "model": "mineru",
            "backend": "pipeline",
            "processed_at": datetime.now(timezone.utc).isoformat(),
        }
    }

    logger.info(f"Processing complete: {len(markdown_content)} chars markdown")

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

    logger.info(f"Starting MinerU job {job_id}")
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
            output_subdir = temp_path / "output"
            output_subdir.mkdir()

            # Download PDF from S3
            logger.info("Downloading PDF from S3...")
            s3.download_file(bucket_name, input_key, str(input_pdf))
            logger.info(f"Downloaded PDF: {input_pdf.stat().st_size} bytes")

            # Process with MinerU
            results = process_pdf_with_mineru(str(input_pdf), str(output_subdir))

            # Generate result S3 keys
            # Extract user_id from input_key (format: {user_id}/{job_id}.pdf)
            user_id = input_key.split("/")[0]
            json_result_key = f"{user_id}/{job_id}-result.json"
            md_result_key = f"{user_id}/{job_id}-result.md"

            # Write and upload JSON result
            json_file = temp_path / "output.json"
            json_file.write_text(
                json.dumps(results["json"], indent=2, default=str, ensure_ascii=False),
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
