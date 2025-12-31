"""Unit tests for CoreInfrastructureStack."""

import aws_cdk as cdk
from aws_cdk.assertions import Template, Match

from backend.core_infrastructure_stack import CoreInfrastructureStack
from backend.stack_config import CONFIG


def test_core_infrastructure_synthesizes():
    """Test that CoreInfrastructureStack synthesizes without errors."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Assert all major resources exist
    template.resource_count_is("AWS::S3::Bucket", 1)
    template.resource_count_is("AWS::DynamoDB::Table", 1)
    template.resource_count_is("AWS::Cognito::UserPool", 1)
    template.resource_count_is("AWS::Cognito::IdentityPool", 1)

    # Assert SSM parameters (5 total for core infrastructure)
    template.resource_count_is("AWS::SSM::Parameter", 5)


def test_s3_bucket_configuration():
    """Test S3 bucket has lifecycle, CORS, and encryption."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Verify S3 bucket has lifecycle rule
    template.has_resource_properties(
        "AWS::S3::Bucket",
        {
            "LifecycleConfiguration": {
                "Rules": Match.array_with([
                    Match.object_like({
                        "ExpirationInDays": CONFIG.S3_EXPIRATION_DAYS,
                        "Status": "Enabled",
                    }),
                ]),
            },
            # CORS configuration exists
            "CorsConfiguration": Match.object_like({
                "CorsRules": Match.array_with([
                    Match.object_like({
                        "AllowedMethods": Match.array_with(["GET", "PUT"]),
                    }),
                ]),
            }),
            # Public access blocked
            "PublicAccessBlockConfiguration": {
                "BlockPublicAcls": True,
                "BlockPublicPolicy": True,
                "IgnorePublicAcls": True,
                "RestrictPublicBuckets": True,
            },
        },
    )


def test_dynamodb_table_schema():
    """Test DynamoDB table has correct keys and GSI."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Verify DynamoDB table properties
    template.has_resource_properties(
        "AWS::DynamoDB::Table",
        {
            "TableName": CONFIG.DYNAMODB_TABLE_NAME,
            "BillingMode": "PAY_PER_REQUEST",
            # Primary key
            "KeySchema": [
                {
                    "AttributeName": CONFIG.DYNAMODB_PK,
                    "KeyType": "HASH",
                },
            ],
            # GSI for querying user's jobs
            "GlobalSecondaryIndexes": Match.array_with([
                Match.object_like({
                    "IndexName": CONFIG.DYNAMODB_GSI_NAME,
                    "KeySchema": [
                        {"AttributeName": CONFIG.DYNAMODB_GSI_PK, "KeyType": "HASH"},
                        {"AttributeName": CONFIG.DYNAMODB_GSI_SK, "KeyType": "RANGE"},
                    ],
                }),
            ]),
        },
    )


def test_cognito_user_pool_configuration():
    """Test Cognito User Pool has correct settings."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Verify User Pool properties
    template.has_resource_properties(
        "AWS::Cognito::UserPool",
        {
            "UserPoolName": CONFIG.COGNITO_USER_POOL_NAME,
            # Self-signup disabled
            "AdminCreateUserConfig": {
                "AllowAdminCreateUserOnly": True,
            },
            # Email as username
            "UsernameAttributes": ["email"],
            # Auto-verify email
            "AutoVerifiedAttributes": ["email"],
            # Password policy
            "Policies": {
                "PasswordPolicy": {
                    "MinimumLength": 8,
                    "RequireLowercase": True,
                    "RequireUppercase": True,
                    "RequireNumbers": True,
                    "RequireSymbols": False,
                },
            },
            # MFA off
            "MfaConfiguration": "OFF",
        },
    )


def test_cognito_user_pool_client():
    """Test Cognito User Pool Client configuration."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Verify User Pool Client exists and has correct settings
    template.has_resource_properties(
        "AWS::Cognito::UserPoolClient",
        {
            # No client secret (public client)
            "GenerateSecret": False,
            # Explicit auth flows enabled
            "ExplicitAuthFlows": Match.array_with([
                "ALLOW_USER_PASSWORD_AUTH",
                "ALLOW_USER_SRP_AUTH",
                "ALLOW_REFRESH_TOKEN_AUTH",
            ]),
        },
    )


def test_cognito_identity_pool_configuration():
    """Test Cognito Identity Pool is configured correctly."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Verify Identity Pool properties
    template.has_resource_properties(
        "AWS::Cognito::IdentityPool",
        {
            "IdentityPoolName": CONFIG.COGNITO_IDENTITY_POOL_NAME,
            # No unauthenticated access
            "AllowUnauthenticatedIdentities": False,
            # Linked to User Pool
            "CognitoIdentityProviders": Match.array_with([
                Match.object_like({
                    "ClientId": Match.any_value(),
                    "ProviderName": Match.any_value(),
                }),
            ]),
        },
    )


def test_cognito_identity_pool_scoped_s3_access():
    """Test authenticated IAM role has scoped S3 permissions."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Find IAM policy with S3 permissions scoped to Cognito identity
    # This is CRITICAL security: users can only access their own prefix
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": Match.array_with([
                    Match.object_like({
                        "Action": Match.array_with(["s3:PutObject", "s3:GetObject"]),
                        "Effect": "Allow",
                        # Resource is a Fn::Join that includes the Cognito identity variable
                        # Check that the Fn::Join array contains the cognito variable string
                        "Resource": Match.object_like({
                            "Fn::Join": Match.array_with([
                                Match.array_with([
                                    Match.string_like_regexp(r".*cognito-identity\.amazonaws\.com:sub.*"),
                                ]),
                            ]),
                        }),
                    }),
                ]),
            },
        },
    )


def test_cognito_identity_pool_list_bucket_permission():
    """Test authenticated role can list objects in their own prefix."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Verify ListBucket permission with prefix condition
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": Match.array_with([
                    Match.object_like({
                        "Action": "s3:ListBucket",
                        "Effect": "Allow",
                        # Condition scopes listing to user's prefix
                        "Condition": Match.object_like({
                            "StringLike": Match.object_like({
                                "s3:prefix": Match.array_with([
                                    Match.string_like_regexp(r".*cognito-identity.*")
                                ]),
                            }),
                        }),
                    }),
                ]),
            },
        },
    )


def test_ssm_parameters_exported():
    """Test all SSM parameters are exported."""
    app = cdk.App()
    stack = CoreInfrastructureStack(app, "TestCoreStack")
    template = Template.from_stack(stack)

    # Expected SSM parameters
    expected_params = [
        CONFIG.SSM_S3_BUCKET_NAME,
        CONFIG.SSM_DYNAMODB_TABLE_NAME,
        CONFIG.SSM_COGNITO_USER_POOL_ID,
        CONFIG.SSM_COGNITO_IDENTITY_POOL_ID,
        CONFIG.SSM_COGNITO_USER_POOL_CLIENT_ID,
    ]

    # Verify each parameter exists
    for param_name in expected_params:
        template.has_resource_properties(
            "AWS::SSM::Parameter",
            {
                "Name": param_name,
                "Type": "String",
            },
        )
