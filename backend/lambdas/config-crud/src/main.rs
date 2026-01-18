use aws_config::BehaviorVersion;
use aws_sdk_dynamodb::types::AttributeValue;
use aws_sdk_dynamodb::Client as DynamoDbClient;
use chrono::Utc;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use tracing::info;
use uuid::Uuid;

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
    model: Option<String>,
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

#[derive(Deserialize)]
struct Claims {
    sub: String,
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

    fn error_with_details(status_code: u16, message: &str, details: Vec<String>) -> Self {
        Self::new(status_code, json!({ "error": message, "details": details }))
    }
}

// ============================================================================
// Configuration Data Types
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
pub struct CreateConfigRequest {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inference_params: Option<InferenceParams>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub infra_params: Option<InfraParams>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub visibility: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateConfigRequest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub inference_params: Option<InferenceParams>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub infra_params: Option<InfraParams>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub visibility: Option<String>,
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


// ============================================================================
// Validation
// ============================================================================

/// Valid Fargate CPU/memory combinations
const VALID_FARGATE_CONFIGS: &[(u32, &[u32])] = &[
    (256, &[512, 1024, 2048]),
    (512, &[1024, 2048, 3072, 4096]),
    (1024, &[2048, 3072, 4096, 5120, 6144, 7168, 8192]),
    (2048, &[4096, 5120, 6144, 7168, 8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384]),
    (4096, &[8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384, 17408, 18432, 19456, 20480, 21504, 22528, 23552, 24576, 25600, 26624, 27648, 28672, 29696, 30720]),
    (8192, &[16384, 20480, 24576, 28672, 32768, 36864, 40960, 45056, 49152, 53248, 57344, 61440]),
    (16384, &[32768, 40960, 49152, 57344, 65536, 73728, 81920, 90112, 98304, 106496, 114688, 122880]),
];

/// Valid Fargate CPU values
const VALID_FARGATE_CPU: &[u32] = &[256, 512, 1024, 2048, 4096, 8192, 16384];

fn validate_fargate_cpu_memory(cpu: u32, memory_mib: u32) -> Result<(), String> {
    for (valid_cpu, valid_memories) in VALID_FARGATE_CONFIGS {
        if cpu == *valid_cpu {
            if valid_memories.contains(&memory_mib) {
                return Ok(());
            } else {
                return Err(format!(
                    "Invalid memory {} MiB for CPU {}. Valid values: {:?}",
                    memory_mib, cpu, valid_memories
                ));
            }
        }
    }
    Err(format!(
        "Invalid CPU value {}. Valid Fargate values: {:?}",
        cpu, VALID_FARGATE_CPU
    ))
}

fn validate_infra_params(params: &InfraParams) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();

    // Validate CPU (Fargate values or EC2 range 1-96)
    if let Some(cpu) = params.cpu {
        let is_valid_fargate = VALID_FARGATE_CPU.contains(&cpu);
        let is_valid_ec2 = cpu >= 1 && cpu <= 96;
        if !is_valid_fargate && !is_valid_ec2 {
            errors.push(format!(
                "Invalid CPU value {}. Must be valid Fargate ({:?}) or EC2 (1-96)",
                cpu, VALID_FARGATE_CPU
            ));
        }
    }

    // Validate CPU/memory combination for Fargate
    if let (Some(cpu), Some(memory)) = (params.cpu, params.memory_mib) {
        if VALID_FARGATE_CPU.contains(&cpu) {
            if let Err(e) = validate_fargate_cpu_memory(cpu, memory) {
                errors.push(e);
            }
        }
    }

    // Validate GPU count (0-4)
    if let Some(gpu_count) = params.gpu_count {
        if gpu_count > 4 {
            errors.push(format!(
                "Invalid GPU count {}. Must be between 0 and 4",
                gpu_count
            ));
        }
    }

    // Validate timeout (1-180 minutes)
    if let Some(timeout) = params.timeout_minutes {
        if timeout < 1 || timeout > 180 {
            errors.push(format!(
                "Invalid timeout {} minutes. Must be between 1 and 180",
                timeout
            ));
        }
    }

    // Validate ephemeral storage (21-200 GiB for Fargate)
    if let Some(storage) = params.ephemeral_storage_gib {
        if storage < 21 || storage > 200 {
            errors.push(format!(
                "Invalid ephemeral storage {} GiB. Must be between 21 and 200",
                storage
            ));
        }
    }

    // Validate EBS volume size (30-500 GB for EC2)
    if let Some(ebs) = params.ebs_volume_size_gb {
        if ebs < 30 || ebs > 500 {
            errors.push(format!(
                "Invalid EBS volume size {} GB. Must be between 30 and 500",
                ebs
            ));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}


// ============================================================================
// DynamoDB Helpers
// ============================================================================

fn config_to_dynamodb(config: &ConfigResponse) -> HashMap<String, AttributeValue> {
    let mut item = HashMap::new();
    
    item.insert("config_id".to_string(), AttributeValue::S(config.config_id.clone()));
    item.insert("user_id".to_string(), AttributeValue::S(config.user_id.clone()));
    item.insert("model".to_string(), AttributeValue::S(config.model.clone()));
    item.insert("name".to_string(), AttributeValue::S(config.name.clone()));
    item.insert("created_at".to_string(), AttributeValue::S(config.created_at.clone()));
    item.insert("updated_at".to_string(), AttributeValue::S(config.updated_at.clone()));
    item.insert("approval_status".to_string(), AttributeValue::S(config.approval_status.clone()));
    item.insert("visibility".to_string(), AttributeValue::S(config.visibility.clone()));
    item.insert("usage_count".to_string(), AttributeValue::N(config.usage_count.to_string()));
    
    if let Some(ref desc) = config.description {
        item.insert("description".to_string(), AttributeValue::S(desc.clone()));
    }
    
    // Serialize inference_params as JSON
    let inference_json = serde_json::to_string(&config.inference_params).unwrap_or_default();
    item.insert("inference_params".to_string(), AttributeValue::S(inference_json));
    
    // Serialize infra_params as JSON
    let infra_json = serde_json::to_string(&config.infra_params).unwrap_or_default();
    item.insert("infra_params".to_string(), AttributeValue::S(infra_json));
    
    if let Some(ref approved_by) = config.approved_by {
        item.insert("approved_by".to_string(), AttributeValue::S(approved_by.clone()));
    }
    if let Some(ref approved_at) = config.approved_at {
        item.insert("approved_at".to_string(), AttributeValue::S(approved_at.clone()));
    }
    if let Some(ref rejection_reason) = config.rejection_reason {
        item.insert("rejection_reason".to_string(), AttributeValue::S(rejection_reason.clone()));
    }
    if let Some(ref task_def_arn) = config.task_definition_arn {
        item.insert("task_definition_arn".to_string(), AttributeValue::S(task_def_arn.clone()));
    }
    if let Some(ref task_def_status) = config.task_definition_status {
        item.insert("task_definition_status".to_string(), AttributeValue::S(task_def_status.clone()));
    }
    if let Some(ref forked_from) = config.forked_from {
        item.insert("forked_from".to_string(), AttributeValue::S(forked_from.clone()));
    }
    
    item
}

fn dynamodb_to_config(item: &HashMap<String, AttributeValue>) -> Option<ConfigResponse> {
    let config_id = item.get("config_id")?.as_s().ok()?.clone();
    let user_id = item.get("user_id")?.as_s().ok()?.clone();
    let model = item.get("model")?.as_s().ok()?.clone();
    let name = item.get("name")?.as_s().ok()?.clone();
    let created_at = item.get("created_at")?.as_s().ok()?.clone();
    let updated_at = item.get("updated_at")?.as_s().ok()?.clone();
    let approval_status = item.get("approval_status")?.as_s().ok()?.clone();
    let visibility = item.get("visibility").and_then(|v| v.as_s().ok()).cloned().unwrap_or_else(|| "private".to_string());
    let usage_count = item.get("usage_count")
        .and_then(|v| v.as_n().ok())
        .and_then(|n| n.parse::<u64>().ok())
        .unwrap_or(0);
    
    let description = item.get("description").and_then(|v| v.as_s().ok()).cloned();
    
    let inference_params: InferenceParams = item.get("inference_params")
        .and_then(|v| v.as_s().ok())
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();
    
    let infra_params: InfraParams = item.get("infra_params")
        .and_then(|v| v.as_s().ok())
        .and_then(|s| serde_json::from_str(s).ok())
        .unwrap_or_default();
    
    let approved_by = item.get("approved_by").and_then(|v| v.as_s().ok()).cloned();
    let approved_at = item.get("approved_at").and_then(|v| v.as_s().ok()).cloned();
    let rejection_reason = item.get("rejection_reason").and_then(|v| v.as_s().ok()).cloned();
    let task_definition_arn = item.get("task_definition_arn").and_then(|v| v.as_s().ok()).cloned();
    let task_definition_status = item.get("task_definition_status").and_then(|v| v.as_s().ok()).cloned();
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

async fn create_config(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    model: &str,
    body: CreateConfigRequest,
) -> Response {
    // Validate infra params if provided
    if let Some(ref infra_params) = body.infra_params {
        if let Err(errors) = validate_infra_params(infra_params) {
            return Response::error_with_details(400, "Invalid infrastructure parameters", errors);
        }
    }

    // Check user limits: 10 per model, 50 total
    let model_count = count_user_configs_for_model(client, table_name, user_id, model).await;
    if model_count >= 10 {
        return Response::error(400, &format!(
            "Configuration limit reached: maximum 10 configurations per model (current: {})",
            model_count
        ));
    }

    let total_count = count_user_total_configs(client, table_name, user_id).await;
    if total_count >= 50 {
        return Response::error(400, &format!(
            "Configuration limit reached: maximum 50 total configurations (current: {})",
            total_count
        ));
    }

    let now = Utc::now().to_rfc3339();
    let config_id = Uuid::new_v4().to_string();
    let visibility = body.visibility.unwrap_or_else(|| "private".to_string());

    // Validate visibility value
    if visibility != "private" && visibility != "public" {
        return Response::error(400, "Invalid visibility value. Must be 'private' or 'public'");
    }

    let config = ConfigResponse {
        config_id: config_id.clone(),
        user_id: user_id.to_string(),
        model: model.to_string(),
        name: body.name,
        description: body.description,
        created_at: now.clone(),
        updated_at: now,
        inference_params: body.inference_params.unwrap_or_default(),
        infra_params: body.infra_params.unwrap_or_default(),
        approval_status: "pending_approval".to_string(),
        approved_by: None,
        approved_at: None,
        rejection_reason: None,
        task_definition_arn: None,
        task_definition_status: None,
        visibility,
        usage_count: 0,
        forked_from: None,
    };

    let item = config_to_dynamodb(&config);

    match client
        .put_item()
        .table_name(table_name)
        .set_item(Some(item))
        .send()
        .await
    {
        Ok(_) => {
            info!("Created configuration: {}", config_id);
            Response::new(201, json!(config))
        }
        Err(e) => {
            info!("Failed to create configuration: {}", e);
            Response::error(500, "Failed to create configuration")
        }
    }
}

async fn count_user_configs_for_model(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    model: &str,
) -> usize {
    // Query using GSI user_id-created_at-index and filter by model
    match client
        .query()
        .table_name(table_name)
        .index_name("user_id-created_at-index")
        .key_condition_expression("user_id = :uid")
        .filter_expression("model = :model")
        .expression_attribute_values(":uid", AttributeValue::S(user_id.to_string()))
        .expression_attribute_values(":model", AttributeValue::S(model.to_string()))
        .select(aws_sdk_dynamodb::types::Select::Count)
        .send()
        .await
    {
        Ok(result) => result.count() as usize,
        Err(_) => 0,
    }
}

async fn count_user_total_configs(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
) -> usize {
    // Query using GSI user_id-created_at-index
    match client
        .query()
        .table_name(table_name)
        .index_name("user_id-created_at-index")
        .key_condition_expression("user_id = :uid")
        .expression_attribute_values(":uid", AttributeValue::S(user_id.to_string()))
        .select(aws_sdk_dynamodb::types::Select::Count)
        .send()
        .await
    {
        Ok(result) => result.count() as usize,
        Err(_) => 0,
    }
}

async fn list_configs(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    model: &str,
) -> Response {
    // Query using GSI user_id-created_at-index and filter by model
    match client
        .query()
        .table_name(table_name)
        .index_name("user_id-created_at-index")
        .key_condition_expression("user_id = :uid")
        .filter_expression("model = :model")
        .expression_attribute_values(":uid", AttributeValue::S(user_id.to_string()))
        .expression_attribute_values(":model", AttributeValue::S(model.to_string()))
        .scan_index_forward(false) // Most recent first
        .send()
        .await
    {
        Ok(result) => {
            let configs: Vec<ConfigResponse> = result
                .items()
                .iter()
                .filter_map(|item| dynamodb_to_config(item))
                .collect();
            Response::new(200, json!({ "configurations": configs }))
        }
        Err(e) => {
            info!("Failed to list configurations: {}", e);
            Response::error(500, "Failed to list configurations")
        }
    }
}


async fn get_config(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    config_id: &str,
) -> Response {
    match client
        .get_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
    {
        Ok(result) => {
            match result.item() {
                Some(item) => {
                    if let Some(config) = dynamodb_to_config(item) {
                        // Check access: owner, or public+approved
                        let is_owner = config.user_id == user_id;
                        let is_public_approved = config.visibility == "public" && config.approval_status == "approved";
                        
                        if is_owner || is_public_approved {
                            Response::new(200, json!(config))
                        } else {
                            Response::error(403, "Access denied to this configuration")
                        }
                    } else {
                        Response::error(500, "Failed to parse configuration")
                    }
                }
                None => Response::error(404, "Configuration not found"),
            }
        }
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            Response::error(500, "Failed to get configuration")
        }
    }
}

async fn update_config(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    config_id: &str,
    body: UpdateConfigRequest,
) -> Response {
    // First, fetch the existing config to verify ownership
    let existing = match client
        .get_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
    {
        Ok(result) => match result.item() {
            Some(item) => match dynamodb_to_config(item) {
                Some(config) => config,
                None => return Response::error(500, "Failed to parse configuration"),
            },
            None => return Response::error(404, "Configuration not found"),
        },
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            return Response::error(500, "Failed to get configuration");
        }
    };

    // Verify ownership
    if existing.user_id != user_id {
        return Response::error(403, "You do not own this configuration");
    }

    // Validate infra params if provided
    if let Some(ref infra_params) = body.infra_params {
        if let Err(errors) = validate_infra_params(infra_params) {
            return Response::error_with_details(400, "Invalid infrastructure parameters", errors);
        }
    }

    // Validate visibility if provided
    if let Some(ref visibility) = body.visibility {
        if visibility != "private" && visibility != "public" {
            return Response::error(400, "Invalid visibility value. Must be 'private' or 'public'");
        }
    }

    let now = Utc::now().to_rfc3339();

    // Build updated config - reset approval_status and clear task_definition_arn
    let updated_config = ConfigResponse {
        config_id: existing.config_id,
        user_id: existing.user_id,
        model: existing.model,
        name: body.name.unwrap_or(existing.name),
        description: body.description.or(existing.description),
        created_at: existing.created_at,
        updated_at: now,
        inference_params: body.inference_params.unwrap_or(existing.inference_params),
        infra_params: body.infra_params.unwrap_or(existing.infra_params),
        approval_status: "pending_approval".to_string(), // Reset on update
        approved_by: None,                               // Clear on update
        approved_at: None,                               // Clear on update
        rejection_reason: None,                          // Clear on update
        task_definition_arn: None,                       // Clear on update
        task_definition_status: None,                    // Clear on update
        visibility: body.visibility.unwrap_or(existing.visibility),
        usage_count: existing.usage_count,
        forked_from: existing.forked_from,
    };

    let item = config_to_dynamodb(&updated_config);

    match client
        .put_item()
        .table_name(table_name)
        .set_item(Some(item))
        .send()
        .await
    {
        Ok(_) => {
            info!("Updated configuration: {}", config_id);
            Response::new(200, json!(updated_config))
        }
        Err(e) => {
            info!("Failed to update configuration: {}", e);
            Response::error(500, "Failed to update configuration")
        }
    }
}

async fn delete_config(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    config_id: &str,
) -> Response {
    // First, fetch the existing config to verify ownership
    let existing = match client
        .get_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
    {
        Ok(result) => match result.item() {
            Some(item) => match dynamodb_to_config(item) {
                Some(config) => config,
                None => return Response::error(500, "Failed to parse configuration"),
            },
            None => return Response::error(404, "Configuration not found"),
        },
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            return Response::error(500, "Failed to get configuration");
        }
    };

    // Verify ownership
    if existing.user_id != user_id {
        return Response::error(403, "You do not own this configuration");
    }

    match client
        .delete_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
    {
        Ok(_) => {
            info!("Deleted configuration: {}", config_id);
            Response::new(204, json!({}))
        }
        Err(e) => {
            info!("Failed to delete configuration: {}", e);
            Response::error(500, "Failed to delete configuration")
        }
    }
}


async fn fork_config(
    client: &DynamoDbClient,
    table_name: &str,
    user_id: &str,
    config_id: &str,
    model: &str,
) -> Response {
    // First, fetch the source config
    let source = match client
        .get_item()
        .table_name(table_name)
        .key("config_id", AttributeValue::S(config_id.to_string()))
        .send()
        .await
    {
        Ok(result) => match result.item() {
            Some(item) => match dynamodb_to_config(item) {
                Some(config) => config,
                None => return Response::error(500, "Failed to parse configuration"),
            },
            None => return Response::error(404, "Configuration not found"),
        },
        Err(e) => {
            info!("Failed to get configuration: {}", e);
            return Response::error(500, "Failed to get configuration");
        }
    };

    // Check access: owner, or public+approved
    let is_owner = source.user_id == user_id;
    let is_public_approved = source.visibility == "public" && source.approval_status == "approved";
    
    if !is_owner && !is_public_approved {
        return Response::error(403, "Access denied to this configuration");
    }

    // Check user limits before forking
    let model_count = count_user_configs_for_model(client, table_name, user_id, model).await;
    if model_count >= 10 {
        return Response::error(400, &format!(
            "Configuration limit reached: maximum 10 configurations per model (current: {})",
            model_count
        ));
    }

    let total_count = count_user_total_configs(client, table_name, user_id).await;
    if total_count >= 50 {
        return Response::error(400, &format!(
            "Configuration limit reached: maximum 50 total configurations (current: {})",
            total_count
        ));
    }

    let now = Utc::now().to_rfc3339();
    let new_config_id = Uuid::new_v4().to_string();

    // Create forked config
    let forked_config = ConfigResponse {
        config_id: new_config_id.clone(),
        user_id: user_id.to_string(),
        model: model.to_string(),
        name: format!("{} (fork)", source.name),
        description: source.description,
        created_at: now.clone(),
        updated_at: now,
        inference_params: source.inference_params,
        infra_params: source.infra_params,
        approval_status: "pending_approval".to_string(),
        approved_by: None,
        approved_at: None,
        rejection_reason: None,
        task_definition_arn: None,
        task_definition_status: None,
        visibility: "private".to_string(), // Forked configs start as private
        usage_count: 0,
        forked_from: Some(config_id.to_string()),
    };

    let item = config_to_dynamodb(&forked_config);

    match client
        .put_item()
        .table_name(table_name)
        .set_item(Some(item))
        .send()
        .await
    {
        Ok(_) => {
            info!("Forked configuration {} to {}", config_id, new_config_id);
            Response::new(201, json!(forked_config))
        }
        Err(e) => {
            info!("Failed to fork configuration: {}", e);
            Response::error(500, "Failed to fork configuration")
        }
    }
}

async fn discover_configs(
    client: &DynamoDbClient,
    table_name: &str,
    model_filter: Option<&str>,
) -> Response {
    // Query using GSI visibility-model-index for public configs
    let mut query = client
        .query()
        .table_name(table_name)
        .index_name("visibility-model-index")
        .key_condition_expression("visibility = :vis")
        .filter_expression("approval_status = :status")
        .expression_attribute_values(":vis", AttributeValue::S("public".to_string()))
        .expression_attribute_values(":status", AttributeValue::S("approved".to_string()));

    // Add model filter if provided
    if let Some(model) = model_filter {
        query = query
            .key_condition_expression("visibility = :vis AND model = :model")
            .expression_attribute_values(":model", AttributeValue::S(model.to_string()));
    }

    match query.send().await {
        Ok(result) => {
            let configs: Vec<ConfigResponse> = result
                .items()
                .iter()
                .filter_map(|item| dynamodb_to_config(item))
                .collect();
            Response::new(200, json!({ "configurations": configs }))
        }
        Err(e) => {
            info!("Failed to discover configurations: {}", e);
            Response::error(500, "Failed to discover configurations")
        }
    }
}


// ============================================================================
// Main Handler
// ============================================================================

async fn function_handler(event: LambdaEvent<Request>) -> Result<Response, Error> {
    let (request, _context) = event.into_parts();

    info!("Processing config-crud request");

    // Extract user ID from Cognito claims
    let user_id = match &request.request_context.authorizer {
        Some(Authorizer::RestApi { claims }) => &claims.sub,
        Some(Authorizer::HttpApiV2 { jwt }) => &jwt.claims.sub,
        None => {
            return Ok(Response::error(401, "No authorizer context found"));
        }
    };

    // Get HTTP method (support both REST API and HTTP API v2 formats)
    let method = request
        .http_method
        .as_deref()
        .or_else(|| request.request_context.http.as_ref().map(|h| h.method.as_str()))
        .unwrap_or("GET");

    // Get path parameters
    let path_params = request.path_parameters.as_ref();
    let model = path_params.and_then(|p| p.model.as_deref());
    let config_id = path_params.and_then(|p| p.config_id.as_deref());

    // Get table name from environment
    let table_name = env::var("CONFIGURATIONS_TABLE_NAME")
        .unwrap_or_else(|_| "pdf-models-configurations".to_string());

    // Initialize AWS clients
    let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let dynamodb_client = DynamoDbClient::new(&config);

    // Determine route based on resource pattern and method
    // Routes:
    // POST   /v1/models/{model}/configs                    -> create
    // GET    /v1/models/{model}/configs                    -> list
    // GET    /v1/models/{model}/configs/{config_id}        -> get
    // PUT    /v1/models/{model}/configs/{config_id}        -> update
    // DELETE /v1/models/{model}/configs/{config_id}        -> delete
    // POST   /v1/models/{model}/configs/{config_id}/fork   -> fork
    // GET    /v1/configs/discover                          -> discover

    // Check for discover route first (no model required)
    let resource = request.resource.as_deref().unwrap_or("");
    let route_key = request.route_key.as_deref().unwrap_or("");
    
    let is_discover = resource.contains("/configs/discover") 
        || route_key.contains("/configs/discover")
        || (model.is_none() && method == "GET");

    if is_discover {
        return Ok(discover_configs(&dynamodb_client, &table_name, None).await);
    }

    // For other routes, model is required
    let model = match model {
        Some(m) => m,
        None => return Ok(Response::error(400, "Model parameter is required")),
    };

    // Check for fork route
    let is_fork = resource.contains("/fork") || route_key.contains("/fork");

    match (method, config_id, is_fork) {
        // POST /v1/models/{model}/configs/{config_id}/fork
        ("POST", Some(cid), true) => {
            Ok(fork_config(&dynamodb_client, &table_name, user_id, cid, model).await)
        }
        // POST /v1/models/{model}/configs
        ("POST", None, false) => {
            let body: CreateConfigRequest = match request.body {
                Some(body_str) if !body_str.is_empty() => match serde_json::from_str(&body_str) {
                    Ok(body) => body,
                    Err(e) => {
                        return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
                    }
                },
                _ => return Ok(Response::error(400, "Request body is required")),
            };
            Ok(create_config(&dynamodb_client, &table_name, user_id, model, body).await)
        }
        // GET /v1/models/{model}/configs
        ("GET", None, false) => {
            Ok(list_configs(&dynamodb_client, &table_name, user_id, model).await)
        }
        // GET /v1/models/{model}/configs/{config_id}
        ("GET", Some(cid), false) => {
            Ok(get_config(&dynamodb_client, &table_name, user_id, cid).await)
        }
        // PUT /v1/models/{model}/configs/{config_id}
        ("PUT", Some(cid), false) => {
            let body: UpdateConfigRequest = match request.body {
                Some(body_str) if !body_str.is_empty() => match serde_json::from_str(&body_str) {
                    Ok(body) => body,
                    Err(e) => {
                        return Ok(Response::error(400, &format!("Invalid request body: {}", e)));
                    }
                },
                _ => return Ok(Response::error(400, "Request body is required")),
            };
            Ok(update_config(&dynamodb_client, &table_name, user_id, cid, body).await)
        }
        // DELETE /v1/models/{model}/configs/{config_id}
        ("DELETE", Some(cid), false) => {
            Ok(delete_config(&dynamodb_client, &table_name, user_id, cid).await)
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
