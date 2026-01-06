use aws_config::BehaviorVersion;
use aws_sdk_dynamodb::Client as DynamoDbClient;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client as S3Client;
use aws_sdk_ssm::Client as SsmClient;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::env;
use std::time::Duration;
use tracing::info;

#[derive(Deserialize)]
struct Request {
    #[serde(rename = "pathParameters")]
    path_parameters: Option<PathParameters>,
    #[serde(rename = "requestContext")]
    request_context: RequestContext,
}

#[derive(Deserialize)]
struct PathParameters {
    model: String,
    #[serde(rename = "job_id")]
    job_id: Option<String>,
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

#[derive(Serialize)]
struct Response {
    #[serde(rename = "statusCode")]
    status_code: u16,
    headers: serde_json::Map<String, Value>,
    body: String,
}

#[derive(Serialize)]
struct JobResponse {
    job_id: String,
    user_id: String,
    model: String,
    status: String,
    s3_input_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    s3_result_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    download_url: Option<String>,
    created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    completed_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
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

    info!("Processing get job request");

    // Extract user ID from Cognito claims (supports both REST API and HTTP API v2 formats)
    let user_id = match &request.request_context.authorizer {
        Some(Authorizer::RestApi { claims }) => &claims.sub,
        Some(Authorizer::HttpApiV2 { jwt }) => &jwt.claims.sub,
        None => {
            return Ok(Response::error(401, "No authorizer context found"));
        }
    };

    // Check if this is a single job query or list query
    let path_params = request.path_parameters.ok_or("Missing path parameters")?;

    let model = &path_params.model;

    // Get environment variables
    let table_name = env::var("DYNAMODB_TABLE_NAME")?;
    let bucket_name = env::var("S3_BUCKET_NAME")?;

    // Initialize AWS clients
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let dynamodb_client = DynamoDbClient::new(&config);
    let s3_client = S3Client::new(&config);
    let ssm_client = SsmClient::new(&config);

    // Validate model exists via SSM lookup
    let ssm_param_name = format!("/pdf-models/{}/state-machine-arn", model);
    if ssm_client
        .get_parameter()
        .name(&ssm_param_name)
        .send()
        .await
        .is_err()
    {
        return Ok(Response::error(
            400,
            &format!("Invalid model '{}'. Model not supported.", model),
        ));
    }

    // If job_id is present, return single job; otherwise list user's jobs
    if let Some(job_id) = &path_params.job_id {
        // Get single job by ID
        let result = dynamodb_client
            .get_item()
            .table_name(&table_name)
            .key("job_id", aws_sdk_dynamodb::types::AttributeValue::S(job_id.clone()))
            .send()
            .await?;

        match result.item {
            Some(item) => {
                // Verify the job belongs to the requesting user
                let job_user_id = item.get("user_id")
                    .and_then(|v| v.as_s().ok())
                    .ok_or("Missing user_id in job record")?;

                if job_user_id != user_id {
                    return Ok(Response::error(404, "Job not found"));
                }

                // Generate download URL if result is available
                let s3_result_key = item.get("s3_result_key").and_then(|v| v.as_s().ok()).map(|s| s.to_string());
                let download_url = if let Some(ref result_key) = s3_result_key {
                    // Generate pre-signed URL for download (1 hour validity)
                    match PresigningConfig::expires_in(Duration::from_secs(3600)) {
                        Ok(presigning_config) => {
                            match s3_client
                                .get_object()
                                .bucket(&bucket_name)
                                .key(result_key)
                                .presigned(presigning_config)
                                .await
                            {
                                Ok(presigned_request) => Some(presigned_request.uri().to_string()),
                                Err(e) => {
                                    info!("Failed to generate pre-signed URL: {}", e);
                                    None
                                }
                            }
                        }
                        Err(e) => {
                            info!("Failed to create presigning config: {}", e);
                            None
                        }
                    }
                } else {
                    None
                };

                // Build job response
                let job = JobResponse {
                    job_id: job_id.clone(),
                    user_id: job_user_id.to_string(),
                    model: item.get("model").and_then(|v| v.as_s().ok()).map_or("", |v| v).to_string(),
                    status: item.get("status").and_then(|v| v.as_s().ok()).map_or("unknown", |v| v).to_string(),
                    s3_input_key: item.get("s3_input_key").and_then(|v| v.as_s().ok()).map_or("", |v| v).to_string(),
                    s3_result_key,
                    download_url,
                    created_at: item.get("created_at").and_then(|v| v.as_s().ok()).map_or("", |v| v).to_string(),
                    completed_at: item.get("completed_at").and_then(|v| v.as_s().ok()).map(|s| s.to_string()),
                    error: item.get("error").and_then(|v| v.as_s().ok()).map(|s| s.to_string()),
                };

                Ok(Response::new(200, json!(job)))
            }
            None => Ok(Response::error(404, "Job not found")),
        }
    } else {
        // List user's jobs using GSI
        let result = dynamodb_client
            .query()
            .table_name(&table_name)
            .index_name("user_id-created_at-index")
            .key_condition_expression("user_id = :user_id")
            .expression_attribute_values(
                ":user_id",
                aws_sdk_dynamodb::types::AttributeValue::S(user_id.to_string()),
            )
            .scan_index_forward(false)  // Sort by created_at descending (newest first)
            .limit(100)  // Limit to 100 most recent jobs
            .send()
            .await?;

        let jobs: Vec<JobResponse> = result
            .items()
            .iter()
            .filter_map(|item| {
                // Note: For list view, we don't generate download URLs to save time
                // Users can get the download URL from the single job endpoint
                Some(JobResponse {
                    job_id: item.get("job_id")?.as_s().ok()?.to_string(),
                    user_id: item.get("user_id")?.as_s().ok()?.to_string(),
                    model: item.get("model")?.as_s().ok()?.to_string(),
                    status: item.get("status")?.as_s().ok()?.to_string(),
                    s3_input_key: item.get("s3_input_key")?.as_s().ok()?.to_string(),
                    s3_result_key: item.get("s3_result_key").and_then(|v| v.as_s().ok()).map(|s| s.to_string()),
                    download_url: None,  // Not generated for list view
                    created_at: item.get("created_at")?.as_s().ok()?.to_string(),
                    completed_at: item.get("completed_at").and_then(|v| v.as_s().ok()).map(|s| s.to_string()),
                    error: item.get("error").and_then(|v| v.as_s().ok()).map(|s| s.to_string()),
                })
            })
            .collect();

        Ok(Response::new(200, json!({ "jobs": jobs })))
    }
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
