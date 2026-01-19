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

from backend.stack_config import CONFIG, MODELS


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
        configurations_table_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_CONFIGURATIONS_TABLE_NAME
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
        config_crud_version = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/lambda/config-crud-version"
        )
        config_admin_version = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/lambda/config-admin-version"
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

        config_crud_log_group = logs.LogGroup(
            self,
            "ConfigCrudLogGroup",
            log_group_name=f"/aws/lambda/{CONFIG.PROJECT_NAME}-config-crud",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        config_admin_log_group = logs.LogGroup(
            self,
            "ConfigAdminLogGroup",
            log_group_name=f"/aws/lambda/{CONFIG.PROJECT_NAME}-config-admin",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        register_task_def_log_group = logs.LogGroup(
            self,
            "RegisterTaskDefLogGroup",
            log_group_name=f"/aws/lambda/{CONFIG.PROJECT_NAME}-register-task-def",
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

        # Grant Step Functions permissions to submit-job role (all model state machines)
        submit_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["states:StartExecution"],
                resources=[
                    f"arn:aws:states:{self.region}:{self.account}:stateMachine:{CONFIG.PROJECT_NAME}-*"
                ],
            )
        )

        # Grant SSM read permissions for model validation (submit-job, get-job, get-upload-url)
        ssm_model_param_resources = [
            f"arn:aws:ssm:{self.region}:{self.account}:parameter/pdf-models/*/state-machine-arn"
        ]

        # Grant S3 permissions for generating pre-signed URLs
        submit_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[f"{s3_bucket_arn}/*"],
            )
        )

        # Grant DynamoDB permissions to submit-job role for configurations table
        # Needed to validate config_id and increment usage_count
        submit_job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:GetItem", "dynamodb:UpdateItem"],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{configurations_table_name}"
                ],
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

        # Grant SSM read permissions to all Lambda roles for model validation
        for role in [submit_job_role, get_job_role, get_upload_url_role]:
            role.add_to_policy(
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["ssm:GetParameter"],
                    resources=ssm_model_param_resources,
                )
            )

        # Create Lambda execution role for config-crud
        config_crud_role = iam.Role(
            self,
            "ConfigCrudLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant DynamoDB permissions to config-crud role for configurations table
        config_crud_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                ],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{configurations_table_name}",
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{configurations_table_name}/index/*",
                ],
            )
        )

        # Create Lambda execution role for config-admin
        config_admin_role = iam.Role(
            self,
            "ConfigAdminLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant DynamoDB permissions to config-admin role for configurations table
        config_admin_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Scan",
                ],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{configurations_table_name}",
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{configurations_table_name}/index/*",
                ],
            )
        )

        # Grant Lambda invoke permission for register-task-def Lambda
        config_admin_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[
                    f"arn:aws:lambda:{self.region}:{self.account}:function:{CONFIG.PROJECT_NAME}-register-task-def",
                ],
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
                "S3_BUCKET_NAME": s3_bucket_name,
                "CONFIGURATIONS_TABLE_NAME": configurations_table_name,
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

        # Create config-crud Lambda function
        config_crud_function = lambda_.Function(
            self,
            "ConfigCrudFunction",
            function_name=f"{CONFIG.PROJECT_NAME}-config-crud",
            runtime=lambda_.Runtime.PROVIDED_AL2023,
            handler="bootstrap",
            code=lambda_.Code.from_bucket(
                bucket=s3.Bucket.from_bucket_name(
                    self, "LambdaArtifactsBucket4", s3_bucket_name
                ),
                key="lambda-artifacts/config-crud.zip",
                object_version=config_crud_version,
            ),
            architecture=lambda_.Architecture.ARM_64,
            role=config_crud_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            log_group=config_crud_log_group,
            environment={
                "CONFIGURATIONS_TABLE_NAME": configurations_table_name,
            },
        )

        # Create config-admin Lambda function
        config_admin_function = lambda_.Function(
            self,
            "ConfigAdminFunction",
            function_name=f"{CONFIG.PROJECT_NAME}-config-admin",
            runtime=lambda_.Runtime.PROVIDED_AL2023,
            handler="bootstrap",
            code=lambda_.Code.from_bucket(
                bucket=s3.Bucket.from_bucket_name(
                    self, "LambdaArtifactsBucket5", s3_bucket_name
                ),
                key="lambda-artifacts/config-admin.zip",
                object_version=config_admin_version,
            ),
            architecture=lambda_.Architecture.ARM_64,
            role=config_admin_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            log_group=config_admin_log_group,
            environment={
                "CONFIGURATIONS_TABLE_NAME": configurations_table_name,
                "REGISTER_TASK_DEF_FUNCTION": f"{CONFIG.PROJECT_NAME}-register-task-def",
            },
        )

        # ============================================
        # Register Task Definition Lambda
        # ============================================

        # Create Lambda execution role for register-task-def
        register_task_def_role = iam.Role(
            self,
            "RegisterTaskDefLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant ECS permissions scoped to user task definitions (pdf-models-*-user-*)
        register_task_def_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecs:RegisterTaskDefinition",
                    "ecs:DescribeTaskDefinition",
                ],
                resources=["*"],  # RegisterTaskDefinition doesn't support resource-level permissions
                conditions={
                    "StringLike": {
                        "ecs:task-definition-family": f"{CONFIG.PROJECT_NAME}-*-user-*"
                    }
                } if False else {},  # Note: RegisterTaskDefinition doesn't support conditions
            )
        )

        # Grant DescribeTaskDefinition for base task definitions (needed to read template)
        register_task_def_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ecs:DescribeTaskDefinition"],
                resources=["*"],  # DescribeTaskDefinition requires * for resource
            )
        )

        # Grant SSM read permissions for base task definition ARNs
        register_task_def_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ssm:GetParameter"],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/pdf-models/*/task-definition-arn"
                ],
            )
        )

        # Grant DynamoDB update permissions for configurations table
        register_task_def_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:UpdateItem"],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{configurations_table_name}",
                ],
            )
        )

        # Grant IAM PassRole for task execution and task roles
        # This is needed when registering task definitions that reference IAM roles
        register_task_def_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[
                    f"arn:aws:iam::{self.account}:role/{CONFIG.PROJECT_NAME}-*"
                ],
                conditions={
                    "StringEquals": {
                        "iam:PassedToService": "ecs-tasks.amazonaws.com"
                    }
                },
            )
        )

        # Create register-task-def Lambda function (Python)
        register_task_def_function = lambda_.Function(
            self,
            "RegisterTaskDefFunction",
            function_name=f"{CONFIG.PROJECT_NAME}-register-task-def",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="handler.handler",
            code=lambda_.Code.from_asset("lambdas/register-task-def"),
            architecture=lambda_.Architecture.ARM_64,
            role=register_task_def_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            log_group=register_task_def_log_group,
            environment={
                "CONFIGURATIONS_TABLE_NAME": configurations_table_name,
            },
        )

        # Create CloudWatch log group for API Gateway access logs
        api_access_log_group = logs.LogGroup(
            self,
            "ApiAccessLogGroup",
            log_group_name=f"/aws/apigateway/{CONFIG.PROJECT_NAME}-http-api-access",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
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
                    apigwv2.CorsHttpMethod.PUT,
                    apigwv2.CorsHttpMethod.DELETE,
                    apigwv2.CorsHttpMethod.OPTIONS,
                ],
                allow_headers=["Content-Type", "Authorization"],
                max_age=Duration.hours(1),
            ),
        )

        # Configure access logging on the default stage
        # HTTP APIs automatically create a $default stage
        cfn_stage = http_api.default_stage.node.default_child
        cfn_stage.access_log_settings = apigwv2.CfnStage.AccessLogSettingsProperty(
            destination_arn=api_access_log_group.log_group_arn,
            format='{"requestId":"$context.requestId","ip":"$context.identity.sourceIp","requestTime":"$context.requestTime","httpMethod":"$context.httpMethod","path":"$context.path","status":"$context.status","responseLength":"$context.responseLength","latency":"$context.responseLatency","integrationLatency":"$context.integrationLatency","errorMessage":"$context.error.message"}',
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

        config_crud_integration = apigwv2_integrations.HttpLambdaIntegration(
            "ConfigCrudIntegration",
            config_crud_function,
        )

        config_admin_integration = apigwv2_integrations.HttpLambdaIntegration(
            "ConfigAdminIntegration",
            config_admin_function,
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

        # ============================================
        # Configuration CRUD Routes
        # ============================================

        # POST /v1/models/{model}/configs - create configuration
        http_api.add_routes(
            path="/v1/models/{model}/configs",
            methods=[apigwv2.HttpMethod.POST],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # GET /v1/models/{model}/configs - list user's configurations
        http_api.add_routes(
            path="/v1/models/{model}/configs",
            methods=[apigwv2.HttpMethod.GET],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # GET /v1/models/{model}/configs/{config_id} - get configuration
        http_api.add_routes(
            path="/v1/models/{model}/configs/{config_id}",
            methods=[apigwv2.HttpMethod.GET],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # PUT /v1/models/{model}/configs/{config_id} - update configuration
        http_api.add_routes(
            path="/v1/models/{model}/configs/{config_id}",
            methods=[apigwv2.HttpMethod.PUT],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # DELETE /v1/models/{model}/configs/{config_id} - delete configuration
        http_api.add_routes(
            path="/v1/models/{model}/configs/{config_id}",
            methods=[apigwv2.HttpMethod.DELETE],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # POST /v1/models/{model}/configs/{config_id}/fork - fork configuration
        http_api.add_routes(
            path="/v1/models/{model}/configs/{config_id}/fork",
            methods=[apigwv2.HttpMethod.POST],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # GET /v1/configs/discover - discover public configurations
        http_api.add_routes(
            path="/v1/configs/discover",
            methods=[apigwv2.HttpMethod.GET],
            integration=config_crud_integration,
            authorizer=authorizer,
        )

        # ============================================
        # Configuration Admin Routes
        # ============================================

        # GET /v1/admin/configs/pending - list pending configurations
        http_api.add_routes(
            path="/v1/admin/configs/pending",
            methods=[apigwv2.HttpMethod.GET],
            integration=config_admin_integration,
            authorizer=authorizer,
        )

        # POST /v1/admin/configs/{config_id}/approve - approve configuration
        http_api.add_routes(
            path="/v1/admin/configs/{config_id}/approve",
            methods=[apigwv2.HttpMethod.POST],
            integration=config_admin_integration,
            authorizer=authorizer,
        )

        # POST /v1/admin/configs/{config_id}/reject - reject configuration
        http_api.add_routes(
            path="/v1/admin/configs/{config_id}/reject",
            methods=[apigwv2.HttpMethod.POST],
            integration=config_admin_integration,
            authorizer=authorizer,
        )

        # POST /v1/admin/configs/{config_id}/revoke - revoke configuration
        http_api.add_routes(
            path="/v1/admin/configs/{config_id}/revoke",
            methods=[apigwv2.HttpMethod.POST],
            integration=config_admin_integration,
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
