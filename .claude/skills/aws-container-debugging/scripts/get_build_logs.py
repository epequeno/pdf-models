#!/usr/bin/env python3
"""Get the latest CodeBuild logs for marker container build."""

import boto3
import sys

def get_latest_build_logs(project_name='pdf-models-marker-container-build', lines=100):
    """Fetch the latest build logs."""
    codebuild = boto3.client('codebuild', region_name='us-east-1')
    logs_client = boto3.client('logs', region_name='us-east-1')

    # Get latest build ID
    builds_response = codebuild.list_builds_for_project(
        projectName=project_name,
        sortOrder='DESCENDING',
        nextToken=None
    )

    if not builds_response.get('ids'):
        print(f"No builds found for project {project_name}")
        return

    build_id = builds_response['ids'][0]

    # Get build details
    build_response = codebuild.batch_get_builds(ids=[build_id])
    build = build_response['builds'][0]

    print(f"Build ID: {build_id}")
    print(f"Status: {build['buildStatus']}")
    print(f"Phase: {build.get('currentPhase', 'N/A')}")
    print(f"Start time: {build.get('startTime', 'N/A')}")
    print("-" * 80)

    # Get logs
    log_group = build['logs']['groupName']
    log_stream = build['logs']['streamName']

    try:
        logs_response = logs_client.get_log_events(
            logGroupName=log_group,
            logStreamName=log_stream,
            limit=lines,
            startFromHead=False  # Get most recent logs
        )

        for event in logs_response['events']:
            print(event['message'])

    except Exception as e:
        print(f"Error fetching logs: {e}")
        sys.exit(1)

if __name__ == '__main__':
    lines = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    get_latest_build_logs(lines=lines)
