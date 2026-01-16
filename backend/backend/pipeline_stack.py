"""
CDK Pipeline for automated deployments.

This stack creates a self-mutating CodePipeline that automatically:
1. Detects changes to CodeCommit
2. Runs CDK synth
3. Updates itself if pipeline definition changed
4. Deploys all application stacks

After initial deployment, all infrastructure changes flow through this pipeline.
"""

from aws_cdk import (
    Stack,
    Stage,
    aws_codecommit as codecommit,
    aws_codebuild as codebuild,
    aws_iam as iam,
    pipelines,
)
from constructs import Construct

from backend.api_v2_stack import ApiV2Stack
from backend.cicd_stack import CiCdStack
from backend.core_infrastructure_stack import CoreInfrastructureStack
from backend.foundation_stack import FoundationStack
from backend.frontend_stack import FrontendStack
from backend.model_stack import ModelStack
from backend.monitoring_stack import MonitoringStack
from backend.networking_stack import NetworkingStack
from backend.stack_config import MODELS


class PdfModelsStage(Stage):
    """
    Deployment stage containing all pdf-models application stacks.

    This stage wraps all the application stacks so they can be deployed
    together as a unit by CDK Pipelines.
    """

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # Stack 1: Foundation (ECR repositories)
        FoundationStack(
            self,
            "FoundationStack",
            description="Foundation infrastructure: ECR repositories",
        )

        # Stack 2: Networking (VPC with VPC endpoints)
        NetworkingStack(
            self,
            "NetworkingStack",
            description="Networking infrastructure: VPC with VPC endpoints",
        )

        # Stack 3: Core Infrastructure (S3, DynamoDB, Cognito)
        CoreInfrastructureStack(
            self,
            "CoreInfrastructureStack",
            description="Core infrastructure: S3 bucket, DynamoDB table, Cognito auth",
        )

        # Stack 4: CI/CD (CodeCommit, CodeBuild projects)
        CiCdStack(
            self,
            "CiCdStack",
            description="CI/CD: CodeCommit repository and CodeBuild projects",
        )

        # Stack 5: Model Processing Stacks (one per model)
        for model_name, model_config in MODELS.items():
            ModelStack(
                self,
                f"{model_name.title()}Stack",
                model_config=model_config,
                description=f"{model_name.title()} processing: ECS, Step Functions",
            )

        # Stack 6: API (HTTP API Gateway with Lambda)
        ApiV2Stack(
            self,
            "ApiV2Stack",
            description="HTTP API Gateway with Cognito JWT authorizer",
        )

        # Stack 7: Monitoring (CloudWatch dashboards and alarms)
        MonitoringStack(
            self,
            "MonitoringStack",
            description="CloudWatch dashboards and alarms",
        )

        # Stack 8: Frontend (S3 + CloudFront)
        FrontendStack(
            self,
            "FrontendStack",
            description="Frontend: S3, CloudFront, Route53",
        )


class PipelineStack(Stack):
    """
    Self-mutating CDK Pipeline for automated infrastructure deployments.

    This pipeline:
    1. Triggers on commits to main branch in CodeCommit
    2. Runs CDK synth using uv for Python dependency management
    3. Runs unit tests before deployment
    4. Deploys all application stacks
    5. Updates itself when pipeline definition changes
    """

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # Source: CodeCommit repository
        source = pipelines.CodePipelineSource.code_commit(
            repository=codecommit.Repository.from_repository_name(
                self, "Repo", "pdf-models"
            ),
            branch="main",
        )

        # Synth step: Install dependencies and run cdk synth
        synth = pipelines.CodeBuildStep(
            "Synth",
            input=source,
            install_commands=[
                # Install CDK CLI and Elm (Node.js is pre-installed in STANDARD_7_0)
                "npm install -g aws-cdk elm",
                # Remove .python-version (for local dev) to use CodeBuild's Python
                "rm -f backend/.python-version",
                # Build frontend (FrontendStack requires frontend/dst to exist)
                # Use subshell to avoid changing cwd
                "(cd frontend && ./build.sh)",
                # Install Python dependencies (this changes cwd to backend/)
                "cd backend && pip install -e .",
            ],
            commands=[
                # Already in backend/ due to install_commands cd
                "cdk synth",
            ],
            # Path relative to repo root
            primary_output_directory="backend/cdk.out",
            build_environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                compute_type=codebuild.ComputeType.MEDIUM,
            ),
            partial_build_spec=codebuild.BuildSpec.from_object({
                "version": "0.2",
                "phases": {
                    "install": {
                        "runtime-versions": {
                            "python": "3.12",
                        },
                    },
                },
            }),
        )

        # Create the pipeline
        pipeline = pipelines.CodePipeline(
            self,
            "Pipeline",
            pipeline_name="pdf-models-infrastructure",
            synth=synth,
            self_mutation=True,
            docker_enabled_for_synth=True,
            docker_enabled_for_self_mutation=True,
            code_build_defaults=pipelines.CodeBuildOptions(
                build_environment=codebuild.BuildEnvironment(
                    build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                    compute_type=codebuild.ComputeType.MEDIUM,
                ),
            ),
        )

        # Unit tests step - runs before deployment
        unit_tests = pipelines.CodeBuildStep(
            "UnitTests",
            input=source,
            install_commands=[
                "rm -f backend/.python-version",
                "cd backend && pip install -e '.[dev]'",
            ],
            commands=[
                # Already in backend/ due to install_commands cd
                "pytest tests/unit/ -v --junitxml=test-results.xml",
            ],
            partial_build_spec=codebuild.BuildSpec.from_object({
                "version": "0.2",
                "phases": {
                    "install": {
                        "runtime-versions": {
                            "python": "3.12",
                        },
                    },
                },
                "reports": {
                    "unit-tests": {
                        "files": ["test-results.xml"],
                        "file-format": "JUNITXML",
                    }
                },
            }),
            build_environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                compute_type=codebuild.ComputeType.SMALL,
            ),
        )

        # Add deployment stage with pre-deployment tests
        pipeline.add_stage(
            PdfModelsStage(self, "Prod"),
            pre=[unit_tests],
        )
