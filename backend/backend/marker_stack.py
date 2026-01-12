"""
MarkerStack: ECS cluster, Fargate task definition, and Step Functions orchestration.

This stack creates the compute infrastructure for processing PDFs with the Marker model.
"""

from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
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

from backend.stack_config import CONFIG


class MarkerStack(Stack):
    """Marker processing infrastructure.

    Creates:
    - ECS Cluster for Fargate tasks
    - Fargate Task Definition for Marker container
    - Step Functions state machine for orchestration
    - IAM roles for task execution and task runtime
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get dependencies from SSM (created by other stacks)
        ecr_repo_uri = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_ECR_MARKER_URI
        )
        s3_bucket_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_S3_BUCKET_NAME
        )
        dynamodb_table_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_DYNAMODB_TABLE_NAME
        )
        # Get the image tag from SSM (updated by CodeBuild after each build)
        image_tag = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_MARKER_IMAGE_TAG
        )
        
        # VPC and networking information from deployed NetworkingStack
        # These values are from the deployed NetworkingStack SSM parameters
        vpc_id = "vpc-0dde40d8bf398e14c"
        isolated_subnet_ids = ["subnet-04a204ceff9880907", "subnet-0c304190e2352482f"]
        ecs_security_group_id = "sg-0a8df0846d1a6fc96"

        # Create ECS cluster with Fargate Spot capacity provider for cost savings
        # The actual networking will be specified in the Step Functions task definition
        cluster = ecs.Cluster(
            self,
            "MarkerCluster",
            cluster_name=f"{CONFIG.PROJECT_NAME}-marker-cluster",
            container_insights_v2=ecs.ContainerInsights.ENHANCED,
            enable_fargate_capacity_providers=True,
        )

        # Create task execution role (used by ECS to pull image, write logs)
        execution_role = iam.Role(
            self,
            "MarkerTaskExecutionRole",
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
            "MarkerTaskRole",
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
            "MarkerTaskLogGroup",
            log_group_name=f"/ecs/{CONFIG.PROJECT_NAME}-marker",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Fargate task definition
        task_definition = ecs.FargateTaskDefinition(
            self,
            "MarkerTaskDefinition",
            family=f"{CONFIG.PROJECT_NAME}-marker",
            cpu=2048,  # 2 vCPU
            memory_limit_mib=8192,  # 8 GB
            execution_role=execution_role,
            task_role=task_role,
        )

        # Add container to task definition
        container = task_definition.add_container(
            "marker",
            container_name="marker",
            image=ecs.ContainerImage.from_registry(f"{ecr_repo_uri}:{image_tag}"),
            logging=ecs.LogDriver.aws_logs(
                stream_prefix="marker",
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
            "MarkerTaskDefinitionArnParam",
            parameter_name="/pdf-models/marker/task-definition-arn",
            string_value=task_definition.task_definition_arn,
            description="Marker Fargate task definition ARN",
        )

        # Export cluster ARN to SSM
        ssm.StringParameter(
            self,
            "MarkerClusterArnParam",
            parameter_name="/pdf-models/marker/cluster-arn",
            string_value=cluster.cluster_arn,
            description="Marker ECS cluster ARN",
        )

        # Create Step Functions role
        sfn_role = iam.Role(
            self,
            "MarkerStateMachineRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
        )

        # Create a simple Lambda function to resolve the current task definition ARN
        # This eliminates all caching issues by reading from SSM at execution time
        resolve_lambda = lambda_.Function(
            self,
            "ResolveTaskDefLambda",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.handler",
            code=lambda_.Code.from_inline("""
import boto3

def handler(event, context):
    ssm = boto3.client('ssm')
    
    # Get the current task definition ARN from SSM
    response = ssm.get_parameter(Name='/pdf-models/marker/task-definition-arn')
    task_def_arn = response['Parameter']['Value']
    
    # Return the original event with the resolved task definition ARN
    return {
        **event,
        'task_definition_arn': task_def_arn
    }
            """),
            timeout=Duration.seconds(30),
        )

        # Grant SSM read permissions
        resolve_lambda.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ssm:GetParameter"],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/pdf-models/marker/task-definition-arn"
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
                    f"arn:aws:ecs:{self.region}:{self.account}:task-definition/{CONFIG.PROJECT_NAME}-marker:*",
                    f"arn:aws:ecs:{self.region}:{self.account}:task-definition/{CONFIG.PROJECT_NAME}-marker",
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

        # Create DynamoDB update task for job status
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
        # Uses Fargate Spot for ~70% cost savings on interruptible workloads
        run_task_state = {
            "Type": "Task",
            "Resource": "arn:aws:states:::ecs:runTask.sync",
            "Parameters": {
                "Cluster": cluster.cluster_arn,
                "TaskDefinition.$": "$.task_definition_arn",
                "CapacityProviderStrategy": [
                    {
                        "CapacityProvider": "FARGATE_SPOT",
                        "Weight": 1,
                        "Base": 0
                    }
                ],
                "PlatformVersion": "LATEST",
                "NetworkConfiguration": {
                    "AwsvpcConfiguration": {
                        "Subnets": isolated_subnet_ids,
                        "SecurityGroups": [ecs_security_group_id],
                        "AssignPublicIp": "DISABLED"
                    }
                },
                "Overrides": {
                    "ContainerOverrides": [
                        {
                            "Name": "marker",
                            "Environment": [
                                {"Name": "JOB_ID", "Value.$": "$.job_id"},
                                {"Name": "S3_INPUT_KEY", "Value.$": "$.s3_input_key"},
                                {"Name": "S3_BUCKET", "Value": s3_bucket_name},
                                {"Name": "DYNAMODB_TABLE", "Value": dynamodb_table_name}
                            ]
                        }
                    ]
                }
            },
            "Retry": [
                {
                    "ErrorEquals": ["States.TaskFailed"],
                    "IntervalSeconds": 30,
                    "MaxAttempts": 3,
                    "BackoffRate": 2.0
                }
            ],
            "ResultPath": None,
            "End": True
        }

        run_task = sfn.CustomState(
            self,
            "RunMarkerTask",
            state_json=run_task_state
        )

        # Create state machine definition with dynamic task definition resolution
        definition = resolve_task_def.next(run_task)

        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "MarkerStateMachine",
            state_machine_name=f"{CONFIG.PROJECT_NAME}-marker",
            definition_body=sfn.DefinitionBody.from_chainable(definition),
            role=sfn_role,
            timeout=Duration.hours(1),
            comment="Marker PDF processing with dynamic task definition resolution to eliminate caching",
        )

        # Export state machine ARN to SSM
        ssm.StringParameter(
            self,
            "MarkerStateMachineArnParam",
            parameter_name="/pdf-models/marker/state-machine-arn",
            string_value=state_machine.state_machine_arn,
            description="Marker Step Functions state machine ARN",
        )
