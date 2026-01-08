# Architecture Diagrams

This document contains Mermaid diagrams for visualizing the PDF Models backend architecture.

Generated SVG files are available in the `diagrams/` subdirectory:

| Diagram | File |
|---------|------|
| System Overview | [01-system-overview.svg](diagrams/01-system-overview.svg) |
| Job Processing Flow | [02-job-processing-flow.svg](diagrams/02-job-processing-flow.svg) |
| CDK Stack Dependencies | [03-cdk-stack-dependencies.svg](diagrams/03-cdk-stack-dependencies.svg) |
| Step Functions State Machine | [04-step-functions-state-machine.svg](diagrams/04-step-functions-state-machine.svg) |
| Data Model | [05-data-model.svg](diagrams/05-data-model.svg) |
| Authentication Architecture | [06-authentication-architecture.svg](diagrams/06-authentication-architecture.svg) |
| S3 Bucket Structure | [07-s3-bucket-structure.svg](diagrams/07-s3-bucket-structure.svg) |
| CI/CD Pipeline | [08-cicd-pipeline.svg](diagrams/08-cicd-pipeline.svg) |
| Model Configuration | [09-model-configuration.svg](diagrams/09-model-configuration.svg) |
| Request/Response Flow | [10-request-response-flow.svg](diagrams/10-request-response-flow.svg) |

## System Overview

```mermaid
flowchart TB
    subgraph API["API Layer"]
        APIGW[API Gateway v2<br/>HTTP API]
        AUTH[Cognito JWT<br/>Authorizer]

        subgraph Lambdas["Rust Lambda Handlers"]
            L1[submit-job]
            L2[get-job]
            L3[get-upload-url]
        end
    end

    subgraph Storage["Storage Layer"]
        S3[(S3 Bucket<br/>pdf-models-docs)]
        DDB[(DynamoDB<br/>jobs table)]
    end

    subgraph Orchestration["Orchestration Layer"]
        SF[Step Functions<br/>State Machine]
    end

    subgraph Compute["Compute Layer"]
        subgraph CPU["CPU Models"]
            MARKER[Marker<br/>4 vCPU / 16GB]
            DOCLING[Docling<br/>4 vCPU / 16GB]
        end
        subgraph GPU["GPU Models (g4dn.xlarge)"]
            DOLPHIN[Dolphin<br/>4 vCPU / 15GB + T4]
            DEEPSEEK[DeepSeek-OCR<br/>4 vCPU / 15GB + T4]
        end
    end

    APIGW --> AUTH
    AUTH --> Lambdas
    L1 --> DDB
    L1 --> SF
    L2 --> DDB
    L3 --> S3

    SF --> MARKER & DOCLING & DOLPHIN & DEEPSEEK
    MARKER & DOCLING & DOLPHIN & DEEPSEEK --> S3
    MARKER & DOCLING & DOLPHIN & DEEPSEEK --> DDB
```

## Job Processing Flow

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant APIGW as API Gateway
    participant Lambda as submit-job Lambda
    participant DDB as DynamoDB
    participant SF as Step Functions
    participant ECS as ECS Fargate
    participant S3

    Note over Client,S3: Job Submission Phase
    Client->>APIGW: POST /v1/models/{model}/jobs<br/>{s3_input_key, start_processing: true}
    APIGW->>APIGW: Validate JWT
    APIGW->>Lambda: Forward request
    Lambda->>DDB: Create job record<br/>status: "pending"
    Lambda->>SF: StartExecution<br/>{job_id, s3_input_key, model}
    Lambda-->>Client: {job_id, status: "pending"}

    Note over Client,S3: Processing Phase
    SF->>SF: LaunchFargateTask state
    SF->>ECS: RunTask (sync)
    activate ECS
    ECS->>S3: Download PDF
    ECS->>ECS: Run ML Model
    ECS->>S3: Upload result.md
    ECS->>DDB: Update status: "completed"
    deactivate ECS
    SF->>SF: Execution complete

    Note over Client,S3: Polling Phase
    loop Every 10 seconds
        Client->>APIGW: GET /v1/models/{model}/jobs/{job_id}
        APIGW->>Lambda: Forward request
        Lambda->>DDB: Query job
        Lambda-->>Client: {status, s3_result_key}
    end

    Note over Client,S3: Download Phase
    Client->>S3: Download result<br/>(using Identity Pool credentials)
```

## CDK Stack Dependencies

```mermaid
flowchart TD
    subgraph Foundation["FoundationStack"]
        ECR[ECR Repositories]
        CERT[ACM Certificates]
        HZ[Route53 Hosted Zone]
    end

    subgraph Network["NetworkingStack"]
        VPC[VPC]
        SUBNETS[Public/Private Subnets]
        SG[Security Groups]
    end

    subgraph Core["CoreInfrastructureStack"]
        S3[(S3 Bucket)]
        DDB[(DynamoDB)]
        UP[Cognito User Pool]
        IP[Cognito Identity Pool]
    end

    subgraph Models["ModelStacks (per model)"]
        TD[ECS Task Definition]
        SFN[Step Functions<br/>State Machine]
        ROLES[IAM Task Roles]
    end

    subgraph API["ApiV2Stack"]
        APIGW[HTTP API Gateway]
        LAMBDAS[Rust Lambdas]
        AUTHZ[JWT Authorizer]
    end

    subgraph CICD["CiCdStack"]
        CB[CodeBuild Projects]
        ARTS[Build Artifacts]
    end

    subgraph Monitor["MonitoringStack"]
        CW[CloudWatch Dashboards]
        ALARMS[Alarms]
    end

    subgraph Front["FrontendStack"]
        S3FE[(S3 Static Site)]
        CF[CloudFront]
    end

    Foundation --> Network
    Foundation --> Core
    Foundation --> CICD
    Network --> Models
    Core --> Models
    Core --> API
    Models --> API
    Foundation --> Front
    Core --> Monitor
    Models --> Monitor
    API --> Monitor

    style Foundation fill:#e1f5fe
    style Core fill:#fff3e0
    style Models fill:#e8f5e9
    style API fill:#fce4ec
```

## Step Functions State Machine

```mermaid
stateDiagram-v2
    [*] --> ResolveTaskDefinition

    ResolveTaskDefinition: Resolve Task Definition
    note right of ResolveTaskDefinition
        Lambda reads current
        task def ARN from SSM
    end note

    ResolveTaskDefinition --> LaunchFargateTask

    LaunchFargateTask: Launch Fargate Task
    note right of LaunchFargateTask
        ECS RunTask (sync)
        Passes job_id, s3_input_key
        via environment variables
    end note

    LaunchFargateTask --> TaskSuccess: Task Exits 0
    LaunchFargateTask --> TaskFailed: Task Exits Non-Zero

    TaskSuccess: Mark Job Completed
    TaskFailed: Mark Job Failed

    TaskSuccess --> [*]
    TaskFailed --> [*]
```

## Data Model

```mermaid
erDiagram
    JOBS {
        string job_id PK "UUID"
        string user_id "Cognito User ID"
        string model "marker|dolphin|docling|deepseek-ocr"
        string status "pending|processing|completed|failed"
        string s3_input_key "identity-id/job-id.pdf"
        string s3_result_key "identity-id/job-id-result.md"
        string prompt "Optional user prompt"
        string created_at "ISO8601 timestamp"
        string completed_at "ISO8601 timestamp"
        string error "Error message if failed"
    }

    S3_OBJECTS {
        string key PK "identity-id/job-id.pdf"
        blob content "PDF or Markdown file"
        datetime expires "7 day lifecycle"
    }

    JOBS ||--o| S3_OBJECTS : "s3_input_key"
    JOBS ||--o| S3_OBJECTS : "s3_result_key"
```

## Authentication Architecture

```mermaid
flowchart LR
    subgraph Client
        APP[Application]
    end

    subgraph Cognito["AWS Cognito"]
        UP[User Pool<br/>Authentication]
        IP[Identity Pool<br/>Authorization]
    end

    subgraph Tokens
        JWT[JWT Tokens<br/>AccessToken, IdToken]
        CREDS[AWS Credentials<br/>AccessKey, SecretKey, SessionToken]
    end

    subgraph Resources
        APIGW[API Gateway<br/>JWT Authorizer]
        S3[(S3<br/>IAM Policy)]
    end

    APP -->|1. username/password| UP
    UP -->|2. JWT tokens| JWT
    APP -->|3. exchange IdToken| IP
    IP -->|4. temp credentials| CREDS

    JWT -->|5. Bearer token| APIGW
    CREDS -->|6. signed requests| S3

    style UP fill:#ff9800
    style IP fill:#4caf50
```

## S3 Bucket Structure

```mermaid
flowchart TD
    BUCKET[("pdf-models-docs")]

    subgraph Users["User Isolation (by Identity Pool ID)"]
        U1["us-east-1:abc123..."]
        U2["us-east-1:def456..."]
    end

    subgraph U1Files["User 1 Files"]
        U1PDF["job-1.pdf"]
        U1RES["job-1-result.md"]
        U1PDF2["job-2.pdf"]
        U1RES2["job-2-result.md"]
    end

    subgraph U2Files["User 2 Files"]
        U2PDF["job-3.pdf"]
        U2RES["job-3-result.md"]
    end

    BUCKET --> U1 & U2
    U1 --> U1Files
    U2 --> U2Files

    style BUCKET fill:#ff9800
```

## CI/CD Pipeline

```mermaid
flowchart LR
    subgraph Source["Source"]
        CC[CodeCommit<br/>Git Repository]
    end

    subgraph Build["CodeBuild Projects"]
        CB1[rust-lambda-builder<br/>Base image build]
        CB2[rust-lambda-build<br/>Lambda compilation]
        CB3[marker-container-build]
        CB4[dolphin-container-build]
        CB5[docling-container-build]
    end

    subgraph Artifacts["Artifacts"]
        ECR[(ECR<br/>Container Images)]
        S3[(S3<br/>Lambda ZIPs)]
        SSM[(SSM Parameters<br/>Version tracking)]
    end

    subgraph Deploy["Deployment"]
        CDK[CDK Deploy<br/>Update Stacks]
    end

    CC -->|Manual trigger| CB1
    CC -->|Manual trigger| CB2
    CC -->|Manual trigger| CB3 & CB4 & CB5

    CB1 --> ECR
    CB2 --> S3
    CB2 --> SSM
    CB3 & CB4 & CB5 --> ECR
    CB3 & CB4 & CB5 --> SSM

    SSM --> CDK

    style CC fill:#e1f5fe
    style ECR fill:#fff3e0
    style SSM fill:#e8f5e9
```

## Model Configuration

```mermaid
flowchart TB
    subgraph Config["stack_config.py"]
        MC[Model Configuration]
    end

    subgraph CPUModels["CPU-Based Models<br/>(ECS Fargate)"]
        M1["Marker<br/>4 vCPU | 16GB | 120min"]
        M2["Docling<br/>4 vCPU | 16GB | 30min"]
    end

    subgraph GPUModels["GPU-Based Models<br/>(EC2 g4dn.xlarge + ASG)"]
        M3["Dolphin<br/>4 vCPU | 15GB | 1x T4 | 30min"]
        M4["DeepSeek-OCR<br/>4 vCPU | 15GB | 1x T4 | 30min"]
    end

    subgraph Outputs["Output Formats"]
        MD[Markdown]
        JSON[JSON]
    end

    MC --> CPUModels
    MC --> GPUModels

    M1 --> MD
    M2 --> MD & JSON
    M3 --> MD & JSON
    M4 --> MD

    style CPUModels fill:#e3f2fd
    style GPUModels fill:#fff8e1
```

## Request/Response Flow

```mermaid
flowchart LR
    subgraph Request["Request Path"]
        R1[Client Request]
        R2[API Gateway]
        R3[JWT Validation]
        R4[Lambda Handler]
        R5[Business Logic]
    end

    subgraph Response["Response Path"]
        S1[JSON Response]
        S2[Lambda Response]
        S3[API Gateway]
        S4[Client]
    end

    R1 --> R2 --> R3 --> R4 --> R5
    R5 --> S1 --> S2 --> S3 --> S4

    subgraph Endpoints["API Endpoints"]
        E1["POST /v1/models/{model}/jobs<br/>Submit new job"]
        E2["GET /v1/models/{model}/jobs<br/>List user's jobs"]
        E3["GET /v1/models/{model}/jobs/{id}<br/>Get job status"]
        E4["GET /upload-url<br/>Get presigned upload URL"]
    end
```
