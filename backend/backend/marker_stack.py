"""
MarkerStack: ECS cluster, Fargate task definition, and Step Functions orchestration.

This stack creates the compute infrastructure for processing PDFs with the Marker model.
"""

from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_ecs as ecs,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as tasks,
    aws_dynamodb as dynamodb,
    aws_ssm as ssm,
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

        # Create ECS cluster
        cluster = ecs.Cluster(
            self,
            "MarkerCluster",
            cluster_name=f"{CONFIG.PROJECT_NAME}-marker-cluster",
            container_insights_v2=ecs.ContainerInsights.ENHANCED,
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
            image=ecs.ContainerImage.from_registry(f"{ecr_repo_uri}:latest"),
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

        # Grant ECS RunTask permissions to Step Functions
        sfn_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ecs:RunTask"],
                resources=[task_definition.task_definition_arn],
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
            expression_attribute_names={
                "#status": "status"
            },
            expression_attribute_values={
                ":status": tasks.DynamoAttributeValue.from_string("failed"),
                ":completed_at": tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.State.EnteredTime")
                )
            },
            result_path=sfn.JsonPath.DISCARD,
        )

        # Create ECS RunTask integration with error handling
        run_task = tasks.EcsRunTask(
            self,
            "RunMarkerTask",
            integration_pattern=sfn.IntegrationPattern.RUN_JOB,
            cluster=cluster,
            task_definition=task_definition,
            launch_target=tasks.EcsFargateLaunchTarget(
                platform_version=ecs.FargatePlatformVersion.LATEST,
            ),
            container_overrides=[
                tasks.ContainerOverride(
                    container_definition=container,
                    environment=[
                        tasks.TaskEnvironmentVariable(
                            name="JOB_ID",
                            value=sfn.JsonPath.string_at("$.job_id"),
                        ),
                        tasks.TaskEnvironmentVariable(
                            name="S3_INPUT_KEY",
                            value=sfn.JsonPath.string_at("$.s3_input_key"),
                        ),
                    ],
                )
            ],
            result_path=sfn.JsonPath.DISCARD,
        ).add_retry(
            # Retry on service exceptions (temporary failures)
            errors=["States.TaskFailed"],
            interval=Duration.seconds(30),
            max_attempts=3,
            backoff_rate=2.0,
        ).add_catch(
            # Catch all errors and update job status to failed
            update_job_status,
            errors=["States.ALL"],
            result_path="$.error",
        )

        # Create success state
        success = sfn.Succeed(self, "ProcessingComplete")

        # Create state machine definition with error handling
        definition = run_task.next(success)

        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "MarkerStateMachine",
            state_machine_name=f"{CONFIG.PROJECT_NAME}-marker",
            definition_body=sfn.DefinitionBody.from_chainable(definition),
            role=sfn_role,
            timeout=Duration.hours(1),
        )

        # Export state machine ARN to SSM
        ssm.StringParameter(
            self,
            "MarkerStateMachineArnParam",
            parameter_name="/pdf-models/marker/state-machine-arn",
            string_value=state_machine.state_machine_arn,
            description="Marker Step Functions state machine ARN",
        )
