"""
CoreInfrastructureStack: Core application infrastructure.

Resources:
- S3 bucket for document storage (inputs + results)
- DynamoDB table for job metadata tracking
- Cognito User Pool for authentication
- Cognito Identity Pool for AWS credentials (scoped S3 access)
- IAM roles for authenticated users

Change Frequency: Occasional
Replaceability: Moderate (contains stateful data)
"""

from aws_cdk import (
    Stack,
    RemovalPolicy,
    Duration,
    Aws,
    Tags,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_cognito as cognito,
    aws_iam as iam,
    aws_ssm as ssm,
)
from constructs import Construct

from .stack_config import CONFIG


class CoreInfrastructureStack(Stack):
    """Core infrastructure stack.

    This stack contains the core AWS resources for the application:
    - Storage (S3 for documents)
    - Database (DynamoDB for job tracking)
    - Authentication & Authorization (Cognito)

    All resources export their identifiers to SSM Parameter Store.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ========================================
        # S3 Bucket for Document Storage
        # ========================================

        # Use Aws.ACCOUNT_ID pseudo-parameter for global uniqueness
        # Never hardcode account ID - resolved at synthesis time from AWS_PROFILE
        bucket_name = f"{CONFIG.S3_BUCKET_NAME_PREFIX}-{Aws.ACCOUNT_ID}"

        docs_bucket = s3.Bucket(
            self,
            "DocsBucket",
            bucket_name=bucket_name,
            # MVP: Allow deletion of bucket and contents
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            # Encryption: Server-side encryption with S3-managed keys (free)
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Security: Require HTTPS for all requests
            enforce_ssl=True,
            # CORS: Enable for browser uploads (frontend will upload directly to S3)
            cors=[
                s3.CorsRule(
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.PUT,
                        s3.HttpMethods.POST,
                    ],
                    # MVP: Allow all origins. Tighten to frontend domain in production.
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    # Expose ETag for upload verification
                    exposed_headers=["ETag"],
                    max_age=3600,  # Cache preflight for 1 hour
                )
            ],
            # Lifecycle: Auto-delete objects after 7 days to control costs
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteAfter7Days",
                    enabled=True,
                    expiration=Duration.days(CONFIG.S3_EXPIRATION_DAYS),
                )
            ],
            # Versioning: Not needed for MVP (users should save results)
            versioned=False,
            # Public access: Block all (users access via scoped IAM credentials)
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
        )

        # Export bucket name to SSM
        ssm.StringParameter(
            self,
            "S3BucketNameParam",
            parameter_name=CONFIG.SSM_S3_BUCKET_NAME,
            string_value=docs_bucket.bucket_name,
            description="S3 bucket name for PDF documents and results",
        )

        # ========================================
        # DynamoDB Table for Job Tracking
        # ========================================

        jobs_table = dynamodb.Table(
            self,
            "JobsTable",
            table_name=CONFIG.DYNAMODB_TABLE_NAME,
            # Partition key: job_id (UUID)
            partition_key=dynamodb.Attribute(
                name=CONFIG.DYNAMODB_PK,
                type=dynamodb.AttributeType.STRING,
            ),
            # Billing: On-demand (pay-per-request, auto-scaling)
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            # MVP: Allow deletion
            removal_policy=RemovalPolicy.DESTROY,
            # Point-in-time recovery: Off for MVP (cost saving)
            point_in_time_recovery_specification=dynamodb.PointInTimeRecoverySpecification(
                point_in_time_recovery_enabled=False
            ),
            # Encryption: AWS-managed keys (default, free)
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )

        # Global Secondary Index: Query jobs by user_id, sorted by created_at
        jobs_table.add_global_secondary_index(
            index_name=CONFIG.DYNAMODB_GSI_NAME,
            partition_key=dynamodb.Attribute(
                name=CONFIG.DYNAMODB_GSI_PK,
                type=dynamodb.AttributeType.STRING,
            ),
            sort_key=dynamodb.Attribute(
                name=CONFIG.DYNAMODB_GSI_SK,
                type=dynamodb.AttributeType.STRING,
            ),
            # Project all attributes to GSI (simplifies queries)
            projection_type=dynamodb.ProjectionType.ALL,
        )

        # Export table name to SSM
        ssm.StringParameter(
            self,
            "DynamoDbTableNameParam",
            parameter_name=CONFIG.SSM_DYNAMODB_TABLE_NAME,
            string_value=jobs_table.table_name,
            description="DynamoDB table name for job metadata",
        )

        # ========================================
        # Cognito User Pool (Authentication)
        # ========================================

        user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=CONFIG.COGNITO_USER_POOL_NAME,
            # Self-registration: Disabled for MVP (admin creates users)
            self_sign_up_enabled=False,
            # Sign-in: Email as username (more user-friendly)
            sign_in_aliases=cognito.SignInAliases(
                email=True,
                username=False,
            ),
            # Auto-verify: Email verification required
            auto_verify=cognito.AutoVerifiedAttrs(
                email=True,
            ),
            # Password policy: Moderate security for MVP
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=False,  # Easier for MVP
            ),
            # MFA: Off for MVP (enable later for production)
            mfa=cognito.Mfa.OFF,
            # Account recovery: Email only
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            # User invitation message
            user_invitation=cognito.UserInvitationConfig(
                email_subject="Welcome to PDF Models",
                email_body="Your username is {username} and temporary password is {####}",
            ),
            # Standard attributes
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(
                    required=True,
                    mutable=True,
                ),
            ),
            # MVP: Allow deletion
            removal_policy=RemovalPolicy.DESTROY,
        )

        # App client for API access
        user_pool_client = user_pool.add_client(
            "ApiClient",
            # Auth flows: Username/password and SRP
            auth_flows=cognito.AuthFlow(
                user_password=True,  # Allow username/password auth
                user_srp=True,  # Secure Remote Password protocol
            ),
            # Public client: No secret (frontend apps can't securely store secrets)
            generate_secret=False,
            # Token validity
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1),
            refresh_token_validity=Duration.days(30),
            # Disable OAuth flows for API Gateway JWT authorization
            o_auth=None,
        )

        # Export User Pool ID to SSM
        ssm.StringParameter(
            self,
            "CognitoUserPoolIdParam",
            parameter_name=CONFIG.SSM_COGNITO_USER_POOL_ID,
            string_value=user_pool.user_pool_id,
            description="Cognito User Pool ID",
        )

        # Export User Pool Client ID to SSM
        ssm.StringParameter(
            self,
            "CognitoUserPoolClientIdParam",
            parameter_name=CONFIG.SSM_COGNITO_USER_POOL_CLIENT_ID,
            string_value=user_pool_client.user_pool_client_id,
            description="Cognito User Pool Client ID for API access",
        )

        # ========================================
        # S3 Bucket ARN Export for Lambda Pre-signed URLs
        # ========================================
        # Note: Cognito Identity Pool removed - using pre-signed URLs for S3 access
        # Lambda functions will generate time-limited pre-signed URLs for uploads/downloads
        # This simplifies authentication and eliminates JWT/AWS credential confusion

        ssm.StringParameter(
            self,
            "S3BucketArnParam",
            parameter_name="/pdf-models/core/s3-bucket-arn",
            string_value=docs_bucket.bucket_arn,
            description="S3 bucket ARN for Lambda IAM permissions",
        )

        # ========================================
        # Tags
        # ========================================

        Tags.of(self).add("Project", CONFIG.PROJECT_NAME)
        Tags.of(self).add("Stack", "CoreInfrastructure")
        Tags.of(self).add("Environment", "dev")
