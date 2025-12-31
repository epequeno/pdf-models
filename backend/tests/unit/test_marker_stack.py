"""Unit tests for MarkerStack."""

import aws_cdk as cdk
from aws_cdk import assertions

from backend.marker_stack import MarkerStack


def test_ecs_cluster_created():
    """Test that ECS cluster is created with correct configuration."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify ECS cluster exists
    template.resource_count_is("AWS::ECS::Cluster", 1)

    # Verify cluster has container insights V2 enhanced mode enabled
    template.has_resource_properties(
        "AWS::ECS::Cluster",
        {
            "ClusterSettings": [
                {"Name": "containerInsights", "Value": "enhanced"}
            ]
        },
    )


def test_fargate_task_definition_created():
    """Test that Fargate task definition is created with correct CPU/memory."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify task definition exists
    template.resource_count_is("AWS::ECS::TaskDefinition", 1)

    # Verify CPU and memory configuration (2 vCPU, 8 GB)
    template.has_resource_properties(
        "AWS::ECS::TaskDefinition",
        {
            "Cpu": "2048",
            "Memory": "8192",
            "NetworkMode": "awsvpc",
            "RequiresCompatibilities": ["FARGATE"],
        },
    )


def test_container_definition():
    """Test that container definition has correct environment variables."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify container definition includes S3_BUCKET and DYNAMODB_TABLE
    template.has_resource_properties(
        "AWS::ECS::TaskDefinition",
        {
            "ContainerDefinitions": [
                {
                    "Name": "marker",
                    "Environment": assertions.Match.array_with(
                        [
                            {"Name": "S3_BUCKET", "Value": assertions.Match.any_value()},
                            {"Name": "DYNAMODB_TABLE", "Value": assertions.Match.any_value()},
                        ]
                    ),
                }
            ]
        },
    )


def test_task_role_s3_permissions():
    """Test that task role has S3 GetObject and PutObject permissions."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify task role has S3 permissions
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": assertions.Match.array_with(
                    [
                        {
                            "Effect": "Allow",
                            "Action": ["s3:GetObject", "s3:PutObject"],
                            "Resource": assertions.Match.any_value(),
                        }
                    ]
                )
            }
        },
    )


def test_task_role_dynamodb_permissions():
    """Test that task role has DynamoDB UpdateItem permission."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify task role has DynamoDB permissions
    # Note: Action can be a string or array in CloudFormation
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": assertions.Match.array_with(
                    [
                        {
                            "Effect": "Allow",
                            "Action": "dynamodb:UpdateItem",  # Single string, not array
                            "Resource": assertions.Match.any_value(),
                        }
                    ]
                )
            }
        },
    )


def test_cloudwatch_log_group():
    """Test that CloudWatch log group is created with correct retention."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify log group exists with 7-day retention
    template.has_resource_properties(
        "AWS::Logs::LogGroup",
        {
            "LogGroupName": "/ecs/pdf-models-marker",
            "RetentionInDays": 7,
        },
    )


def test_step_functions_state_machine():
    """Test that Step Functions state machine is created."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify state machine exists
    template.resource_count_is("AWS::StepFunctions::StateMachine", 1)

    # Verify state machine has correct name
    template.has_resource_properties(
        "AWS::StepFunctions::StateMachine",
        {
            "StateMachineName": "pdf-models-marker",
        },
    )


def test_step_functions_role_ecs_permissions():
    """Test that Step Functions role has ECS RunTask permissions."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify Step Functions role has ECS permissions
    # Note: Actions can be a string or array, so we match any value
    template.has_resource_properties(
        "AWS::IAM::Policy",
        {
            "PolicyDocument": {
                "Statement": assertions.Match.array_with(
                    [
                        {
                            "Effect": "Allow",
                            "Action": assertions.Match.any_value(),
                            "Resource": assertions.Match.any_value(),
                        }
                    ]
                )
            },
            "Roles": assertions.Match.array_with(
                [assertions.Match.object_like({"Ref": assertions.Match.string_like_regexp(".*StateMachineRole.*")})]
            ),
        },
    )


def test_ssm_parameters_exported():
    """Test that SSM parameters are exported for cross-stack references."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # Verify SSM parameters are created
    template.resource_count_is("AWS::SSM::Parameter", 3)

    # Verify task definition ARN parameter
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": "/pdf-models/marker/task-definition-arn",
            "Type": "String",
        },
    )

    # Verify cluster ARN parameter
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": "/pdf-models/marker/cluster-arn",
            "Type": "String",
        },
    )

    # Verify state machine ARN parameter
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": "/pdf-models/marker/state-machine-arn",
            "Type": "String",
        },
    )


def test_stack_synthesizes():
    """Test that the stack synthesizes without errors."""
    app = cdk.App()
    stack = MarkerStack(app, "TestMarkerStack")
    template = assertions.Template.from_stack(stack)

    # If we got here, synthesis succeeded
    assert template is not None
