"""
NetworkingStack: VPC with VPC endpoints for secure AWS service access.

This stack creates:
- VPC with public and private subnets
- VPC endpoints for AWS services (ECR, S3, DynamoDB, etc.)
- Security groups for ECS tasks
- NAT Gateway (optional, can use VPC endpoints instead)

This enables ECS tasks in private subnets to access AWS services
without requiring internet access or NAT Gateway costs.
"""

from aws_cdk import (
    Stack,
    Tags,
)
from aws_cdk import (
    aws_ec2 as ec2,
)
from aws_cdk import (
    aws_ssm as ssm,
)
from constructs import Construct

from .stack_config import CONFIG


class NetworkingStack(Stack):
    """Networking infrastructure with VPC endpoints.
    
    Creates a VPC with the necessary endpoints for ECS tasks to access
    AWS services without internet connectivity.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ========================================
        # VPC with Public and Private Subnets
        # ========================================
        
        self.vpc = ec2.Vpc(
            self,
            "PdfModelsVpc",
            vpc_name=f"{CONFIG.PROJECT_NAME}-vpc",
            # Use 2 AZs for high availability
            max_azs=2,
            # CIDR block
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            # Subnet configuration
            subnet_configuration=[
                # Public subnets for future ALB (if needed)
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,  # 10.0.1.0/24, 10.0.2.0/24
                ),
                # Isolated subnets for ECS tasks (no internet access, VPC endpoints only)
                ec2.SubnetConfiguration(
                    name="Isolated",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,  # 10.0.11.0/24, 10.0.12.0/24
                ),
            ],
            # Enable DNS
            enable_dns_hostnames=True,
            enable_dns_support=True,
            # No NAT Gateways - use VPC endpoints instead for cost optimization
            nat_gateways=0,
        )

        # ========================================
        # Security Group for ECS Tasks
        # ========================================
        
        self.ecs_security_group = ec2.SecurityGroup(
            self,
            "EcsTaskSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS Fargate tasks",
            allow_all_outbound=True,  # Allow all outbound traffic
        )

        # ========================================
        # VPC Endpoints for AWS Services
        # ========================================
        
        # ECR API endpoint (for pulling container images)
        self.ecr_api_endpoint = self.vpc.add_interface_endpoint(
            "EcrApiEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECR,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # ECR Docker endpoint (for pulling container layers)
        self.ecr_docker_endpoint = self.vpc.add_interface_endpoint(
            "EcrDockerEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # S3 endpoint (for accessing S3 buckets)
        self.s3_endpoint = self.vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED)],
        )

        # DynamoDB endpoint (for accessing DynamoDB tables)
        self.dynamodb_endpoint = self.vpc.add_gateway_endpoint(
            "DynamoDbEndpoint",
            service=ec2.GatewayVpcEndpointAwsService.DYNAMODB,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED)],
        )

        # CloudWatch Logs endpoint (for ECS task logging)
        self.logs_endpoint = self.vpc.add_interface_endpoint(
            "LogsEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # SSM endpoint (for parameter store access)
        self.ssm_endpoint = self.vpc.add_interface_endpoint(
            "SsmEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.SSM,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # ECS Agent endpoint (required for EC2 instances in isolated subnets)
        self.ecs_agent_endpoint = self.vpc.add_interface_endpoint(
            "EcsAgentEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECS_AGENT,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # ECS Telemetry endpoint (required for container metrics from EC2)
        self.ecs_telemetry_endpoint = self.vpc.add_interface_endpoint(
            "EcsTelemetryEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECS_TELEMETRY,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # ECS endpoint (for ECS API calls from EC2 instances)
        self.ecs_endpoint = self.vpc.add_interface_endpoint(
            "EcsEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECS,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            security_groups=[self.ecs_security_group],
        )

        # ========================================
        # Export VPC Information to SSM
        # ========================================
        
        # VPC ID
        ssm.StringParameter(
            self,
            "VpcIdParam",
            parameter_name="/pdf-models/networking/vpc-id",
            string_value=self.vpc.vpc_id,
            description="VPC ID for the PDF Models application",
        )

        # Private subnet IDs (for ECS tasks) - now isolated subnets
        isolated_subnet_ids = [subnet.subnet_id for subnet in self.vpc.isolated_subnets]
        ssm.StringParameter(
            self,
            "IsolatedSubnetIdsParam",
            parameter_name="/pdf-models/networking/isolated-subnet-ids",
            string_value=",".join(isolated_subnet_ids),
            description="Comma-separated list of isolated subnet IDs for ECS tasks",
        )

        # Public subnet IDs (for load balancers, NAT gateways)
        public_subnet_ids = [subnet.subnet_id for subnet in self.vpc.public_subnets]
        ssm.StringParameter(
            self,
            "PublicSubnetIdsParam",
            parameter_name="/pdf-models/networking/public-subnet-ids",
            string_value=",".join(public_subnet_ids),
            description="Comma-separated list of public subnet IDs",
        )

        # ECS Security Group ID
        ssm.StringParameter(
            self,
            "EcsSecurityGroupIdParam",
            parameter_name="/pdf-models/networking/ecs-security-group-id",
            string_value=self.ecs_security_group.security_group_id,
            description="Security group ID for ECS tasks",
        )

        # ========================================
        # Tags
        # ========================================
        
        Tags.of(self).add("Project", CONFIG.PROJECT_NAME)
        Tags.of(self).add("Stack", "Networking")
        Tags.of(self).add("Environment", "dev")