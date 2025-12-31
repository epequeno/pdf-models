use aws_config::BehaviorVersion;
use aws_sdk_dynamodb::Client as DynamoDbClient;
use aws_sdk_sfn::Client as SfnClient;
use chrono::Utc;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::env;
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
    authorizer: Authorizer,
}

#[derive(Deserialize)]
struct Authorizer {
    claims: Claims,
}

#[derive(Deserialize)]
struct Claims {
    sub: String,  // Cognito user ID
}

#[derive(Deserialize)]
struct SubmitJobBody {
    s3_input_key: String,
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

    // Extract user ID from Cognito claims
    let user_id = &request.request_context.authorizer.claims.sub;

    // Parse request body
    let body: SubmitJobBody = match request.body {
        Some(body_str) => match serde_json::from_str(&body_str) {
            Ok(body) => body,
            Err(e) => {
                return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
            }
        },
        None => {
            return Ok(Response::error(400, "Missing request body"));
        }
    };

    // Validate s3_input_key starts with user_id
    if !body.s3_input_key.starts_with(&format!("{}/", user_id)) {
        return Ok(Response::error(
            403,
            "S3 input key must start with your user ID prefix",
        ));
    }

    // Generate job ID
    let job_id = Uuid::new_v4().to_string();
    let created_at = Utc::now().to_rfc3339();

    // Get environment variables
    let table_name = env::var("DYNAMODB_TABLE_NAME")?;
    let state_machine_arn = env::var("STATE_MACHINE_ARN")?;

    // Initialize AWS clients
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let dynamodb_client = DynamoDbClient::new(&config);
    let sfn_client = SfnClient::new(&config);

    // Create job record in DynamoDB
    dynamodb_client
        .put_item()
        .table_name(&table_name)
        .item("job_id", aws_sdk_dynamodb::types::AttributeValue::S(job_id.clone()))
        .item("user_id", aws_sdk_dynamodb::types::AttributeValue::S(user_id.clone()))
        .item("model", aws_sdk_dynamodb::types::AttributeValue::S(model.clone()))
        .item("status", aws_sdk_dynamodb::types::AttributeValue::S("pending".to_string()))
        .item("s3_input_key", aws_sdk_dynamodb::types::AttributeValue::S(body.s3_input_key.clone()))
        .item("created_at", aws_sdk_dynamodb::types::AttributeValue::S(created_at.clone()))
        .send()
        .await?;

    info!("Created job record in DynamoDB: {}", job_id);

    // Start Step Functions execution
    let execution_input = json!({
        "job_id": job_id,
        "s3_input_key": body.s3_input_key,
    });

    sfn_client
        .start_execution()
        .state_machine_arn(&state_machine_arn)
        .name(&job_id)  // Use job_id as execution name for idempotency
        .input(execution_input.to_string())
        .send()
        .await?;

    info!("Started Step Functions execution for job: {}", job_id);

    // Return response
    let response_body = SubmitJobResponse {
        job_id,
        model: model.clone(),
        status: "pending".to_string(),
        s3_input_key: body.s3_input_key,
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
