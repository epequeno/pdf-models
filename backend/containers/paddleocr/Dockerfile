# PaddleOCR PDF Processing Container
#
# Uses PaddleOCR for multilingual text detection and recognition.
# Supports GPU acceleration for optimal performance.

# Use NVIDIA CUDA base image from NGC
FROM nvcr.io/nvidia/cuda:12.1.0-runtime-ubuntu22.04

# Install Python and system dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create directories
RUN mkdir -p /app/models /app/.paddleocr && chown -R appuser:appuser /app

# Install PaddlePaddle GPU version and PaddleOCR
RUN pip3 install --no-cache-dir \
    paddlepaddle-gpu \
    paddleocr \
    boto3 \
    pdf2image \
    Pillow

COPY task.py /app/task.py
WORKDIR /app

# Set PaddleOCR model directory
ENV HOME=/app

USER appuser

# Pre-download PaddleOCR models during build (detection, recognition, angle classification)
# This downloads models to avoid runtime downloads
RUN python3 -c "from paddleocr import PaddleOCR; PaddleOCR(use_angle_cls=True, lang='en')" && \
    echo "PaddleOCR models pre-downloaded successfully"

# Set NVIDIA environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["python3", "task.py"]
