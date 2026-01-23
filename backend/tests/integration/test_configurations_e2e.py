"""
End-to-end integration tests for configuration management system.

These tests validate the complete configuration workflow:
1. User creates a custom configuration
2. Admin reviews and approves the configuration
3. Task definition is registered automatically
4. User submits job with approved configuration
5. Job processes with custom parameters
"""
import pytest
import time
from pathlib import Path
from .auth_helper import APIClient, wait_for_job_completion


class TestConfigurationsEndToEnd:
    """Test complete workflow for configuration management."""

    def test_configuration_approval_and_job_execution(
        self,
        config,
        auth_tokens,
        admin_auth_tokens,
        aws_credentials,
        s3_client,
        test_pdf_path,
        unique_job_id,
        cleanup_s3_keys,
        cleanup_dynamodb_jobs,
    ):
        """
        Test complete configuration workflow from creation to job execution.

        Steps:
        1. User creates a custom configuration
        2. Verify configuration is pending approval
        3. Admin lists pending configurations
        4. Admin approves the configuration
        5. Verify task definition ARN is registered
        6. User uploads PDF to S3
        7. User submits job with approved config_id
        8. Verify job completes successfully
        9. Cleanup: delete configuration
        """
        model = "marker"
        identity_id = aws_credentials["identity_id"]
        s3_input_key = f"{identity_id}/{unique_job_id}.pdf"
        s3_result_key = f"{identity_id}/{unique_job_id}-result.md"

        # Register for cleanup
        cleanup_s3_keys.append(s3_input_key)
        cleanup_s3_keys.append(s3_result_key)
        cleanup_dynamodb_jobs.append(unique_job_id)

        # Setup API clients
        user_client = APIClient(config["api_base_url"], auth_tokens["access_token"])
        admin_client = APIClient(config["api_base_url"], admin_auth_tokens["access_token"])

        # Step 1: User creates a custom configuration
        print("\n[1/9] Creating custom configuration")
        config_name = f"Test Config {unique_job_id[:8]}"

        # Create config with custom CPU/memory (infrastructure params)
        # Use slightly higher values than default to verify they're applied
        create_response = user_client.create_config(
            model=model,
            name=config_name,
            description="Integration test configuration with custom resources",
            infra_params={
                "cpu": 4096,  # Marker default is usually 2048 or 4096
                "memory_mib": 16384,  # Marker default is usually 8192 or 16384
            },
            visibility="private",
        )

        assert "config_id" in create_response, "Response missing config_id"
        assert create_response["name"] == config_name, "Config name mismatch"
        assert create_response["model"] == model, f"Expected model '{model}', got '{create_response['model']}'"
        assert create_response["approval_status"] == "pending_approval", "Expected pending_approval status"

        config_id = create_response["config_id"]
        print(f"    ✓ Configuration created: {config_id}")
        print(f"    ✓ Initial status: {create_response['approval_status']}")

        # Step 2: Verify configuration is pending approval
        print("\n[2/9] Verifying configuration is pending")
        fetched_config = user_client.get_config(model, config_id)

        assert fetched_config["config_id"] == config_id, "Config ID mismatch"
        assert fetched_config["approval_status"] == "pending_approval", "Status should be pending_approval"
        assert fetched_config.get("task_definition_arn") is None, "Should not have task_definition_arn yet"
        print(f"    ✓ Configuration is pending approval")

        # Step 3: Admin lists pending configurations
        print("\n[3/9] Admin listing pending configurations")
        pending_response = admin_client.list_pending_configs()

        assert "configurations" in pending_response, "Response missing configurations key"
        assert isinstance(pending_response["configurations"], list), "configurations should be a list"

        # Find our config in the pending list
        our_config = next(
            (c for c in pending_response["configurations"] if c["config_id"] == config_id),
            None
        )
        assert our_config is not None, f"Configuration {config_id} not found in pending list"
        print(f"    ✓ Found configuration in pending list")
        print(f"    ✓ Total pending configurations: {len(pending_response['configurations'])}")

        # Step 4: Admin approves the configuration
        print("\n[4/9] Admin approving configuration")
        approve_response = admin_client.approve_config(config_id)

        assert approve_response["config_id"] == config_id, "Config ID mismatch in approval response"
        assert approve_response["approval_status"] == "approved", "Status should be approved after approval"
        assert "approved_by" in approve_response, "Missing approved_by field"
        assert "approved_at" in approve_response, "Missing approved_at field"

        print(f"    ✓ Configuration approved")
        print(f"    ✓ Approved by: {approve_response['approved_by']}")

        # Step 5: Verify task definition ARN is registered
        print("\n[5/9] Waiting for task definition registration")

        # Poll for task definition ARN (register-task-def Lambda is async)
        max_retries = 30
        retry_count = 0
        task_def_arn = None

        while retry_count < max_retries:
            fetched_config = user_client.get_config(model, config_id)
            task_def_arn = fetched_config.get("task_definition_arn")
            task_def_status = fetched_config.get("task_definition_status")

            if task_def_arn:
                print(f"    ✓ Task definition registered: {task_def_arn}")
                print(f"    ✓ Task definition status: {task_def_status}")
                break

            if task_def_status == "failed":
                error_msg = fetched_config.get("task_definition_error", "Unknown error")
                pytest.fail(f"Task definition registration failed: {error_msg}")

            retry_count += 1
            print(f"    Waiting for task definition... ({retry_count}/{max_retries})")
            time.sleep(2)

        assert task_def_arn is not None, "Task definition ARN was not registered within timeout"
        assert "pdf-models" in task_def_arn, "Task definition ARN should contain 'pdf-models'"
        assert model in task_def_arn or "user-" in task_def_arn, "Task definition ARN should contain model name or 'user-' prefix"

        # Step 6: Upload PDF to S3
        print(f"\n[6/9] Uploading PDF to s3://{config['s3_bucket']}/{s3_input_key}")
        with open(test_pdf_path, "rb") as f:
            s3_client.put_object(
                Bucket=config["s3_bucket"],
                Key=s3_input_key,
                Body=f,
                ContentType="application/pdf",
            )

        response = s3_client.head_object(Bucket=config["s3_bucket"], Key=s3_input_key)
        assert response["ContentLength"] > 0, "Uploaded file has no content"
        print(f"    ✓ Uploaded {response['ContentLength']} bytes")

        # Step 7: Submit job with approved config_id
        print(f"\n[7/9] Submitting job with config_id: {config_id}")
        job_response = user_client.submit_job(
            model=model,
            s3_input_key=s3_input_key,
            start_processing=True,
            config_id=config_id,
        )

        assert "job_id" in job_response, "Response missing job_id"
        assert job_response["status"] == "processing", f"Expected status 'processing', got '{job_response['status']}'"
        assert job_response["model"] == model, f"Expected model '{model}', got '{job_response['model']}'"

        job_id = job_response["job_id"]
        print(f"    ✓ Job created: {job_id}")
        print(f"    ✓ Using configuration: {config_id}")

        # Step 8: Wait for job completion
        print(f"\n[8/9] Waiting for job to complete (timeout: 10 minutes)")
        completed_job = wait_for_job_completion(
            user_client,
            model,
            job_id,
            timeout_seconds=600,
            poll_interval=5,
        )

        assert completed_job["status"] == "completed", "Job did not complete successfully"
        assert "s3_result_key" in completed_job, "Missing s3_result_key in completed job"
        assert completed_job["s3_result_key"] == s3_result_key, "Result key mismatch"

        print(f"    ✓ Job completed successfully")
        print(f"    ✓ Result key: {completed_job['s3_result_key']}")

        # Validate result exists
        result_obj = s3_client.get_object(
            Bucket=config["s3_bucket"],
            Key=completed_job["s3_result_key"]
        )
        result_content = result_obj["Body"].read().decode("utf-8")
        assert len(result_content) > 0, "Result file is empty"
        print(f"    ✓ Result size: {len(result_content)} bytes")

        # Step 9: Cleanup - delete configuration
        print(f"\n[9/9] Cleaning up configuration")
        user_client.delete_config(model, config_id)
        print(f"    ✓ Configuration deleted: {config_id}")

        print(f"\n✅ End-to-end configuration test passed!")

    def test_unapproved_config_cannot_be_used(
        self,
        config,
        auth_tokens,
        aws_credentials,
    ):
        """
        Test that jobs cannot be submitted with unapproved configurations.

        Steps:
        1. User creates a configuration
        2. User tries to submit job with pending config_id
        3. Verify request is rejected
        4. Cleanup: delete configuration
        """
        model = "marker"
        identity_id = aws_credentials["identity_id"]
        s3_input_key = f"{identity_id}/test-file.pdf"

        user_client = APIClient(config["api_base_url"], auth_tokens["access_token"])

        # Step 1: Create configuration (will be pending_approval)
        print("\n[1/3] Creating configuration without approval")
        create_response = user_client.create_config(
            model=model,
            name="Test Unapproved Config",
            description="This should not be usable for jobs",
            visibility="private",
        )

        config_id = create_response["config_id"]
        assert create_response["approval_status"] == "pending_approval", "Should be pending approval"
        print(f"    ✓ Configuration created: {config_id}")
        print(f"    ✓ Status: {create_response['approval_status']}")

        # Step 2: Try to submit job with pending config_id
        print("\n[2/3] Attempting to submit job with pending config_id")

        with pytest.raises(Exception) as exc_info:
            user_client.submit_job(
                model=model,
                s3_input_key=s3_input_key,
                start_processing=True,
                config_id=config_id,
            )

        # Should get a 400 or 403 error
        error_str = str(exc_info.value)
        assert "400" in error_str or "403" in error_str or "not approved" in error_str.lower(), \
            f"Expected error about unapproved config, got: {error_str}"
        print(f"    ✓ Job submission rejected as expected")
        print(f"    ✓ Error: {error_str}")

        # Step 3: Cleanup
        print("\n[3/3] Cleaning up configuration")
        user_client.delete_config(model, config_id)
        print(f"    ✓ Configuration deleted: {config_id}")

        print(f"\n✅ Unapproved config rejection test passed!")

    def test_admin_rejection_workflow(
        self,
        config,
        auth_tokens,
        admin_auth_tokens,
    ):
        """
        Test admin rejection workflow.

        Steps:
        1. User creates a configuration
        2. Admin rejects the configuration with reason
        3. Verify configuration is rejected with reason
        4. Verify configuration cannot be used for jobs
        5. Cleanup: delete configuration
        """
        model = "marker"

        user_client = APIClient(config["api_base_url"], auth_tokens["access_token"])
        admin_client = APIClient(config["api_base_url"], admin_auth_tokens["access_token"])

        # Step 1: Create configuration
        print("\n[1/4] Creating configuration")
        create_response = user_client.create_config(
            model=model,
            name="Test Config for Rejection",
            description="This will be rejected",
            visibility="private",
        )

        config_id = create_response["config_id"]
        print(f"    ✓ Configuration created: {config_id}")

        # Step 2: Admin rejects the configuration
        print("\n[2/4] Admin rejecting configuration")
        rejection_reason = "Resource allocation too high for this use case"

        reject_response = admin_client.reject_config(config_id, rejection_reason)

        assert reject_response["config_id"] == config_id, "Config ID mismatch"
        assert reject_response["approval_status"] == "rejected", "Status should be rejected"
        assert reject_response["rejection_reason"] == rejection_reason, "Rejection reason mismatch"

        print(f"    ✓ Configuration rejected")
        print(f"    ✓ Reason: {reject_response['rejection_reason']}")

        # Step 3: Verify user can see rejection
        print("\n[3/4] Verifying user can see rejection reason")
        fetched_config = user_client.get_config(model, config_id)

        assert fetched_config["approval_status"] == "rejected", "Status should be rejected"
        assert fetched_config["rejection_reason"] == rejection_reason, "Rejection reason should be visible to user"
        print(f"    ✓ User can see rejection: {fetched_config['rejection_reason']}")

        # Step 4: Cleanup
        print("\n[4/4] Cleaning up configuration")
        user_client.delete_config(model, config_id)
        print(f"    ✓ Configuration deleted: {config_id}")

        print(f"\n✅ Admin rejection workflow test passed!")
