#!/usr/bin/env python3
"""Check which container image ECS tasks are using."""

import boto3
import json

def check_task_images():
    """Check the container image used by recent ECS tasks."""
    ecs = boto3.client('ecs', region_name='us-east-1')
    ecr = boto3.client('ecr', region_name='us-east-1')

    cluster = 'pdf-models-marker-cluster'

    # Get latest ECR image
    ecr_response = ecr.describe_images(repositoryName='pdf-models/marker')
    images = sorted(ecr_response['imageDetails'], key=lambda x: x['imagePushedAt'], reverse=True)
    latest_ecr = images[0] if images else None

    print("=== Latest ECR Image ===")
    if latest_ecr:
        print(f"Digest: {latest_ecr['imageDigest']}")
        print(f"Tags: {latest_ecr.get('imageTags', [])}")
        print(f"Pushed: {latest_ecr['imagePushedAt']}")
    print()

    # Get recent tasks
    tasks_response = ecs.list_tasks(cluster=cluster, maxResults=5, desiredStatus='STOPPED')
    task_arns = tasks_response.get('taskArns', [])

    if not task_arns:
        print("No recent tasks found")
        return

    # Describe tasks
    tasks_detail = ecs.describe_tasks(cluster=cluster, tasks=task_arns)

    print("=== Recent ECS Tasks ===")
    for task in tasks_detail['tasks']:
        task_id = task['taskArn'].split('/')[-1]
        container = task['containers'][0] if task['containers'] else {}
        image = container.get('image', 'Unknown')

        print(f"\nTask: {task_id}")
        print(f"Image: {image}")
        print(f"Status: {task.get('lastStatus')}")
        print(f"Exit code: {container.get('exitCode', 'N/A')}")

        # Check if using latest ECR image
        if latest_ecr and latest_ecr['imageDigest'] in image:
            print("✓ Using latest ECR image")
        elif latest_ecr:
            print("✗ NOT using latest ECR image")

if __name__ == '__main__':
    check_task_images()
