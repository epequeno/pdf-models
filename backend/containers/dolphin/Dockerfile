FROM public.ecr.aws/docker/library/python:3.11-slim

# Install system dependencies required by Dolphin (pdf2image, PIL, etc.)
RUN apt-get update && apt-get install -y \
    poppler-utils \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user first
RUN useradd -m -u 1000 appuser

# Create directories for model cache
RUN mkdir -p /app/models /app/cache && \
    chown -R appuser:appuser /app

# Install Python dependencies
# Note: Using CPU-only PyTorch to reduce image size for Fargate
RUN pip install --no-cache-dir \
    torch --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir \
    transformers \
    accelerate \
    pdf2image \
    pillow \
    boto3

# Copy task script
COPY task.py /app/task.py
WORKDIR /app

# Set environment variables for Hugging Face cache (needed for download)
ENV HF_HOME=/app/cache
ENV TRANSFORMERS_CACHE=/app/cache

# Switch to appuser for model download
USER appuser

# Pre-download Dolphin-v2 model during build to avoid runtime downloads
# This downloads ~8GB of model weights but makes runtime much faster
RUN python -c "\
from transformers import AutoModelForVision2Seq, AutoProcessor; \
print('Downloading ByteDance/Dolphin model...'); \
processor = AutoProcessor.from_pretrained('ByteDance/Dolphin', trust_remote_code=True); \
model = AutoModelForVision2Seq.from_pretrained('ByteDance/Dolphin', trust_remote_code=True); \
print('Model pre-downloaded successfully')"

# Force offline mode AFTER model is downloaded - prevents any runtime network requests
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

ENTRYPOINT ["python", "task.py"]
