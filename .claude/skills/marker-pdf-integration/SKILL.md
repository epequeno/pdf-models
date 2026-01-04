---
name: marker-pdf-integration
description: Integrate the marker-pdf library for PDF to Markdown conversion. Use when working with the Marker library, fixing Marker container issues, configuring Marker directories, or debugging Marker API changes.
---

# Marker PDF Integration

Configure and use the marker-pdf library for high-quality PDF to Markdown conversion.

## Quick setup

**Install with dependencies** (correct order matters):
```bash
pip install pypdfium2  # Install first - required dependency
pip install marker-pdf
```

**Basic usage**:
```python
from marker.convert import convert_single_pdf
from marker.models import create_model_dict

# Create model dictionary
model_dict = create_model_dict()

# Convert PDF
markdown_text, images, metadata = convert_single_pdf(
    pdf_path="input.pdf",
    model_dict=model_dict
)
```

## Directory structure requirements

Marker requires write access to specific directories for fonts, cache, and models.

### Default locations (problematic in containers)

Marker tries to write to:
- `/usr/local/lib/python3.11/site-packages/marker_pdf/static/` - Fonts
- `~/.cache/datalab/` - Model cache

**Problem**: Non-root users lack permissions to these locations.

### Solution: Redirect with environment variables

**Set before importing marker**:
```python
import os

# Set environment variables BEFORE importing marker
os.environ['MARKER_DATA_DIR'] = '/app/marker_data'
os.environ['FONT_DIR'] = '/app/marker_data/static'

# Now import marker
from marker.convert import convert_single_pdf
```

**In Dockerfile**:
```dockerfile
# Create writable directories
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

# Set environment variables
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static

# Switch to non-root user
USER appuser
```

## Model management

### Pre-downloading models

**Problem**: First run downloads ~1.35 GB of models, adding 2-5 minutes to startup.

**Solution**: Pre-download during container build:
```dockerfile
# Pre-download models (requires MEDIUM or larger build instance)
RUN python -c "from marker.models import create_model_dict; create_model_dict()" && \
    echo "Models pre-downloaded successfully"
```

**Build requirements**:
- CodeBuild compute type: BUILD_GENERAL1_MEDIUM (7 GB RAM) or larger
- Timeout: 30+ minutes for first build
- Subsequent builds faster (layers cached)

### Model locations

Models download to:
- Default: `~/.cache/datalab/models/`
- Custom: `$MARKER_DATA_DIR/models/` if MARKER_DATA_DIR set

Model types:
- Layout detection: `layout/2025_09_23/` (~700 MB)
- Text recognition: Various models (~600 MB)
- Total: ~1.35 GB

## API changes

### Version differences

**Old API** (marker-pdf < 1.0):
```python
from marker.convert import convert_single_pdf

markdown, images, metadata = convert_single_pdf(
    pdf_path,
    model_dict=models  # Old parameter name
)
```

**New API** (marker-pdf >= 1.0):
```python
from marker.convert import convert_single_pdf

markdown, images, metadata = convert_single_pdf(
    pdf_path,
    artifact_dict=models  # New parameter name
)
```

**Migration**: Change `model_dict` → `artifact_dict` in function calls.

### Breaking changes checklist

When upgrading marker-pdf:
- [ ] Check parameter names (model_dict vs artifact_dict)
- [ ] Verify import paths (marker.convert, marker.models)
- [ ] Test model download works with new version
- [ ] Update requirements.txt with specific version
- [ ] Rebuild container and test

## Common issues

### Import error: No module named 'marker.convert'

**Cause**: Missing pypdfium2 dependency

**Solution**: Install pypdfium2 first:
```bash
pip install pypdfium2
pip install marker-pdf
```

### Permission denied: static directory

**Cause**: Marker trying to write fonts to system directory

**Solution**: Set environment variables (see "Directory structure" section above)

### Models download at runtime

**Symptom**: First conversion takes 5+ minutes

**Solution**: Pre-download models in Dockerfile (see "Model management" section)

### Out of memory during model download

**Symptom**: Container build killed (exit code 137)

**Cause**: Model download (1.35 GB) exceeds available memory

**Solution**: Use MEDIUM or larger CodeBuild instance:
```python
# In cicd_stack.py
compute_type=codebuild.ComputeType.MEDIUM,  # 7 GB RAM
```

## Container integration

**Complete Dockerfile example**:
```dockerfile
FROM python:3.11-slim

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create writable directories for marker
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir pypdfium2
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=appuser:appuser . .

# Set environment variables for marker
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static

# Pre-download models (requires MEDIUM+ build instance)
RUN python -c "from marker.models import create_model_dict; create_model_dict()" && \
    echo "Models pre-downloaded successfully"

# Switch to non-root user
USER appuser

ENTRYPOINT ["python", "task.py"]
```

## Reference

- [Marker GitHub](https://github.com/VikParuchuri/marker)
- [Marker PyPI](https://pypi.org/project/marker-pdf/)
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for debugging tips
