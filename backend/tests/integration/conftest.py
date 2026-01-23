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


def _get_ssm_parameter(parameter_name: str, region: str = "us-east-1") -> Optional[str]:
    """
    Fetch a parameter from SSM Parameter Store.

    Returns None if the parameter doesn't exist or if there's an error.
    """
    try:
        # Use AWS_PROFILE environment variable if set (for local integration tests)
        profile_name = os.getenv("AWS_PROFILE")
        if profile_name:
            session = boto3.Session(profile_name=profile_name)
            ssm = session.client("ssm", region_name=region)
        else:
            ssm = boto3.client("ssm", region_name=region)

        response = ssm.get_parameter(Name=parameter_name)
        return response["Parameter"]["Value"]
    except Exception as e:
        print(f"Warning: Could not fetch SSM parameter {parameter_name}: {e}")
        return None


def _load_config() -> Dict[str, Optional[str]]:
    """
    Load test configuration from environment variables or SSM Parameter Store.

    Priority:
    1. Environment variables (if explicitly set)
    2. SSM Parameter Store (deployed infrastructure values)
    3. None (will cause test to fail with clear error message)
    """
    region = os.getenv("AWS_REGION", "us-east-1")

    # Fetch from SSM if not provided via environment
    api_base_url = os.getenv("API_BASE_URL") or _get_ssm_parameter("/pdf-models/api-v2/endpoint", region)

    # API v2 endpoint needs /v1 appended (routes are defined with /v1 prefix)
    if api_base_url and not api_base_url.endswith("/v1"):
        api_base_url = f"{api_base_url.rstrip('/')}/v1"

    config = {
        "region": region,
        "user_pool_id": os.getenv("COGNITO_USER_POOL_ID") or _get_ssm_parameter("/pdf-models/core/cognito-user-pool-id", region),
        "client_id": os.getenv("COGNITO_CLIENT_ID") or _get_ssm_parameter("/pdf-models/core/cognito-user-pool-client-id", region),
        "identity_pool_id": os.getenv("COGNITO_IDENTITY_POOL_ID") or _get_ssm_parameter("/pdf-models/core/cognito-identity-pool-id", region),
        "api_base_url": api_base_url,
        "s3_bucket": os.getenv("S3_BUCKET") or _get_ssm_parameter("/pdf-models/core/s3-bucket-name", region),
        "dynamodb_table": os.getenv("DYNAMODB_TABLE") or _get_ssm_parameter("/pdf-models/core/dynamodb-table-name", region),
        "test_email": os.getenv("TEST_USER_EMAIL"),
        "test_password": os.getenv("TEST_USER_PASSWORD"),
        "admin_email": os.getenv("ADMIN_USER_EMAIL"),
        "admin_password": os.getenv("ADMIN_USER_PASSWORD"),
    }

    return config


# Test configuration - loaded once when module is imported
TEST_CONFIG = _load_config()


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
def admin_auth_tokens(config, cognito_client):
    """
    Authenticate admin user with Cognito and return tokens.

    This fixture requires ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD environment variables.
    The admin user must be in the 'pdf-models-admins' Cognito group.

    Returns the same structure as auth_tokens but for an admin user.
    """
    if not config.get("admin_email") or not config.get("admin_password"):
        pytest.skip("ADMIN_USER_EMAIL and ADMIN_USER_PASSWORD environment variables not set")

    try:
        response = cognito_client.initiate_auth(
            ClientId=config["client_id"],
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": config["admin_email"],
                "PASSWORD": config["admin_password"],
            },
        )

        tokens = response["AuthenticationResult"]
        return {
            "access_token": tokens["AccessToken"],
            "id_token": tokens["IdToken"],
            "refresh_token": tokens["RefreshToken"],
        }
    except cognito_client.exceptions.NotAuthorizedException:
        pytest.fail(f"Admin authentication failed for user {config['admin_email']}. Check credentials.")
    except cognito_client.exceptions.UserNotFoundException:
        pytest.fail(f"Admin user {config['admin_email']} not found. Create admin user and add to pdf-models-admins group.")
    except Exception as e:
        pytest.fail(f"Unexpected error during admin authentication: {e}")


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
