#!/usr/bin/env python3
"""
Setup script for creating a Cognito test user for integration tests.

This script creates a test user in the Cognito User Pool and sets up
the necessary credentials for running integration tests.

Usage:
    python setup_test_user.py

Or via Makefile:
    make test-integration-setup
"""
import os
import sys
import boto3
import getpass
from pathlib import Path


# Configuration - should match conftest.py
REGION = "us-east-1"
USER_POOL_ID = "us-east-1_wslqPOxQd"
CLIENT_ID = "4tmf8s58738hrbrp4ff2utqg5"


def create_test_user(email: str, password: str, cognito_client):
    """
    Create a test user in Cognito User Pool.

    Args:
        email: Email address for the test user
        password: Password for the test user
        cognito_client: Boto3 Cognito IDP client

    Returns:
        True if user was created, False if user already exists
    """
    try:
        # Create user (admin-created users are auto-confirmed)
        cognito_client.admin_create_user(
            UserPoolId=USER_POOL_ID,
            Username=email,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"},
            ],
            MessageAction="SUPPRESS",  # Don't send welcome email
            TemporaryPassword=password,
        )
        print(f"✓ Created user: {email}")

        # Set permanent password
        cognito_client.admin_set_user_password(
            UserPoolId=USER_POOL_ID,
            Username=email,
            Password=password,
            Permanent=True,
        )
        print(f"✓ Set permanent password")

        return True

    except cognito_client.exceptions.UsernameExistsException:
        print(f"ℹ User {email} already exists")

        # Try to update password in case it changed
        try:
            cognito_client.admin_set_user_password(
                UserPoolId=USER_POOL_ID,
                Username=email,
                Password=password,
                Permanent=True,
            )
            print(f"✓ Updated password for existing user")
        except Exception as e:
            print(f"⚠ Could not update password: {e}")

        return False

    except Exception as e:
        print(f"✗ Error creating user: {e}")
        raise


def verify_authentication(email: str, password: str, cognito_client):
    """
    Verify that the user can authenticate successfully.

    Args:
        email: Email address
        password: Password
        cognito_client: Boto3 Cognito IDP client

    Returns:
        True if authentication succeeds
    """
    try:
        response = cognito_client.initiate_auth(
            ClientId=CLIENT_ID,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": email,
                "PASSWORD": password,
            },
        )

        # Check if we got tokens
        if "AuthenticationResult" in response:
            print(f"✓ Authentication successful")
            print(f"  Access token expires in: {response['AuthenticationResult']['ExpiresIn']} seconds")
            return True
        else:
            print(f"⚠ Authentication returned unexpected response: {response}")
            return False

    except cognito_client.exceptions.NotAuthorizedException:
        print(f"✗ Authentication failed - incorrect password")
        return False
    except Exception as e:
        print(f"✗ Authentication error: {e}")
        return False


def save_env_template(email: str):
    """
    Save a .env.test template file with the test user credentials.

    Args:
        email: Email address to include in template
    """
    env_file = Path(__file__).parent / ".env.test"

    content = f"""# Integration Test Configuration
# Source this file before running tests: source backend/tests/integration/.env.test

# Test user credentials
export TEST_USER_EMAIL="{email}"
export TEST_USER_PASSWORD="YOUR_PASSWORD_HERE"

# AWS Configuration (usually auto-detected)
export AWS_REGION="us-east-1"
export COGNITO_USER_POOL_ID="us-east-1_0Puc2vOAn"
export COGNITO_CLIENT_ID="3a9qpq5sb48plnt6eg52t26ula"
export COGNITO_IDENTITY_POOL_ID="us-east-1:725ee04f-7250-4862-9158-de9fa49ef895"
export API_BASE_URL="https://ivd1t6g04g.execute-api.us-east-1.amazonaws.com/v1"
export S3_BUCKET="pdf-models-docs-496830984285"
export DYNAMODB_TABLE="pdf-models-jobs"
"""

    env_file.write_text(content)
    print(f"\n✓ Created template file: {env_file}")
    print(f"  Edit this file and update TEST_USER_PASSWORD, then source it:")
    print(f"  $ source {env_file}")


def main():
    """Main setup script."""
    print("=" * 70)
    print("Cognito Test User Setup")
    print("=" * 70)
    print()
    print(f"User Pool ID: {USER_POOL_ID}")
    print(f"Region: {REGION}")
    print()

    # Check for command-line arguments for automation
    if len(sys.argv) == 3:
        # Automated mode: python setup_test_user.py <email> <password>
        email = sys.argv[1].strip()
        password = sys.argv[2].strip()
        print(f"Using provided credentials for: {email}")
    else:
        # Interactive mode
        # Get credentials from user
        email = input("Enter test user email: ").strip()
        if not email or "@" not in email:
            print("✗ Invalid email address")
            sys.exit(1)

        # Get password (with confirmation)
        while True:
            password = getpass.getpass("Enter test user password: ").strip()
            if len(password) < 8:
                print("✗ Password must be at least 8 characters")
                continue

            password_confirm = getpass.getpass("Confirm password: ").strip()
            if password != password_confirm:
                print("✗ Passwords do not match")
                continue

            break

    # Validate inputs
    if not email or "@" not in email:
        print("✗ Invalid email address")
        sys.exit(1)
    
    if len(password) < 8:
        print("✗ Password must be at least 8 characters")
        sys.exit(1)

    print()
    print("Creating user...")

    # Create Cognito client
    try:
        cognito_client = boto3.client("cognito-idp", region_name=REGION)
    except Exception as e:
        print(f"✗ Failed to create AWS client: {e}")
        print(f"  Make sure AWS credentials are configured (AWS_PROFILE=arch)")
        sys.exit(1)

    # Create user
    try:
        create_test_user(email, password, cognito_client)
    except Exception as e:
        print(f"\n✗ Failed to create user: {e}")
        sys.exit(1)

    # Verify authentication
    print("\nVerifying authentication...")
    if not verify_authentication(email, password, cognito_client):
        print("\n✗ Setup failed - authentication verification failed")
        sys.exit(1)

    # Save environment template
    save_env_template(email)

    # Success message
    print("\n" + "=" * 70)
    print("✅ Setup Complete!")
    print("=" * 70)
    print("\nTo run integration tests:")
    print(f"  1. Set environment variables:")
    print(f"     export TEST_USER_EMAIL=\"{email}\"")
    print(f"     export TEST_USER_PASSWORD=\"your-password\"")
    print()
    print(f"  2. Run tests:")
    print(f"     make test-integration")
    print()
    print(f"Alternatively, edit and source the .env.test file:")
    print(f"  source backend/tests/integration/.env.test")
    print(f"  make test-integration")
    print()


if __name__ == "__main__":
    main()
