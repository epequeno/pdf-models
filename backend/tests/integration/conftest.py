"""
Pytest configuration and fixtures for integration tests.

These fixtures provide authentication, AWS clients, and cleanup for integration tests.
"""
import os
import uuid
import pytest
import boto3
from pathlib import Path
from typing import Dict, Optional


# Test configuration - can be overridden with environment variables
TEST_CONFIG = {
    "region": os.getenv("AWS_REGION", "us-east-1"),
    "user_pool_id": os.getenv("COGNITO_USER_POOL_ID", "us-east-1_wslqPOxQd"),
    "client_id": os.getenv("COGNITO_CLIENT_ID", "4tmf8s58738hrbrp4ff2utqg5"),
    "identity_pool_id": os.getenv("COGNITO_IDENTITY_POOL_ID", "us-east-1:ea186bba-83ba-467a-be54-550f7fed870a"),
    "api_base_url": os.getenv("API_BASE_URL", "https://gh0j9u3bx5.execute-api.us-east-1.amazonaws.com/v1"),
    "s3_bucket": os.getenv("S3_BUCKET", "pdf-models-docs-496830984285"),
    "dynamodb_table": os.getenv("DYNAMODB_TABLE", "pdf-models-jobs"),
    "test_email": os.getenv("TEST_USER_EMAIL"),
    "test_password": os.getenv("TEST_USER_PASSWORD"),
}


@pytest.fixture(scope="session")
def config():
    """Provide test configuration."""
    # Validate required configuration
    if not TEST_CONFIG["test_email"]:
        pytest.skip("TEST_USER_EMAIL environment variable not set")
    if not TEST_CONFIG["test_password"]:
        pytest.skip("TEST_USER_PASSWORD environment variable not set")

    return TEST_CONFIG


@pytest.fixture(scope="session")
def cognito_client(config):
    """Provide Cognito Identity Provider client."""
    return boto3.client("cognito-idp", region_name=config["region"])


@pytest.fixture(scope="session")
def cognito_identity_client(config):
    """Provide Cognito Identity client."""
    return boto3.client("cognito-identity", region_name=config["region"])


@pytest.fixture(scope="session")
def auth_tokens(config, cognito_client):
    """
    Authenticate with Cognito and return tokens.

    This fixture authenticates once per test session and returns:
    - access_token: For API Gateway authorization
    - id_token: For Identity Pool authentication
    - refresh_token: For token renewal
    """
    try:
        response = cognito_client.initiate_auth(
            ClientId=config["client_id"],
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": config["test_email"],
                "PASSWORD": config["test_password"],
            },
        )

        tokens = response["AuthenticationResult"]
        return {
            "access_token": tokens["AccessToken"],
            "id_token": tokens["IdToken"],
            "refresh_token": tokens["RefreshToken"],
        }
    except cognito_client.exceptions.NotAuthorizedException:
        pytest.fail(f"Authentication failed for user {config['test_email']}. Check credentials.")
    except cognito_client.exceptions.UserNotFoundException:
        pytest.fail(f"User {config['test_email']} not found. Run setup script to create test user.")
    except Exception as e:
        pytest.fail(f"Unexpected error during authentication: {e}")


@pytest.fixture(scope="session")
def aws_credentials(config, cognito_identity_client, auth_tokens):
    """
    Get temporary AWS credentials from Identity Pool.

    Returns credentials for direct S3 access.
    """
    # Get Identity ID
    identity_response = cognito_identity_client.get_id(
        IdentityPoolId=config["identity_pool_id"],
        Logins={
            f'cognito-idp.{config["region"]}.amazonaws.com/{config["user_pool_id"]}': auth_tokens["id_token"]
        },
    )
    identity_id = identity_response["IdentityId"]

    # Get credentials
    credentials_response = cognito_identity_client.get_credentials_for_identity(
        IdentityId=identity_id,
        Logins={
            f'cognito-idp.{config["region"]}.amazonaws.com/{config["user_pool_id"]}': auth_tokens["id_token"]
        },
    )

    creds = credentials_response["Credentials"]
    return {
        "identity_id": identity_id,
        "access_key_id": creds["AccessKeyId"],
        "secret_access_key": creds["SecretKey"],
        "session_token": creds["SessionToken"],
    }


@pytest.fixture
def s3_client(config, aws_credentials):
    """Provide S3 client with temporary credentials."""
    return boto3.client(
        "s3",
        region_name=config["region"],
        aws_access_key_id=aws_credentials["access_key_id"],
        aws_secret_access_key=aws_credentials["secret_access_key"],
        aws_session_token=aws_credentials["session_token"],
    )


@pytest.fixture
def dynamodb_client(config):
    """Provide DynamoDB client (uses default AWS profile credentials)."""
    return boto3.client("dynamodb", region_name=config["region"])


@pytest.fixture
def stepfunctions_client(config):
    """Provide Step Functions client (uses default AWS profile credentials)."""
    return boto3.client("stepfunctions", region_name=config["region"])


@pytest.fixture
def test_pdf_path():
    """Return path to test PDF file."""
    fixtures_dir = Path(__file__).parent / "fixtures"
    pdf_path = fixtures_dir / "test.pdf"

    if not pdf_path.exists():
        pytest.fail(f"Test PDF not found at {pdf_path}")

    return pdf_path


@pytest.fixture
def unique_job_id():
    """Generate a unique job ID for each test."""
    return str(uuid.uuid4())


@pytest.fixture
def cleanup_s3_keys(config, s3_client, aws_credentials):
    """
    Track and cleanup S3 keys created during tests.

    Usage in tests:
        cleanup_s3_keys.append("path/to/file.pdf")
    """
    keys_to_cleanup = []

    yield keys_to_cleanup

    # Cleanup after test
    for key in keys_to_cleanup:
        try:
            s3_client.delete_object(Bucket=config["s3_bucket"], Key=key)
            print(f"Cleaned up S3 key: {key}")
        except Exception as e:
            print(f"Warning: Failed to cleanup S3 key {key}: {e}")


@pytest.fixture
def cleanup_dynamodb_jobs(config, dynamodb_client):
    """
    Track and cleanup DynamoDB jobs created during tests.

    Usage in tests:
        cleanup_dynamodb_jobs.append("job-id-uuid")
    """
    job_ids_to_cleanup = []

    yield job_ids_to_cleanup

    # Cleanup after test
    for job_id in job_ids_to_cleanup:
        try:
            dynamodb_client.delete_item(
                TableName=config["dynamodb_table"],
                Key={"job_id": {"S": job_id}}
            )
            print(f"Cleaned up DynamoDB job: {job_id}")
        except Exception as e:
            print(f"Warning: Failed to cleanup DynamoDB job {job_id}: {e}")
