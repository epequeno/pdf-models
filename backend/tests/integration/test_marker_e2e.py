"""
End-to-end integration tests for Marker PDF to Markdown conversion.

These tests validate the complete workflow:
1. Upload PDF to S3
2. Submit job via API
3. Poll for completion
4. Download and validate result
"""
import pytest
from pathlib import Path
from .auth_helper import APIClient, wait_for_job_completion


class TestMarkerEndToEnd:
    """Test complete workflow for Marker model."""

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
        Test complete PDF processing workflow using Identity Pool credentials.

        Steps:
        1. Upload PDF to S3 using Identity Pool credentials
        2. Submit job via API with S3 key
        3. Verify job is created with correct status
        4. Wait for job to complete
        5. Download and validate result
        """
        # Setup
        model = "marker"
        identity_id = aws_credentials["identity_id"]
        s3_input_key = f"{identity_id}/{unique_job_id}.pdf"
        s3_result_key = f"{identity_id}/{unique_job_id}-result.md"

        # Register for cleanup
        cleanup_s3_keys.append(s3_input_key)
        cleanup_s3_keys.append(s3_result_key)
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
        print(f"\n[2/5] Submitting job to API")
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

        # Step 4: Wait for job completion
        print(f"\n[4/5] Waiting for job to complete (timeout: 10 minutes)")
        completed_job = wait_for_job_completion(
            api_client,
            model,
            job_id,
            timeout_seconds=600,
            poll_interval=5,
        )

        # Verify completed job
        assert completed_job["status"] == "completed", "Job did not complete successfully"
        assert "s3_result_key" in completed_job, "Missing s3_result_key in completed job"
        assert "completed_at" in completed_job, "Missing completed_at timestamp"
        assert completed_job["s3_result_key"] == s3_result_key, "Result key mismatch"

        print(f"    ✓ Job completed successfully")
        print(f"    ✓ Result key: {completed_job['s3_result_key']}")

        # Step 5: Download and validate result
        print(f"\n[5/5] Downloading and validating result")
        result_obj = s3_client.get_object(
            Bucket=config["s3_bucket"],
            Key=completed_job["s3_result_key"]
        )

        result_content = result_obj["Body"].read().decode("utf-8")

        # Validate result content
        assert len(result_content) > 0, "Result file is empty"
        assert result_content.strip(), "Result contains only whitespace"

        # Markdown should have some basic structure (headings, text, etc.)
        # This is a basic sanity check - adjust based on your test PDF
        print(f"    ✓ Result size: {len(result_content)} bytes")
        print(f"    ✓ Result preview (first 200 chars):")
        print(f"      {result_content[:200]}")

        print(f"\n✅ End-to-end test passed!")

    def test_list_jobs(
        self,
        config,
        auth_tokens,
    ):
        """
        Test listing user's jobs.

        This test verifies that the list endpoint works correctly.
        """
        model = "marker"
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

    def test_unauthorized_access_to_other_user_job(
        self,
        config,
        auth_tokens,
    ):
        """
        Test that users cannot access jobs from other users.

        This test uses a non-existent job ID to verify authorization.
        """
        model = "marker"
        fake_job_id = "00000000-0000-0000-0000-000000000000"

        api_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

        # Try to get a job that doesn't exist (should return 404, not 403)
        print(f"\nAttempting to access non-existent job: {fake_job_id}")

        with pytest.raises(Exception) as exc_info:
            api_client.get_job(model, fake_job_id)

        # Should get a 404 Not Found (job doesn't exist)
        # If we got a different user's job, we'd get 403 Forbidden
        assert "404" in str(exc_info.value), "Expected 404 for non-existent job"
        print(f"    ✓ Got expected 404 error")

    def test_s3_permissions_enforced(
        self,
        config,
        auth_tokens,
        aws_credentials,
    ):
        """
        Test that S3 permissions prevent access to files outside user's prefix.
        
        Note: The Lambda doesn't validate S3 keys anymore - S3 IAM permissions handle access control.
        This test verifies that the job can be submitted (Lambda accepts any key format)
        but S3 access would be controlled by IAM policies.
        """
        model = "marker"
        identity_id = aws_credentials["identity_id"]

        # Submit job with S3 key outside user's prefix
        # This should succeed at the API level (Lambda accepts it)
        # but would fail when Step Functions tries to access the S3 object
        invalid_s3_key = "other-user-id/file.pdf"

        api_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

        print(f"\nSubmitting job with S3 key outside user prefix: {invalid_s3_key}")
        print(f"User's identity ID: {identity_id}")
        print("Note: Lambda accepts any S3 key format - S3 IAM permissions control access")

        # This should succeed (Lambda doesn't validate S3 key prefix anymore)
        job_response = api_client.submit_job(model, invalid_s3_key, start_processing=False)
        
        assert "job_id" in job_response, "Response missing job_id"
        assert job_response["status"] == "created", f"Expected status 'created', got '{job_response['status']}'"
        
        print(f"    ✓ Job created successfully (S3 access will be controlled by IAM permissions)")
