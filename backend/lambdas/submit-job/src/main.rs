use aws_config::BehaviorVersion;
use aws_sdk_dynamodb::Client as DynamoDbClient;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_sfn::Client as SfnClient;
use chrono::Utc;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use std::time::Duration;
use tracing::info;
use uuid::Uuid;

#[derive(Deserialize)]
struct Request {
    #[serde(rename = "pathParameters")]
    path_parameters: PathParameters,
    #[serde(rename = "requestContext")]
    request_context: RequestContext,
    body: Option<String>,
}

#[derive(Deserialize)]
struct PathParameters {
    model: String,
}

#[derive(Deserialize)]
struct RequestContext {
    #[serde(rename = "requestId")]
    request_id: String,
    authorizer: Option<Authorizer>,
}

#[derive(Deserialize)]
struct Authorizer {
    // REST API format
    claims: Option<Claims>,
    // HTTP API v2 format - JWT claims are at top level
    jwt: Option<JwtAuthorizer>,
    // Handle different possible structures
    #[serde(flatten)]
    extra: std::collections::HashMap<String, serde_json::Value>,
}

#[derive(Deserialize)]
struct Claims {
    sub: String,  // Cognito user ID
}

#[derive(Deserialize)]
struct JwtAuthorizer {
    claims: Claims,
}

#[derive(Deserialize)]
struct SubmitJobBody {
    /// Optional: if provided, start processing immediately
    /// If not provided, return upload_url for client to upload first
    #[serde(default)]
    start_processing: bool,
}

#[derive(Serialize)]
struct Response {
    #[serde(rename = "statusCode")]
    status_code: u16,
    headers: serde_json::Map<String, Value>,
    body: String,
}

#[derive(Serialize)]
struct SubmitJobResponse {
    job_id: String,
    model: String,
    status: String,
    s3_input_key: String,
    upload_url: String,
    created_at: String,
}

impl Response {
    fn new(status_code: u16, body: Value) -> Self {
        let mut headers = serde_json::Map::new();
        headers.insert("Content-Type".to_string(), json!("application/json"));
        headers.insert(
            "Access-Control-Allow-Origin".to_string(),
            json!("*"),
        );

        Self {
            status_code,
            headers,
            body: serde_json::to_string(&body).unwrap(),
        }
    }

    fn error(status_code: u16, message: &str) -> Self {
        Self::new(status_code, json!({ "error": message }))
    }
}

async fn function_handler(event: LambdaEvent<Request>) -> Result<Response, Error> {
    let (request, _context) = event.into_parts();

    info!("Processing submit job request");

    // Extract model from path
    let model = &request.path_parameters.model;
    if model != "marker" {
        return Ok(Response::error(400, "Invalid model. Only 'marker' is supported"));
    }

    // Extract user ID from Cognito claims (supports both REST API and HTTP API v2 formats)
    let user_id = match &request.request_context.authorizer {
        Some(authorizer) => {
            // Try REST API format first
            if let Some(claims) = &authorizer.claims {
                &claims.sub
            }
            // Try HTTP API v2 format
            else if let Some(jwt) = &authorizer.jwt {
                &jwt.claims.sub
            }
            // Try to extract from extra fields
            else if let Some(sub) = authorizer.extra.get("sub") {
                if let Some(sub_str) = sub.as_str() {
                    sub_str
                } else {
                    return Ok(Response::error(401, "Invalid user ID in authorizer context"));
                }
            } else {
                return Ok(Response::error(401, "No user ID found in authorizer context"));
            }
        },
        None => {
            return Ok(Response::error(401, "No authorizer context found"));
        }
    };

    // Parse request body (optional)
    let body: SubmitJobBody = match request.body {
        Some(body_str) if !body_str.is_empty() => match serde_json::from_str(&body_str) {
            Ok(body) => body,
            Err(e) => {
                return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
            }
        },
        _ => SubmitJobBody {
            start_processing: false,
        },
    };

    // Generate job ID and S3 key
    let job_id = Uuid::new_v4().to_string();
    let s3_input_key = format!("{}/{}.pdf", user_id, job_id);
    let created_at = Utc::now().to_rfc3339();

    // Get environment variables
    let table_name = env::var("DYNAMODB_TABLE_NAME")?;
    let state_machine_arn = env::var("STATE_MACHINE_ARN")?;
    let bucket_name = env::var("S3_BUCKET_NAME")?;

    // Initialize AWS clients
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let dynamodb_client = DynamoDbClient::new(&config);
    let sfn_client = SfnClient::new(&config);
    let s3_client = S3Client::new(&config);

    // Generate pre-signed URL for upload (15 minutes validity)
    let presigning_config = PresigningConfig::expires_in(Duration::from_secs(900))?;
    let presigned_request = s3_client
        .put_object()
        .bucket(&bucket_name)
        .key(&s3_input_key)
        .content_type("application/pdf")
        .presigned(presigning_config)
        .await?;

    let upload_url = presigned_request.uri().to_string();

    info!("Generated pre-signed upload URL for job: {}", job_id);

    // Create job record in DynamoDB
    let initial_status = if body.start_processing {
        "processing".to_string()
    } else {
        "created".to_string()
    };

    dynamodb_client
        .put_item()
        .table_name(&table_name)
        .item("job_id", aws_sdk_dynamodb::types::AttributeValue::S(job_id.clone()))
        .item("user_id", aws_sdk_dynamodb::types::AttributeValue::S(user_id.to_string()))
        .item("model", aws_sdk_dynamodb::types::AttributeValue::S(model.clone()))
        .item("status", aws_sdk_dynamodb::types::AttributeValue::S(initial_status.clone()))
        .item("s3_input_key", aws_sdk_dynamodb::types::AttributeValue::S(s3_input_key.clone()))
        .item("created_at", aws_sdk_dynamodb::types::AttributeValue::S(created_at.clone()))
        .send()
        .await?;

    info!("Created job record in DynamoDB: {}", job_id);

    // Start Step Functions execution if requested
    if body.start_processing {
        let execution_input = json!({
            "job_id": job_id,
            "s3_input_key": s3_input_key,
        });

        sfn_client
            .start_execution()
            .state_machine_arn(&state_machine_arn)
            .name(&job_id)  // Use job_id as execution name for idempotency
            .input(execution_input.to_string())
            .send()
            .await?;

        info!("Started Step Functions execution for job: {}", job_id);
    }

    // Return response
    let response_body = SubmitJobResponse {
        job_id,
        model: model.clone(),
        status: initial_status,
        s3_input_key,
        upload_url,
        created_at,
    };

    Ok(Response::new(201, json!(response_body)))
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .without_time()
        .init();

    lambda_runtime::run(service_fn(function_handler)).await
}
