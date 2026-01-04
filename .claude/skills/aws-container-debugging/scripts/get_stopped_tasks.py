#!/Users/steven/code/pdf-models/backend/.venv/bin/python3
"""Get stopped ECS tasks and their stop reasons."""

import boto3

def get_stopped_tasks():
    """Get recent stopped tasks and why they stopped."""
    session = boto3.Session(profile_name='arch', region_name='us-east-1')
    ecs = session.client('ecs')
    cluster = 'pdf-models-marker-cluster'

    # Get stopped tasks
    tasks_response = ecs.list_tasks(cluster=cluster, maxResults=10, desiredStatus='STOPPED')
    task_arns = tasks_response.get('taskArns', [])

    if not task_arns:
        print("No stopped tasks found")
        return

    # Describe tasks
    tasks_detail = ecs.describe_tasks(cluster=cluster, tasks=task_arns)

    print("=== Recent Stopped Tasks ===\n")
    for task in tasks_detail['tasks']:
        task_id = task['taskArn'].split('/')[-1]
        container = task['containers'][0] if task['containers'] else {}

        print(f"Task ID: {task_id}")
        print(f"Created: {task.get('createdAt')}")
        print(f"Stopped: {task.get('stoppedAt')}")
        print(f"Stop reason: {task.get('stoppedReason', 'N/A')}")
        print(f"Exit code: {container.get('exitCode', 'N/A')}")
        print(f"Reason: {container.get('reason', 'N/A')}")
        print("-" * 80)

if __name__ == '__main__':
    get_stopped_tasks()
