# Use NVIDIA CUDA base image for GPU support
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and system dependencies
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

RUN pip3 install --no-cache-dir \
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

# Pre-download Dolphin model with FP16 for GPU inference
# This downloads ~8GB of model weights but makes runtime much faster
RUN python3 -c "\
from transformers import AutoModelForVision2Seq, AutoProcessor; \
import torch; \
print('Downloading ByteDance/Dolphin model for GPU...'); \
processor = AutoProcessor.from_pretrained('ByteDance/Dolphin', trust_remote_code=True); \
model = AutoModelForVision2Seq.from_pretrained('ByteDance/Dolphin', trust_remote_code=True, torch_dtype=torch.float16); \
print('Model pre-downloaded successfully')"

# Force offline mode AFTER model is downloaded - prevents any runtime network requests
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
