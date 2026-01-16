#!/usr/bin/env python3
"""
Dolphin PDF Processing Task

This script runs inside an ECS container to process PDFs using ByteDance's Dolphin model.
It converts PDF pages to images, processes with Dolphin VLM, and outputs both JSON and Markdown.

Supports both CPU (Fargate) and GPU (EC2 with g4dn.xlarge) execution:
- GPU: Uses float16 for faster inference (~10-15s per page)
- CPU: Uses float32 for compatibility (~1-2 min per page)

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


def load_dolphin_model():
    """Load the Dolphin model and processor with GPU support if available.

    Returns:
        tuple: (model, processor, tokenizer, device)
    """
    from transformers import VisionEncoderDecoderModel, AutoProcessor
    import torch

    # Detect device - use GPU if available
    device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info(f"Using device: {device}")

    if device == "cuda":
        gpu_name = torch.cuda.get_device_name(0)
        gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
        logger.info(f"GPU: {gpu_name}")
        logger.info(f"GPU Memory: {gpu_memory:.1f} GB")

    logger.info("Loading Dolphin model...")

    # Use local_files_only=True to prevent any network requests
    # Model is pre-downloaded in Docker build
    processor = AutoProcessor.from_pretrained(
        'ByteDance/Dolphin',
        trust_remote_code=True,
        local_files_only=True
    )

    # Get tokenizer from processor
    tokenizer = processor.tokenizer

    # Use FP16 on GPU for faster inference, FP32 on CPU
    dtype = torch.float16 if device == "cuda" else torch.float32
    logger.info(f"Using dtype: {dtype}")

    # Use VisionEncoderDecoderModel - the correct class for Dolphin
    model = VisionEncoderDecoderModel.from_pretrained(
        'ByteDance/Dolphin',
        trust_remote_code=True,
        torch_dtype=dtype,
        local_files_only=True
    )

    # Move model to GPU if available
    model = model.to(device)
    model.eval()

    logger.info("Dolphin model loaded successfully")
    return model, processor, tokenizer, device


def process_page_with_dolphin(model, processor, tokenizer, image: Image.Image, page_num: int, device: str, custom_prompt: str = None) -> dict:
    """Process a single page image with Dolphin model.

    Args:
        model: The Dolphin model (VisionEncoderDecoderModel)
        processor: The Dolphin processor
        tokenizer: The tokenizer from processor
        image: PIL Image of the page
        page_num: Page number (1-indexed)
        device: Device to run inference on ('cuda' or 'cpu')
        custom_prompt: Optional custom prompt from user. If None/empty, uses default.

    Returns:
        dict with page number, content, and dimensions
    """
    import torch

    logger.info(f"Processing page {page_num}...")

    # Use custom prompt if provided, otherwise use default
    # Dolphin requires specific prompt format with special tokens
    prompt = custom_prompt if custom_prompt else "Read text in the image."
    full_prompt = f"<s>{prompt} <Answer/>"

    if custom_prompt:
        logger.info(f"Using custom prompt: {prompt}")

    # Process the image separately
    inputs = processor(image, return_tensors="pt")

    # Get pixel values and move to device with correct dtype
    dtype = torch.float16 if device == "cuda" else torch.float32
    pixel_values = inputs.pixel_values.to(device, dtype=dtype)

    # Tokenize the prompt separately
    prompt_ids = tokenizer(
        full_prompt,
        add_special_tokens=False,
        return_tensors="pt"
    ).input_ids.to(device)

    decoder_attention_mask = torch.ones_like(prompt_ids).to(device)

    # Generate output with correct parameters for Dolphin
    with torch.no_grad():
        outputs = model.generate(
            pixel_values=pixel_values,
            decoder_input_ids=prompt_ids,
            decoder_attention_mask=decoder_attention_mask,
            min_length=1,
            max_length=4096,
            pad_token_id=tokenizer.pad_token_id,
            eos_token_id=tokenizer.eos_token_id,
            use_cache=True,
            bad_words_ids=[[tokenizer.unk_token_id]],
            return_dict_in_generate=True,
            do_sample=False,
            num_beams=1,
        )

    # Decode the output, keeping special tokens to remove them properly
    sequence = tokenizer.batch_decode(outputs.sequences, skip_special_tokens=False)[0]

    # Remove prompt and special tokens from output
    generated_text = sequence.replace(full_prompt, "").replace("<pad>", "").replace("</s>", "").strip()

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

    # Get optional custom prompt (empty string means use default)
    custom_prompt = os.environ.get("PROMPT", "").strip() or None

    logger.info(f"Starting Dolphin job {job_id}")
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

            # Load Dolphin model (with GPU support if available)
            model, processor, tokenizer, device = load_dolphin_model()

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process each page
            pages_data = []
            for i, image in enumerate(images, start=1):
                page_result = process_page_with_dolphin(model, processor, tokenizer, image, i, device, custom_prompt)
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

            # Update substatus - uploading
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="uploading")

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
