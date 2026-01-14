.PHONY: help test test-watch test-integration test-integration-setup test-integration-auto test-integration-debug \
        test-unit-cloud test-integration-cloud test-cloud-status \
        cdk-synth cdk-diff cdk-deploy cdk-destroy cdk-deploy-all \
        aws-logs aws-s3-ls aws-stepfunctions-list aws-ecs-force-new-deployment \
        container-build base-image-build lambda-build lambda-build-status lambda-clean \
        frontend-build frontend-deploy frontend-deploy-quick setup

# Configuration
AWS_PROFILE := arch

# Helper variables to reduce repetition
AWS := AWS_PROFILE=$(AWS_PROFILE) aws
BACKEND_UV := cd backend && AWS_PROFILE=$(AWS_PROFILE) uv run

# Default target
help:
	@echo "pdf-models Makefile"
	@echo ""
	@echo "Testing Commands (Local):"
	@echo "  make test                          - Run all unit tests"
	@echo "  make test-watch                    - Run tests in watch mode"
	@echo "  make test-integration              - Run integration tests (requires setup)"
	@echo "  make test-integration-setup        - Create Cognito test user for integration tests (interactive)"
	@echo "  make test-integration-auto         - Create test user and run integration tests (automated)"
	@echo ""
	@echo "Testing Commands (Cloud - runs in CodeBuild):"
	@echo "  make test-unit-cloud               - Run unit tests in CodeBuild"
	@echo "  make test-integration-cloud        - Run integration tests in CodeBuild"
	@echo "  make test-integration-cloud MODEL=<name> - Run integration tests for specific model"
	@echo "  make test-cloud-status             - Check status of latest cloud test builds"
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
	@echo "Stack Deployment Order (make cdk-deploy-all):"
	@echo "  1. FoundationStack"
	@echo "  2. NetworkingStack"
	@echo "  3. CoreInfrastructureStack"
	@echo "  4. CiCdStack"
	@echo "  5. MarkerStack"
	@echo "  6. ApiV2Stack"
	@echo "  7. MonitoringStack"
	@echo "  8. FrontendStack"
	@echo ""
	@echo "Note: All commands automatically use AWS_PROFILE=$(AWS_PROFILE) and uv"

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
	$(BACKEND_UV) pytest tests/integration/ -v -s

test-integration-setup:
	@echo "Creating Cognito test user for integration tests..."
	@echo "This will prompt you for test user credentials."
	$(BACKEND_UV) python tests/integration/setup_test_user.py

test-integration-auto:
	@echo "Setting up test user and running integration tests automatically..."
	@echo "Using default test credentials..."
	$(BACKEND_UV) python tests/integration/setup_test_user.py "integration-test@pdf-models.local" "TestPass123!"
	@echo "Running integration tests..."
	cd backend && AWS_PROFILE=$(AWS_PROFILE) TEST_USER_EMAIL="integration-test@pdf-models.local" TEST_USER_PASSWORD="TestPass123!" uv run pytest tests/integration/ -v -s

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

# Cloud Testing Commands (triggers CodeBuild)
test-unit-cloud:
	@echo "Triggering CodeBuild for unit tests..."
	@BUILD_ID=$$($(AWS) codebuild start-build \
		--project-name pdf-models-unit-tests \
		--query 'build.id' --output text) && \
	echo "Build started: $$BUILD_ID" && \
	echo "View logs: https://console.aws.amazon.com/codesuite/codebuild/projects/pdf-models-unit-tests/build/$$BUILD_ID"

test-integration-cloud:
	@echo "Triggering CodeBuild for integration tests..."
	@if [ -n "$(MODEL)" ]; then \
		BUILD_ID=$$($(AWS) codebuild start-build \
			--project-name pdf-models-integration-tests \
			--environment-variables-override "name=MODEL,value=$(MODEL),type=PLAINTEXT" \
			--query 'build.id' --output text); \
	else \
		BUILD_ID=$$($(AWS) codebuild start-build \
			--project-name pdf-models-integration-tests \
			--query 'build.id' --output text); \
	fi && \
	echo "Build started: $$BUILD_ID" && \
	echo "View logs: https://console.aws.amazon.com/codesuite/codebuild/projects/pdf-models-integration-tests/build/$$BUILD_ID"

test-cloud-status:
	@echo "=== Unit Tests ===" && \
	BUILD_ID=$$($(AWS) codebuild list-builds-for-project \
		--project-name pdf-models-unit-tests --query 'ids[0]' --output text) && \
	if [ "$$BUILD_ID" != "None" ]; then \
		$(AWS) codebuild batch-get-builds --ids "$$BUILD_ID" \
			--query 'builds[0].{status:buildStatus,phase:currentPhase}'; \
	else \
		echo "No builds found"; \
	fi
	@echo "=== Integration Tests ===" && \
	BUILD_ID=$$($(AWS) codebuild list-builds-for-project \
		--project-name pdf-models-integration-tests --query 'ids[0]' --output text) && \
	if [ "$$BUILD_ID" != "None" ]; then \
		$(AWS) codebuild batch-get-builds --ids "$$BUILD_ID" \
			--query 'builds[0].{status:buildStatus,phase:currentPhase}'; \
	else \
		echo "No builds found"; \
	fi

# CDK Commands
cdk-synth:
	@echo "Synthesizing CDK stacks with AWS_PROFILE=$(AWS_PROFILE)..."
	$(BACKEND_UV) cdk synth

cdk-diff:
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK parameter required. Usage: make cdk-diff STACK=FoundationStack"; \
		exit 1; \
	fi
	@echo "Showing diff for $(STACK) with AWS_PROFILE=$(AWS_PROFILE)..."
	$(BACKEND_UV) cdk diff $(STACK)

cdk-deploy:
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK parameter required. Usage: make cdk-deploy STACK=FoundationStack"; \
		exit 1; \
	fi
	@echo "Deploying $(STACK) with AWS_PROFILE=$(AWS_PROFILE)..."
	$(BACKEND_UV) cdk deploy $(STACK) --require-approval never

cdk-destroy:
	@if [ -z "$(STACK)" ]; then \
		echo "Error: STACK parameter required. Usage: make cdk-destroy STACK=FoundationStack"; \
		exit 1; \
	fi
	@echo "Destroying $(STACK) with AWS_PROFILE=$(AWS_PROFILE)..."
	$(BACKEND_UV) cdk destroy $(STACK)

cdk-deploy-all:
	@echo "Deploying all stacks in correct order with AWS_PROFILE=$(AWS_PROFILE)..."
	@echo "Step 1/8: Deploying FoundationStack..."
	$(BACKEND_UV) cdk deploy FoundationStack --require-approval never
	@echo "Step 2/8: Deploying NetworkingStack..."
	$(BACKEND_UV) cdk deploy NetworkingStack --require-approval never
	@echo "Step 3/8: Deploying CoreInfrastructureStack..."
	$(BACKEND_UV) cdk deploy CoreInfrastructureStack --require-approval never
	@echo "Step 4/8: Deploying CiCdStack..."
	$(BACKEND_UV) cdk deploy CiCdStack --require-approval never
	@echo "Step 5/8: Deploying MarkerStack..."
	$(BACKEND_UV) cdk deploy MarkerStack --require-approval never
	@echo "Step 6/8: Deploying ApiV2Stack..."
	$(BACKEND_UV) cdk deploy ApiV2Stack --require-approval never
	@echo "Step 7/8: Deploying MonitoringStack..."
	$(BACKEND_UV) cdk deploy MonitoringStack --require-approval never
	@echo "Step 8/8: Deploying FrontendStack..."
	$(BACKEND_UV) cdk deploy FrontendStack --require-approval never
	@echo "All stacks deployed successfully!"

# AWS Commands
aws-logs:
	@if [ -z "$(LOGGROUP)" ]; then \
		echo "Error: LOGGROUP parameter required. Usage: make aws-logs LOGGROUP=/aws/lambda/function-name"; \
		exit 1; \
	fi
	@echo "Tailing logs for $(LOGGROUP) with AWS_PROFILE=$(AWS_PROFILE)..."
	$(AWS) logs tail $(LOGGROUP) --follow

aws-s3-ls:
	@echo "Listing S3 buckets with AWS_PROFILE=$(AWS_PROFILE)..."
	$(AWS) s3 ls

aws-stepfunctions-list:
	@echo "Listing Step Functions state machines with AWS_PROFILE=$(AWS_PROFILE)..."
	$(AWS) stepfunctions list-state-machines

aws-ecs-force-new-deployment:
	@echo "Forcing new ECS task definition to pull latest container image..."
	@echo "This updates the task definition to force ECS to pull the latest :latest image"
	$(AWS) ecs register-task-definition \
		--cli-input-json "$$($(AWS) ecs describe-task-definition --task-definition pdf-models-marker --query 'taskDefinition' | \
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
	@# Check for uncommitted changes in the container directory
	@if [ -n "$$(git status --porcelain backend/containers/$(MODEL)/)" ]; then \
		echo ""; \
		echo "⚠️  WARNING: Uncommitted changes in backend/containers/$(MODEL)/"; \
		echo "   CodeBuild pulls from CodeCommit - your local changes won't be included!"; \
		echo ""; \
		git status --short backend/containers/$(MODEL)/; \
		echo ""; \
		read -p "   Commit and push changes now? [y/N] " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			git add backend/containers/$(MODEL)/ && \
			git commit -m "Update $(MODEL) container" && \
			git push; \
		else \
			echo "Aborting build. Commit and push your changes first."; \
			exit 1; \
		fi; \
	fi
	@# Check for unpushed commits
	@UNPUSHED=$$(git log origin/$$(git rev-parse --abbrev-ref HEAD)..HEAD --oneline 2>/dev/null); \
	if [ -n "$$UNPUSHED" ]; then \
		echo ""; \
		echo "⚠️  WARNING: Unpushed commits detected:"; \
		echo "$$UNPUSHED"; \
		echo ""; \
		echo "   CodeBuild pulls from CodeCommit - unpushed commits won't be included!"; \
		echo ""; \
		read -p "   Push now? [y/N] " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			git push; \
		else \
			echo "Aborting build. Push your changes first."; \
			exit 1; \
		fi; \
	fi
	@echo "Triggering CodeBuild for $(MODEL) container with AWS_PROFILE=$(AWS_PROFILE)..."
	@echo "Note: This triggers the CodeBuild project, it does not build locally."
	$(AWS) codebuild start-build \
		--project-name pdf-models-$(MODEL)-container-build

# Base Image Build (triggers CodeBuild) - run once to build Rust Lambda builder image
base-image-build:
	@echo "Triggering CodeBuild for Rust Lambda builder base image with AWS_PROFILE=$(AWS_PROFILE)..."
	@echo "Note: This is a one-time build that takes ~30 minutes. Subsequent Lambda builds will be fast."
	$(AWS) codebuild start-build \
		--project-name pdf-models-rust-lambda-builder-build

# Lambda Build Commands (triggers CodeBuild)
lambda-build:
	@echo "Triggering CodeBuild for Rust Lambda functions with AWS_PROFILE=$(AWS_PROFILE)..."
	@echo "Note: This triggers the CodeBuild project, it does not build locally."
	$(AWS) codebuild start-build \
		--project-name pdf-models-rust-lambda-build

lambda-build-status:
	@echo "Checking status of latest Lambda build..."
	@BUILD_ID=$$($(AWS) codebuild list-builds-for-project \
		--project-name pdf-models-rust-lambda-build \
		--query 'ids[0]' --output text) && \
	$(AWS) codebuild batch-get-builds --ids "$$BUILD_ID" \
		--query 'builds[0].{status:buildStatus,phase:currentPhase,startTime:startTime}'

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
	$(BACKEND_UV) cdk deploy FrontendStack --require-approval never
	@echo "Frontend deployed successfully!"
	@echo "Note: CloudFront cache invalidation may take a few minutes to propagate."

frontend-deploy-quick:
	@echo "Deploying pre-built frontend (skipping build)..."
	@if [ ! -d "frontend/dst" ] || [ -z "$$(ls -A frontend/dst)" ]; then \
		echo "Error: frontend/dst is empty or doesn't exist. Run 'make frontend-build' first."; \
		exit 1; \
	fi
	@echo "Deploying to S3 + CloudFront via CDK..."
	$(BACKEND_UV) cdk deploy FrontendStack --require-approval never
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
