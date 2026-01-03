# Frontend Deployment Guide

## Overview

The frontend is deployed to AWS using S3 + CloudFront with automatic deployments from the `frontend/dst` folder.

**Domain:** epequeno.app
**CDN:** CloudFront with Origin Access Control (OAC)
**DNS:** Route53 (existing hosted zone)
**SSL/TLS:** ACM certificate with automatic DNS validation

## Architecture

```
User → CloudFront (CDN) → S3 Bucket (private)
       ↑
       Route53 (epequeno.app)
       ACM Certificate (SSL/TLS)
```

**Key Features:**
- Automatic deployments when `frontend/dst` changes
- CloudFront cache invalidations on deploy
- HTTPS-only with redirect from HTTP
- SPA routing support (404/403 → index.html)
- Gzip compression enabled
- S3 versioning for rollback capability

## Prerequisites

1. **Build the frontend first:**
   ```bash
   cd frontend
   ./build.sh
   ```

2. **Verify `dst/` folder exists:**
   ```bash
   ls -la frontend/dst
   # Should contain: index.html, main.js, interop.js
   ```

3. **AWS credentials configured:**
   ```bash
   # Verify AWS_PROFILE=arch is configured
   aws sts get-caller-identity --profile arch
   ```

## Deployment Steps

### First-Time Deployment

1. **Deploy the FrontendStack:**
   ```bash
   make cdk-deploy STACK=FrontendStack
   ```

   This will:
   - Create S3 bucket: `epequeno.app-frontend`
   - Create CloudFront distribution
   - Create ACM certificate (requires DNS validation)
   - Set up Route53 A records for apex and www
   - Deploy contents of `frontend/dst` to S3
   - Invalidate CloudFront cache

2. **Wait for certificate validation:**

   ACM will automatically create DNS validation records in Route53. This typically takes 5-10 minutes. You can check the status:
   ```bash
   aws acm list-certificates --region us-east-1 --profile arch
   ```

3. **Wait for CloudFront deployment:**

   CloudFront distributions take 15-30 minutes to deploy globally. Check status:
   ```bash
   aws cloudfront list-distributions --profile arch --query 'DistributionList.Items[?Comment==`CDN for epequeno.app`].[Id,Status]'
   ```

4. **Access your site:**
   ```
   https://epequeno.app
   https://www.epequeno.app
   ```

### Subsequent Deployments

For updates to the frontend:

1. **Build the frontend:**
   ```bash
   cd frontend
   ./build.sh
   ```

2. **Deploy changes:**
   ```bash
   make cdk-deploy STACK=FrontendStack
   ```

   The BucketDeployment construct will:
   - Detect changes in `frontend/dst`
   - Upload only modified files to S3
   - Automatically invalidate CloudFront cache (`/*`)
   - Prune files that no longer exist

**Note:** CloudFront cache invalidations take 1-2 minutes to propagate globally.

## Stack Outputs

After deployment, you'll see:

```
Outputs:
FrontendStack.BucketName = epequeno.app-frontend
FrontendStack.DistributionId = E1XXXXXXXXXX
FrontendStack.DistributionDomainName = d1234567890abc.cloudfront.net
FrontendStack.WebsiteURL = https://epequeno.app
```

## Manual Operations

### Invalidate CloudFront Cache

If you need to force a cache invalidation:

```bash
# Get distribution ID
DIST_ID=$(aws cloudfront list-distributions --profile arch --query 'DistributionList.Items[?Comment==`CDN for epequeno.app`].Id' --output text)

# Create invalidation
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*" \
  --profile arch
```

### View CloudFront Logs

CloudFront access logging is not enabled by default. To enable, update the stack with:

```python
# In frontend_stack.py
distribution = cloudfront.Distribution(
    # ... existing config ...
    enable_logging=True,
    log_bucket=log_bucket,  # Create separate S3 bucket for logs
)
```

### Rollback Deployment

S3 versioning is enabled, so you can rollback:

1. List object versions:
   ```bash
   aws s3api list-object-versions \
     --bucket epequeno.app-frontend \
     --prefix index.html \
     --profile arch
   ```

2. Restore previous version via S3 console or CLI

3. Invalidate CloudFront cache

## Cost Estimate

**Monthly costs (approximate):**
- S3 storage: $0.023/GB (~$0.05 for small frontend)
- CloudFront data transfer: $0.085/GB for first 10 TB
- Route53 hosted zone: $0.50/month (existing)
- ACM certificate: Free

**Expected total: < $5/month** for typical traffic

## Troubleshooting

### Site shows old version after deployment

**Cause:** CloudFront cache not invalidated
**Solution:** Check that BucketDeployment has `distribution_paths=["/*"]` set

### Certificate validation stuck

**Cause:** DNS records not created or propagated
**Solution:** Check Route53 for CNAME validation records. May take up to 30 minutes.

### 403 Forbidden errors

**Cause:** CloudFront OAC not configured properly
**Solution:** Verify S3 bucket policy allows CloudFront access. CDK handles this automatically.

### SPA routing not working (404 on refresh)

**Cause:** CloudFront error responses not configured
**Solution:** Verify `error_responses` are set to return `index.html` for 404/403

### Website URL doesn't work

**Cause:** CloudFront distribution not fully deployed
**Solution:** Wait 15-30 minutes for global propagation. Check distribution status.

## DNS Configuration

The stack automatically creates:

```
epequeno.app.          A    ALIAS → CloudFront distribution
www.epequeno.app.      A    ALIAS → CloudFront distribution
```

Both apex and www subdomain point to the same CloudFront distribution.

## Security

- **S3 Bucket:** Private, no public access
- **CloudFront OAC:** Modern origin access control (replaces legacy OAI)
- **HTTPS Only:** HTTP requests automatically redirect to HTTPS
- **TLS 1.2+:** Enforced by CloudFront default security policy
- **CORS:** Not needed (same-origin policy)

## Performance

**Optimizations:**
- Gzip compression enabled
- Cache-Control headers: `max-age=3600, must-revalidate`
- CloudFront edge caching (PriceClass: US, Canada, Europe)
- Static asset optimization (minified JS)

**Monitoring:**
- CloudFront metrics available in CloudWatch
- Real user monitoring (RUM) can be added if needed

## Updating Configuration

To modify stack configuration:

1. Edit `backend/cdk/frontend_stack.py`
2. Preview changes:
   ```bash
   make cdk-diff STACK=FrontendStack
   ```
3. Deploy changes:
   ```bash
   make cdk-deploy STACK=FrontendStack
   ```

## CI/CD Integration

**Future Enhancement:** Automate deployment on git push

Options:
1. GitHub Actions workflow that runs `./build.sh` and `make cdk-deploy`
2. AWS CodePipeline triggered by CodeCommit
3. Custom webhook that triggers deployment

**Basic GitHub Action example:**
```yaml
name: Deploy Frontend
on:
  push:
    branches: [main]
    paths: ['frontend/**']
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build frontend
        run: cd frontend && ./build.sh
      - name: Deploy to AWS
        run: make cdk-deploy STACK=FrontendStack
        env:
          AWS_PROFILE: arch
```

## Stack Dependencies

**FrontendStack is independent** - can be deployed without other stacks.

However, for the app to work end-to-end, you need:
- CoreInfrastructureStack (Cognito auth)
- ApiV2Stack (backend API)
- MarkerStack (processing jobs)

## Cleanup

To remove the frontend infrastructure:

```bash
# Warning: This will delete the S3 bucket and all content
make cdk-destroy STACK=FrontendStack
```

**Note:** The S3 bucket has `RemovalPolicy.RETAIN`, so it won't be deleted automatically. You must manually empty and delete the bucket if needed.
