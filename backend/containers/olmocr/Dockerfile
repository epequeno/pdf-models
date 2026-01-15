# olmocr PDF Processing Container
#
# Uses Allen AI's olmocr (7B parameter VLM) for document OCR and markdown conversion.
# Requires GPU with vLLM backend.
#
# Model: allenai/olmOCR-7B-0225-preview (pre-downloaded at build time)

# Use NVIDIA CUDA base image from NGC (avoids Docker Hub rate limits)
# olmocr requires CUDA 12.x for vLLM compatibility
FROM nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu22.04 AS builder

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
    torch torchvision --index-url https://download.pytorch.org/whl/cu124

# Install flash-attention (needs CUDA dev tools to build)
RUN pip3 install --no-cache-dir packaging wheel
RUN pip3 install flash-attn --no-build-isolation

# Runtime stage - smaller image without build tools
FROM nvcr.io/nvidia/cuda:12.4.0-runtime-ubuntu22.04

# Install Python and runtime dependencies (including fonts for PDF rendering)
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    poppler-utils \
    fonts-liberation \
    fonts-dejavu-core \
    fontconfig \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -fv

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories for model cache
RUN mkdir -p /app/models /app/cache /app/output && \
    chown -R appuser:appuser /app

# Copy flash-attn from builder
COPY --from=builder /usr/local/lib/python3.11/dist-packages /usr/local/lib/python3.11/dist-packages

# Install PyTorch with CUDA support
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu124

# Install olmocr with GPU support
# Use the PyTorch CUDA wheel index for compatible packages
RUN pip3 install --no-cache-dir \
    olmocr[gpu] --extra-index-url https://download.pytorch.org/whl/cu124

# Install additional dependencies for our task script
RUN pip3 install --no-cache-dir \
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

# Pre-download olmocr model
# This downloads the 7B parameter model (~15GB+)
RUN python3 -c "\
from huggingface_hub import snapshot_download; \
print('Downloading olmOCR model...'); \
snapshot_download(repo_id='allenai/olmOCR-7B-0225-preview', cache_dir='/app/cache'); \
print('Model pre-downloaded successfully')"

# Force offline mode AFTER model is downloaded
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV HF_DATASETS_OFFLINE=1

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
