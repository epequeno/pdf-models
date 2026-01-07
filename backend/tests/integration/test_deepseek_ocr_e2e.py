"""
End-to-end integration tests for DeepSeek-OCR PDF processing.

These tests validate the complete workflow:
1. Upload PDF to S3
2. Submit job via API
3. Poll for completion
4. Download and validate Markdown results
"""
import pytest
from pathlib import Path
from .auth_helper import APIClient, wait_for_job_completion


class TestDeepSeekOcrEndToEnd:
    """Test complete workflow for DeepSeek-OCR model."""

    def test_submit_and_process_pdf(
        self,
        config,
        auth_tokens,
        aws_credentials,
        s3_client,
        test_pdf_path,
        unique_job_id,
        cleanup_s3_keys,
        cleanup_dynamodb_jobs,
    ):
        """
        Test complete PDF processing workflow with DeepSeek-OCR model.

        Steps:
        1. Upload PDF to S3 using Identity Pool credentials
        2. Submit job via API with S3 key
        3. Verify job is created with correct status
        4. Wait for job to complete
        5. Download and validate Markdown results
        """
        # Setup
        model = "deepseek-ocr"
        identity_id = aws_credentials["identity_id"]
        s3_input_key = f"{identity_id}/{unique_job_id}.pdf"
        s3_md_result_key = f"{identity_id}/{unique_job_id}-result.md"

        # Register for cleanup
        cleanup_s3_keys.append(s3_input_key)
        cleanup_s3_keys.append(s3_md_result_key)
        cleanup_dynamodb_jobs.append(unique_job_id)

        # Step 1: Upload PDF to S3 using Identity Pool credentials
        print(f"\n[1/5] Uploading PDF to s3://{config['s3_bucket']}/{s3_input_key}")
        with open(test_pdf_path, "rb") as f:
            s3_client.put_object(
                Bucket=config["s3_bucket"],
                Key=s3_input_key,
                Body=f,
                ContentType="application/pdf",
            )

        # Verify upload
        response = s3_client.head_object(Bucket=config["s3_bucket"], Key=s3_input_key)
        assert response["ContentLength"] > 0, "Uploaded file has no content"
        print(f"    ✓ Uploaded {response['ContentLength']} bytes")

        # Step 2: Submit job via API with existing S3 key
        print(f"\n[2/5] Submitting job to API (model: {model})")
        api_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

        job_response = api_client.submit_job(model, s3_input_key)

        # Verify job creation response
        assert "job_id" in job_response, "Response missing job_id"
        assert "status" in job_response, "Response missing status"
        assert job_response["status"] == "processing", f"Expected status 'processing', got '{job_response['status']}'"
        assert job_response["model"] == model, f"Expected model '{model}', got '{job_response['model']}'"
        assert job_response["s3_input_key"] == s3_input_key, "S3 input key mismatch"

        job_id = job_response["job_id"]
        print(f"    ✓ Job created: {job_id}")
        print(f"    ✓ Initial status: {job_response['status']}")

        # Step 3: Verify job can be retrieved
        print(f"\n[3/5] Verifying job can be retrieved")
        job_details = api_client.get_job(model, job_id)

        assert job_details["job_id"] == job_id, "Job ID mismatch"
        assert job_details["status"] in ["processing", "completed"], (
            f"Unexpected status: {job_details['status']}"
        )
        assert "created_at" in job_details, "Missing created_at timestamp"
        print(f"    ✓ Job retrieved successfully")
        print(f"    ✓ Current status: {job_details['status']}")

        # Step 4: Wait for job completion (GPU model, may take time for cold start)
        print(f"\n[4/5] Waiting for job to complete (timeout: 15 minutes)")
        completed_job = wait_for_job_completion(
            api_client,
            model,
            job_id,
            timeout_seconds=900,  # 15 minutes - GPU cold start can be slow
            poll_interval=15,
        )

        # Verify completed job
        assert completed_job["status"] == "completed", "Job did not complete successfully"
        assert "s3_result_key" in completed_job, "Missing s3_result_key in completed job"
        assert "completed_at" in completed_job, "Missing completed_at timestamp"

        print(f"    ✓ Job completed successfully")
        print(f"    ✓ Result key: {completed_job['s3_result_key']}")

        # Step 5: Download and validate results
        print(f"\n[5/5] Downloading and validating results")

        # Download Markdown result
        md_result_obj = s3_client.get_object(
            Bucket=config["s3_bucket"],
            Key=completed_job["s3_result_key"]
        )
        md_content = md_result_obj["Body"].read().decode("utf-8")

        # Validate Markdown content
        assert len(md_content) > 0, "Markdown result file is empty"
        assert md_content.strip(), "Markdown result contains only whitespace"

        print(f"    ✓ Markdown result size: {len(md_content)} bytes")
        print(f"    ✓ Markdown preview (first 200 chars):")
        print(f"      {md_content[:200]}")

        print(f"\n✅ DeepSeek-OCR end-to-end test passed!")

    def test_list_jobs(
        self,
        config,
        auth_tokens,
    ):
        """
        Test listing user's jobs for DeepSeek-OCR model.
        """
        model = "deepseek-ocr"
        api_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

        # List jobs
        print(f"\nListing jobs for model '{model}'")
        response = api_client.list_jobs(model)

        # Verify response structure
        assert "jobs" in response, "Response missing 'jobs' key"
        assert isinstance(response["jobs"], list), "'jobs' should be a list"

        print(f"    ✓ Found {len(response['jobs'])} jobs")

        # If there are jobs, verify structure
        if response["jobs"]:
            job = response["jobs"][0]
            assert "job_id" in job, "Job missing job_id"
            assert "status" in job, "Job missing status"
            assert "model" in job, "Job missing model"
            assert "created_at" in job, "Job missing created_at"
            print(f"    ✓ Job structure validated")
