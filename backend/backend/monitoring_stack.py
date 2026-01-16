"""
MonitoringStack: CloudWatch dashboards and alarms for operational visibility.

This stack creates monitoring infrastructure for the PDF Models platform.
"""

from aws_cdk import (
    Duration,
    Stack,
)
from aws_cdk import (
    aws_cloudwatch as cloudwatch,
)
from aws_cdk import (
    aws_cloudwatch_actions as cw_actions,
)
from aws_cdk import (
    aws_sns as sns,
)
from aws_cdk import (
    aws_ssm as ssm,
)
from constructs import Construct

from backend.stack_config import CONFIG, MODELS


class MonitoringStack(Stack):
    """Monitoring and observability infrastructure.

    Creates:
    - SNS topic for alert notifications
    - CloudWatch dashboard for system overview
    - Comprehensive alarms for Lambda, DynamoDB, Step Functions, and API Gateway
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get resource names from SSM
        api_id = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/api-v2/id"
        )
        dynamodb_table_name = ssm.StringParameter.value_for_string_parameter(
            self, CONFIG.SSM_DYNAMODB_TABLE_NAME
        )

        # =================================================================
        # SNS Topic for Alerts
        # =================================================================
        alerts_topic = sns.Topic(
            self,
            "AlertsTopic",
            topic_name=f"{CONFIG.PROJECT_NAME}-alerts",
            display_name="PDF Models Alerts",
        )

        # Note: To add email subscription, run:
        # AWS_PROFILE=arch aws sns subscribe --topic-arn <topic-arn> --protocol email --notification-endpoint your@email.com
        # The topic ARN is stored in SSM at /pdf-models/monitoring/alerts-topic-arn

        # Store topic ARN in SSM for other stacks to use
        ssm.StringParameter(
            self,
            "AlertsTopicArn",
            parameter_name="/pdf-models/monitoring/alerts-topic-arn",
            string_value=alerts_topic.topic_arn,
            description="SNS topic ARN for monitoring alerts",
        )

        # Helper to add alarm action
        alarm_action = cw_actions.SnsAction(alerts_topic)

        # =================================================================
        # Lambda Configuration (for alarms)
        # =================================================================
        lambda_functions = [
            {"name": f"{CONFIG.PROJECT_NAME}-submit-job", "timeout_seconds": 30},
            {"name": f"{CONFIG.PROJECT_NAME}-get-job", "timeout_seconds": 30},
            {"name": f"{CONFIG.PROJECT_NAME}-get-upload-url", "timeout_seconds": 10},
        ]

        # =================================================================
        # Dashboard
        # =================================================================
        # Create dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "PdfModelsDashboard",
            dashboard_name=f"{CONFIG.PROJECT_NAME}-overview",
        )

        # API Gateway metrics
        api_requests_widget = cloudwatch.GraphWidget(
            title="API Requests",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ApiGateway",
                    metric_name="Count",
                    dimensions_map={"ApiId": api_id},
                    statistic="Sum",
                    period=Duration.minutes(5),
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ApiGateway",
                    metric_name="4XXError",
                    dimensions_map={"ApiId": api_id},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/ApiGateway",
                    metric_name="5XXError",
                    dimensions_map={"ApiId": api_id},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
        )

        # Lambda metrics
        lambda_metrics_widget = cloudwatch.GraphWidget(
            title="Lambda Performance",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Duration",
                    dimensions_map={
                        "FunctionName": f"{CONFIG.PROJECT_NAME}-submit-job"
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Duration",
                    dimensions_map={"FunctionName": f"{CONFIG.PROJECT_NAME}-get-job"},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={
                        "FunctionName": f"{CONFIG.PROJECT_NAME}-submit-job"
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={"FunctionName": f"{CONFIG.PROJECT_NAME}-get-job"},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
        )

        # Step Functions metrics
        sfn_metrics_widget = cloudwatch.GraphWidget(
            title="Step Functions Executions",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/States",
                    metric_name="ExecutionsStarted",
                    dimensions_map={"StateMachineArn": "*"},
                    statistic="Sum",
                    period=Duration.minutes(5),
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/States",
                    metric_name="ExecutionsFailed",
                    dimensions_map={"StateMachineArn": "*"},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/States",
                    metric_name="ExecutionsSucceeded",
                    dimensions_map={"StateMachineArn": "*"},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
        )

        # ECS/Fargate metrics
        ecs_metrics_widget = cloudwatch.GraphWidget(
            title="Fargate Tasks",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="RunningTaskCount",
                    dimensions_map={
                        "ClusterName": f"{CONFIG.PROJECT_NAME}-marker-cluster"
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "ClusterName": f"{CONFIG.PROJECT_NAME}-marker-cluster"
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="MemoryUtilization",
                    dimensions_map={
                        "ClusterName": f"{CONFIG.PROJECT_NAME}-marker-cluster"
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            api_requests_widget,
            lambda_metrics_widget,
            sfn_metrics_widget,
            ecs_metrics_widget,
        )

        # =================================================================
        # API Gateway Alarms
        # =================================================================

        # API Gateway 5XX errors
        api_5xx_alarm = cloudwatch.Alarm(
            self,
            "Api5xxAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-api-5xx-errors",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="5XXError",
                dimensions_map={"ApiId": api_id},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            alarm_description="API Gateway 5XX errors exceed threshold (>5 errors in 10 min)",
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        api_5xx_alarm.add_alarm_action(alarm_action)

        # API Gateway 4XX errors (high rate indicates client issues or attacks)
        api_4xx_alarm = cloudwatch.Alarm(
            self,
            "Api4xxAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-api-4xx-errors",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="4XXError",
                dimensions_map={"ApiId": api_id},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=50,
            evaluation_periods=2,
            alarm_description="API Gateway 4XX errors exceed threshold (>50 errors in 10 min)",
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        api_4xx_alarm.add_alarm_action(alarm_action)

        # =================================================================
        # Lambda Alarms (Error Rate and Duration)
        # =================================================================

        for lambda_config in lambda_functions:
            fn_name = lambda_config["name"]
            timeout_ms = lambda_config["timeout_seconds"] * 1000
            # Clean name for CloudFormation logical IDs (remove hyphens)
            clean_name = fn_name.replace(f"{CONFIG.PROJECT_NAME}-", "").replace("-", "")

            # Lambda Error Alarm - triggers on any errors
            error_alarm = cloudwatch.Alarm(
                self,
                f"Lambda{clean_name.title()}ErrorAlarm",
                alarm_name=f"{fn_name}-errors",
                metric=cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={"FunctionName": fn_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                threshold=3,
                evaluation_periods=1,
                alarm_description=f"Lambda {fn_name} errors (>3 errors in 5 min)",
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )
            error_alarm.add_alarm_action(alarm_action)

            # Lambda Duration Alarm - approaching timeout (>80% of limit)
            duration_threshold_ms = timeout_ms * 0.8
            duration_alarm = cloudwatch.Alarm(
                self,
                f"Lambda{clean_name.title()}DurationAlarm",
                alarm_name=f"{fn_name}-duration-warning",
                metric=cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Duration",
                    dimensions_map={"FunctionName": fn_name},
                    statistic="p95",  # 95th percentile to catch slowdowns
                    period=Duration.minutes(5),
                ),
                threshold=duration_threshold_ms,
                evaluation_periods=2,
                alarm_description=f"Lambda {fn_name} p95 duration approaching timeout (>{duration_threshold_ms:.0f}ms, timeout={timeout_ms}ms)",
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )
            duration_alarm.add_alarm_action(alarm_action)

            # Lambda Throttles Alarm
            throttle_alarm = cloudwatch.Alarm(
                self,
                f"Lambda{clean_name.title()}ThrottleAlarm",
                alarm_name=f"{fn_name}-throttles",
                metric=cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Throttles",
                    dimensions_map={"FunctionName": fn_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                threshold=1,
                evaluation_periods=1,
                alarm_description=f"Lambda {fn_name} being throttled",
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )
            throttle_alarm.add_alarm_action(alarm_action)

        # =================================================================
        # DynamoDB Alarms
        # =================================================================

        # DynamoDB Read Throttling
        dynamodb_read_throttle_alarm = cloudwatch.Alarm(
            self,
            "DynamoDBReadThrottleAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-dynamodb-read-throttles",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="ReadThrottledRequests",
                dimensions_map={"TableName": dynamodb_table_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            alarm_description="DynamoDB read requests being throttled",
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        dynamodb_read_throttle_alarm.add_alarm_action(alarm_action)

        # DynamoDB Write Throttling
        dynamodb_write_throttle_alarm = cloudwatch.Alarm(
            self,
            "DynamoDBWriteThrottleAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-dynamodb-write-throttles",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="WriteThrottledRequests",
                dimensions_map={"TableName": dynamodb_table_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            alarm_description="DynamoDB write requests being throttled",
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        dynamodb_write_throttle_alarm.add_alarm_action(alarm_action)

        # DynamoDB System Errors
        dynamodb_error_alarm = cloudwatch.Alarm(
            self,
            "DynamoDBSystemErrorAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-dynamodb-system-errors",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="SystemErrors",
                dimensions_map={"TableName": dynamodb_table_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            alarm_description="DynamoDB system errors (AWS-side issues)",
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        dynamodb_error_alarm.add_alarm_action(alarm_action)

        # =================================================================
        # Per-Model Step Functions Alarms
        # =================================================================

        for model_name in MODELS.keys():
            state_machine_name = f"{CONFIG.PROJECT_NAME}-{model_name}"

            # Step Functions failures per model
            sfn_model_alarm = cloudwatch.Alarm(
                self,
                f"SfnFailure{model_name.title().replace('-', '')}Alarm",
                alarm_name=f"{state_machine_name}-failures",
                metric=cloudwatch.Metric(
                    namespace="AWS/States",
                    metric_name="ExecutionsFailed",
                    dimensions_map={
                        "StateMachineArn": f"arn:aws:states:{self.region}:{self.account}:stateMachine:{state_machine_name}"
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                threshold=2,
                evaluation_periods=1,
                alarm_description=f"Step Functions {model_name} executions failing (>2 in 5 min)",
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )
            sfn_model_alarm.add_alarm_action(alarm_action)

            # Step Functions execution time exceeded (for timeout detection)
            sfn_timeout_alarm = cloudwatch.Alarm(
                self,
                f"SfnTimeout{model_name.title().replace('-', '')}Alarm",
                alarm_name=f"{state_machine_name}-execution-time",
                metric=cloudwatch.Metric(
                    namespace="AWS/States",
                    metric_name="ExecutionTime",
                    dimensions_map={
                        "StateMachineArn": f"arn:aws:states:{self.region}:{self.account}:stateMachine:{state_machine_name}"
                    },
                    statistic="p95",
                    period=Duration.minutes(15),
                ),
                # Alert if p95 execution time exceeds 80% of model timeout
                threshold=MODELS[model_name].timeout_minutes * 60 * 1000 * 0.8,
                evaluation_periods=1,
                alarm_description=f"Step Functions {model_name} p95 execution time approaching timeout",
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )
            sfn_timeout_alarm.add_alarm_action(alarm_action)

        # =================================================================
        # Aggregate Step Functions Alarm (all models)
        # =================================================================

        sfn_failure_alarm = cloudwatch.Alarm(
            self,
            "StepFunctionsFailureAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-step-functions-failures-all",
            metric=cloudwatch.Metric(
                namespace="AWS/States",
                metric_name="ExecutionsFailed",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=1,
            alarm_description="Step Functions total failures across all models (>5 in 5 min)",
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        sfn_failure_alarm.add_alarm_action(alarm_action)

        # =================================================================
        # Export SSM Parameters
        # =================================================================

        # Export dashboard URL to SSM
        ssm.StringParameter(
            self,
            "DashboardUrl",
            parameter_name="/pdf-models/monitoring/dashboard-url",
            string_value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={CONFIG.PROJECT_NAME}-overview",
            description="CloudWatch dashboard URL",
        )
