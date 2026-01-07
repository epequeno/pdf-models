# DeepSeek-OCR PDF Processing Container
#
# Uses DeepSeek-OCR (3B parameter VLM) for document OCR and markdown conversion.
# Requires GPU with flash-attention support.
#
# Model: deepseek-ai/DeepSeek-OCR (pre-downloaded at build time)

# Use NVIDIA CUDA base image from NGC (avoids Docker Hub rate limits)
FROM nvcr.io/nvidia/cuda:12.1.0-devel-ubuntu22.04 AS builder

# Install Python and build dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-dev \
    python3.11-venv \
    python3-pip \
    git \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Install PyTorch with CUDA support first (required for flash-attn build)
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu121

# Install flash-attention (needs CUDA dev tools to build)
# Pin to 2.7.3 per DeepSeek-OCR requirements
RUN pip3 install --no-cache-dir packaging wheel
RUN pip3 install flash-attn==2.7.3 --no-build-isolation

# Runtime stage - smaller image without build tools
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
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories for model cache
RUN mkdir -p /app/models /app/cache && \
    chown -R appuser:appuser /app

# Copy flash-attn from builder
COPY --from=builder /usr/local/lib/python3.11/dist-packages /usr/local/lib/python3.11/dist-packages

# Install PyTorch with CUDA support
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu121

# Install other dependencies with pinned versions per DeepSeek-OCR requirements
# See https://huggingface.co/deepseek-ai/DeepSeek-OCR for version requirements
# addict, easydict, and matplotlib are required by DeepSeek-OCR's custom modeling code
RUN pip3 install --no-cache-dir \
    transformers==4.46.3 \
    tokenizers==0.20.3 \
    accelerate \
    einops \
    addict \
    easydict \
    matplotlib \
    pdf2image \
    pillow \
    boto3

# Copy task script
COPY task.py /app/task.py
WORKDIR /app

# Set environment variables for Hugging Face cache
ENV HF_HOME=/app/cache
ENV TRANSFORMERS_CACHE=/app/cache

# Switch to appuser for model download
USER appuser

# Pre-download DeepSeek-OCR model
# This downloads ~6GB of model weights
RUN python3 -c "\
from transformers import AutoModel, AutoTokenizer; \
import torch; \
print('Downloading DeepSeek-OCR model...'); \
tokenizer = AutoTokenizer.from_pretrained('deepseek-ai/DeepSeek-OCR', trust_remote_code=True); \
model = AutoModel.from_pretrained('deepseek-ai/DeepSeek-OCR', trust_remote_code=True, torch_dtype=torch.bfloat16); \
print('Model pre-downloaded successfully')"

# Force offline mode AFTER model is downloaded
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
