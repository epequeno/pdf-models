"""
FoundationStack: Rarely-changing infrastructure.

Resources:
- ECR repositories for container images
- (Future) Route53 hosted zone for custom domain
- (Future) ACM certificate for HTTPS

Change Frequency: Rare
Replaceability: Hard (especially DNS/certs)
"""

from aws_cdk import (
    RemovalPolicy,
    Stack,
    Tags,
)
from aws_cdk import (
    aws_ecr as ecr,
)
from aws_cdk import (
    aws_ssm as ssm,
)
from constructs import Construct

from .stack_config import CONFIG


class FoundationStack(Stack):
    """Foundation infrastructure stack.

    This stack contains long-lived resources that rarely change:
    - ECR repositories for model container images
    - (Future) DNS and SSL/TLS certificates

    All resources export their identifiers to SSM Parameter Store
    for loose coupling with dependent stacks.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ECR Repository for Marker container
        marker_repo = ecr.Repository(
            self,
            "MarkerEcrRepo",
            repository_name=CONFIG.ECR_MARKER_REPO_NAME,
            # MVP: Allow deletion of repository
            removal_policy=RemovalPolicy.DESTROY,
            # Automatically empty repository before deletion (prevents failure)
            empty_on_delete=True,
            # Security: Scan images on push for vulnerabilities
            image_scan_on_push=True,
            # Lifecycle: Keep only last 5 images to control costs
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep last 5 images only",
                    max_image_count=5,
                    rule_priority=1,
                )
            ],
        )

        # Export ECR URI to SSM Parameter Store
        ssm.StringParameter(
            self,
            "MarkerEcrUriParam",
            parameter_name=CONFIG.SSM_ECR_MARKER_URI,
            string_value=marker_repo.repository_uri,
            description="ECR repository URI for Marker container",
        )

        # ECR Repository for Rust Lambda builder base image
        rust_builder_repo = ecr.Repository(
            self,
            "RustLambdaBuilderEcrRepo",
            repository_name=CONFIG.ECR_RUST_LAMBDA_BUILDER_REPO_NAME,
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True,
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep last 3 images only",
                    max_image_count=3,
                    rule_priority=1,
                )
            ],
        )

        # Export ECR URI to SSM Parameter Store
        ssm.StringParameter(
            self,
            "RustLambdaBuilderEcrUriParam",
            parameter_name=CONFIG.SSM_ECR_RUST_LAMBDA_BUILDER_URI,
            string_value=rust_builder_repo.repository_uri,
            description="ECR repository URI for Rust Lambda builder base image",
        )

        # Tags for cost tracking and organization
        Tags.of(self).add("Project", CONFIG.PROJECT_NAME)
        Tags.of(self).add("Stack", "Foundation")
        Tags.of(self).add("Environment", "dev")

        # FUTURE: Route53 and ACM will go here
        # Deferred until custom domain is needed for production
        # API Gateway provides default HTTPS endpoints for MVP
        #
        # Example (when ready):
        # hosted_zone = route53.HostedZone(
        #     self, "HostedZone",
        #     zone_name="pdf-models.example.com",
        # )
        # certificate = acm.Certificate(
        #     self, "Certificate",
        #     domain_name="pdf-models.example.com",
        #     validation=acm.CertificateValidation.from_dns(hosted_zone),
        # )
        # ssm.StringParameter(..., CONFIG.SSM_HOSTED_ZONE_ID, hosted_zone.zone_id)
        # ssm.StringParameter(..., CONFIG.SSM_CERTIFICATE_ARN, certificate.arn)
