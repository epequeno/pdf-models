"""
CDK App for pdf-models serverless platform.

CRITICAL: Account and region are determined by AWS_PROFILE at deployment time.
The Makefile ensures all CDK commands use AWS_PROFILE=arch.
"""
import aws_cdk as cdk

from backend.foundation_stack import FoundationStack
from backend.core_infrastructure_stack import CoreInfrastructureStack
from backend.cicd_stack import CiCdStack


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

# Note: Foundation and Core are independent in Phase 1
# CiCdStack reads ECR URI from Foundation via SSM
# Later phases (MarkerStack, ApiStack) will depend on both Foundation and Core

app.synth()
