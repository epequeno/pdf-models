#!/usr/bin/env python3
"""
DeepSeek-OCR PDF Processing Task

This script runs inside an ECS container to process PDFs using DeepSeek-OCR model.
It converts PDF pages to images, processes with the 3B parameter VLM, and outputs Markdown.

GPU required (g4dn.xlarge or better). Uses FlashAttention2 on Ampere+ GPUs, falls back
to eager attention on older GPUs (T4/Turing).

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

# Force offline mode - model is pre-downloaded, no need to check HuggingFace
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

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


def load_deepseek_ocr_model():
    """Load the DeepSeek-OCR model and tokenizer with GPU support.

    Returns:
        tuple: (model, tokenizer)
    """
    from transformers import AutoModel, AutoTokenizer
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("DeepSeek-OCR requires CUDA GPU support")

    device = "cuda"
    gpu_name = torch.cuda.get_device_name(0)
    gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
    logger.info(f"GPU: {gpu_name}")
    logger.info(f"GPU Memory: {gpu_memory:.1f} GB")

    logger.info("Loading DeepSeek-OCR model...")

    # Use local_files_only=True to prevent any network requests
    tokenizer = AutoTokenizer.from_pretrained(
        'deepseek-ai/DeepSeek-OCR',
        trust_remote_code=True,
        local_files_only=True
    )

    # Check GPU compute capability for attention implementation
    # FlashAttention requires Ampere+ (sm_80+), T4 is Turing (sm_75)
    compute_capability = torch.cuda.get_device_capability(0)
    if compute_capability[0] >= 8:
        attn_impl = 'flash_attention_2'
        logger.info("Using FlashAttention2 (Ampere+ GPU detected)")
    else:
        attn_impl = 'eager'
        logger.info(f"Using eager attention (compute capability {compute_capability[0]}.{compute_capability[1]} < 8.0)")

    model = AutoModel.from_pretrained(
        'deepseek-ai/DeepSeek-OCR',
        _attn_implementation=attn_impl,
        trust_remote_code=True,
        use_safetensors=True,
        local_files_only=True
    )

    model = model.eval().cuda().to(torch.bfloat16)

    logger.info("DeepSeek-OCR model loaded successfully")
    return model, tokenizer


def process_page_with_deepseek(model, tokenizer, image: Image.Image, page_num: int, temp_dir: Path, custom_prompt: str = None) -> str:
    """Process a single page image with DeepSeek-OCR model.

    Args:
        model: The DeepSeek-OCR model
        tokenizer: The tokenizer
        image: PIL Image of the page
        page_num: Page number (1-indexed)
        temp_dir: Temporary directory for intermediate files
        custom_prompt: Optional custom prompt from user. If None/empty, uses default.

    Returns:
        str: Markdown content for the page
    """
    logger.info(f"Processing page {page_num}...")

    # Save image to temp file (model.infer expects a file path)
    image_path = temp_dir / f"page_{page_num}.png"
    image.save(str(image_path), "PNG")

    # Output directory for this page
    output_dir = temp_dir / f"output_{page_num}"
    output_dir.mkdir(exist_ok=True)

    # Use custom prompt if provided, otherwise use default
    # DeepSeek-OCR requires <image> tag in prompt
    if custom_prompt:
        # If user's prompt doesn't include <image>, prepend it
        if "<image>" not in custom_prompt:
            prompt = f"<image>\n{custom_prompt}"
        else:
            prompt = custom_prompt
        logger.info(f"Using custom prompt: {prompt}")
    else:
        prompt = "<image>\nConvert the document to markdown."

    # Run inference using the model's infer method
    # Using "Gundam" config (base_size=1024, image_size=640, crop_mode=True)
    # which balances quality and speed
    # Note: model.infer() prints output and saves to file but returns None
    model.infer(
        tokenizer,
        prompt=prompt,
        image_file=str(image_path),
        output_path=str(output_dir),
        base_size=1024,
        image_size=640,
        crop_mode=True,
        save_results=True,  # Save output to file so we can read it
        test_compress=False
    )

    # Read the saved output file - DeepSeek-OCR saves as {image_name}_ocr.txt
    output_file = output_dir / f"page_{page_num}_ocr.txt"
    if not output_file.exists():
        # Try alternate naming patterns
        txt_files = list(output_dir.glob("*.txt"))
        if txt_files:
            output_file = txt_files[0]
        else:
            logger.warning(f"No output file found for page {page_num}, using empty string")
            return ""

    result = output_file.read_text(encoding="utf-8")
    logger.info(f"Page {page_num} processed ({len(result)} chars)")
    return result


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    # Get optional custom prompt (empty string means use default)
    custom_prompt = os.environ.get("PROMPT", "").strip() or None

    logger.info(f"Starting DeepSeek-OCR job {job_id}")
    logger.info(f"Input: s3://{bucket_name}/{input_key}")
    if custom_prompt:
        logger.info(f"Custom prompt provided: {custom_prompt}")

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

            # Load DeepSeek-OCR model
            model, tokenizer = load_deepseek_ocr_model()

            # Process each page
            markdown_parts = []
            for i, image in enumerate(images, start=1):
                page_content = process_page_with_deepseek(model, tokenizer, image, i, temp_path, custom_prompt)

                # Add page separator for multi-page documents
                if i > 1:
                    markdown_parts.append("\n---\n")

                markdown_parts.append(f"<!-- Page {i} -->\n")
                markdown_parts.append(page_content)
                markdown_parts.append("\n")

                logger.info(f"Page {i}/{len(images)} completed")

            # Combine all pages into final markdown
            markdown_content = "\n".join(markdown_parts)

            # Generate result S3 key
            # Extract user_id from input_key (format: {user_id}/{job_id}.pdf)
            user_id = input_key.split("/")[0]
            md_result_key = f"{user_id}/{job_id}-result.md"

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
