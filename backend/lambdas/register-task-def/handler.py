"""
Register Task Definition Lambda

This Lambda is invoked by config-admin when a configuration is approved.
It creates a new ECS task definition based on the configuration's infrastructure parameters.

Event format:
{
    "config_id": "uuid",
    "model": "marker",
    "infra_params": {
        "cpu": 4096,
        "memory_mib": 16384,
        "gpu_count": 0,
        "timeout_minutes": 60,
        "ephemeral_storage_gib": 50,
        "ebs_volume_size_gb": null,
        "spot_enabled": false
    }
}

Returns:
{
    "task_definition_arn": "arn:aws:ecs:...",
    "status": "active" | "failed",
    "error": "optional error message"
}
"""

import json
import logging
import os
from typing import Any

import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ecs_client = boto3.client("ecs")
ssm_client = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")


def get_base_task_definition_arn(model: str) -> str:
    """Read base task definition ARN from SSM parameter."""
    param_name = f"/pdf-models/{model}/task-definition-arn"
    try:
        response = ssm_client.get_parameter(Name=param_name)
        return response["Parameter"]["Value"]
    except ClientError as e:
        logger.error(f"Failed to get SSM parameter {param_name}: {e}")
        raise ValueError(f"Base task definition not found for model: {model}")


def describe_task_definition(task_def_arn: str) -> dict[str, Any]:
    """Describe an existing task definition to use as a template."""
    try:
        response = ecs_client.describe_task_definition(taskDefinition=task_def_arn)
        return response["taskDefinition"]
    except ClientError as e:
        logger.error(f"Failed to describe task definition {task_def_arn}: {e}")
        raise ValueError(f"Failed to describe base task definition: {e}")



def derive_task_definition(
    base_task_def: dict[str, Any],
    config_id: str,
    model: str,
    infra_params: dict[str, Any],
) -> dict[str, Any]:
    """
    Derive a new task definition from the base, applying custom infrastructure parameters.
    
    The new task definition family follows the pattern: pdf-models-{model}-user-{config_id[:8]}
    """
    # Generate new family name
    family = f"pdf-models-{model}-user-{config_id[:8]}"
    
    # Start with base task definition parameters
    # We need to extract only the parameters that can be passed to register_task_definition
    new_task_def: dict[str, Any] = {
        "family": family,
        "containerDefinitions": base_task_def.get("containerDefinitions", []),
        "taskRoleArn": base_task_def.get("taskRoleArn"),
        "executionRoleArn": base_task_def.get("executionRoleArn"),
        "networkMode": base_task_def.get("networkMode", "awsvpc"),
        "volumes": base_task_def.get("volumes", []),
        "placementConstraints": base_task_def.get("placementConstraints", []),
        "requiresCompatibilities": base_task_def.get("requiresCompatibilities", []),
        "tags": base_task_def.get("tags", []),
    }
    
    # Determine if this is a Fargate or EC2 task
    requires_compatibilities = base_task_def.get("requiresCompatibilities", [])
    is_fargate = "FARGATE" in requires_compatibilities
    is_ec2 = "EC2" in requires_compatibilities or not is_fargate
    
    # Apply CPU override
    if infra_params.get("cpu"):
        cpu_value = str(infra_params["cpu"])
        new_task_def["cpu"] = cpu_value
        # Also update container CPU if present
        for container in new_task_def["containerDefinitions"]:
            if "cpu" in container:
                container["cpu"] = infra_params["cpu"]
    elif base_task_def.get("cpu"):
        new_task_def["cpu"] = base_task_def["cpu"]
    
    # Apply memory override
    if infra_params.get("memory_mib"):
        memory_value = str(infra_params["memory_mib"])
        new_task_def["memory"] = memory_value
        # Also update container memory if present
        for container in new_task_def["containerDefinitions"]:
            if "memory" in container:
                container["memory"] = infra_params["memory_mib"]
            if "memoryReservation" in container:
                container["memoryReservation"] = infra_params["memory_mib"]
    elif base_task_def.get("memory"):
        new_task_def["memory"] = base_task_def["memory"]
    
    # Apply GPU override (EC2 only)
    if infra_params.get("gpu_count") and infra_params["gpu_count"] > 0:
        for container in new_task_def["containerDefinitions"]:
            # Update or add GPU resource requirement
            resource_requirements = container.get("resourceRequirements", [])
            # Remove existing GPU requirement if present
            resource_requirements = [r for r in resource_requirements if r.get("type") != "GPU"]
            # Add new GPU requirement
            resource_requirements.append({
                "type": "GPU",
                "value": str(infra_params["gpu_count"])
            })
            container["resourceRequirements"] = resource_requirements
    
    # Apply ephemeral storage override (Fargate only)
    if is_fargate and infra_params.get("ephemeral_storage_gib"):
        new_task_def["ephemeralStorage"] = {
            "sizeInGiB": infra_params["ephemeral_storage_gib"]
        }
    elif is_fargate and base_task_def.get("ephemeralStorage"):
        new_task_def["ephemeralStorage"] = base_task_def["ephemeralStorage"]
    
    # Copy runtime platform if present (Fargate)
    if base_task_def.get("runtimePlatform"):
        new_task_def["runtimePlatform"] = base_task_def["runtimePlatform"]
    
    # Copy PID mode and IPC mode if present
    if base_task_def.get("pidMode"):
        new_task_def["pidMode"] = base_task_def["pidMode"]
    if base_task_def.get("ipcMode"):
        new_task_def["ipcMode"] = base_task_def["ipcMode"]
    
    # Remove None values
    new_task_def = {k: v for k, v in new_task_def.items() if v is not None}
    
    return new_task_def


def register_task_definition(task_def_params: dict[str, Any]) -> str:
    """Register a new task definition and return its ARN."""
    try:
        response = ecs_client.register_task_definition(**task_def_params)
        task_def_arn = response["taskDefinition"]["taskDefinitionArn"]
        logger.info(f"Registered task definition: {task_def_arn}")
        return task_def_arn
    except ClientError as e:
        logger.error(f"Failed to register task definition: {e}")
        raise ValueError(f"Failed to register task definition: {e}")


def update_configuration(
    config_id: str,
    task_definition_arn: str | None,
    status: str,
    error: str | None = None,
) -> None:
    """Update the configuration in DynamoDB with task definition status."""
    table_name = os.environ.get("CONFIGURATIONS_TABLE_NAME", "pdf-models-configurations")
    table = dynamodb.Table(table_name)
    
    update_expr = "SET task_definition_status = :status, updated_at = :updated"
    expr_values: dict[str, Any] = {
        ":status": status,
        ":updated": __import__("datetime").datetime.utcnow().isoformat() + "Z",
    }
    
    if task_definition_arn:
        update_expr += ", task_definition_arn = :arn"
        expr_values[":arn"] = task_definition_arn
    
    if error:
        update_expr += ", task_definition_error = :error"
        expr_values[":error"] = error
    
    try:
        table.update_item(
            Key={"config_id": config_id},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expr_values,
        )
        logger.info(f"Updated configuration {config_id} with status: {status}")
    except ClientError as e:
        logger.error(f"Failed to update configuration {config_id}: {e}")
        # Don't raise - we want to return the result even if DynamoDB update fails


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Main Lambda handler.
    
    Receives configuration details and creates a new ECS task definition.
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Extract parameters from event
    config_id = event.get("config_id")
    model = event.get("model")
    infra_params = event.get("infra_params", {})
    
    if not config_id:
        return {
            "status": "failed",
            "error": "config_id is required",
        }
    
    if not model:
        return {
            "status": "failed",
            "error": "model is required",
        }
    
    try:
        # Step 1: Get base task definition ARN from SSM
        base_task_def_arn = get_base_task_definition_arn(model)
        logger.info(f"Base task definition ARN: {base_task_def_arn}")
        
        # Step 2: Describe the base task definition
        base_task_def = describe_task_definition(base_task_def_arn)
        logger.info(f"Base task definition family: {base_task_def.get('family')}")
        
        # Step 3: Derive new task definition with custom parameters
        new_task_def_params = derive_task_definition(
            base_task_def, config_id, model, infra_params
        )
        logger.info(f"New task definition family: {new_task_def_params.get('family')}")
        
        # Step 4: Register the new task definition
        task_def_arn = register_task_definition(new_task_def_params)
        
        # Step 5: Update configuration with success
        update_configuration(config_id, task_def_arn, "active")
        
        return {
            "task_definition_arn": task_def_arn,
            "status": "active",
        }
        
    except ValueError as e:
        error_msg = str(e)
        logger.error(f"Task definition registration failed: {error_msg}")
        
        # Update configuration with failure
        update_configuration(config_id, None, "failed", error_msg)
        
        return {
            "status": "failed",
            "error": error_msg,
        }
    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"
        logger.error(error_msg)
        
        # Update configuration with failure
        update_configuration(config_id, None, "failed", error_msg)
        
        return {
            "status": "failed",
            "error": error_msg,
        }
