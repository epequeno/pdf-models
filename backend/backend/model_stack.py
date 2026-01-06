"""
ModelStack: Generic ECS cluster, task definition, and Step Functions orchestration.

This stack creates the compute infrastructure for processing PDFs with any model.
It is parameterized by ModelConfig to support multiple models (marker, dolphin, etc).

Supports two launch types:
- Fargate (default): Serverless containers, CPU-only
- EC2 with GPU: Auto Scaling Group with GPU instances (g4dn.xlarge)
"""

from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
)
from aws_cdk import (
    aws_autoscaling as autoscaling,
)
from aws_cdk import (
    aws_dynamodb as dynamodb,
)
from aws_cdk import (
    aws_ec2 as ec2,
)
from aws_cdk import (
    aws_ecs as ecs,
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
    aws_ssm as ssm,
)
from aws_cdk import (
    aws_stepfunctions as sfn,
)
from aws_cdk import (
    aws_stepfunctions_tasks as tasks,
)
from constructs import Construct

from backend.stack_config import CONFIG, ModelConfig


class ModelStack(Stack):
    """Generic model processing infrastructure.

    Creates:
    - ECS Cluster for container tasks
    - Task Definition (Fargate or EC2 based on model_config.use_gpu)
    - For GPU models: Auto Scaling Group with GPU instances + Capacity Provider
    - Step Functions state machine for orchestration
    - IAM roles for task execution and task runtime

    All resources are parameterized by the ModelConfig passed in.
    """

    def __init__(
        self, scope: Construct, construct_id: str, model_config: ModelConfig, **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        model_name = model_config.name

        # Get dependencies from SSM (created by other stacks)
        ecr_repo_uri = ssm.StringParameter.value_for_string_parameter(
            self, f"/pdf-models/foundation/ecr-repo-uri-{model_name}"
        )
        s3_bucket_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_S3_BUCKET_NAME
        )
        dynamodb_table_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_DYNAMODB_TABLE_NAME
        )
        # Get the image tag from SSM (updated by CodeBuild after each build)
        image_tag = ssm.StringParameter.value_for_string_parameter(
            self, f"/pdf-models/cicd/{model_name}-image-tag"
        )

        # VPC and networking information from deployed NetworkingStack
        # These values are from the deployed NetworkingStack SSM parameters
        vpc_id = "vpc-0dde40d8bf398e14c"
        isolated_subnet_ids = ["subnet-04a204ceff9880907", "subnet-0c304190e2352482f"]
        ecs_security_group_id = "sg-0a8df0846d1a6fc96"

        # Import security group
        ecs_security_group = ec2.SecurityGroup.from_security_group_id(
            self, "ImportedSecurityGroup", ecs_security_group_id
        )

        # Import VPC with attributes (avoids context lookup which requires env-aware synthesis)
        vpc = ec2.Vpc.from_vpc_attributes(
            self,
            "ImportedVpc",
            vpc_id=vpc_id,
            availability_zones=["us-east-1a", "us-east-1b"],  # Must match subnet AZs
            isolated_subnet_ids=isolated_subnet_ids,
        )

        # Create ECS cluster
        # Note: VPC is not specified - cluster uses default VPC for EC2 capacity providers
        # The ASG explicitly specifies the isolated subnets
        cluster = ecs.Cluster(
            self,
            f"{model_name.title()}Cluster",
            cluster_name=f"{CONFIG.PROJECT_NAME}-{model_name}-cluster",
            container_insights_v2=ecs.ContainerInsights.ENHANCED,
        )

        # Track capacity provider name for GPU models (used in Step Functions)
        capacity_provider_name = None

        # Create task execution role (used by ECS to pull image, write logs)
        execution_role = iam.Role(
            self,
            f"{model_name.title()}TaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )

        # Create task role (used by container at runtime)
        task_role = iam.Role(
            self,
            f"{model_name.title()}TaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )

        # Grant S3 permissions to task role
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:PutObject"],
                resources=[f"arn:aws:s3:::{s3_bucket_name}/*"],
            )
        )

        # Also grant bucket-level permissions for ListBucket (needed for some S3 operations)
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:ListBucket"],
                resources=[f"arn:aws:s3:::{s3_bucket_name}"],
            )
        )

        # Grant DynamoDB permissions to task role
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:UpdateItem"],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{dynamodb_table_name}"
                ],
            )
        )

        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            f"{model_name.title()}TaskLogGroup",
            log_group_name=f"/ecs/{CONFIG.PROJECT_NAME}-{model_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create task definition based on launch type (GPU vs Fargate)
        if model_config.use_gpu:
            # ========== EC2 GPU Path ==========

            # Create instance role for EC2 (ECS agent communication)
            instance_role = iam.Role(
                self,
                f"{model_name.title()}InstanceRole",
                assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "service-role/AmazonEC2ContainerServiceforEC2Role"
                    ),
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "AmazonSSMManagedInstanceCore"  # For SSM access in isolated subnets
                    ),
                ],
            )

            # Create Auto Scaling Group with GPU instances
            asg = autoscaling.AutoScalingGroup(
                self,
                f"{model_name.title()}Asg",
                auto_scaling_group_name=f"{CONFIG.PROJECT_NAME}-{model_name}-asg",
                vpc=vpc,
                vpc_subnets=ec2.SubnetSelection(
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
                ),
                instance_type=ec2.InstanceType(model_config.instance_type),
                machine_image=ecs.EcsOptimizedImage.amazon_linux2(
                    hardware_type=ecs.AmiHardwareType.GPU
                ),
                min_capacity=model_config.min_capacity,
                max_capacity=model_config.max_capacity,
                security_group=ecs_security_group,
                role=instance_role,
                spot_price=str(0.20) if model_config.spot_enabled else None,  # ~25% above typical spot
            )

            # Add user data to configure ECS agent
            asg.add_user_data(
                f"echo ECS_CLUSTER={cluster.cluster_name} >> /etc/ecs/ecs.config",
                "echo ECS_ENABLE_GPU_SUPPORT=true >> /etc/ecs/ecs.config",
            )

            # Create Capacity Provider
            capacity_provider = ecs.AsgCapacityProvider(
                self,
                f"{model_name.title()}CapacityProvider",
                capacity_provider_name=f"{CONFIG.PROJECT_NAME}-{model_name}-cp",
                auto_scaling_group=asg,
                enable_managed_scaling=True,
                enable_managed_termination_protection=False,  # Allow scale-in
                target_capacity_percent=100,
            )
            cluster.add_asg_capacity_provider(capacity_provider)
            capacity_provider_name = capacity_provider.capacity_provider_name

            # Create EC2 Task Definition (not Fargate)
            task_definition = ecs.Ec2TaskDefinition(
                self,
                f"{model_name.title()}TaskDefinition",
                family=f"{CONFIG.PROJECT_NAME}-{model_name}",
                network_mode=ecs.NetworkMode.AWS_VPC,  # Required for isolated subnets
                execution_role=execution_role,
                task_role=task_role,
            )

            # Add container with GPU
            container = task_definition.add_container(
                model_name,
                container_name=model_name,
                image=ecs.ContainerImage.from_registry(f"{ecr_repo_uri}:{image_tag}"),
                memory_limit_mib=model_config.memory_mib,
                cpu=model_config.cpu,
                gpu_count=model_config.gpu_count,  # GPU resource requirement
                logging=ecs.LogDriver.aws_logs(
                    stream_prefix=model_name,
                    log_group=log_group,
                ),
                environment={
                    "S3_BUCKET": s3_bucket_name,
                    "DYNAMODB_TABLE": dynamodb_table_name,
                    "AWS_DEFAULT_REGION": self.region,  # Required for EC2 (Fargate infers from task metadata)
                },
            )
        else:
            # ========== Fargate Path (existing) ==========

            # Create Fargate task definition with model-specific resources
            task_definition = ecs.FargateTaskDefinition(
                self,
                f"{model_name.title()}TaskDefinition",
                family=f"{CONFIG.PROJECT_NAME}-{model_name}",
                cpu=model_config.cpu,
                memory_limit_mib=model_config.memory_mib,
                execution_role=execution_role,
                task_role=task_role,
            )

            # Add container to task definition
            container = task_definition.add_container(
                model_name,
                container_name=model_name,
                image=ecs.ContainerImage.from_registry(f"{ecr_repo_uri}:{image_tag}"),
                logging=ecs.LogDriver.aws_logs(
                    stream_prefix=model_name,
                    log_group=log_group,
                ),
                environment={
                    "S3_BUCKET": s3_bucket_name,
                    "DYNAMODB_TABLE": dynamodb_table_name,
                },
            )

        # Export task definition ARN to SSM
        ssm.StringParameter(
            self,
            f"{model_name.title()}TaskDefinitionArnParam",
            parameter_name=f"/pdf-models/{model_name}/task-definition-arn",
            string_value=task_definition.task_definition_arn,
            description=f"{model_name.title()} Fargate task definition ARN",
        )

        # Export cluster ARN to SSM
        ssm.StringParameter(
            self,
            f"{model_name.title()}ClusterArnParam",
            parameter_name=f"/pdf-models/{model_name}/cluster-arn",
            string_value=cluster.cluster_arn,
            description=f"{model_name.title()} ECS cluster ARN",
        )

        # Create Step Functions role
        sfn_role = iam.Role(
            self,
            f"{model_name.title()}StateMachineRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
        )

        # Create a simple Lambda function to resolve the current task definition ARN
        # This eliminates all caching issues by reading from SSM at execution time
        resolve_lambda = lambda_.Function(
            self,
            "ResolveTaskDefLambda",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.handler",
            code=lambda_.Code.from_inline(f"""
import boto3

def handler(event, context):
    ssm = boto3.client('ssm')

    # Get the current task definition ARN from SSM
    response = ssm.get_parameter(Name='/pdf-models/{model_name}/task-definition-arn')
    task_def_arn = response['Parameter']['Value']

    # Return the original event with the resolved task definition ARN
    return {{
        **event,
        'task_definition_arn': task_def_arn
    }}
            """),
            timeout=Duration.seconds(30),
        )

        # Grant SSM read permissions
        resolve_lambda.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ssm:GetParameter"],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/pdf-models/{model_name}/task-definition-arn"
                ],
            )
        )

        # Grant Lambda invoke permissions to Step Functions
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[resolve_lambda.function_arn],
            )
        )
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ecs:RunTask"],
                resources=[
                    # Use wildcard to allow any revision of the task definition family
                    f"arn:aws:ecs:{self.region}:{self.account}:task-definition/{CONFIG.PROJECT_NAME}-{model_name}:*",
                    f"arn:aws:ecs:{self.region}:{self.account}:task-definition/{CONFIG.PROJECT_NAME}-{model_name}",
                ],
            )
        )

        # Grant PassRole for execution and task roles
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[
                    execution_role.role_arn,
                    task_role.role_arn,
                ],
            )
        )

        # Grant ECS DescribeTasks and StopTask (for .sync)
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ecs:DescribeTasks", "ecs:StopTask"],
                resources=["*"],
            )
        )

        # Grant DynamoDB permissions to Step Functions (for error handling)
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:UpdateItem"],
                resources=[
                    f"arn:aws:dynamodb:{self.region}:{self.account}:table/{dynamodb_table_name}"
                ],
            )
        )

        # Grant EventBridge permissions for task state changes
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["events:PutTargets", "events:PutRule", "events:DescribeRule"],
                resources=[
                    f"arn:aws:events:{self.region}:{self.account}:rule/StepFunctionsGetEventsForECSTaskRule"
                ],
            )
        )

        # Import the DynamoDB table for error handling
        jobs_table = dynamodb.Table.from_table_name(
            self,
            "JobsTable",
            dynamodb_table_name,
        )

        # Create DynamoDB update task for job status (unused currently but keeping for future error handling)
        update_job_status = tasks.DynamoUpdateItem(
            self,
            "UpdateJobStatus",
            table=jobs_table,
            key={
                "job_id": tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$.job_id")
                )
            },
            update_expression="SET #status = :status, completed_at = :completed_at",
            expression_attribute_names={"#status": "status"},
            expression_attribute_values={
                ":status": tasks.DynamoAttributeValue.from_string("failed"),
                ":completed_at": tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.State.EnteredTime")
                ),
            },
            result_path=sfn.JsonPath.DISCARD,
        )

        # Step 1: Resolve the current task definition ARN from SSM
        resolve_task_def = tasks.LambdaInvoke(
            self,
            "ResolveTaskDefinition",
            lambda_function=resolve_lambda,
            comment="Get current task definition ARN from SSM to avoid caching",
            payload_response_only=True,
        )

        # Step 2: Use the resolved ARN in a custom ECS RunTask state
        # Build different parameters for EC2 vs Fargate
        if model_config.use_gpu:
            # EC2 with GPU: Use CapacityProviderStrategy instead of LaunchType
            run_task_params = {
                "Cluster": cluster.cluster_arn,
                "TaskDefinition.$": "$.task_definition_arn",
                "CapacityProviderStrategy": [
                    {
                        "CapacityProvider": capacity_provider_name,
                        "Weight": 1,
                    }
                ],
                "NetworkConfiguration": {
                    "AwsvpcConfiguration": {
                        "Subnets": isolated_subnet_ids,
                        "SecurityGroups": [ecs_security_group_id],
                    }
                },
                "Overrides": {
                    "ContainerOverrides": [
                        {
                            "Name": model_name,
                            "Environment": [
                                {"Name": "JOB_ID", "Value.$": "$.job_id"},
                                {"Name": "S3_INPUT_KEY", "Value.$": "$.s3_input_key"},
                                {"Name": "S3_BUCKET", "Value": s3_bucket_name},
                                {"Name": "DYNAMODB_TABLE", "Value": dynamodb_table_name},
                                {"Name": "AWS_DEFAULT_REGION", "Value": self.region},
                            ],
                        }
                    ]
                },
            }
        else:
            # Fargate: Use LaunchType
            run_task_params = {
                "Cluster": cluster.cluster_arn,
                "TaskDefinition.$": "$.task_definition_arn",
                "LaunchType": "FARGATE",
                "PlatformVersion": "LATEST",
                "NetworkConfiguration": {
                    "AwsvpcConfiguration": {
                        "Subnets": isolated_subnet_ids,
                        "SecurityGroups": [ecs_security_group_id],
                        "AssignPublicIp": "DISABLED",
                    }
                },
                "Overrides": {
                    "ContainerOverrides": [
                        {
                            "Name": model_name,
                            "Environment": [
                                {"Name": "JOB_ID", "Value.$": "$.job_id"},
                                {"Name": "S3_INPUT_KEY", "Value.$": "$.s3_input_key"},
                                {"Name": "S3_BUCKET", "Value": s3_bucket_name},
                                {"Name": "DYNAMODB_TABLE", "Value": dynamodb_table_name},
                            ],
                        }
                    ]
                },
            }

        run_task_state = {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.sync",
            "Parameters": run_task_params,
            "Retry": [
                {
                    "ErrorEquals": ["States.TaskFailed"],
                    "IntervalSeconds": 30,
                    "MaxAttempts": 3,
                    "BackoffRate": 2.0,
                }
            ],
            "ResultPath": None,
            "End": True,
        }

        run_task = sfn.CustomState(
            self, f"Run{model_name.title()}Task", state_json=run_task_state
        )

        # Create state machine definition with dynamic task definition resolution
        definition = resolve_task_def.next(run_task)

        # Create state machine with model-specific timeout
        state_machine = sfn.StateMachine(
            self,
            f"{model_name.title()}StateMachine",
            state_machine_name=f"{CONFIG.PROJECT_NAME}-{model_name}",
            definition_body=sfn.DefinitionBody.from_chainable(definition),
            role=sfn_role,
            timeout=Duration.minutes(model_config.timeout_minutes),
            comment=f"{model_name.title()} PDF processing with dynamic task definition resolution",
        )

        # Export state machine ARN to SSM
        ssm.StringParameter(
            self,
            f"{model_name.title()}StateMachineArnParam",
            parameter_name=f"/pdf-models/{model_name}/state-machine-arn",
            string_value=state_machine.state_machine_arn,
            description=f"{model_name.title()} Step Functions state machine ARN",
        )
