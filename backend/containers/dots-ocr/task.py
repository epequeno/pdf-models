#!/usr/bin/env python3
"""
dots.ocr PDF Processing Task

This script runs inside an ECS container to process PDFs using dots.ocr model.
It converts PDF pages to images, processes with the 1.7B parameter VLM, and outputs
structured JSON with layout detection and Markdown text.

GPU required (g4dn.xlarge or better). Uses FlashAttention2 on Ampere+ GPUs.

Environment Variables:
    JOB_ID: Unique job identifier
    S3_BUCKET: S3 bucket name
    S3_INPUT_KEY: S3 key for input PDF
    DYNAMODB_TABLE: DynamoDB table name for job tracking
    PROMPT: Optional custom prompt (default: layout detection + OCR)
"""

import os
import sys
import tempfile
import logging
import json
from pathlib import Path
from datetime import datetime, timezone

# Force offline mode - model is pre-downloaded
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import boto3
from pdf2image import convert_from_path
from PIL import Image
import torch
from transformers import AutoModelForCausalLM, AutoProcessor
from qwen_vl_utils import process_vision_info

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Model path (pre-downloaded during container build)
# Note: Directory name must not contain periods per dots.ocr docs
MODEL_PATH = "/app/weights/DotsOCR"

# Default prompt for layout detection + OCR
DEFAULT_PROMPT = """Please output the layout information from the PDF image, including each layout element's bbox, its category, and the corresponding text content within the bbox.

1. Bbox format: [x1, y1, x2, y2]

2. Layout Categories: The possible categories are ['Caption', 'Footnote', 'Formula', 'List-item', 'Page-footer', 'Page-header', 'Picture', 'Section-header', 'Table', 'Text', 'Title'].

3. Text Extraction & Formatting Rules:
    - Picture: For the 'Picture' category, the text field should be omitted.
    - Formula: Format its text as LaTeX.
    - Table: Format its text as HTML.
    - All Others (Text, Title, etc.): Format their text as Markdown.

4. Constraints:
    - The output text must be the original text from the image, with no translation.
    - All layout elements must be sorted according to human reading order.

5. Final Output: The entire output must be a single JSON object."""


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


def load_dots_ocr_model():
    """Load the dots.ocr model and processor with GPU support.

    Returns:
        tuple: (model, processor)
    """
    if not torch.cuda.is_available():
        raise RuntimeError("dots.ocr requires CUDA GPU support")

    gpu_name = torch.cuda.get_device_name(0)
    gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1e9
    logger.info(f"GPU: {gpu_name}")
    logger.info(f"GPU Memory: {gpu_memory:.1f} GB")

    logger.info("Loading dots.ocr model...")

    # Check GPU compute capability for attention implementation
    compute_capability = torch.cuda.get_device_capability(0)
    if compute_capability[0] >= 8:
        attn_impl = 'flash_attention_2'
        logger.info("Using FlashAttention2 (Ampere+ GPU detected)")
    else:
        attn_impl = 'eager'
        logger.info(f"Using eager attention (compute capability {compute_capability[0]}.{compute_capability[1]} < 8.0)")

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        attn_implementation=attn_impl,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
        local_files_only=True
    )

    processor = AutoProcessor.from_pretrained(
        MODEL_PATH,
        trust_remote_code=True,
        local_files_only=True
    )

    logger.info("dots.ocr model loaded successfully")
    return model, processor



def process_page_with_dots_ocr(model, processor, image: Image.Image, page_num: int, temp_dir: Path, custom_prompt: str = None) -> dict:
    """Process a single page image with dots.ocr model.

    Args:
        model: The dots.ocr model
        processor: The processor
        image: PIL Image of the page
        page_num: Page number (1-indexed)
        temp_dir: Temporary directory for intermediate files
        custom_prompt: Optional custom prompt from user

    Returns:
        dict: Parsed JSON output with layout information
    """
    logger.info(f"Processing page {page_num}...")

    # Save image to temp file
    image_path = temp_dir / f"page_{page_num}.png"
    image.save(str(image_path), "PNG")

    # Use custom prompt if provided, otherwise use default
    prompt = custom_prompt if custom_prompt else DEFAULT_PROMPT

    # Build messages for the model
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image", "image": str(image_path)},
                {"type": "text", "text": prompt}
            ]
        }
    ]

    # Prepare inputs
    text = processor.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True
    )
    image_inputs, video_inputs = process_vision_info(messages)
    inputs = processor(
        text=[text],
        images=image_inputs,
        videos=video_inputs,
        padding=True,
        return_tensors="pt",
    )
    inputs = inputs.to("cuda")

    # Generate output
    generated_ids = model.generate(**inputs, max_new_tokens=24000)
    generated_ids_trimmed = [
        out_ids[len(in_ids):] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
    ]
    output_text = processor.batch_decode(
        generated_ids_trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
    )[0]

    logger.info(f"Page {page_num} processed ({len(output_text)} chars)")

    # Try to parse as JSON
    try:
        result = json.loads(output_text)
    except json.JSONDecodeError:
        # If not valid JSON, wrap in a simple structure
        result = {"raw_output": output_text}

    return result


def extract_markdown_from_layout(layout_data: dict) -> str:
    """Extract markdown text from dots.ocr layout output.

    Args:
        layout_data: Parsed JSON from dots.ocr

    Returns:
        str: Concatenated markdown text in reading order
    """
    if "raw_output" in layout_data:
        return layout_data["raw_output"]

    # dots.ocr outputs elements in reading order
    # Extract text from each element
    markdown_parts = []

    elements = layout_data if isinstance(layout_data, list) else layout_data.get("elements", [])

    for element in elements:
        text = element.get("text", "")
        category = element.get("category", "")

        if category == "Picture":
            # Pictures don't have text
            markdown_parts.append("[Image]")
        elif category == "Title":
            markdown_parts.append(f"# {text}")
        elif category == "Section-header":
            markdown_parts.append(f"## {text}")
        else:
            markdown_parts.append(text)

    return "\n\n".join(markdown_parts)


def main():
    """Main processing logic."""
    # Get required environment variables
    job_id = get_required_env("JOB_ID")
    bucket_name = get_required_env("S3_BUCKET")
    input_key = get_required_env("S3_INPUT_KEY")
    table_name = get_required_env("DYNAMODB_TABLE")

    # Get optional custom prompt
    custom_prompt = os.environ.get("PROMPT", "").strip() or None

    logger.info(f"Starting dots.ocr job {job_id}")
    logger.info(f"Input: s3://{bucket_name}/{input_key}")
    if custom_prompt:
        logger.info("Custom prompt provided")

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

            # Load dots.ocr model
            model, processor = load_dots_ocr_model()

            # Update substatus - converting
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="converting")

            # Process each page
            all_layouts = []
            markdown_parts = []

            for i, image in enumerate(images, start=1):
                layout_data = process_page_with_dots_ocr(model, processor, image, i, temp_path, custom_prompt)
                all_layouts.append({"page": i, "layout": layout_data})

                # Extract markdown from layout
                page_markdown = extract_markdown_from_layout(layout_data)
                if i > 1:
                    markdown_parts.append("\n---\n")
                markdown_parts.append(f"<!-- Page {i} -->\n")
                markdown_parts.append(page_markdown)

                logger.info(f"Page {i}/{len(images)} completed")

            # Generate result S3 keys
            user_id = input_key.split("/")[0]
            json_result_key = f"{user_id}/{job_id}-result.json"
            md_result_key = f"{user_id}/{job_id}-result.md"

            # Update substatus - uploading
            update_job_status(dynamodb, table_name, job_id, "processing", substatus="uploading")

            # Write and upload JSON result (full layout data)
            json_file = temp_path / "output.json"
            json_file.write_text(json.dumps({"pages": all_layouts}, indent=2), encoding="utf-8")
            logger.info(f"Uploading JSON result to s3://{bucket_name}/{json_result_key}")
            s3.upload_file(str(json_file), bucket_name, json_result_key)

            # Write and upload Markdown result
            markdown_content = "\n".join(markdown_parts)
            md_file = temp_path / "output.md"
            md_file.write_text(markdown_content, encoding="utf-8")
            logger.info(f"Uploading Markdown result to s3://{bucket_name}/{md_result_key}")
            s3.upload_file(str(md_file), bucket_name, md_result_key)

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
