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

# Create writable directories for marker data
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
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

# Run as non-root user
USER appuser

# Set environment variables to redirect marker data to writable locations
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static

ENTRYPOINT ["python", "task.py"]
