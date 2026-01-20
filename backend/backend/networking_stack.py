"""
NetworkingStack: VPC with public subnets for ECS tasks.

This stack creates:
- VPC with public subnets only (cost-optimized)
- Gateway VPC endpoints for S3 and DynamoDB (free)
- Restrictive security group for ECS tasks (egress-only, no inbound)

ECS tasks run in public subnets with public IPs for AWS service access.
This eliminates ~$51/month in interface endpoint costs while maintaining
security through restrictive security groups (no inbound traffic allowed).

GPU instances only run when processing jobs (ASG min_capacity=0), so
exposure to public internet is minimal and controlled.
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
    """Cost-optimized networking with public subnets.
    
    Creates a VPC with public subnets for ECS tasks. Tasks access AWS
    services via public internet with restrictive security groups
    (egress-only, no inbound traffic allowed).
    
    This saves ~$51/month compared to interface VPC endpoints while
    maintaining security - ECS tasks never accept inbound connections.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ========================================
        # VPC with Public Subnets Only
        # ========================================
        
        self.vpc = ec2.Vpc(
            self,
            "PdfModelsVpc",
            vpc_name=f"{CONFIG.PROJECT_NAME}-vpc",
            # Use 2 AZs for high availability
            max_azs=2,
            # CIDR block
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            # Subnet configuration - public subnets only for cost optimization
            subnet_configuration=[
                # Public subnets for ECS tasks (Fargate and EC2)
                # Tasks get public IPs to access AWS services directly
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,  # 10.0.1.0/24, 10.0.2.0/24
                ),
            ],
            # Enable DNS
            enable_dns_hostnames=True,
            enable_dns_support=True,
            # No NAT Gateways needed - tasks use public IPs
            nat_gateways=0,
        )

        # ========================================
        # Restrictive Security Group for ECS Tasks
        # ========================================
        # CRITICAL: No inbound rules - tasks never accept traffic from internet
        # Only egress allowed for accessing AWS services and pulling images
        
        self.ecs_security_group = ec2.SecurityGroup(
            self,
            "EcsTaskSecurityGroup",
            vpc=self.vpc,
            description="Restrictive security group for ECS tasks - egress only, no inbound",
            allow_all_outbound=True,  # Allow outbound to AWS services
        )
        
        # Explicitly note: NO ingress rules added
        # ECS tasks are job processors that pull work, they never need inbound connections

        # ========================================
        # Gateway VPC Endpoints (FREE)
        # ========================================
        # These are free and improve performance/security for S3 and DynamoDB access
        
        # S3 endpoint (for accessing S3 buckets - free gateway endpoint)
        self.s3_endpoint = self.vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)],
        )

        # DynamoDB endpoint (for accessing DynamoDB tables - free gateway endpoint)
        self.dynamodb_endpoint = self.vpc.add_gateway_endpoint(
            "DynamoDbEndpoint",
            service=ec2.GatewayVpcEndpointAwsService.DYNAMODB,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)],
        )
        
        # NOTE: Interface endpoints removed for cost savings (~$51/month)
        # ECR, CloudWatch Logs, SSM, ECS endpoints no longer needed
        # Tasks access these services via public internet with public IPs

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

        # Public subnet IDs (for ECS tasks - both Fargate and EC2)
        public_subnet_ids = [subnet.subnet_id for subnet in self.vpc.public_subnets]
        ssm.StringParameter(
            self,
            "PublicSubnetIdsParam",
            parameter_name="/pdf-models/networking/public-subnet-ids",
            string_value=",".join(public_subnet_ids),
            description="Comma-separated list of public subnet IDs for ECS tasks",
        )

        # ECS Security Group ID
        ssm.StringParameter(
            self,
            "EcsSecurityGroupIdParam",
            parameter_name="/pdf-models/networking/ecs-security-group-id",
            string_value=self.ecs_security_group.security_group_id,
            description="Security group ID for ECS tasks (egress-only)",
        )

        # ========================================
        # Tags
        # ========================================
        
        Tags.of(self).add("Project", CONFIG.PROJECT_NAME)
        Tags.of(self).add("Stack", "Networking")
        Tags.of(self).add("Environment", "dev")