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
    #[allow(dead_code)]
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
    /// Optional custom prompt for VLM models (dolphin, deepseek-ocr)
    /// If not provided, the model uses its default prompt
    prompt: Option<String>,
    /// Optional original filename (before renaming to UUID)
    /// Used for display purposes in the UI
    original_filename: Option<String>,
    /// Optional configuration ID for custom model parameters
    /// If provided, the configuration must be approved and accessible to the user
    config_id: Option<String>,
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

// ============================================================================
// Configuration Types and Validation
// ============================================================================

/// Configuration data from DynamoDB
#[derive(Debug)]
#[allow(dead_code)]
struct ConfigurationData {
    config_id: String,
    user_id: String,
    approval_status: String,
    visibility: String,
}

/// Fetch and validate a configuration for job submission
/// Returns the configuration if valid, or an error Response
async fn validate_configuration(
    dynamodb_client: &DynamoDbClient,
    config_table_name: &str,
    config_id: &str,
    user_id: &str,
) -> Result<ConfigurationData, Response> {
    use aws_sdk_dynamodb::types::AttributeValue;

    // Fetch configuration from DynamoDB
    let result = dynamodb_client
        .get_item()
        .table_name(config_table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
        .map_err(|e| {
            info!("Failed to fetch configuration {}: {}", config_id, e);
            Response::error(500, "Failed to fetch configuration")
        })?;

    let item = result.item().ok_or_else(|| {
        Response::error(404, &format!("Configuration '{}' not found", config_id))
    })?;

    // Parse configuration fields
    let config_user_id = item
        .get("user_id")
        .and_then(|v| v.as_s().ok())
        .ok_or_else(|| Response::error(500, "Invalid configuration: missing user_id"))?;

    let approval_status = item
        .get("approval_status")
        .and_then(|v| v.as_s().ok())
        .ok_or_else(|| Response::error(500, "Invalid configuration: missing approval_status"))?;

    let visibility = item
        .get("visibility")
        .and_then(|v| v.as_s().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(|| "private".to_string());

    // Verify approval status is "approved"
    if approval_status != "approved" {
        return Err(Response::error(
            400,
            &format!(
                "Configuration '{}' is not approved (status: {})",
                config_id, approval_status
            ),
        ));
    }

    // Verify user has access: owner OR public+approved
    let is_owner = config_user_id == user_id;
    let is_public = visibility == "public";

    if !is_owner && !is_public {
        return Err(Response::error(
            403,
            "Access denied to this configuration",
        ));
    }

    Ok(ConfigurationData {
        config_id: config_id.to_string(),
        user_id: config_user_id.to_string(),
        approval_status: approval_status.to_string(),
        visibility,
    })
}

/// Increment the usage_count for a configuration atomically
async fn increment_config_usage_count(
    dynamodb_client: &DynamoDbClient,
    config_table_name: &str,
    config_id: &str,
) -> Result<(), String> {
    use aws_sdk_dynamodb::types::AttributeValue;

    dynamodb_client
        .update_item()
        .table_name(config_table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .update_expression("SET usage_count = if_not_exists(usage_count, :zero) + :inc")
        .expression_attribute_values(":zero", AttributeValue::N("0".to_string()))
        .expression_attribute_values(":inc", AttributeValue::N("1".to_string()))
        .send()
        .await
        .map_err(|e| format!("Failed to increment usage_count: {}", e))?;

    Ok(())
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
            prompt: None,
            original_filename: None,
            config_id: None,
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

    // Validate configuration if config_id is provided
    let validated_config_id: Option<String> = if let Some(ref config_id) = body.config_id {
        // Get configurations table name from environment
        let config_table_name = env::var("CONFIGURATIONS_TABLE_NAME")
            .unwrap_or_else(|_| "pdf-models-configurations".to_string());

        // Validate the configuration (checks approval status and access)
        match validate_configuration(&dynamodb_client, &config_table_name, config_id, user_id).await {
            Ok(config_data) => {
                info!(
                    "Validated configuration {} for job submission (owner: {}, visibility: {})",
                    config_data.config_id, config_data.user_id, config_data.visibility
                );
                Some(config_data.config_id)
            }
            Err(error_response) => {
                return Ok(error_response);
            }
        }
    } else {
        None
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

    // Build the DynamoDB put_item request
    let mut put_item_request = dynamodb_client
        .put_item()
        .table_name(&table_name)
        .item("job_id", aws_sdk_dynamodb::types::AttributeValue::S(job_id.clone()))
        .item("user_id", aws_sdk_dynamodb::types::AttributeValue::S(user_id.to_string()))
        .item("model", aws_sdk_dynamodb::types::AttributeValue::S(model.clone()))
        .item("status", aws_sdk_dynamodb::types::AttributeValue::S(initial_status.clone()))
        .item("s3_input_key", aws_sdk_dynamodb::types::AttributeValue::S(s3_input_key.clone()))
        .item("created_at", aws_sdk_dynamodb::types::AttributeValue::S(created_at.clone()));

    // Add prompt field if provided (for VLM models like dolphin, deepseek-ocr)
    if let Some(ref prompt) = body.prompt {
        put_item_request = put_item_request.item(
            "prompt",
            aws_sdk_dynamodb::types::AttributeValue::S(prompt.clone()),
        );
    }

    // Add original_filename if provided (for display in UI)
    if let Some(ref original_filename) = body.original_filename {
        put_item_request = put_item_request.item(
            "original_filename",
            aws_sdk_dynamodb::types::AttributeValue::S(original_filename.clone()),
        );
    }

    // Add config_id if provided (for custom model parameters)
    if let Some(ref config_id) = validated_config_id {
        put_item_request = put_item_request.item(
            "config_id",
            aws_sdk_dynamodb::types::AttributeValue::S(config_id.clone()),
        );
    }

    put_item_request.send().await?;

    info!("Created job record in DynamoDB: {}", job_id);

    // Start Step Functions execution if requested
    if body.start_processing {
        // Build execution input, including prompt if provided
        let mut execution_input = json!({
            "job_id": job_id,
            "s3_input_key": s3_input_key,
        });

        // Add prompt to execution input if provided (for VLM models)
        if let Some(ref prompt) = body.prompt {
            execution_input["prompt"] = json!(prompt);
        }

        // Add config_id to execution input if provided
        if let Some(ref config_id) = validated_config_id {
            execution_input["config_id"] = json!(config_id);
        }

        sfn_client
            .start_execution()
            .state_machine_arn(&state_machine_arn)
            .name(&job_id)  // Use job_id as execution name for idempotency
            .input(execution_input.to_string())
            .send()
            .await?;

        info!("Started Step Functions execution for job: {}", job_id);

        // Increment usage_count for the configuration if one was used
        if let Some(ref config_id) = validated_config_id {
            let config_table_name = env::var("CONFIGURATIONS_TABLE_NAME")
                .unwrap_or_else(|_| "pdf-models-configurations".to_string());

            if let Err(e) = increment_config_usage_count(&dynamodb_client, &config_table_name, config_id).await {
                // Log the error but don't fail the job submission
                info!("Warning: Failed to increment usage_count for config {}: {}", config_id, e);
            } else {
                info!("Incremented usage_count for configuration: {}", config_id);
            }
        }
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
