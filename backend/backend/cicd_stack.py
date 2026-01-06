"""
CI/CD Stack for container and Lambda builds.

This stack creates CodeBuild projects for building container images and Rust Lambda functions.
Separated from other stacks as CI/CD has different lifecycle and change frequency.
"""

from aws_cdk import (
    Duration,
    Stack,
)
from aws_cdk import (
    aws_codebuild as codebuild,
)
from aws_cdk import (
    aws_codecommit as codecommit,
)
from aws_cdk import (
    aws_ecr as ecr,
)
from aws_cdk import (
    aws_iam as iam,
)
from aws_cdk import (
    aws_s3 as s3,
)
from aws_cdk import (
    aws_ssm as ssm,
)
from constructs import Construct

from backend.stack_config import CONFIG, MODELS


class CiCdStack(Stack):
    """CI/CD infrastructure for container and Lambda builds.

    Creates:
    - CodeCommit repository for source code
    - CodeBuild project for Marker container
    - CodeBuild project for Rust Lambda functions
    - IAM roles with appropriate permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create CodeCommit repository
        repo = codecommit.Repository(
            self,
            "SourceRepo",
            repository_name=f"{CONFIG.PROJECT_NAME}",
            description="PDF Models source code repository",
        )

        # Export repository clone URLs to SSM for easy access
        ssm.StringParameter(
            self,
            "CodeCommitCloneUrlHttp",
            parameter_name="/pdf-models/cicd/codecommit-clone-url-http",
            string_value=repo.repository_clone_url_http,
            description="CodeCommit repository HTTP clone URL",
        )

        ssm.StringParameter(
            self,
            "CodeCommitCloneUrlSsh",
            parameter_name="/pdf-models/cicd/codecommit-clone-url-ssh",
            string_value=repo.repository_clone_url_ssh,
            description="CodeCommit repository SSH clone URL",
        )

        # Get ECR repository URI for Rust builder from SSM (created by FoundationStack)
        ecr_rust_builder_uri = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_ECR_RUST_LAMBDA_BUILDER_URI
        )

        # Create CodeBuild project for Rust Lambda builder base image
        base_image_build = codebuild.Project(
            self,
            "BaseImageBuild",
            project_name=f"{CONFIG.PROJECT_NAME}-rust-lambda-builder-build",
            description="Build Rust Lambda builder base image with pre-installed Rust and cargo-lambda",
            source=codebuild.Source.code_commit(
                repository=repo,
                branch_or_ref="main",
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                privileged=True,  # Required for Docker builds
                compute_type=codebuild.ComputeType.MEDIUM,  # Medium for longer build
                environment_variables={
                    "ECR_REPO_URI": codebuild.BuildEnvironmentVariable(
                        value=ecr_rust_builder_uri
                    ),
                },
            ),
            build_spec=codebuild.BuildSpec.from_source_filename(
                "backend/containers/rust-lambda-builder/buildspec.yml"
            ),
            timeout=Duration.minutes(60),  # Allow up to 60 minutes for base image build
        )

        # Grant ECR permissions to base image build
        base_image_build.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ecr:GetAuthorizationToken"],
                resources=["*"],
            )
        )

        base_image_build.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:PutImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                ],
                resources=[
                    f"arn:aws:ecr:{self.region}:{self.account}:repository/{CONFIG.ECR_RUST_LAMBDA_BUILDER_REPO_NAME}"
                ],
            )
        )

        # Export base image build project name to SSM
        ssm.StringParameter(
            self,
            "BaseImageBuildProject",
            parameter_name="/pdf-models/cicd/base-image-build-project",
            string_value=base_image_build.project_name,
            description="CodeBuild project name for Rust Lambda builder base image",
        )

        # Create CodeBuild projects for all registered models
        for model_name, model_config in MODELS.items():
            # Get ECR repository URI for this model
            ecr_model_uri = ssm.StringParameter.value_for_string_parameter(
                self, f"/pdf-models/foundation/ecr-repo-uri-{model_name}"
            )

            model_build = codebuild.Project(
                self,
                f"{model_name.title()}ContainerBuild",
                project_name=f"{CONFIG.PROJECT_NAME}-{model_name}-container-build",
                description=f"Build and push {model_name.title()} PDF processing container to ECR",
                source=codebuild.Source.code_commit(
                    repository=repo,
                    branch_or_ref="main",
                ),
                environment=codebuild.BuildEnvironment(
                    build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                    privileged=True,  # Required for Docker builds
                    compute_type=codebuild.ComputeType.X_LARGE,  # X_LARGE (32GB) for model downloads
                    environment_variables={
                        "ECR_REPOSITORY_URI": codebuild.BuildEnvironmentVariable(
                            value=ecr_model_uri
                        ),
                    },
                ),
                build_spec=codebuild.BuildSpec.from_source_filename(
                    f"backend/containers/{model_config.container_path}/buildspec.yml"
                ),
            )

            # Grant ECR permissions to CodeBuild
            model_build.add_to_role_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ecr:GetAuthorizationToken",
                    ],
                    resources=["*"],
                )
            )

            model_build.add_to_role_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ecr:BatchCheckLayerAvailability",
                        "ecr:GetDownloadUrlForLayer",
                        "ecr:BatchGetImage",
                        "ecr:PutImage",
                        "ecr:InitiateLayerUpload",
                        "ecr:UploadLayerPart",
                        "ecr:CompleteLayerUpload",
                    ],
                    resources=[
                        f"arn:aws:ecr:{self.region}:{self.account}:repository/{CONFIG.PROJECT_NAME}/{model_name}"
                    ],
                )
            )

            # Grant SSM permissions to write image tag
            model_build.add_to_role_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["ssm:PutParameter"],
                    resources=[
                        f"arn:aws:ssm:{self.region}:{self.account}:parameter/pdf-models/cicd/{model_name}-image-tag"
                    ],
                )
            )

        # Get S3 bucket name from SSM and import bucket
        s3_bucket_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_S3_BUCKET_NAME
        )
        artifacts_bucket = s3.Bucket.from_bucket_name(
            self,
            "S3BucketForArtifacts",
            s3_bucket_name,
        )

        # Create CodeBuild project for Rust Lambda functions
        lambda_build = codebuild.Project(
            self,
            "RustLambdaBuild",
            project_name=f"{CONFIG.PROJECT_NAME}-rust-lambda-build",
            description="Build Rust Lambda functions for API",
            source=codebuild.Source.code_commit(
                repository=repo,
                branch_or_ref="main",
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.from_ecr_repository(
                    repository=ecr.Repository.from_repository_name(
                        self,
                        "RustBuilderRepo",
                        CONFIG.ECR_RUST_LAMBDA_BUILDER_REPO_NAME,
                    )
                ),
                compute_type=codebuild.ComputeType.SMALL,
                environment_variables={
                    "S3_BUCKET_NAME": codebuild.BuildEnvironmentVariable(
                        value=s3_bucket_name
                    ),
                },
            ),
            build_spec=codebuild.BuildSpec.from_source_filename(
                "backend/lambdas/buildspec.yml"
            ),
            artifacts=codebuild.Artifacts.s3(
                bucket=artifacts_bucket,
                include_build_id=True,
                package_zip=True,
                name="rust-lambda-builds.zip",
            ),
        )

        # Grant S3 permissions to Lambda build for uploading individual Lambda packages
        lambda_build.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[f"arn:aws:s3:::{s3_bucket_name}/lambda-artifacts/*"],
            )
        )

        # Export CodeBuild project name to SSM for easy reference
        ssm.StringParameter(
            self,
            "RustLambdaBuildProject",
            parameter_name="/pdf-models/cicd/rust-lambda-build-project",
            string_value=lambda_build.project_name,
            description="CodeBuild project name for Rust Lambda builds",
        )
