"""Unit tests for ApiStack."""

import aws_cdk as cdk
from aws_cdk import assertions

from backend.api_stack import ApiStack


def test_api_stack_synthesizes():
    """Test that the API stack synthesizes without errors."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # If we got here, synthesis succeeded
    assert template is not None


def test_lambda_functions_created():
    """Test that both Lambda functions are created."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify both Lambda functions exist
    template.resource_count_is("AWS::Lambda::Function", 2)

    # Verify submit-job Lambda
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "pdf-models-submit-job",
            "Runtime": "provided.al2023",
            "Handler": "bootstrap",
            "Architectures": ["arm64"],
            "Timeout": 30,
            "MemorySize": 256,
        },
    )

    # Verify get-job Lambda
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "pdf-models-get-job",
            "Runtime": "provided.al2023",
            "Handler": "bootstrap",
            "Architectures": ["arm64"],
            "Timeout": 30,
            "MemorySize": 256,
        },
    )


def test_lambda_environment_variables():
    """Test that Lambda functions have correct environment variables."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify submit-job has DYNAMODB_TABLE_NAME and STATE_MACHINE_ARN
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "pdf-models-submit-job",
            "Environment": {
                "Variables": assertions.Match.object_like(
                    {
                        "DYNAMODB_TABLE_NAME": assertions.Match.any_value(),
                        "STATE_MACHINE_ARN": assertions.Match.any_value(),
                    }
                )
            },
        },
    )

    # Verify get-job has DYNAMODB_TABLE_NAME
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "pdf-models-get-job",
            "Environment": {
                "Variables": assertions.Match.object_like(
                    {
                        "DYNAMODB_TABLE_NAME": assertions.Match.any_value(),
                    }
                )
            },
        },
    )


def test_submit_job_lambda_permissions():
    """Test that submit-job Lambda has correct DynamoDB and Step Functions permissions."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify IAM policy for submit-job
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": assertions.Match.array_with(
                    [
                        {
                            "Effect": "Allow",
                            "Action": "dynamodb:PutItem",
                            "Resource": assertions.Match.any_value(),
                        }
                    ]
                )
            }
        },
    )

    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": assertions.Match.array_with(
                    [
                        {
                            "Effect": "Allow",
                            "Action": "states:StartExecution",
                            "Resource": assertions.Match.any_value(),
                        }
                    ]
                )
            }
        },
    )


def test_get_job_lambda_permissions():
    """Test that get-job Lambda has correct DynamoDB permissions."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify IAM policy for get-job (GetItem and Query)
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": assertions.Match.array_with(
                    [
                        {
                            "Effect": "Allow",
                            "Action": ["dynamodb:GetItem", "dynamodb:Query"],
                            "Resource": assertions.Match.any_value(),
                        }
                    ]
                )
            }
        },
    )


def test_cloudwatch_log_groups():
    """Test that CloudWatch log groups are created for Lambda functions."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify log groups exist
    template.resource_count_is("AWS::Logs::LogGroup", 2)

    # Verify submit-job log group
    template.has_resource_properties(
        "AWS::Logs::LogGroup",
        {
            "LogGroupName": "/aws/lambda/pdf-models-submit-job",
            "RetentionInDays": 7,
        },
    )

    # Verify get-job log group
    template.has_resource_properties(
        "AWS::Logs::LogGroup",
        {
            "LogGroupName": "/aws/lambda/pdf-models-get-job",
            "RetentionInDays": 7,
        },
    )


def test_api_gateway_created():
    """Test that API Gateway REST API is created."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify REST API exists
    template.resource_count_is("AWS::ApiGateway::RestApi", 1)

    # Verify API name
    template.has_resource_properties(
        "AWS::ApiGateway::RestApi",
        {
            "Name": "pdf-models-api",
        },
    )


def test_api_gateway_deployment():
    """Test that API Gateway deployment is created with correct stage."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify deployment exists
    template.resource_count_is("AWS::ApiGateway::Deployment", 1)

    # Verify stage exists with correct name
    template.has_resource_properties(
        "AWS::ApiGateway::Stage",
        {
            "StageName": "v1",
        },
    )


def test_cognito_authorizer():
    """Test that Cognito User Pool Authorizer is created."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify authorizer exists
    template.resource_count_is("AWS::ApiGateway::Authorizer", 1)

    # Verify it's a Cognito User Pool authorizer
    template.has_resource_properties(
        "AWS::ApiGateway::Authorizer",
        {
            "Type": "COGNITO_USER_POOLS",
        },
    )


def test_api_methods():
    """Test that API methods are created with authorization."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify methods exist (POST /jobs, GET /jobs, GET /jobs/{job_id})
    # Each method creates an AWS::ApiGateway::Method resource
    # We should have at least 3 methods (excluding OPTIONS for CORS)
    methods = template.find_resources("AWS::ApiGateway::Method")

    # Count non-OPTIONS methods (actual API methods)
    api_methods = {k: v for k, v in methods.items() if v.get("Properties", {}).get("HttpMethod") != "OPTIONS"}
    assert len(api_methods) >= 3, f"Expected at least 3 API methods, found {len(api_methods)}"

    # Verify that methods have Cognito authorization
    template.has_resource_properties(
        "AWS::ApiGateway::Method",
        {
            "HttpMethod": "POST",
            "AuthorizationType": "COGNITO_USER_POOLS",
        },
    )

    template.has_resource_properties(
        "AWS::ApiGateway::Method",
        {
            "HttpMethod": "GET",
            "AuthorizationType": "COGNITO_USER_POOLS",
        },
    )


def test_ssm_parameters_exported():
    """Test that API endpoint and ID are exported to SSM."""
    app = cdk.App()
    stack = ApiStack(app, "TestApiStack")
    template = assertions.Template.from_stack(stack)

    # Verify SSM parameters are created
    template.resource_count_is("AWS::SSM::Parameter", 2)

    # Verify API endpoint parameter
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": "/pdf-models/api/endpoint",
            "Type": "String",
        },
    )

    # Verify API ID parameter
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": "/pdf-models/api/id",
            "Type": "String",
        },
    )
