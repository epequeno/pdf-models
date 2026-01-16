#!/usr/bin/env python3
"""
docext (Nanonets-OCR-s) PDF Processing Task

This script runs inside an ECS container to process PDFs using Nanonets-OCR-s model.
It converts PDF pages to images, processes with the 3B parameter VLM (based on Qwen2.5-VL),
and outputs Markdown with semantic understanding.

GPU required (g4dn.xlarge or better). Uses FlashAttention2 on Ampere+ GPUs, falls back
to eager attention on older GPUs (T4/Turing).

Environment Variables:
    JOB_ID: Unique job identifier
    S3_BUCKET: S3 bucket name
    S3_INPUT_KEY: S3 key for input PDF
    DYNAMODB_TABLE: DynamoDB table name for job tracking
    PROMPT: Optional custom prompt for processing
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

# Default prompt for Nanonets-OCR-s
DEFAULT_PROMPT = """Extract the text from the above document as if you were reading it naturally.
Return the tables in html format. Return the equations in LaTeX representation.
If there is an image in the document and image caption is not present, add a small description of the image inside the <img></img> tag; otherwise, add the image caption inside <img></img>.
Watermarks should be wrapped in brackets. Ex: <watermark>OFFICIAL COPY</watermark>.
Page numbers should be wrapped in brackets. Ex: <page_number>14</page_number>.
Prefer using \u2610 and \u2611 for check boxes."""


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


def load_nanonets_model():
    """Load the Nanonets-OCR-s model, processor, and tokenizer with GPU support.

    Returns:
        tuple: (model, processor, tokenizer)
    """
    from transformers import AutoTokenizer, AutoProcessor, AutoModelForImageTextToText
    import torch

    if not torch.cuda.is_available():
        raise RuntimeError("Nanonets-OCR-s requires CUDA GPU support")

    device = "cuda"
    gpu_name = torch.cuda.get_device_name(0)
    gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
    logger.info(f"GPU: {gpu_name}")
    logger.info(f"GPU Memory: {gpu_memory:.1f} GB")

    logger.info("Loading Nanonets-OCR-s model...")

    model_path = "nanonets/Nanonets-OCR-s"

    # Use local_files_only=True to prevent any network requests
    tokenizer = AutoTokenizer.from_pretrained(
        model_path,
        local_files_only=True
    )

    processor = AutoProcessor.from_pretrained(
        model_path,
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

    model = AutoModelForImageTextToText.from_pretrained(
        model_path,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        attn_implementation=attn_impl,
        local_files_only=True
    )
    model.eval()

    logger.info("Nanonets-OCR-s model loaded successfully")
    return model, processor, tokenizer


def process_page_with_nanonets(
    model,
    processor,
    image: Image.Image,
    page_num: int,
    temp_dir: Path,
    custom_prompt: str = None
) -> str:
    """Process a single page image with Nanonets-OCR-s model.

    Args:
        model: The Nanonets-OCR-s model
        processor: The processor
        image: PIL Image of the page
        page_num: Page number (1-indexed)
        temp_dir: Temporary directory for intermediate files
        custom_prompt: Optional custom prompt from user. If None/empty, uses default.

    Returns:
        str: Markdown content for the page
    """
    import torch

    logger.info(f"Processing page {page_num}...")

    # Save image to temp file for the message format
    image_path = temp_dir / f"page_{page_num}.png"
    image.save(str(image_path), "PNG")

    # Use custom prompt if provided, otherwise use default
    prompt = custom_prompt if custom_prompt else DEFAULT_PROMPT
    if custom_prompt:
        logger.info(f"Using custom prompt: {prompt}")

    # Build messages in the format expected by Nanonets-OCR-s
    messages = [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": [
            {"type": "image", "image": f"file://{image_path}"},
            {"type": "text", "text": prompt},
        ]},
    ]

    # Apply chat template
    text = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)

    # Process inputs
    inputs = processor(
        text=[text],
        images=[image],
        padding=True,
        return_tensors="pt"
    )
    inputs = inputs.to(model.device)

    # Generate output
    with torch.no_grad():
        output_ids = model.generate(
            **inputs,
            max_new_tokens=4096,
            do_sample=False
        )

    # Decode output (skip the input tokens)
    generated_ids = [
        output_ids[len(input_ids):]
        for input_ids, output_ids in zip(inputs.input_ids, output_ids)
    ]

    result = processor.batch_decode(
        generated_ids,
        skip_special_tokens=True,
        clean_up_tokenization_spaces=True
    )[0]

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

    logger.info(f"Starting docext (Nanonets-OCR-s) job {job_id}")
    logger.info(f"Input: s3://{bucket_name}/{input_key}")
    if custom_prompt:
        logger.info(f"Custom prompt provided: {custom_prompt}")

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

            # Load Nanonets-OCR-s model
            model, processor, tokenizer = load_nanonets_model()

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process each page
            markdown_parts = []
            for i, image in enumerate(images, start=1):
                page_content = process_page_with_nanonets(
                    model, processor, image, i, temp_path, custom_prompt
                )

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
