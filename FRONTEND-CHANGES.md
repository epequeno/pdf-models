# Backend API Changes for Frontend

This document tracks backend changes that affect the frontend during multi-model implementation.

---

## Summary of Changes (Phase 1: Refactor for Modularity)

### API Changes

**No breaking changes for existing frontend code.** The API endpoints remain the same:
- `POST /v1/models/{model}/upload-url`
- `POST /v1/models/{model}/jobs`
- `GET /v1/models/{model}/jobs`
- `GET /v1/models/{model}/jobs/{job_id}`

### Behavioral Changes

1. **Model validation is now dynamic**: Instead of hardcoded "marker" validation, the backend now validates models by checking for SSM parameters. This means:
   - New models can be added without Lambda redeployment
   - Invalid models will get a clearer error: `"Invalid model '{model}'. Model not supported."`

2. **Error message change**: The error message for invalid models changed from:
   - Old: `"Invalid model. Only 'marker' is supported"`
   - New: `"Invalid model '{model}'. Model not supported."`

### New Models (Coming in Phase 2)

When Dolphin model is added, the frontend will be able to use:
- `POST /v1/models/dolphin/upload-url`
- `POST /v1/models/dolphin/jobs`
- `GET /v1/models/dolphin/jobs`
- `GET /v1/models/dolphin/jobs/{job_id}`

### Future: Multiple Output Formats

Dolphin will support multiple output formats (JSON and Markdown). The job response will include:
```json
{
  "s3_result_keys": {
    "json": "user-id/job-id-result.json",
    "markdown": "user-id/job-id-result.md"
  },
  "download_urls": {
    "json": "https://...",
    "markdown": "https://..."
  }
}
```

**Note**: This will require frontend updates to handle multiple download options when Phase 2 is implemented.

---

## Files Modified in Phase 1

| File | Change Summary |
|------|----------------|
| `backend/backend/stack_config.py` | Added `ModelConfig` dataclass and `MODELS` registry |
| `backend/backend/model_stack.py` | NEW: Generic parameterized model stack |
| `backend/backend/foundation_stack.py` | Dynamic ECR repo creation per model |
| `backend/backend/cicd_stack.py` | Dynamic CodeBuild project creation per model |
| `backend/backend/api_v2_stack.py` | Multi-model permissions, removed hardcoded state machine ARN |
| `backend/app.py` | Dynamic model stack instantiation |
| `backend/lambdas/submit-job/` | SSM-based model validation |
| `backend/lambdas/get-job/` | SSM-based model validation |
| `backend/lambdas/get-upload-url/` | SSM-based model validation |

---

## Deployment Notes

Phase 1 changes require redeploying:
1. FoundationStack (updates ECR creation logic)
2. CiCdStack (updates CodeBuild creation logic)
3. MarkerStack → now uses ModelStack
4. ApiV2Stack (Lambda permissions and environment)
5. Lambda code rebuild (new SSM dependencies)
