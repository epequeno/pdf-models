"""
End-to-end integration tests for Dolphin PDF processing.

These tests validate the complete workflow:
1. Upload PDF to S3
2. Submit job via API
3. Poll for completion
4. Download and validate both JSON and Markdown results
"""
import json
import pytest
from pathlib import Path
from .auth_helper import APIClient, wait_for_job_completion


class TestDolphinEndToEnd:
    """Test complete workflow for Dolphin model."""

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
        Test complete PDF processing workflow with Dolphin model.

        Steps:
        1. Upload PDF to S3 using Identity Pool credentials
        2. Submit job via API with S3 key
        3. Verify job is created with correct status
        4. Wait for job to complete
        5. Download and validate both JSON and Markdown results
        """
        # Setup
        model = "dolphin"
        identity_id = aws_credentials["identity_id"]
        s3_input_key = f"{identity_id}/{unique_job_id}.pdf"
        s3_json_result_key = f"{identity_id}/{unique_job_id}-result.json"
        s3_md_result_key = f"{identity_id}/{unique_job_id}-result.md"

        # Register for cleanup
        cleanup_s3_keys.append(s3_input_key)
        cleanup_s3_keys.append(s3_json_result_key)
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

        # Step 4: Wait for job completion (Dolphin may take longer due to CPU inference)
        print(f"\n[4/5] Waiting for job to complete (timeout: 30 minutes for CPU inference)")
        completed_job = wait_for_job_completion(
            api_client,
            model,
            job_id,
            timeout_seconds=1800,  # 30 minutes for CPU-based Dolphin
            poll_interval=10,
        )

        # Verify completed job
        assert completed_job["status"] == "completed", "Job did not complete successfully"
        assert "s3_result_key" in completed_job, "Missing s3_result_key in completed job"
        assert "completed_at" in completed_job, "Missing completed_at timestamp"

        print(f"    ✓ Job completed successfully")
        print(f"    ✓ Result key: {completed_job['s3_result_key']}")

        # Check for multi-format results (Dolphin outputs both JSON and Markdown)
        if "s3_result_keys" in completed_job:
            print(f"    ✓ Multi-format results: {completed_job['s3_result_keys']}")

        # Step 5: Download and validate results
        print(f"\n[5/5] Downloading and validating results")

        # Download Markdown result (always available via s3_result_key)
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

        # Try to download JSON result if multi-format keys are available
        if "s3_result_keys" in completed_job and "json" in completed_job["s3_result_keys"]:
            json_key = completed_job["s3_result_keys"]["json"]
            json_result_obj = s3_client.get_object(
                Bucket=config["s3_bucket"],
                Key=json_key
            )
            json_content = json_result_obj["Body"].read().decode("utf-8")

            # Validate JSON content
            assert len(json_content) > 0, "JSON result file is empty"

            # Parse and validate JSON structure
            json_data = json.loads(json_content)
            assert "job_id" in json_data, "JSON missing job_id"
            assert "model" in json_data, "JSON missing model"
            assert json_data["model"] == "dolphin", "JSON model should be 'dolphin'"
            assert "pages" in json_data, "JSON missing pages"
            assert isinstance(json_data["pages"], list), "pages should be a list"

            print(f"    ✓ JSON result size: {len(json_content)} bytes")
            print(f"    ✓ JSON page count: {len(json_data['pages'])}")

        print(f"\n✅ Dolphin end-to-end test passed!")

    def test_submit_with_custom_prompt(
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
        Test PDF processing with a custom prompt.

        Dolphin is a VLM model that supports custom prompts to guide
        how it processes the document.

        Steps:
        1. Upload PDF to S3
        2. Submit job with custom prompt
        3. Wait for job to complete
        4. Validate results contain expected content
        """
        # Setup
        model = "dolphin"
        identity_id = aws_credentials["identity_id"]
        s3_input_key = f"{identity_id}/{unique_job_id}.pdf"
        s3_json_result_key = f"{identity_id}/{unique_job_id}-result.json"
        s3_md_result_key = f"{identity_id}/{unique_job_id}-result.md"

        # Custom prompt for extracting specific content
        custom_prompt = "Extract all text from this document. Focus on identifying any headings, paragraphs, and lists."

        # Register for cleanup
        cleanup_s3_keys.append(s3_input_key)
        cleanup_s3_keys.append(s3_json_result_key)
        cleanup_s3_keys.append(s3_md_result_key)
        cleanup_dynamodb_jobs.append(unique_job_id)

        # Step 1: Upload PDF to S3
        print(f"\n[1/4] Uploading PDF to s3://{config['s3_bucket']}/{s3_input_key}")
        with open(test_pdf_path, "rb") as f:
            s3_client.put_object(
                Bucket=config["s3_bucket"],
                Key=s3_input_key,
                Body=f,
                ContentType="application/pdf",
            )
        print(f"    ✓ PDF uploaded")

        # Step 2: Submit job with custom prompt
        print(f"\n[2/4] Submitting job with custom prompt")
        print(f"    Prompt: {custom_prompt}")
        api_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

        job_response = api_client.submit_job(
            model,
            s3_input_key,
            start_processing=True,
            prompt=custom_prompt,
        )

        assert "job_id" in job_response, "Response missing job_id"
        assert job_response["status"] == "processing", f"Expected status 'processing', got '{job_response['status']}'"

        job_id = job_response["job_id"]
        print(f"    ✓ Job created: {job_id}")

        # Step 3: Wait for job completion
        print(f"\n[3/4] Waiting for job to complete (timeout: 30 minutes)")
        completed_job = wait_for_job_completion(
            api_client,
            model,
            job_id,
            timeout_seconds=1800,
            poll_interval=10,
        )

        assert completed_job["status"] == "completed", "Job did not complete successfully"
        print(f"    ✓ Job completed successfully")

        # Step 4: Download and validate results
        print(f"\n[4/4] Downloading and validating results")

        md_result_obj = s3_client.get_object(
            Bucket=config["s3_bucket"],
            Key=completed_job["s3_result_key"]
        )
        md_content = md_result_obj["Body"].read().decode("utf-8")

        assert len(md_content) > 0, "Markdown result file is empty"
        print(f"    ✓ Markdown result size: {len(md_content)} bytes")
        print(f"    ✓ Result preview (first 200 chars):")
        print(f"      {md_content[:200]}")

        print(f"\n✅ Dolphin custom prompt test passed!")

    def test_list_jobs(
        self,
        config,
        auth_tokens,
    ):
        """
        Test listing user's jobs for Dolphin model.
        """
        model = "dolphin"
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
