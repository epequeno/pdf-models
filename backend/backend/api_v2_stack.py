"""
API v2 Stack: HTTP API Gateway with Cognito JWT authorizer and Lambda functions.

This stack uses API Gateway v2 (HTTP API) instead of REST API for better Cognito integration.
"""

from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
)
from aws_cdk import (
    aws_apigatewayv2 as apigwv2,
)
from aws_cdk import (
    aws_apigatewayv2_authorizers as apigwv2_authorizers,
)
from aws_cdk import (
    aws_apigatewayv2_integrations as apigwv2_integrations,
)
from aws_cdk import (
    aws_certificatemanager as acm,
)
from aws_cdk import (
    aws_cognito as cognito,
)
from aws_cdk import (
    aws_iam as iam,
)
from aws_cdk import (
    aws_lambda as lambda_,
)
from aws_cdk import (
    aws_logs as logs,
)
from aws_cdk import (
    aws_route53 as route53,
)
from aws_cdk import (
    aws_route53_targets as route53_targets,
)
from aws_cdk import (
    aws_s3 as s3,
)
from aws_cdk import (
    aws_ssm as ssm,
)
from constructs import Construct

from backend.stack_config import CONFIG


class ApiV2Stack(Stack):
    """HTTP API Gateway and Lambda functions for job management.

    Creates:
    - HTTP API Gateway (v2) with Cognito JWT Authorizer
    - Lambda functions for job submission and status queries
    - CORS configuration
    - CloudWatch log groups
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get dependencies from SSM
        dynamodb_table_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_DYNAMODB_TABLE_NAME
        )
        state_machine_arn = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/marker/state-machine-arn"
        )
        user_pool_id = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_COGNITO_USER_POOL_ID
        )
        user_pool_client_id = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_COGNITO_USER_POOL_CLIENT_ID
        )
        s3_bucket_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_S3_BUCKET_NAME
        )
        s3_bucket_arn = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/core/s3-bucket-arn"
        )

        # Use the same hosted zone as FrontendStack (hardcoded ID)
        hosted_zone_id = "Z04774573K4OEWVFBEMS5"
        domain_name = "epequeno.app"

        # Get Lambda S3 object versions from SSM
        # These are updated by CodeBuild after each Lambda build
        submit_job_version = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/lambda/submit-job-version"
        )
        get_job_version = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/lambda/get-job-version"
        )
        get_upload_url_version = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/lambda/get-upload-url-version"
        )

        # Create CloudWatch log groups for Lambdas
        submit_job_log_group = logs.LogGroup(
            self,
            "SubmitJobLogGroup",
            log_group_name=f"/aws/lambda/{CONFIG.PROJECT_NAME}-submit-job-v2",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        get_job_log_group = logs.LogGroup(
            self,
            "GetJobLogGroup",
            log_group_name=f"/aws/lambda/{CONFIG.PROJECT_NAME}-get-job-v2",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        get_upload_url_log_group = logs.LogGroup(
            self,
            "GetUploadUrlLogGroup",
            log_group_name=f"/aws/lambda/{CONFIG.PROJECT_NAME}-get-upload-url",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Lambda execution role for submit-job
        submit_job_role = iam.Role(
            self,
            "SubmitJobLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant DynamoDB permissions to submit-job role
        submit_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:PutItem"],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{dynamodb_table_name}"
                ],
            )
        )

        # Grant Step Functions permissions to submit-job role
        submit_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["states:StartExecution"],
                resources=[state_machine_arn],
            )
        )

        # Grant S3 permissions for generating pre-signed URLs
        submit_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[f"{s3_bucket_arn}/*"],
            )
        )

        # Create Lambda execution role for get-job
        get_job_role = iam.Role(
            self,
            "GetJobLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant DynamoDB permissions to get-job role
        get_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:GetItem", "dynamodb:Query"],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{dynamodb_table_name}",
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{dynamodb_table_name}/index/*",
                ],
            )
        )

        # Grant S3 permissions for generating pre-signed URLs
        get_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject"],
                resources=[f"{s3_bucket_arn}/*"],
            )
        )

        # Create Lambda execution role for get-upload-url
        get_upload_url_role = iam.Role(
            self,
            "GetUploadUrlLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant S3 permissions for generating pre-signed upload URLs
        get_upload_url_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[f"{s3_bucket_arn}/*"],
            )
        )

        # Create submit-job Lambda function
        submit_job_function = lambda_.Function(
            self,
            "SubmitJobFunction",
            function_name=f"{CONFIG.PROJECT_NAME}-submit-job-v2",
            runtime=lambda_.Runtime.PROVIDED_AL2023,
            handler="bootstrap",
            code=lambda_.Code.from_bucket(
                bucket=s3.Bucket.from_bucket_name(
                    self, "LambdaArtifactsBucket", s3_bucket_name
                ),
                key="lambda-artifacts/submit-job.zip",
                object_version=submit_job_version,
            ),
            architecture=lambda_.Architecture.ARM_64,
            role=submit_job_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            log_group=submit_job_log_group,
            environment={
                "DYNAMODB_TABLE_NAME": dynamodb_table_name,
                "STATE_MACHINE_ARN": state_machine_arn,
                "S3_BUCKET_NAME": s3_bucket_name,
            },
        )

        # Create get-job Lambda function
        get_job_function = lambda_.Function(
            self,
            "GetJobFunction",
            function_name=f"{CONFIG.PROJECT_NAME}-get-job-v2",
            runtime=lambda_.Runtime.PROVIDED_AL2023,
            handler="bootstrap",
            code=lambda_.Code.from_bucket(
                bucket=s3.Bucket.from_bucket_name(
                    self, "LambdaArtifactsBucket2", s3_bucket_name
                ),
                key="lambda-artifacts/get-job.zip",
                object_version=get_job_version,
            ),
            architecture=lambda_.Architecture.ARM_64,
            role=get_job_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            log_group=get_job_log_group,
            environment={
                "DYNAMODB_TABLE_NAME": dynamodb_table_name,
                "S3_BUCKET_NAME": s3_bucket_name,
            },
        )

        # Create get-upload-url Lambda function
        get_upload_url_function = lambda_.Function(
            self,
            "GetUploadUrlFunction",
            function_name=f"{CONFIG.PROJECT_NAME}-get-upload-url",
            runtime=lambda_.Runtime.PROVIDED_AL2023,
            handler="bootstrap",
            code=lambda_.Code.from_bucket(
                bucket=s3.Bucket.from_bucket_name(
                    self, "LambdaArtifactsBucket3", s3_bucket_name
                ),
                key="lambda-artifacts/get-upload-url.zip",
                object_version=get_upload_url_version,
            ),
            architecture=lambda_.Architecture.ARM_64,
            role=get_upload_url_role,
            timeout=Duration.seconds(10),
            memory_size=256,
            log_group=get_upload_url_log_group,
            environment={
                "S3_BUCKET_NAME": s3_bucket_name,
            },
        )

        # Create HTTP API Gateway (v2)
        http_api = apigwv2.HttpApi(
            self,
            "HttpApi",
            api_name=f"{CONFIG.PROJECT_NAME}-http-api",
            description="PDF Models HTTP API for job submission and status queries",
            cors_preflight=apigwv2.CorsPreflightOptions(
                allow_origins=["https://epequeno.app"],  # Restrict to our domain
                allow_methods=[
                    apigwv2.CorsHttpMethod.GET,
                    apigwv2.CorsHttpMethod.POST,
                    apigwv2.CorsHttpMethod.OPTIONS,
                ],
                allow_headers=["Content-Type", "Authorization"],
                max_age=Duration.hours(1),
            ),
        )

        # Import the existing hosted zone (same pattern as FrontendStack)
        hosted_zone = route53.HostedZone.from_hosted_zone_attributes(
            self,
            "HostedZone",
            hosted_zone_id=hosted_zone_id,
            zone_name=domain_name,
        )

        # Create certificate for api.epequeno.app
        certificate = acm.Certificate(
            self,
            "ApiCertificate",
            domain_name="api.epequeno.app",
            validation=acm.CertificateValidation.from_dns(hosted_zone),
        )

        # Create custom domain for API
        domain_name_resource = apigwv2.DomainName(
            self,
            "ApiDomainName",
            domain_name="api.epequeno.app",
            certificate=certificate,
        )

        # Map the custom domain to the HTTP API
        apigwv2.ApiMapping(
            self,
            "ApiMapping",
            api=http_api,
            domain_name=domain_name_resource,
        )

        # Create Route53 A record for api.epequeno.app
        route53.ARecord(
            self,
            "ApiARecord",
            zone=hosted_zone,
            record_name="api",
            target=route53.RecordTarget.from_alias(
                route53_targets.ApiGatewayv2DomainProperties(
                    regional_domain_name=domain_name_resource.regional_domain_name,
                    regional_hosted_zone_id=domain_name_resource.regional_hosted_zone_id,
                )
            ),
        )

        # Create Cognito JWT Authorizer for HTTP API
        user_pool = cognito.UserPool.from_user_pool_id(
            self,
            "UserPool",
            user_pool_id,
        )

        authorizer = apigwv2_authorizers.HttpUserPoolAuthorizer(
            "CognitoAuthorizer",
            user_pool,
            user_pool_clients=[
                cognito.UserPoolClient.from_user_pool_client_id(
                    self, "UserPoolClient", user_pool_client_id
                )
            ],
        )

        # Create Lambda integrations
        submit_job_integration = apigwv2_integrations.HttpLambdaIntegration(
            "SubmitJobIntegration",
            submit_job_function,
        )

        get_job_integration = apigwv2_integrations.HttpLambdaIntegration(
            "GetJobIntegration",
            get_job_function,
        )

        get_upload_url_integration = apigwv2_integrations.HttpLambdaIntegration(
            "GetUploadUrlIntegration",
            get_upload_url_function,
        )

        # Add routes with Cognito authorizer
        # POST /v1/models/{model}/upload-url - get pre-signed upload URL
        http_api.add_routes(
            path="/v1/models/{model}/upload-url",
            methods=[apigwv2.HttpMethod.POST],
            integration=get_upload_url_integration,
            authorizer=authorizer,
        )

        # POST /v1/models/{model}/jobs - submit job
        http_api.add_routes(
            path="/v1/models/{model}/jobs",
            methods=[apigwv2.HttpMethod.POST],
            integration=submit_job_integration,
            authorizer=authorizer,
        )

        # GET /v1/models/{model}/jobs - list jobs
        http_api.add_routes(
            path="/v1/models/{model}/jobs",
            methods=[apigwv2.HttpMethod.GET],
            integration=get_job_integration,
            authorizer=authorizer,
        )

        # GET /v1/models/{model}/jobs/{job_id} - get single job
        http_api.add_routes(
            path="/v1/models/{model}/jobs/{job_id}",
            methods=[apigwv2.HttpMethod.GET],
            integration=get_job_integration,
            authorizer=authorizer,
        )

        # Export API endpoint to SSM
        ssm.StringParameter(
            self,
            "HttpApiEndpoint",
            parameter_name="/pdf-models/api-v2/endpoint",
            string_value=http_api.url or "",
            description="HTTP API Gateway endpoint URL",
        )

        # Export API ID to SSM
        ssm.StringParameter(
            self,
            "HttpApiId",
            parameter_name="/pdf-models/api-v2/id",
            string_value=http_api.http_api_id,
            description="HTTP API Gateway ID",
        )
