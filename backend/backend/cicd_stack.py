"""
CI/CD Stack for container builds.

This stack creates CodeBuild projects for building and pushing container images to ECR.
Separated from other stacks as CI/CD has different lifecycle and change frequency.
"""

from aws_cdk import (
    Stack,
    aws_codecommit as codecommit,
    aws_codebuild as codebuild,
    aws_iam as iam,
    aws_ssm as ssm,
)
from constructs import Construct

from backend.stack_config import CONFIG


class CiCdStack(Stack):
    """CI/CD infrastructure for container builds.

    Creates:
    - CodeCommit repository for source code
    - CodeBuild project for Marker container
    - IAM role with ECR push permissions
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

        # Get ECR repository URI from SSM (created by FoundationStack)
        ecr_repo_uri = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_ECR_MARKER_URI
        )

        # Create CodeBuild project for Marker container
        marker_build = codebuild.Project(
            self,
            "MarkerContainerBuild",
            project_name=f"{CONFIG.PROJECT_NAME}-marker-container-build",
            description="Build and push Marker PDF processing container to ECR",
            source=codebuild.Source.code_commit(
                repository=repo,
                branch_or_ref="main",
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                privileged=True,  # Required for Docker builds
                compute_type=codebuild.ComputeType.SMALL,
                environment_variables={
                    "ECR_REPOSITORY_URI": codebuild.BuildEnvironmentVariable(value=ecr_repo_uri),
                }
            ),
            build_spec=codebuild.BuildSpec.from_source_filename("backend/containers/marker/buildspec.yml"),
        )

        # Grant ECR permissions to CodeBuild
        marker_build.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetAuthorizationToken",
                ],
                resources=["*"],
            )
        )

        marker_build.add_to_role_policy(
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
                    f"arn:aws:ecr:{self.region}:{self.account}:repository/{CONFIG.ECR_MARKER_REPO_NAME}"
                ],
            )
        )
