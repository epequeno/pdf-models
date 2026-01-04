# Marker PDF Troubleshooting

## Dependency issues

### Error: No module named 'pypdfium2'

**Full error**:
```
ModuleNotFoundError: No module named 'pypdfium2'
```

**Cause**: Missing required dependency

**Fix**: Install pypdfium2 BEFORE marker-pdf:
```bash
pip install pypdfium2
pip install marker-pdf
```

**In Dockerfile**:
```dockerfile
RUN pip install pypdfium2
RUN pip install marker-pdf
```

### Error: No module named 'marker.convert'

**Cause**: Usually means marker-pdf installation failed

**Diagnosis**:
```bash
pip show marker-pdf
```

**Fix**: Reinstall with dependencies:
```bash
pip install --force-reinstall pypdfium2 marker-pdf
```

## Permission issues

### Error: [Errno 13] Permission denied: '/usr/local/lib/.../static'

**Full error**:
```
PermissionError: [Errno 13] Permission denied:
'/usr/local/lib/python3.11/site-packages/static'
```

**Cause**: The marker library's `download_font()` function doesn't respect `MARKER_DATA_DIR` environment variable and tries to write to read-only package directories.

**❌ Environment variables alone don't work**: Setting `MARKER_DATA_DIR` and `FONT_DIR` environment variables is **not sufficient** because the marker library hardcodes the font path at import time.

**✅ Solution**: Monkey-patch the `download_font()` function:

```python
# Import marker settings and configure paths BEFORE other marker imports
from marker import settings
settings.FONT_PATH = '/app/marker_data/static/GoNotoCurrent.ttf'
settings.MARKER_DATA_DIR = '/app/marker_data'

# Monkey-patch the download_font function to prevent permission errors
import marker.util
_original_download_font = marker.util.download_font

def patched_download_font():
    """Patched version that catches permission errors gracefully."""
    import os
    font_path = '/app/marker_data/static/GoNotoCurrent.ttf'
    font_dir = os.path.dirname(font_path)

    os.makedirs(font_dir, exist_ok=True)

    if not os.path.exists(font_path):
        try:
            _original_download_font()
        except (PermissionError, OSError):
            # Font download failed due to permissions - skip gracefully
            pass

# Replace the function before importing marker components
marker.util.download_font = patched_download_font

# Now safe to import
from marker.converters.pdf import PdfConverter
from marker.models import create_model_dict
```

**In Dockerfile**: Still set environment variables and create writable directories:
```dockerfile
# Create writable directories
RUN mkdir -p /app/marker_data/static /app/marker_data/cache && \
    chown -R appuser:appuser /app

# Set environment variables (helps with other marker data)
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static
```

**Why this is necessary**: The marker library reads `settings.FONT_PATH` at import time and the `download_font()` function uses `os.path.dirname(settings.FONT_PATH)` which may still point to the package directory. The monkey-patch ensures permission errors are caught before they crash the application.

## Model download issues

### First conversion takes 5+ minutes

**Symptom**: Long delay before conversion starts, downloading progress bars

**Cause**: Models downloading at runtime

**Fix**: Pre-download in Dockerfile:
```dockerfile
RUN python -c "from marker.models import create_model_dict; create_model_dict()"
```

**Requirements**:
- Sufficient memory (MEDIUM or larger instance)
- Good network connection
- Time (5-10 minutes for first build)

### Build killed during model download (exit code 137)

**Symptom**: Docker build fails with "Killed", exit code 137

**Cause**: Out of memory during model download (1.35 GB)

**Fix**: Increase CodeBuild compute type:
```python
# In cicd_stack.py
compute_type=codebuild.ComputeType.MEDIUM,  # 7 GB RAM
```

Then deploy: `make cdk-deploy STACK=CiCdStack`

### Models download every time container runs

**Symptom**: Despite pre-downloading, models download again at runtime

**Cause**: Models saved to wrong location or cache directory not persisted

**Diagnosis**: Check model location:
```python
import os
print(f"MARKER_DATA_DIR: {os.environ.get('MARKER_DATA_DIR')}")
```

**Fix**: Ensure environment variables set before model download:
```dockerfile
# Set env vars BEFORE downloading models
ENV MARKER_DATA_DIR=/app/marker_data
ENV FONT_DIR=/app/marker_data/static

# Then download
RUN python -c "from marker.models import create_model_dict; create_model_dict()"
```

## API compatibility issues

### Error: unexpected keyword argument 'model_dict'

**Full error**:
```
TypeError: convert_single_pdf() got an unexpected keyword argument 'model_dict'
```

**Cause**: Using old parameter name with new marker-pdf version

**Fix**: Change to new parameter name:
```python
# Old (marker-pdf < 1.0)
convert_single_pdf(pdf_path, model_dict=models)

# New (marker-pdf >= 1.0)
convert_single_pdf(pdf_path, artifact_dict=models)
```

### Error: No attribute 'create_model_dict'

**Cause**: API changed in newer version

**Diagnosis**: Check version:
```bash
pip show marker-pdf
```

**Fix**: Update code to match API version in use.

## Performance issues

### Conversion very slow (>1 minute per page)

**Possible causes**:
- CPU-bound instance type (use compute-optimized)
- No GPU acceleration (Marker can use GPU)
- Very complex PDFs (scanned documents)

**Optimization**:
1. Use appropriate instance type for workload
2. Consider GPU instances for batch processing
3. Check if PDF is already searchable (OCR may not be needed)

### High memory usage

**Symptom**: Container killed, exit code 137

**Cause**: Large PDF or multiple simultaneous conversions

**Fix**:
- Process PDFs sequentially, not in parallel
- Increase ECS task memory
- Consider pagination for very large PDFs

## Testing

### Verify installation

```python
# Test imports
from marker.convert import convert_single_pdf
from marker.models import create_model_dict

# Test model loading
models = create_model_dict()
print("Models loaded successfully")
```

### Test conversion

```python
from marker.convert import convert_single_pdf
from marker.models import create_model_dict

model_dict = create_model_dict()

try:
    markdown, images, metadata = convert_single_pdf(
        "test.pdf",
        artifact_dict=model_dict  # Use correct parameter name
    )
    print(f"Converted {len(markdown)} characters")
    print(f"Extracted {len(images)} images")
except Exception as e:
    print(f"Conversion failed: {e}")
    import traceback
    traceback.print_exc()
```

## Environment checklist

Before deploying, verify:

- [ ] pypdfium2 installed before marker-pdf
- [ ] Environment variables set (MARKER_DATA_DIR, FONT_DIR)
- [ ] Writable directories created with correct permissions
- [ ] Models pre-downloaded in container build
- [ ] Using correct API (artifact_dict vs model_dict)
- [ ] Sufficient memory for build (MEDIUM+) and runtime
- [ ] Container runs as non-root user
