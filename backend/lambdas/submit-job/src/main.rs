use aws_config::BehaviorVersion;
use aws_sdk_dynamodb::Client as DynamoDbClient;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_sfn::Client as SfnClient;
use aws_sdk_ssm::Client as SsmClient;
use chrono::Utc;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
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
#[serde(untagged)]
enum Authorizer {
    // REST API v1 format: claims at top level
    RestApi {
        claims: Claims,
    },
    // HTTP API v2 format: JWT with nested claims
    HttpApiV2 {
        jwt: JwtAuthorizer,
    },
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
    /// S3 key of the input file (required when using Identity Pool credentials)
    s3_input_key: Option<String>,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    upload_url: Option<String>,
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

    // Extract user ID from Cognito claims (supports both REST API and HTTP API v2 formats)
    let user_id = match &request.request_context.authorizer {
        Some(Authorizer::RestApi { claims }) => &claims.sub,
        Some(Authorizer::HttpApiV2 { jwt }) => &jwt.claims.sub,
        None => {
            return Ok(Response::error(401, "No authorizer context found"));
        }
    };

    // Parse request body
    let body: SubmitJobBody = match request.body {
        Some(body_str) if !body_str.is_empty() => match serde_json::from_str(&body_str) {
            Ok(body) => body,
            Err(e) => {
                return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
            }
        },
        _ => SubmitJobBody {
            s3_input_key: None,
            start_processing: false,
        },
    };

    // Determine S3 input key and job ID
    let (job_id, s3_input_key) = match &body.s3_input_key {
        Some(provided_key) => {
            // Note: S3 key validation is handled by S3 IAM permissions
            // Users can only access files in their Identity Pool prefix due to IAM policies
            // We don't validate the prefix here since Cognito User ID != Identity Pool ID
            
            // Extract job ID from the S3 key (assuming format: prefix/job_id.pdf)
            let key_parts: Vec<&str> = provided_key.split('/').collect();
            if key_parts.len() != 2 || !key_parts[1].ends_with(".pdf") {
                return Ok(Response::error(400, "Invalid S3 key format. Expected: prefix/job_id.pdf"));
            }
            
            let job_id = key_parts[1].trim_end_matches(".pdf").to_string();
            (job_id, provided_key.clone())
        }
        None => {
            // Generate new job ID and S3 key (for pre-signed URL workflow)
            let job_id = Uuid::new_v4().to_string();
            let s3_input_key = format!("{}/{}.pdf", user_id, job_id);
            (job_id, s3_input_key)
        }
    };

    let created_at = Utc::now().to_rfc3339();

    // Get environment variables
    let table_name = env::var("DYNAMODB_TABLE_NAME")?;
    let bucket_name = env::var("S3_BUCKET_NAME")?;

    // Initialize AWS clients
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let dynamodb_client = DynamoDbClient::new(&config);
    let sfn_client = SfnClient::new(&config);
    let s3_client = S3Client::new(&config);
    let ssm_client = SsmClient::new(&config);

    // Look up state machine ARN from SSM (validates model exists)
    let ssm_param_name = format!("/pdf-models/{}/state-machine-arn", model);
    let state_machine_arn = match ssm_client
        .get_parameter()
        .name(&ssm_param_name)
        .send()
        .await
    {
        Ok(response) => {
            response
                .parameter()
                .and_then(|p| p.value().map(|v| v.to_string()))
                .ok_or_else(|| format!("SSM parameter {} has no value", ssm_param_name))?
        }
        Err(e) => {
            info!("Model '{}' not found in SSM: {}", model, e);
            return Ok(Response::error(
                400,
                &format!("Invalid model '{}'. Model not supported.", model),
            ));
        }
    };

    // Generate pre-signed URL for upload only if no S3 key was provided
    let upload_url = if body.s3_input_key.is_none() {
        let presigning_config = PresigningConfig::expires_in(Duration::from_secs(900))?;
        let presigned_request = s3_client
            .put_object()
            .bucket(&bucket_name)
            .key(&s3_input_key)
            .content_type("application/pdf")
            .presigned(presigning_config)
            .await?;

        Some(presigned_request.uri().to_string())
    } else {
        None
    };

    if upload_url.is_some() {
        info!("Generated pre-signed upload URL for job: {}", job_id);
    } else {
        info!("Using provided S3 key for job: {}", job_id);
    }

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
