"""
CDK Stack for Frontend Deployment to S3 + CloudFront

This stack deploys the Elm frontend to S3 with CloudFront CDN.
It automatically monitors frontend/dst for changes and triggers deployments.
"""

from aws_cdk import (
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
)
from aws_cdk import (
    aws_certificatemanager as acm,
)
from aws_cdk import (
    aws_cloudfront as cloudfront,
)
from aws_cdk import (
    aws_cloudfront_origins as origins,
)
from aws_cdk import (
    aws_route53 as route53,
)
from aws_cdk import (
    aws_route53_targets as targets,
)
from aws_cdk import (
    aws_s3 as s3,
)
from aws_cdk import (
    aws_s3_deployment as s3_deploy,
)
from constructs import Construct


class FrontendStack(Stack):
    """
    Stack for deploying the Elm frontend as a static site.

    Features:
    - S3 bucket for hosting static assets
    - CloudFront distribution with SSL/TLS
    - Automatic deployments from frontend/dst
    - Cache invalidations on deployment
    - Custom domain with Route53
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration
        domain_name = "epequeno.app"
        hosted_zone_id = "Z04774573K4OEWVFBEMS5"

        # Import existing hosted zone
        hosted_zone = route53.HostedZone.from_hosted_zone_attributes(
            self,
            "HostedZone",
            hosted_zone_id=hosted_zone_id,
            zone_name=domain_name,
        )

        # S3 bucket for static website hosting
        website_bucket = s3.Bucket(
            self,
            "WebsiteBucket",
            bucket_name=f"{domain_name}-frontend",
            # Block all public access - CloudFront will access via OAI
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Enable versioning for rollback capability
            versioned=True,
            # Retain bucket on stack deletion for safety
            removal_policy=RemovalPolicy.RETAIN,
            # Lifecycle rules to clean up old versions
            lifecycle_rules=[
                s3.LifecycleRule(
                    noncurrent_version_expiration=Duration.days(30),
                    enabled=True,
                )
            ],
        )

        # SSL/TLS Certificate
        # Note: Certificate for CloudFront must be in us-east-1
        certificate = acm.Certificate(
            self,
            "Certificate",
            domain_name=domain_name,
            # Also cover www subdomain
            subject_alternative_names=[f"www.{domain_name}"],
            validation=acm.CertificateValidation.from_dns(hosted_zone),
        )

        # CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "Distribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3BucketOrigin.with_origin_access_control(
                    website_bucket,
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
                compress=True,
                # Custom cache policy for development - shorter TTLs
                cache_policy=cloudfront.CachePolicy(
                    self,
                    "FrontendCachePolicy",
                    cache_policy_name=f"{domain_name.replace('.', '-')}-frontend-cache",
                    comment="Cache policy for frontend with short TTLs for development",
                    default_ttl=Duration.minutes(5),  # Default cache time
                    max_ttl=Duration.hours(1),  # Maximum cache time
                    min_ttl=Duration.seconds(0),  # Minimum cache time (allow no-cache)
                    cookie_behavior=cloudfront.CacheCookieBehavior.none(),
                    header_behavior=cloudfront.CacheHeaderBehavior.none(),
                    query_string_behavior=cloudfront.CacheQueryStringBehavior.none(),
                    enable_accept_encoding_gzip=True,
                    enable_accept_encoding_brotli=True,
                ),
            ),
            # Custom domain
            domain_names=[domain_name, f"www.{domain_name}"],
            certificate=certificate,
            # Default root object
            default_root_object="index.html",
            # Enable IPv6
            enable_ipv6=True,
            # Price class (use all edge locations for best performance)
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,  # US, Canada, Europe
            # Error responses - serve index.html for SPA routing
            error_responses=[
                cloudfront.ErrorResponse(
                    http_status=404,
                    response_http_status=200,
                    response_page_path="/index.html",
                    ttl=Duration.minutes(5),
                ),
                cloudfront.ErrorResponse(
                    http_status=403,
                    response_http_status=200,
                    response_page_path="/index.html",
                    ttl=Duration.minutes(5),
                ),
            ],
            comment=f"CDN for {domain_name}",
        )

        # Route53 A record for apex domain
        route53.ARecord(
            self,
            "ARecord",
            zone=hosted_zone,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(distribution)
            ),
            record_name=domain_name,
        )

        # Route53 A record for www subdomain
        route53.ARecord(
            self,
            "WwwARecord",
            zone=hosted_zone,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(distribution)
            ),
            record_name=f"www.{domain_name}",
        )

        # Deploy website content from frontend/dst
        # This will automatically deploy whenever the content changes
        s3_deploy.BucketDeployment(
            self,
            "DeployWebsite",
            sources=[s3_deploy.Source.asset("../frontend/dst")],
            destination_bucket=website_bucket,
            distribution=distribution,
            # Invalidate CloudFront cache on deployment
            distribution_paths=["/*"],
            # Prune old files that are no longer in the source
            prune=True,
            # Cache control headers - short cache for development
            cache_control=[
                s3_deploy.CacheControl.max_age(Duration.minutes(5)),
                s3_deploy.CacheControl.must_revalidate(),
                s3_deploy.CacheControl.no_cache(),  # Force revalidation
            ],
        )

        # Outputs
        CfnOutput(
            self,
            "BucketName",
            value=website_bucket.bucket_name,
            description="S3 bucket name for website hosting",
        )

        CfnOutput(
            self,
            "DistributionId",
            value=distribution.distribution_id,
            description="CloudFront distribution ID",
        )

        CfnOutput(
            self,
            "DistributionDomainName",
            value=distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
        )

        CfnOutput(
            self,
            "WebsiteURL",
            value=f"https://{domain_name}",
            description="Website URL",
        )
