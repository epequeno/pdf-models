.PHONY: help test test-watch cdk-synth cdk-diff cdk-deploy cdk-destroy aws-logs aws-s3-ls container-build lambda-build setup

# AWS Profile to use for all commands
AWS_PROFILE := arch

# Default target
help:
	@echo "pdf-models Makefile"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make test                          - Run all unit tests"
	@echo "  make test-watch                    - Run tests in watch mode"
	@echo ""
	@echo "CDK Commands:"
	@echo "  make cdk-synth                     - Synthesize all CDK stacks"
	@echo "  make cdk-diff STACK=<name>         - Show changes for a specific stack"
	@echo "  make cdk-deploy STACK=<name>       - Deploy a specific stack"
	@echo "  make cdk-destroy STACK=<name>      - Destroy a specific stack"
	@echo ""
	@echo "AWS Commands:"
	@echo "  make aws-logs LOGGROUP=<name>      - Tail CloudWatch logs"
	@echo "  make aws-s3-ls                     - List S3 buckets"
	@echo "  make aws-stepfunctions-list        - List Step Functions state machines"
	@echo ""
	@echo "Build Commands:"
	@echo "  make container-build MODEL=<name>  - Build and push container (runs in CodeBuild)"
	@echo "  make lambda-build                  - Build Rust Lambda functions (runs in CodeBuild)"
	@echo ""
	@echo "Stack Deployment Order:"
	@echo "  1. make cdk-deploy STACK=FoundationStack"
	@echo "  2. make cdk-deploy STACK=CoreInfrastructureStack"
	@echo "  3. make cdk-deploy STACK=MarkerStack"
	@echo "  4. make cdk-deploy STACK=ApiStack"
	@echo "  5. make cdk-deploy STACK=CiCdStack"
	@echo ""
	@echo "Note: All commands automatically use AWS_PROFILE=arch and uv"

# Testing Commands
test:
	@echo "Running unit tests..."
	cd backend && uv run pytest tests/ -v

test-watch:
	@echo "Running tests in watch mode..."
	cd backend && uv run pytest-watch tests/ -v

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

# Lambda Build Commands (triggers CodeBuild)
lambda-build:
	@echo "Triggering CodeBuild for Rust Lambda functions with AWS_PROFILE=arch..."
	@echo "Note: This triggers the CodeBuild project, it does not build locally."
	AWS_PROFILE=arch aws codebuild start-build \
		--project-name pdf-models-rust-lambda-build

# Development setup
setup:
	@echo "Setting up development environment..."
	@echo "Installing uv if not present..."
	@which uv > /dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo "Installing CDK dependencies..."
	cd backend/cdk && uv sync
	@echo "Setup complete! Use 'make help' to see available commands."
