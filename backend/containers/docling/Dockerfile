# Docling PDF Processing Container
#
# Uses IBM's Docling library for document conversion with layout detection
# and table structure recognition. Outputs JSON and Markdown.
#
# Model: granite-docling-258M (pre-downloaded at build time)

# Use AWS ECR Public Gallery to avoid Docker Hub rate limits
FROM public.ecr.aws/docker/library/python:3.11-slim

# Install system dependencies for PDF processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
# Use CPU-only PyTorch to reduce image size
RUN pip install --no-cache-dir \
    torch --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir \
    docling \
    boto3

# Pre-download models at build time to avoid runtime downloads
# This initializes Docling and downloads the granite-docling model
ENV HF_HOME=/app/hf_cache
ENV TORCH_HOME=/app/torch_cache

RUN python -c "\
from docling.document_converter import DocumentConverter; \
print('Initializing Docling and downloading models...'); \
converter = DocumentConverter(); \
print('Models downloaded successfully')"

# Set offline mode after download
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

WORKDIR /app
COPY task.py .

CMD ["python", "task.py"]
