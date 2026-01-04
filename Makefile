.PHONY: help test test-watch test-integration test-integration-setup cdk-synth cdk-diff cdk-deploy cdk-destroy aws-logs aws-s3-ls container-build base-image-build lambda-build lambda-clean frontend-build frontend-deploy frontend-deploy-quick setup

# AWS Profile to use for all commands
AWS_PROFILE := arch

# Default target
help:
	@echo "pdf-models Makefile"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make test                          - Run all unit tests"
	@echo "  make test-watch                    - Run tests in watch mode"
	@echo "  make test-integration              - Run integration tests (requires setup)"
	@echo "  make test-integration-setup        - Create Cognito test user for integration tests (interactive)"
	@echo "  make test-integration-auto         - Create test user and run integration tests (automated)"
	@echo ""
	@echo "CDK Commands:"
	@echo "  make cdk-synth                     - Synthesize all CDK stacks"
	@echo "  make cdk-diff STACK=<name>         - Show changes for a specific stack"
	@echo "  make cdk-deploy STACK=<name>       - Deploy a specific stack"
	@echo "  make cdk-deploy-all                - Deploy all stacks in correct order"
	@echo "  make cdk-destroy STACK=<name>      - Destroy a specific stack"
	@echo ""
	@echo "AWS Commands:"
	@echo "  make aws-logs LOGGROUP=<name>      - Tail CloudWatch logs"
	@echo "  make aws-s3-ls                     - List S3 buckets"
	@echo "  make aws-stepfunctions-list        - List Step Functions state machines"
	@echo "  make aws-ecs-force-new-deployment  - Force ECS to pull latest container image"
	@echo ""
	@echo "Build Commands:"
	@echo "  make base-image-build              - Build Rust Lambda builder base image (runs in CodeBuild)"
	@echo "  make container-build MODEL=<name>  - Build and push container (runs in CodeBuild)"
	@echo "  make lambda-build                  - Build Rust Lambda functions (runs in CodeBuild)"
	@echo "  make lambda-build-status           - Check status of latest Lambda build"
	@echo "  make lambda-clean                  - Clean local Lambda build artifacts"
	@echo ""
	@echo "Frontend Commands:"
	@echo "  make frontend-build                - Build Elm frontend (compiles to frontend/dst)"
	@echo "  make frontend-deploy               - Build and deploy frontend to S3+CloudFront"
	@echo "  make frontend-deploy-quick         - Deploy frontend (assumes already built)"
	@echo ""
	@echo "Stack Deployment Order:"
	@echo "  1. make cdk-deploy STACK=FoundationStack"
	@echo "  2. make cdk-deploy STACK=NetworkingStack"
	@echo "  3. make cdk-deploy STACK=CoreInfrastructureStack"
	@echo "  4. make cdk-deploy STACK=MarkerStack"
	@echo "  5. make cdk-deploy STACK=ApiStack"
	@echo "  6. make cdk-deploy STACK=CiCdStack"
	@echo "  7. make cdk-deploy STACK=MonitoringStack"
	@echo ""
	@echo "Note: All commands automatically use AWS_PROFILE=arch and uv"

# Testing Commands
test:
	@echo "Running unit tests..."
	cd backend && uv run pytest tests/ -v

test-watch:
	@echo "Running tests in watch mode..."
	cd backend && uv run pytest-watch tests/ -v

test-integration:
	@echo "Running integration tests..."
	@if [ -z "$$TEST_USER_EMAIL" ] || [ -z "$$TEST_USER_PASSWORD" ]; then \
		echo "Error: Integration tests require environment variables:"; \
		echo "  TEST_USER_EMAIL - Email of test user"; \
		echo "  TEST_USER_PASSWORD - Password of test user"; \
		echo ""; \
		echo "Run 'make test-integration-setup' first to create a test user."; \
		exit 1; \
	fi
	cd backend && AWS_PROFILE=arch uv run pytest tests/integration/ -v -s

test-integration-setup:
	@echo "Creating Cognito test user for integration tests..."
	@echo "This will prompt you for test user credentials."
	cd backend && AWS_PROFILE=arch uv run python tests/integration/setup_test_user.py

test-integration-auto:
	@echo "Setting up test user and running integration tests automatically..."
	@echo "Using default test credentials..."
	cd backend && AWS_PROFILE=arch uv run python tests/integration/setup_test_user.py "integration-test@pdf-models.local" "TestPass123!"
	@echo "Running integration tests..."
	cd backend && AWS_PROFILE=arch TEST_USER_EMAIL="integration-test@pdf-models.local" TEST_USER_PASSWORD="TestPass123!" uv run pytest tests/integration/ -v -s

test-integration-debug:
	@echo "Debugging Cognito authentication and API access..."
	cd backend && TEST_USER_EMAIL="integration-test@pdf-models.local" TEST_USER_PASSWORD="TestPass123!" uv run python -c "\
import os, boto3, requests, json, base64; \
cognito = boto3.client('cognito-idp', region_name='us-east-1'); \
response = cognito.initiate_auth( \
    ClientId='4tmf8s58738hrbrp4ff2utqg5', \
    AuthFlow='USER_PASSWORD_AUTH', \
    AuthParameters={'USERNAME': 'integration-test@pdf-models.local', 'PASSWORD': 'TestPass123!'} \
); \
tokens = response['AuthenticationResult']; \
access_token = tokens['AccessToken']; \
print('=== TOKEN DEBUG ==='); \
parts = access_token.split('.'); \
header = json.loads(base64.b64decode(parts[0] + '==').decode()); \
payload = json.loads(base64.b64decode(parts[1] + '==').decode()); \
print('Header:', json.dumps(header, indent=2)); \
print('Payload:', json.dumps(payload, indent=2)); \
print('=== API TEST ==='); \
api_response = requests.post( \
    'https://gh0j9u3bx5.execute-api.us-east-1.amazonaws.com/v1/models/marker/jobs', \
    headers={'Authorization': f'Bearer {access_token}', 'Content-Type': 'application/json'}, \
    json={'s3_input_key': 'test-key'} \
); \
print(f'Status: {api_response.status_code}'); \
print(f'Response: {api_response.text}'); \
"

# CDK Commands
cdk-synth:
	@echo "Synthesizing CDK stacks with AWS_PROFILE=arch..."
	cd backend && AWS_PROFILE=arch uv run cdk synth

cdk-diff:
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK parameter required. Usage: make cdk-diff STACK=FoundationStack"; \
		exit 1; \
	fi
	@echo "Showing diff for $(STACK) with AWS_PROFILE=arch..."
	cd backend && AWS_PROFILE=arch uv run cdk diff $(STACK)

cdk-deploy:
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK parameter required. Usage: make cdk-deploy STACK=FoundationStack"; \
		exit 1; \
	fi
	@echo "Deploying $(STACK) with AWS_PROFILE=arch..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy $(STACK) --require-approval never

cdk-destroy:
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK parameter required. Usage: make cdk-destroy STACK=FoundationStack"; \
		exit 1; \
	fi
	@echo "Destroying $(STACK) with AWS_PROFILE=arch..."
	cd backend && AWS_PROFILE=arch uv run cdk destroy $(STACK)

cdk-deploy-all:
	@echo "Deploying all stacks in correct order with AWS_PROFILE=arch..."
	@echo "Step 1/8: Deploying FoundationStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy FoundationStack --require-approval never
	@echo "Step 2/8: Deploying NetworkingStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy NetworkingStack --require-approval never
	@echo "Step 3/8: Deploying CoreInfrastructureStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy CoreInfrastructureStack --require-approval never
	@echo "Step 4/8: Deploying CiCdStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy CiCdStack --require-approval never
	@echo "Step 5/8: Deploying MarkerStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy MarkerStack --require-approval never
	@echo "Step 6/8: Deploying ApiV2Stack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy ApiV2Stack --require-approval never
	@echo "Step 7/8: Deploying MonitoringStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy MonitoringStack --require-approval never
	@echo "Step 8/8: Deploying FrontendStack..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy FrontendStack --require-approval never
	@echo "All stacks deployed successfully!"

# AWS Commands
aws-logs:
	@if [ -z "$(LOGGROUP)" ]; then \
		echo "Error: LOGGROUP parameter required. Usage: make aws-logs LOGGROUP=/aws/lambda/function-name"; \
		exit 1; \
	fi
	@echo "Tailing logs for $(LOGGROUP) with AWS_PROFILE=arch..."
	AWS_PROFILE=arch aws logs tail $(LOGGROUP) --follow

aws-s3-ls:
	@echo "Listing S3 buckets with AWS_PROFILE=arch..."
	AWS_PROFILE=arch aws s3 ls

aws-stepfunctions-list:
	@echo "Listing Step Functions state machines with AWS_PROFILE=arch..."
	AWS_PROFILE=arch aws stepfunctions list-state-machines

aws-ecs-force-new-deployment:
	@echo "Forcing new ECS task definition to pull latest container image..."
	@echo "This updates the task definition to force ECS to pull the latest :latest image"
	AWS_PROFILE=arch aws ecs register-task-definition \
		--cli-input-json "$$(AWS_PROFILE=arch aws ecs describe-task-definition --task-definition pdf-models-marker --query 'taskDefinition' | \
		python3 -c 'import sys, json; td = json.load(sys.stdin); \
		del td["taskDefinitionArn"]; del td["revision"]; del td["status"]; \
		del td["requiresAttributes"]; del td["compatibilities"]; del td["registeredAt"]; del td["registeredBy"]; \
		print(json.dumps(td))')" \
		--query 'taskDefinition.taskDefinitionArn' --output text
	@echo "New task definition revision created. ECS will now pull the latest container image."

# Container Commands (triggers CodeBuild)
container-build:
	@if [ -z "$(MODEL)" ]; then \
		echo "Error: MODEL parameter required. Usage: make container-build MODEL=marker"; \
		exit 1; \
	fi
	@echo "Triggering CodeBuild for $(MODEL) container with AWS_PROFILE=arch..."
	@echo "Note: This triggers the CodeBuild project, it does not build locally."
	AWS_PROFILE=arch aws codebuild start-build \
		--project-name pdf-models-$(MODEL)-container-build

# Base Image Build (triggers CodeBuild) - run once to build Rust Lambda builder image
base-image-build:
	@echo "Triggering CodeBuild for Rust Lambda builder base image with AWS_PROFILE=arch..."
	@echo "Note: This is a one-time build that takes ~30 minutes. Subsequent Lambda builds will be fast."
	AWS_PROFILE=arch aws codebuild start-build \
		--project-name pdf-models-rust-lambda-builder-build

# Lambda Build Commands (triggers CodeBuild)
lambda-build:
	@echo "Triggering CodeBuild for Rust Lambda functions with AWS_PROFILE=arch..."
	@echo "Note: This triggers the CodeBuild project, it does not build locally."
	AWS_PROFILE=arch aws codebuild start-build \
		--project-name pdf-models-rust-lambda-build

lambda-build-status:
	@echo "Checking status of latest Lambda build..."
	AWS_PROFILE=arch aws codebuild list-builds-for-project \
		--project-name pdf-models-rust-lambda-build \
		--query 'ids[0]' --output text | \
	xargs -I {} aws codebuild batch-get-builds --ids {} \
		--query 'builds[0].{status:buildStatus,phase:currentPhase,startTime:startTime}' \
		--profile arch

lambda-clean:
	@echo "Cleaning Lambda build artifacts..."
	rm -rf backend/lambdas/*/target/
	rm -rf backend/lambdas/backend/
	@echo "Lambda build artifacts cleaned."

# Frontend Commands
frontend-build:
	@echo "Building Elm frontend..."
	cd frontend && ./build.sh
	@echo "Frontend build complete! Output in frontend/dst/"

frontend-deploy:
	@echo "Building and deploying frontend..."
	@echo "Step 1/2: Building Elm frontend..."
	cd frontend && ./build.sh
	@echo "Step 2/2: Deploying to S3 + CloudFront via CDK..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy FrontendStack --require-approval never
	@echo "Frontend deployed successfully!"
	@echo "Note: CloudFront cache invalidation may take a few minutes to propagate."

frontend-deploy-quick:
	@echo "Deploying pre-built frontend (skipping build)..."
	@if [ ! -d "frontend/dst" ] || [ -z "$$(ls -A frontend/dst)" ]; then \
		echo "Error: frontend/dst is empty or doesn't exist. Run 'make frontend-build' first."; \
		exit 1; \
	fi
	@echo "Deploying to S3 + CloudFront via CDK..."
	cd backend && AWS_PROFILE=arch uv run cdk deploy FrontendStack --require-approval never
	@echo "Frontend deployed successfully!"
	@echo "Note: CloudFront cache invalidation may take a few minutes to propagate."

# Development setup
setup:
	@echo "Setting up development environment..."
	@echo "Installing uv if not present..."
	@which uv > /dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo "Installing CDK dependencies..."
	cd backend/cdk && uv sync
	@echo "Setup complete! Use 'make help' to see available commands."
