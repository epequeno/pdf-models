# Docling PDF Processing Container
#
# Uses IBM's Docling library for document conversion with layout detection
# and table structure recognition. Outputs JSON and Markdown.
#
# Models: granite-docling-258M + RapidOCR (pre-downloaded at build time)

# Use AWS ECR Public Gallery to avoid Docker Hub rate limits
FROM public.ecr.aws/docker/library/python:3.11-slim

# Install system dependencies for PDF processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    poppler-utils \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install docling with all dependencies
# Let docling manage its own torch/torchvision versions for compatibility
RUN pip install --no-cache-dir docling boto3

# Set up model cache directories
ENV HF_HOME=/app/hf_cache
ENV TORCH_HOME=/app/torch_cache

# Pre-download ALL models at build time using docling-tools
# Downloads to ~/.cache/docling/models by default (which is /root/.cache/docling/models in Docker)
RUN docling-tools models download

# Point to the actual download location for runtime
ENV DOCLING_ARTIFACTS_PATH=/root/.cache/docling/models

# Set offline mode after download
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

WORKDIR /app
COPY task.py .

CMD ["python", "task.py"]
