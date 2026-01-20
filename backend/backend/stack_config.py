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

    # Custom prompt support (for VLM models like Dolphin, DeepSeek-OCR)
    supports_prompt: bool = False  # If True, model accepts custom user prompts

    # Fargate ephemeral storage (for large container images with pre-downloaded models)
    ephemeral_storage_gib: int = 21  # Fargate ephemeral storage (21-200 GiB, default 20)

    # GPU/EC2 configuration (defaults to Fargate CPU)
    use_gpu: bool = False  # If True, use EC2 with GPU instead of Fargate
    gpu_count: int = 0  # Number of GPUs per task (typically 1 for GPU models)
    instance_type: str = ""  # EC2 instance type (e.g., "g4dn.xlarge")
    spot_enabled: bool = True  # Use Spot instances for cost savings
    min_capacity: int = 0  # ASG min capacity (0 = scale to zero when idle)
    max_capacity: int = 2  # ASG max capacity
    ebs_volume_size_gb: int = 30  # Root EBS volume size (increase for large container images)


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
        supports_prompt=True,  # VLM model accepts custom prompts
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
        ebs_volume_size_gb=50,  # ~5GB image + headroom
    ),
    "docling": ModelConfig(
        name="docling",
        cpu=4096,  # 4 vCPU
        memory_mib=16384,  # 16GB (PyTorch + model overhead)
        container_path="docling",
        output_formats=("json", "markdown"),
        timeout_minutes=30,  # CPU is fast for this small model (~0.8s/page)
    ),
    "deepseek-ocr": ModelConfig(
        name="deepseek-ocr",
        cpu=4096,  # 4 vCPU on g4dn.xlarge
        memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
        container_path="deepseek-ocr",
        output_formats=("markdown",),
        timeout_minutes=30,
        supports_prompt=True,  # VLM model accepts custom prompts
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
        ebs_volume_size_gb=100,  # 9.29GB image + Docker overhead + headroom
    ),
    "mineru": ModelConfig(
        name="mineru",
        cpu=4096,  # 4 vCPU
        memory_mib=16384,  # 16GB (MinerU recommends 8GB min, 16GB for headroom)
        container_path="mineru",
        output_formats=("markdown", "json"),
        timeout_minutes=30,  # CPU pipeline is reasonably fast
        ephemeral_storage_gib=50,  # ~5GB models + image layers
    ),
    "olmocr": ModelConfig(
        name="olmocr",
        cpu=4096,  # 4 vCPU on g4dn.xlarge
        memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
        container_path="olmocr",
        output_formats=("markdown",),
        timeout_minutes=30,
        supports_prompt=True,  # VLM model accepts custom prompts
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
        ebs_volume_size_gb=100,  # 7B model + vLLM + headroom
    ),
    "docext": ModelConfig(
        name="docext",
        cpu=4096,  # 4 vCPU on g4dn.xlarge
        memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
        container_path="docext",
        output_formats=("markdown",),
        timeout_minutes=30,
        supports_prompt=True,  # VLM model accepts custom prompts
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
        ebs_volume_size_gb=80,  # 3B model + transformers
    ),
    "dots-ocr": ModelConfig(
        name="dots-ocr",
        cpu=4096,  # 4 vCPU on g4dn.xlarge
        memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
        container_path="dots-ocr",
        output_formats=("json", "markdown"),  # JSON with layout + markdown text
        timeout_minutes=30,
        supports_prompt=True,  # VLM model accepts custom prompts
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
        ebs_volume_size_gb=80,  # 1.7B model + transformers
    ),
    "lightonocr": ModelConfig(
        name="lightonocr",
        cpu=4096,  # 4 vCPU on g4dn.xlarge
        memory_mib=15360,  # 15GB (leave headroom from 16GB instance)
        container_path="lightonocr",
        output_formats=("markdown",),  # Clean text output
        timeout_minutes=30,  # Very fast inference
        supports_prompt=False,  # OCR-focused, no custom prompts
        use_gpu=True,
        gpu_count=1,
        instance_type="g4dn.xlarge",  # 1 T4 GPU, 4 vCPU, 16GB RAM
        spot_enabled=True,
        min_capacity=0,  # Scale to zero when idle
        max_capacity=2,
        ebs_volume_size_gb=60,  # ~2GB model + container overhead
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
    SSM_CONFIGURATIONS_TABLE_NAME: str = "/pdf-models/core/configurations-table-name"
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
    DYNAMODB_CONFIGURATIONS_TABLE_NAME: str = "pdf-models-configurations"
    COGNITO_USER_POOL_NAME: str = "pdf-models-users"
    COGNITO_IDENTITY_POOL_NAME: str = "pdf-models-identity-pool"
    COGNITO_ADMIN_GROUP_NAME: str = "pdf-models-admins"

    # S3 Configuration
    S3_EXPIRATION_DAYS: int = 7

    # DynamoDB Schema - Jobs Table
    DYNAMODB_PK: str = "job_id"
    DYNAMODB_GSI_NAME: str = "user_id-created_at-index"
    DYNAMODB_GSI_PK: str = "user_id"
    DYNAMODB_GSI_SK: str = "created_at"

    # DynamoDB Schema - Configurations Table
    DYNAMODB_CONFIGS_PK: str = "config_id"
    DYNAMODB_CONFIGS_GSI_USER: str = "user_id-created_at-index"
    DYNAMODB_CONFIGS_GSI_VISIBILITY: str = "visibility-model-index"


# Single instance to import across stacks
CONFIG = StackConfig()
