"""
MonitoringStack: CloudWatch dashboards and alarms for operational visibility.

This stack creates monitoring infrastructure for the PDF Models platform.
"""

from aws_cdk import (
    Stack,
    Duration,
    aws_cloudwatch as cloudwatch,
    aws_ssm as ssm,
)
from constructs import Construct

from backend.stack_config import CONFIG


class MonitoringStack(Stack):
    """Monitoring and observability infrastructure.

    Creates:
    - CloudWatch dashboard for system overview
    - Alarms for critical metrics
    - Log insights queries for troubleshooting
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get resource names from SSM
        api_id = ssm.StringParameter.value_for_string_parameter(
            self, "/pdf-models/api/id"
        )
        
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
                    dimensions_map={"FunctionName": f"{CONFIG.PROJECT_NAME}-submit-job"},
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
                    dimensions_map={"FunctionName": f"{CONFIG.PROJECT_NAME}-submit-job"},
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
                    dimensions_map={"ClusterName": f"{CONFIG.PROJECT_NAME}-marker-cluster"},
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="CPUUtilization",
                    dimensions_map={"ClusterName": f"{CONFIG.PROJECT_NAME}-marker-cluster"},
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="MemoryUtilization",
                    dimensions_map={"ClusterName": f"{CONFIG.PROJECT_NAME}-marker-cluster"},
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

        # Create critical alarms
        
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
            alarm_description="API Gateway 5XX errors exceed threshold",
        )

        # Step Functions failures
        sfn_failure_alarm = cloudwatch.Alarm(
            self,
            "StepFunctionsFailureAlarm",
            alarm_name=f"{CONFIG.PROJECT_NAME}-step-functions-failures",
            metric=cloudwatch.Metric(
                namespace="AWS/States",
                metric_name="ExecutionsFailed",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=3,
            evaluation_periods=1,
            alarm_description="Step Functions executions failing",
        )

        # Export dashboard URL to SSM
        ssm.StringParameter(
            self,
            "DashboardUrl",
            parameter_name="/pdf-models/monitoring/dashboard-url",
            string_value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={CONFIG.PROJECT_NAME}-overview",
            description="CloudWatch dashboard URL",
        )