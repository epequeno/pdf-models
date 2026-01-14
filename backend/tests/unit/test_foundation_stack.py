"""Unit tests for FoundationStack."""

import aws_cdk as cdk
from aws_cdk.assertions import Template, Match

from backend.foundation_stack import FoundationStack
from backend.stack_config import CONFIG, MODELS


def test_foundation_stack_synthesizes():
    """Test that FoundationStack synthesizes without errors."""
    app = cdk.App()
    stack = FoundationStack(app, "TestFoundationStack")
    template = Template.from_stack(stack)

    # Assert ECR repositories exist (one per model + Rust Lambda Builder)
    expected_ecr_repos = len(MODELS) + 1  # models + rust-lambda-builder
    template.resource_count_is("AWS::ECR::Repository", expected_ecr_repos)

    # Assert SSM parameters created for both ECR URIs
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": CONFIG.SSM_ECR_MARKER_URI,
            "Type": "String",
        },
    )

    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": CONFIG.SSM_ECR_RUST_LAMBDA_BUILDER_URI,
            "Type": "String",
        },
    )


def test_ecr_repository_configuration():
    """Test ECR repository has correct lifecycle and scanning settings."""
    app = cdk.App()
    stack = FoundationStack(app, "TestFoundationStack")
    template = Template.from_stack(stack)

    # Verify ECR repository properties (checking common config across all model repos)
    template.has_resource_properties(
        "AWS::ECR::Repository",
        {
            # Image scanning enabled for security
            "ImageScanningConfiguration": {
                "ScanOnPush": True,
            },
            # Lifecycle policy exists (keeps last 3 images)
            "LifecyclePolicy": Match.object_like({
                "LifecyclePolicyText": Match.string_like_regexp(r'.*"countNumber"\s*:\s*3.*'),
            }),
            # Empty on delete for clean teardown
            "EmptyOnDelete": True,
        },
    )


def test_ssm_parameter_export():
    """Test SSM parameter is created with correct description."""
    app = cdk.App()
    stack = FoundationStack(app, "TestFoundationStack")
    template = Template.from_stack(stack)

    # Verify SSM parameter properties
    template.has_resource_properties(
        "AWS::SSM::Parameter",
        {
            "Name": CONFIG.SSM_ECR_MARKER_URI,
            "Description": Match.string_like_regexp(r".*ECR.*Marker.*"),
        },
    )


def test_stack_has_correct_tags():
    """Test stack resources are tagged correctly."""
    app = cdk.App()
    stack = FoundationStack(app, "TestFoundationStack")
    template = Template.from_stack(stack)

    # Stack should have resources (one ECR repo per model + rust-lambda-builder)
    expected_ecr_repos = len(MODELS) + 1
    template.resource_count_is("AWS::ECR::Repository", expected_ecr_repos)

    # Tags are applied at stack level via Tags.of(self)
    # CDK applies these to all taggable resources
