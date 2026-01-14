# MinerU PDF Processing Container
#
# Uses OpenDataLab's MinerU library for high-quality PDF to Markdown/JSON conversion.
# Supports layout detection, table extraction, and formula recognition.
#
# Backend: pipeline (CPU-only, ~82% accuracy)
# Models: Pre-downloaded at build time for fast runtime execution

# Use AWS ECR Public Gallery to avoid Docker Hub rate limits
FROM public.ecr.aws/docker/library/python:3.11-slim

# Install system dependencies for PDF processing
# - poppler-utils: PDF utilities (pdfinfo, pdftoppm)
# - libgl1, libglib2.0-0: OpenCV dependencies
# - libgomp1: OpenMP for parallel processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install MinerU with all dependencies
# Note: Using pip instead of uv for simpler Docker builds
RUN pip install --no-cache-dir "mineru[all]" boto3

# Set up model cache directories
ENV HF_HOME=/app/hf_cache
ENV TORCH_HOME=/app/torch_cache
ENV MINERU_MODELS_DIR=/app/mineru_models

# Create working directory
WORKDIR /app

# Create MinerU configuration file for CPU pipeline mode
# This configures MinerU to use pre-downloaded models and CPU backend
RUN mkdir -p /app/mineru_models && \
    echo '{\n\
    "device-mode": "cpu",\n\
    "layout-config": {\n\
        "model": "doclayout_yolo"\n\
    },\n\
    "formula-config": {\n\
        "mfd_model": "yolo_v8_mfd",\n\
        "mfr_model": "unimernet_small",\n\
        "enable": true\n\
    },\n\
    "table-config": {\n\
        "model": "rapid_table",\n\
        "enable": true\n\
    }\n\
}' > /app/magic-pdf.json

# Set config file location
ENV MINERU_TOOLS_CONFIG_JSON=/app/magic-pdf.json

# Pre-download models at build time using mineru's official download command
# This downloads all required models (~2-5GB total) including:
# - Layout detection models (doclayout_yolo)
# - OCR models (paddleocr_torch)
# - Formula recognition models
# - Table detection models
RUN echo "Pre-downloading MinerU models..." && \
    mineru-models-download && \
    echo "Models pre-downloaded successfully"

# Set offline mode after download to prevent runtime downloads
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

# Copy task script
COPY task.py .

CMD ["python", "task.py"]
