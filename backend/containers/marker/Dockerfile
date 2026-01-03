FROM public.ecr.aws/docker/library/python:3.11-slim

# Install system dependencies required by Marker
RUN apt-get update && apt-get install -y \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user first
RUN useradd -m -u 1000 appuser

# Create directories for marker data and models
RUN mkdir -p /app/marker_data/static /app/marker_data/cache /app/models && \
    chown -R appuser:appuser /app

# Install Python dependencies
# Note: pypdfium2 must be installed to avoid warnings
RUN pip install --no-cache-dir \
    pypdfium2 \
    marker-pdf \
    boto3

# Copy task script
COPY task.py /app/task.py
WORKDIR /app

# Set environment variables to redirect marker data to writable locations
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static

# Switch to appuser for model download (models will be owned by appuser)
USER appuser

# Pre-download Marker models during build to avoid runtime downloads
# This downloads ~1.34GB of models but makes runtime much faster
RUN python -c "from marker.models import create_model_dict; create_model_dict()" && \
    echo "Models pre-downloaded successfully"

ENTRYPOINT ["python", "task.py"]
