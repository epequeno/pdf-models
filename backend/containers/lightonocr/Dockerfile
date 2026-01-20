# LightOnOCR-2 PDF Processing Container
#
# Uses LightOnOCR-2-1B (1B parameter VLM) for efficient document OCR.
# Requires GPU for optimal performance.
#
# Model: lightonai/LightOnOCR-2-1B (pre-downloaded at build time)

# Use NVIDIA CUDA base image from NGC (avoids Docker Hub rate limits)
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and runtime dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    poppler-utils \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    git \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories for model cache
RUN mkdir -p /app/models /app/cache && \
    chown -R appuser:appuser /app

# Install PyTorch with CUDA support
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu121

# Install transformers from source (LightOnOCR-2 requires unreleased features)
# This is per the model's documentation
RUN pip3 install --no-cache-dir \
    git+https://github.com/huggingface/transformers

# Install other dependencies
RUN pip3 install --no-cache-dir \
    pillow \
    pypdfium2 \
    boto3 \
    accelerate

# Copy task script
COPY task.py /app/task.py
WORKDIR /app

# Set environment variables for Hugging Face cache
ENV HF_HOME=/app/cache
ENV TRANSFORMERS_CACHE=/app/cache

# Switch to appuser for model download
USER appuser

# Pre-download LightOnOCR-2 model
# This downloads ~2GB of model weights
RUN python3 -c "\
from transformers import LightOnOcrForConditionalGeneration, LightOnOcrProcessor; \
import torch; \
print('Downloading LightOnOCR-2 model...'); \
model = LightOnOcrForConditionalGeneration.from_pretrained('lightonai/LightOnOCR-2-1B', torch_dtype=torch.bfloat16); \
processor = LightOnOcrProcessor.from_pretrained('lightonai/LightOnOCR-2-1B'); \
print('Model pre-downloaded successfully')"

# Force offline mode AFTER model is downloaded
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
