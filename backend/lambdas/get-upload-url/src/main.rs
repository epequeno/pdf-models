//! Get Upload URL Lambda
//!
//! Generates pre-signed S3 upload URLs for authenticated users.
//! POST /v1/models/{model}/upload-url
//!
//! Request: { "filename": "doc.pdf", "content_type": "application/pdf" }
//! Response: { "upload_url": "...", "s3_key": "user-sub/uuid.pdf", "content_type": "..." }

use aws_config::BehaviorVersion;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client as S3Client;
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
    path_parameters: Option<PathParameters>,
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
    authorizer: Option<Authorizer>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Authorizer {
    // HTTP API v2 format: JWT with nested claims
    HttpApiV2 { jwt: JwtAuthorizer },
}

#[derive(Deserialize)]
struct JwtAuthorizer {
    claims: Claims,
}

#[derive(Deserialize)]
struct Claims {
    sub: String, // Cognito user ID
}

#[derive(Deserialize)]
struct UploadUrlRequest {
    filename: String,
    #[serde(default)]
    content_type: Option<String>,
}

#[derive(Serialize)]
struct Response {
    #[serde(rename = "statusCode")]
    status_code: u16,
    headers: serde_json::Map<String, Value>,
    body: String,
}

#[derive(Serialize)]
struct UploadUrlResponse {
    upload_url: String,
    s3_key: String,
    content_type: String,
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

    info!("Processing upload URL request");

    // Validate model from path
    if let Some(ref path_params) = request.path_parameters {
        if path_params.model != "marker" {
            return Ok(Response::error(400, "Invalid model. Only 'marker' is supported"));
        }
    }

    // Extract user ID from JWT claims
    let user_id = match &request.request_context.authorizer {
        Some(Authorizer::HttpApiV2 { jwt }) => &jwt.claims.sub,
        None => {
            return Ok(Response::error(401, "No authorizer context found"));
        }
    };

    // Parse request body
    let body: UploadUrlRequest = match request.body {
        Some(body_str) if !body_str.is_empty() => {
            match serde_json::from_str(&body_str) {
                Ok(b) => b,
                Err(e) => {
                    return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
                }
            }
        }
        _ => {
            return Ok(Response::error(400, "Missing request body"));
        }
    };

    // Determine content type (default to PDF)
    let content_type = body.content_type.unwrap_or_else(|| "application/pdf".to_string());

    // Generate unique file ID and S3 key
    // Format: {user_id}/{uuid}.pdf
    let file_id = Uuid::new_v4().to_string();
    let s3_key = format!("{}/{}.pdf", user_id, file_id);

    // Get environment variables
    let bucket_name = env::var("S3_BUCKET_NAME")?;

    // Initialize S3 client
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let s3_client = S3Client::new(&config);

    // Generate pre-signed URL (15 minutes validity)
    let presigning_config = PresigningConfig::expires_in(Duration::from_secs(900))?;
    let presigned_request = s3_client
        .put_object()
        .bucket(&bucket_name)
        .key(&s3_key)
        .content_type(&content_type)
        .presigned(presigning_config)
        .await?;

    info!(
        "Generated upload URL for user {} with key {}",
        user_id, s3_key
    );

    let response = UploadUrlResponse {
        upload_url: presigned_request.uri().to_string(),
        s3_key,
        content_type,
    };

    Ok(Response::new(200, json!(response)))
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
