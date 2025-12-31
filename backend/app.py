"""
CDK App for pdf-models serverless platform.

CRITICAL: Account and region are determined by AWS_PROFILE at deployment time.
The Makefile ensures all CDK commands use AWS_PROFILE=arch.
"""
import aws_cdk as cdk

from backend.foundation_stack import FoundationStack
from backend.core_infrastructure_stack import CoreInfrastructureStack
from backend.cicd_stack import CiCdStack
from backend.marker_stack import MarkerStack
from backend.api_stack import ApiStack


app = cdk.App()

# Stack 1: Foundation (ECR repositories, future DNS/certs)
# No env= specified - AWS_PROFILE handles account/region automatically
foundation_stack = FoundationStack(
    app,
    "FoundationStack",
    description="Foundation infrastructure: ECR repositories, DNS (future)",
)

# Stack 2: Core Infrastructure (S3, DynamoDB, Cognito)
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

# Stack 4: Marker Processing (ECS cluster, Fargate task, Step Functions)
# Depends on: Foundation (ECR), Core (S3, DynamoDB)
marker_stack = MarkerStack(
    app,
    "MarkerStack",
    description="Marker processing: ECS cluster, Fargate task definition, Step Functions orchestration",
)

# Stack 5: API (API Gateway, Lambda functions, Cognito authorizer)
# Depends on: Core (Cognito, DynamoDB), Marker (Step Functions)
api_stack = ApiStack(
    app,
    "ApiStack",
    description="API Gateway with Cognito authorization and Lambda functions for job management",
)

# Note: Foundation and Core are independent in Phase 1
# CiCdStack reads ECR URI from Foundation via SSM
# MarkerStack reads from Foundation (ECR) and Core (S3, DynamoDB) via SSM
# ApiStack reads from Core (Cognito, DynamoDB) and Marker (Step Functions) via SSM

app.synth()
