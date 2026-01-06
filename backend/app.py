"""
CDK App for pdf-models serverless platform.

CRITICAL: Account and region are determined by AWS_PROFILE at deployment time.
The Makefile ensures all CDK commands use AWS_PROFILE=arch.
"""

import aws_cdk as cdk

from backend.api_v2_stack import ApiV2Stack
from backend.cicd_stack import CiCdStack
from backend.core_infrastructure_stack import CoreInfrastructureStack
from backend.foundation_stack import FoundationStack
from backend.frontend_stack import FrontendStack
from backend.model_stack import ModelStack
from backend.monitoring_stack import MonitoringStack
from backend.networking_stack import NetworkingStack
from backend.stack_config import MODELS

app = cdk.App()

# Stack 1: Foundation (ECR repositories, future DNS/certs)
# No env= specified - AWS_PROFILE handles account/region automatically
foundation_stack = FoundationStack(
    app,
    "FoundationStack",
    description="Foundation infrastructure: ECR repositories, DNS (future)",
)

# Stack 2: Networking (VPC with VPC endpoints for secure AWS service access)
networking_stack = NetworkingStack(
    app,
    "NetworkingStack",
    description="Networking infrastructure: VPC with VPC endpoints for ECS tasks",
)

# Stack 3: Core Infrastructure (S3, DynamoDB, Cognito)
core_stack = CoreInfrastructureStack(
    app,
    "CoreInfrastructureStack",
    description="Core infrastructure: S3 bucket, DynamoDB table, Cognito auth",
)

# Stack 3: CI/CD (CodeCommit repository, CodeBuild for containers)
# Independent stack - can be deployed anytime after Foundation
cicd_stack = CiCdStack(
    app,
    "CiCdStack",
    description="CI/CD: CodeCommit repository and CodeBuild for container builds",
)

# Stack 4: Model Processing Stacks (ECS cluster, Fargate task, Step Functions)
# Creates one stack per registered model
# Depends on: Foundation (ECR), Core (S3, DynamoDB), Networking (VPC via hardcoded values)
for model_name, model_config in MODELS.items():
    ModelStack(
        app,
        f"{model_name.title()}Stack",
        model_config=model_config,
        description=f"{model_name.title()} processing: ECS cluster, Fargate task definition, Step Functions orchestration",
    )

# Stack 5: API (HTTP API Gateway with Cognito JWT authorizer)
# Depends on: Core (Cognito, DynamoDB), Marker (Step Functions)
# Uses HTTP API (v2) for native Cognito JWT support
api_v2_stack = ApiV2Stack(
    app,
    "ApiV2Stack",
    description="HTTP API Gateway with Cognito JWT authorizer and Lambda functions",
)


# Stack 6: Monitoring (CloudWatch dashboards and alarms)
# Depends on: API (for metrics)
monitoring_stack = MonitoringStack(
    app,
    "MonitoringStack",
    description="CloudWatch dashboards and alarms for operational visibility",
)

# Stack 7: Frontend (S3 + CloudFront static site hosting)
# Independent stack - serves the Elm frontend
# Requires frontend/dst to be built before deployment
frontend_stack = FrontendStack(
    app,
    "FrontendStack",
    description="Frontend deployment: S3 bucket, CloudFront CDN, and Route53 DNS for epequeno.app",
)

# Note: Foundation and Core are independent
# CiCdStack reads ECR URIs from Foundation via SSM (one per model)
# ModelStack (one per model) reads from Foundation (ECR) and Core (S3, DynamoDB) via SSM
# ApiV2Stack reads from Core (Cognito, DynamoDB) via SSM; validates models via SSM at runtime
# FrontendStack is independent and deploys from frontend/dst

app.synth()
