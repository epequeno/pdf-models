"""
Centralized configuration for all CDK stacks.

CRITICAL: This file contains NO hardcoded account IDs or regions.
Account and region are determined by AWS_PROFILE at deployment time.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class ModelConfig:
    """Configuration for a PDF processing model.

    Each model has its own ECS task, Step Functions state machine,
    and container image. This dataclass defines the resources needed.
    """

    name: str  # Model identifier: "marker", "dolphin"
    cpu: int  # Fargate vCPU units or EC2 vCPU count
    memory_mib: int  # Fargate memory in MiB or EC2 memory limit
    container_path: str  # Directory under backend/containers/
    output_formats: tuple[str, ...]  # ("markdown",) or ("json", "markdown")
    timeout_minutes: int = 120  # Task timeout

    # GPU/EC2 configuration (defaults to Fargate CPU)
    use_gpu: bool = False  # If True, use EC2 with GPU instead of Fargate
    gpu_count: int = 0  # Number of GPUs per task (typically 1 for GPU models)
    instance_type: str = ""  # EC2 instance type (e.g., "g4dn.xlarge")
    spot_enabled: bool = True  # Use Spot instances for cost savings
    min_capacity: int = 0  # ASG min capacity (0 = scale to zero when idle)
    max_capacity: int = 2  # ASG max capacity


# Model registry - add new models here
MODELS: dict[str, ModelConfig] = {
    "marker": ModelConfig(
        name="marker",
        cpu=4096,
        memory_mib=16384,
        container_path="marker",
        output_formats=("markdown",),
        timeout_minutes=120,
    ),
    "dolphin": ModelConfig(
        name="dolphin",
        cpu=4096,  # 4 vCPU on g4dn.xlarge
        memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
        container_path="dolphin",
        output_formats=("json", "markdown"),
        timeout_minutes=30,  # Reduced from 120 - GPU is much faster
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
    ),
}


@dataclass(frozen=True)
class StackConfig:
    """Centralized configuration for all CDK stacks.

    This configuration is environment-agnostic. Account ID and region
    are determined by AWS_PROFILE and accessed via CDK's Aws.ACCOUNT_ID
    and Aws.REGION pseudo-parameters where needed.
    """

    # Project naming
    PROJECT_NAME: str = "pdf-models"

    # SSM Parameter Names - Foundation
    SSM_ECR_MARKER_URI: str = "/pdf-models/foundation/ecr-repo-uri-marker"
    SSM_ECR_RUST_LAMBDA_BUILDER_URI: str = (
        "/pdf-models/foundation/ecr-repo-uri-rust-lambda-builder"
    )
    SSM_HOSTED_ZONE_ID: str = "/pdf-models/foundation/hosted-zone-id"
    SSM_CERTIFICATE_ARN: str = "/pdf-models/foundation/certificate-arn"

    # SSM Parameter Names - CI/CD
    SSM_MARKER_IMAGE_TAG: str = "/pdf-models/cicd/marker-image-tag"

    # SSM Parameter Names - Core
    SSM_S3_BUCKET_NAME: str = "/pdf-models/core/s3-bucket-name"
    SSM_DYNAMODB_TABLE_NAME: str = "/pdf-models/core/dynamodb-table-name"
    SSM_COGNITO_USER_POOL_ID: str = "/pdf-models/core/cognito-user-pool-id"
    SSM_COGNITO_IDENTITY_POOL_ID: str = "/pdf-models/core/cognito-identity-pool-id"
    SSM_COGNITO_USER_POOL_CLIENT_ID: str = (
        "/pdf-models/core/cognito-user-pool-client-id"
    )

    # Resource Names (base names, account-specific suffixes added in stacks)
    ECR_MARKER_REPO_NAME: str = "pdf-models/marker"
    ECR_RUST_LAMBDA_BUILDER_REPO_NAME: str = "pdf-models/rust-lambda-builder"
    S3_BUCKET_NAME_PREFIX: str = (
        "pdf-models-docs"  # Actual name will be: {prefix}-{account-id}
    )
    DYNAMODB_TABLE_NAME: str = "pdf-models-jobs"
    COGNITO_USER_POOL_NAME: str = "pdf-models-users"
    COGNITO_IDENTITY_POOL_NAME: str = "pdf-models-identity-pool"

    # S3 Configuration
    S3_EXPIRATION_DAYS: int = 7

    # DynamoDB Schema
    DYNAMODB_PK: str = "job_id"
    DYNAMODB_GSI_NAME: str = "user_id-created_at-index"
    DYNAMODB_GSI_PK: str = "user_id"
    DYNAMODB_GSI_SK: str = "created_at"


# Single instance to import across stacks
CONFIG = StackConfig()
