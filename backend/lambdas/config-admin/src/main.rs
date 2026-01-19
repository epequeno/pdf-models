use aws_config::BehaviorVersion;
use aws_sdk_dynamodb::types::AttributeValue;
use aws_sdk_dynamodb::Client as DynamoDbClient;
use aws_sdk_lambda::Client as LambdaClient;
use aws_sdk_lambda::primitives::Blob;
use chrono::Utc;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use tracing::info;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Deserialize)]
struct Request {
    #[serde(rename = "pathParameters")]
    path_parameters: Option<PathParameters>,
    #[serde(rename = "requestContext")]
    request_context: RequestContext,
    #[serde(rename = "httpMethod")]
    http_method: Option<String>,
    #[serde(rename = "routeKey")]
    route_key: Option<String>,
    body: Option<String>,
    resource: Option<String>,
}

#[derive(Deserialize)]
struct PathParameters {
    config_id: Option<String>,
}

#[derive(Deserialize)]
struct RequestContext {
    authorizer: Option<Authorizer>,
    http: Option<HttpContext>,
}

#[derive(Deserialize)]
struct HttpContext {
    method: String,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Authorizer {
    RestApi { claims: Claims },
    HttpApiV2 { jwt: JwtAuthorizer },
}

#[derive(Deserialize, Clone)]
struct Claims {
    sub: String,
    #[serde(rename = "cognito:groups")]
    cognito_groups: Option<String>,
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

impl Response {
    fn new(status_code: u16, body: Value) -> Self {
        let mut headers = serde_json::Map::new();
        headers.insert("Content-Type".to_string(), json!("application/json"));
        headers.insert("Access-Control-Allow-Origin".to_string(), json!("*"));
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
// Configuration Data Types (shared with config-crud)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct InferenceParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prompt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_format: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub custom_env_vars: Option<HashMap<String, String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct InfraParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cpu: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memory_mib: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gpu_count: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeout_minutes: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ephemeral_storage_gib: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ebs_volume_size_gb: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spot_enabled: Option<bool>,
}


#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigResponse {
    pub config_id: String,
    pub user_id: String,
    pub model: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub inference_params: InferenceParams,
    pub infra_params: InfraParams,
    pub approval_status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approved_by: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approved_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rejection_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_definition_arn: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_definition_status: Option<String>,
    pub visibility: String,
    pub usage_count: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub forked_from: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RejectRequest {
    pub reason: String,
}

// ============================================================================
// Admin Verification
// ============================================================================

const ADMIN_GROUP: &str = "pdf-models-admins";

fn is_admin(claims: &Claims) -> bool {
    claims
        .cognito_groups
        .as_ref()
        .map(|groups| {
            // Groups can be a JSON array string or comma-separated
            groups.contains(ADMIN_GROUP)
        })
        .unwrap_or(false)
}

// ============================================================================
// DynamoDB Helpers
// ============================================================================

fn dynamodb_to_config(item: &HashMap<String, AttributeValue>) -> Option<ConfigResponse> {
    let config_id = item.get("config_id")?.as_s().ok()?.clone();
    let user_id = item.get("user_id")?.as_s().ok()?.clone();
    let model = item.get("model")?.as_s().ok()?.clone();
    let name = item.get("name")?.as_s().ok()?.clone();
    let created_at = item.get("created_at")?.as_s().ok()?.clone();
    let updated_at = item.get("updated_at")?.as_s().ok()?.clone();
    let approval_status = item.get("approval_status")?.as_s().ok()?.clone();
    let visibility = item
        .get("visibility")
        .and_then(|v| v.as_s().ok())
        .cloned()
        .unwrap_or_else(|| "private".to_string());
    let usage_count = item
        .get("usage_count")
        .and_then(|v| v.as_n().ok())
        .and_then(|n| n.parse::<u64>().ok())
        .unwrap_or(0);

    let description = item.get("description").and_then(|v| v.as_s().ok()).cloned();

    let inference_params: InferenceParams = item
        .get("inference_params")
        .and_then(|v| v.as_s().ok())
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();

    let infra_params: InfraParams = item
        .get("infra_params")
        .and_then(|v| v.as_s().ok())
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();

    let approved_by = item.get("approved_by").and_then(|v| v.as_s().ok()).cloned();
    let approved_at = item.get("approved_at").and_then(|v| v.as_s().ok()).cloned();
    let rejection_reason = item
        .get("rejection_reason")
        .and_then(|v| v.as_s().ok())
        .cloned();
    let task_definition_arn = item
        .get("task_definition_arn")
        .and_then(|v| v.as_s().ok())
        .cloned();
    let task_definition_status = item
        .get("task_definition_status")
        .and_then(|v| v.as_s().ok())
        .cloned();
    let forked_from = item.get("forked_from").and_then(|v| v.as_s().ok()).cloned();

    Some(ConfigResponse {
        config_id,
        user_id,
        model,
        name,
        description,
        created_at,
        updated_at,
        inference_params,
        infra_params,
        approval_status,
        approved_by,
        approved_at,
        rejection_reason,
        task_definition_arn,
        task_definition_status,
        visibility,
        usage_count,
        forked_from,
    })
}


// ============================================================================
// Handlers
// ============================================================================

async fn list_pending_configs(client: &DynamoDbClient, table_name: &str) -> Response {
    // Scan for all configs with approval_status = pending_approval
    // Note: In production, consider adding a GSI on approval_status for efficiency
    match client
        .scan()
        .table_name(table_name)
        .filter_expression("approval_status = :status")
        .expression_attribute_values(
            ":status",
            AttributeValue::S("pending_approval".to_string()),
        )
        .send()
        .await
    {
        Ok(result) => {
            let configs: Vec<ConfigResponse> = result
                .items()
                .iter()
                .filter_map(dynamodb_to_config)
                .collect();
            Response::new(200, json!({ "configurations": configs }))
        }
        Err(e) => {
            info!("Failed to list pending configurations: {}", e);
            Response::error(500, "Failed to list pending configurations")
        }
    }
}

async fn approve_config(
    dynamodb_client: &DynamoDbClient,
    lambda_client: &LambdaClient,
    table_name: &str,
    config_id: &str,
    admin_user_id: &str,
    register_task_def_function: &str,
) -> Response {
    // First, fetch the config to verify it exists and is pending
    let config = match get_config_by_id(dynamodb_client, table_name, config_id).await {
        Ok(Some(c)) => c,
        Ok(None) => return Response::error(404, "Configuration not found"),
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            return Response::error(500, "Failed to get configuration");
        }
    };

    if config.approval_status != "pending_approval" {
        return Response::error(
            400,
            &format!(
                "Configuration is not pending approval (current status: {})",
                config.approval_status
            ),
        );
    }

    let now = Utc::now().to_rfc3339();

    // Update the configuration to approved status
    match dynamodb_client
        .update_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .update_expression(
            "SET approval_status = :status, approved_by = :by, approved_at = :at, updated_at = :updated, rejection_reason = :null_val",
        )
        .expression_attribute_values(":status", AttributeValue::S("approved".to_string()))
        .expression_attribute_values(":by", AttributeValue::S(admin_user_id.to_string()))
        .expression_attribute_values(":at", AttributeValue::S(now.clone()))
        .expression_attribute_values(":updated", AttributeValue::S(now))
        .expression_attribute_values(":null_val", AttributeValue::Null(true))
        .send()
        .await
    {
        Ok(_) => {
            info!("Approved configuration: {}", config_id);
        }
        Err(e) => {
            info!("Failed to approve configuration: {}", e);
            return Response::error(500, "Failed to approve configuration");
        }
    }

    // Invoke register-task-def Lambda to create the task definition
    let payload = json!({
        "config_id": config_id,
        "model": config.model,
        "infra_params": config.infra_params
    });

    match lambda_client
        .invoke()
        .function_name(register_task_def_function)
        .payload(Blob::new(serde_json::to_vec(&payload).unwrap()))
        .send()
        .await
    {
        Ok(result) => {
            // Check if Lambda execution was successful
            if let Some(error) = result.function_error() {
                info!(
                    "register-task-def Lambda returned error: {}",
                    error
                );
                // Update config with failed status
                let _ = update_task_def_status(
                    dynamodb_client,
                    table_name,
                    config_id,
                    None,
                    "failed",
                    Some(&format!("Task definition registration failed: {}", error)),
                )
                .await;
            } else {
                info!(
                    "Successfully invoked register-task-def Lambda for config: {}",
                    config_id
                );
                // The register-task-def Lambda will update the config with the task definition ARN
            }
        }
        Err(e) => {
            info!("Failed to invoke register-task-def Lambda: {}", e);
            // Update config with failed status
            let _ = update_task_def_status(
                dynamodb_client,
                table_name,
                config_id,
                None,
                "failed",
                Some(&format!("Failed to invoke task definition registration: {}", e)),
            )
            .await;
        }
    }

    // Fetch and return the updated config
    match get_config_by_id(dynamodb_client, table_name, config_id).await {
        Ok(Some(updated_config)) => Response::new(200, json!(updated_config)),
        Ok(None) => Response::error(404, "Configuration not found after update"),
        Err(e) => {
            info!("Failed to fetch updated configuration: {}", e);
            Response::error(500, "Configuration approved but failed to fetch updated state")
        }
    }
}


async fn reject_config(
    client: &DynamoDbClient,
    table_name: &str,
    config_id: &str,
    reason: &str,
) -> Response {
    // First, fetch the config to verify it exists and is pending
    let config = match get_config_by_id(client, table_name, config_id).await {
        Ok(Some(c)) => c,
        Ok(None) => return Response::error(404, "Configuration not found"),
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            return Response::error(500, "Failed to get configuration");
        }
    };

    if config.approval_status != "pending_approval" {
        return Response::error(
            400,
            &format!(
                "Configuration is not pending approval (current status: {})",
                config.approval_status
            ),
        );
    }

    let now = Utc::now().to_rfc3339();

    // Update the configuration to rejected status
    match client
        .update_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .update_expression(
            "SET approval_status = :status, rejection_reason = :reason, updated_at = :updated",
        )
        .expression_attribute_values(":status", AttributeValue::S("rejected".to_string()))
        .expression_attribute_values(":reason", AttributeValue::S(reason.to_string()))
        .expression_attribute_values(":updated", AttributeValue::S(now))
        .send()
        .await
    {
        Ok(_) => {
            info!("Rejected configuration: {} with reason: {}", config_id, reason);
        }
        Err(e) => {
            info!("Failed to reject configuration: {}", e);
            return Response::error(500, "Failed to reject configuration");
        }
    }

    // Fetch and return the updated config
    match get_config_by_id(client, table_name, config_id).await {
        Ok(Some(updated_config)) => Response::new(200, json!(updated_config)),
        Ok(None) => Response::error(404, "Configuration not found after update"),
        Err(e) => {
            info!("Failed to fetch updated configuration: {}", e);
            Response::error(500, "Configuration rejected but failed to fetch updated state")
        }
    }
}

async fn revoke_config(client: &DynamoDbClient, table_name: &str, config_id: &str) -> Response {
    // First, fetch the config to verify it exists and is approved
    let config = match get_config_by_id(client, table_name, config_id).await {
        Ok(Some(c)) => c,
        Ok(None) => return Response::error(404, "Configuration not found"),
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            return Response::error(500, "Failed to get configuration");
        }
    };

    if config.approval_status != "approved" {
        return Response::error(
            400,
            &format!(
                "Configuration is not approved (current status: {})",
                config.approval_status
            ),
        );
    }

    let now = Utc::now().to_rfc3339();

    // Update the configuration: reset to pending_approval and clear task definition
    match client
        .update_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .update_expression(
            "SET approval_status = :status, updated_at = :updated, task_definition_arn = :null_val, task_definition_status = :null_val, approved_by = :null_val, approved_at = :null_val",
        )
        .expression_attribute_values(":status", AttributeValue::S("pending_approval".to_string()))
        .expression_attribute_values(":updated", AttributeValue::S(now))
        .expression_attribute_values(":null_val", AttributeValue::Null(true))
        .send()
        .await
    {
        Ok(_) => {
            info!("Revoked configuration: {}", config_id);
        }
        Err(e) => {
            info!("Failed to revoke configuration: {}", e);
            return Response::error(500, "Failed to revoke configuration");
        }
    }

    // Fetch and return the updated config
    match get_config_by_id(client, table_name, config_id).await {
        Ok(Some(updated_config)) => Response::new(200, json!(updated_config)),
        Ok(None) => Response::error(404, "Configuration not found after update"),
        Err(e) => {
            info!("Failed to fetch updated configuration: {}", e);
            Response::error(500, "Configuration revoked but failed to fetch updated state")
        }
    }
}


// ============================================================================
// Helper Functions
// ============================================================================

async fn get_config_by_id(
    client: &DynamoDbClient,
    table_name: &str,
    config_id: &str,
) -> Result<Option<ConfigResponse>, String> {
    match client
        .get_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
    {
        Ok(result) => match result.item() {
            Some(item) => Ok(dynamodb_to_config(item)),
            None => Ok(None),
        },
        Err(e) => Err(e.to_string()),
    }
}

async fn update_task_def_status(
    client: &DynamoDbClient,
    table_name: &str,
    config_id: &str,
    task_definition_arn: Option<&str>,
    status: &str,
    error: Option<&str>,
) -> Result<(), String> {
    let now = Utc::now().to_rfc3339();

    let mut update_expr =
        "SET task_definition_status = :status, updated_at = :updated".to_string();
    let mut builder = client
        .update_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .expression_attribute_values(":status", AttributeValue::S(status.to_string()))
        .expression_attribute_values(":updated", AttributeValue::S(now));

    if let Some(arn) = task_definition_arn {
        update_expr.push_str(", task_definition_arn = :arn");
        builder = builder.expression_attribute_values(":arn", AttributeValue::S(arn.to_string()));
    }

    if let Some(err) = error {
        update_expr.push_str(", task_definition_error = :error");
        builder = builder.expression_attribute_values(":error", AttributeValue::S(err.to_string()));
    }

    match builder.update_expression(update_expr).send().await {
        Ok(_) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

// ============================================================================
// Main Handler
// ============================================================================

async fn function_handler(event: LambdaEvent<Request>) -> Result<Response, Error> {
    let (request, _context) = event.into_parts();

    info!("Processing config-admin request");

    // Extract claims from Cognito authorizer
    let claims = match &request.request_context.authorizer {
        Some(Authorizer::RestApi { claims }) => claims.clone(),
        Some(Authorizer::HttpApiV2 { jwt }) => jwt.claims.clone(),
        None => {
            return Ok(Response::error(401, "No authorizer context found"));
        }
    };

    // Verify admin access
    if !is_admin(&claims) {
        info!("Non-admin user attempted to access admin endpoint: {}", claims.sub);
        return Ok(Response::error(403, "Admin access required"));
    }

    let user_id = &claims.sub;

    // Get HTTP method
    let method = request
        .http_method
        .as_deref()
        .or_else(|| {
            request
                .request_context
                .http
                .as_ref()
                .map(|h| h.method.as_str())
        })
        .unwrap_or("GET");

    // Get path parameters
    let config_id = request
        .path_parameters
        .as_ref()
        .and_then(|p| p.config_id.as_deref());

    // Get table name and Lambda function name from environment
    let table_name = env::var("CONFIGURATIONS_TABLE_NAME")
        .unwrap_or_else(|_| "pdf-models-configurations".to_string());
    let register_task_def_function = env::var("REGISTER_TASK_DEF_FUNCTION")
        .unwrap_or_else(|_| "pdf-models-register-task-def".to_string());

    // Initialize AWS clients
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let dynamodb_client = DynamoDbClient::new(&config);
    let lambda_client = LambdaClient::new(&config);

    // Determine route based on resource pattern and method
    // Routes:
    // GET  /v1/admin/configs/pending              -> list pending
    // POST /v1/admin/configs/{config_id}/approve  -> approve
    // POST /v1/admin/configs/{config_id}/reject   -> reject
    // POST /v1/admin/configs/{config_id}/revoke   -> revoke

    let resource = request.resource.as_deref().unwrap_or("");
    let route_key = request.route_key.as_deref().unwrap_or("");

    let is_pending = resource.contains("/pending") || route_key.contains("/pending");
    let is_approve = resource.contains("/approve") || route_key.contains("/approve");
    let is_reject = resource.contains("/reject") || route_key.contains("/reject");
    let is_revoke = resource.contains("/revoke") || route_key.contains("/revoke");

    match (method, config_id, is_pending, is_approve, is_reject, is_revoke) {
        // GET /v1/admin/configs/pending
        ("GET", None, true, false, false, false) => {
            Ok(list_pending_configs(&dynamodb_client, &table_name).await)
        }
        // POST /v1/admin/configs/{config_id}/approve
        ("POST", Some(cid), false, true, false, false) => {
            Ok(approve_config(
                &dynamodb_client,
                &lambda_client,
                &table_name,
                cid,
                user_id,
                &register_task_def_function,
            )
            .await)
        }
        // POST /v1/admin/configs/{config_id}/reject
        ("POST", Some(cid), false, false, true, false) => {
            let body: RejectRequest = match request.body {
                Some(body_str) if !body_str.is_empty() => match serde_json::from_str(&body_str) {
                    Ok(body) => body,
                    Err(e) => {
                        return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
                    }
                },
                _ => return Ok(Response::error(400, "Request body with reason is required")),
            };
            Ok(reject_config(&dynamodb_client, &table_name, cid, &body.reason).await)
        }
        // POST /v1/admin/configs/{config_id}/revoke
        ("POST", Some(cid), false, false, false, true) => {
            Ok(revoke_config(&dynamodb_client, &table_name, cid).await)
        }
        _ => Ok(Response::error(400, "Invalid request")),
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
