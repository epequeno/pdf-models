#!/usr/bin/env python3
"""Get Step Functions execution details including all events and outputs."""

import boto3
import json
import sys

def get_execution_details(execution_name_or_arn):
    """Get detailed execution information."""
    sfn = boto3.client('stepfunctions', region_name='us-east-1')

    # If just name provided, construct full ARN
    if not execution_name_or_arn.startswith('arn:'):
        state_machine_arn = 'arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker'
        execution_arn = f"{state_machine_arn.replace(':stateMachine:', ':execution:')}:{execution_name_or_arn}"
    else:
        execution_arn = execution_name_or_arn

    # Get execution details
    try:
        execution = sfn.describe_execution(executionArn=execution_arn)
    except Exception as e:
        print(f"Error fetching execution: {e}")
        sys.exit(1)

    print("=" * 80)
    print("EXECUTION DETAILS")
    print("=" * 80)
    print(f"Name: {execution['name']}")
    print(f"Status: {execution['status']}")
    print(f"Started: {execution['startDate']}")
    print(f"Stopped: {execution.get('stopDate', 'N/A')}")
    print()

    # Get execution history
    history = sfn.get_execution_history(
        executionArn=execution_arn,
        maxResults=100,
        reverseOrder=False
    )

    print("=" * 80)
    print("EXECUTION EVENTS")
    print("=" * 80)

    task_outputs = {}

    for event in history['events']:
        event_type = event['type']
        timestamp = event['timestamp']

        if event_type == 'ExecutionStarted':
            input_data = json.loads(event['executionStartedEventDetails']['input'])
            print(f"\n[{timestamp}] Execution Started")
            print(f"Input: {json.dumps(input_data, indent=2)}")

        elif event_type == 'LambdaFunctionScheduled':
            details = event['lambdaFunctionScheduledEventDetails']
            print(f"\n[{timestamp}] Lambda Scheduled: {details.get('resource', 'N/A')}")

        elif event_type == 'LambdaFunctionSucceeded':
            details = event['lambdaFunctionSucceededEventDetails']
            output = json.loads(details.get('output', '{}'))
            print(f"\n[{timestamp}] Lambda Succeeded")
            print(f"Output: {json.dumps(output, indent=2)}")
            task_outputs['lambda'] = output

        elif event_type == 'LambdaFunctionFailed':
            details = event['lambdaFunctionFailedEventDetails']
            print(f"\n[{timestamp}] ❌ Lambda Failed")
            print(f"Error: {details.get('error', 'Unknown')}")
            print(f"Cause: {details.get('cause', 'Unknown')}")

        elif event_type == 'TaskScheduled':
            details = event['taskScheduledEventDetails']
            print(f"\n[{timestamp}] Task Scheduled: {details['resource']}")
            params = json.loads(details.get('parameters', '{}'))
            print(f"Parameters: {json.dumps(params, indent=2)}")

        elif event_type == 'TaskSucceeded':
            details = event['taskSucceededEventDetails']
            output = json.loads(details.get('output', '{}'))
            print(f"\n[{timestamp}] Task Succeeded")

            # For ECS tasks, extract useful info
            if 'Containers' in output:
                container = output['Containers'][0]
                print(f"Exit Code: {container.get('ExitCode', 'N/A')}")
                print(f"Reason: {container.get('Reason', 'N/A')}")

            task_outputs['task'] = output

        elif event_type == 'TaskFailed':
            details = event['taskFailedEventDetails']
            print(f"\n[{timestamp}] ❌ Task Failed")
            print(f"Error: {details.get('error', 'Unknown')}")
            print(f"Cause: {details.get('cause', 'Unknown')}")

        elif event_type == 'ExecutionSucceeded':
            print(f"\n[{timestamp}] ✓ Execution Succeeded")
            output = json.loads(event['executionSucceededEventDetails'].get('output', '{}'))
            print(f"Final Output: {json.dumps(output, indent=2)}")

        elif event_type == 'ExecutionFailed':
            details = event['executionFailedEventDetails']
            print(f"\n[{timestamp}] ❌ Execution Failed")
            print(f"Error: {details.get('error', 'Unknown')}")
            print(f"Cause: {details.get('cause', 'Unknown')}")

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    if task_outputs:
        if 'task' in task_outputs and 'Containers' in task_outputs['task']:
            container = task_outputs['task']['Containers'][0]
            exit_code = container.get('ExitCode')

            if exit_code == 0:
                print("✓ Container exited successfully (exit code 0)")
            else:
                print(f"✗ Container failed with exit code {exit_code}")

                if exit_code == 137:
                    print("  → Exit code 137: Out of memory (OOM)")
                elif exit_code == 1:
                    print("  → Exit code 1: Application error (check logs)")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python get_execution.py <execution-name-or-arn>")
        sys.exit(1)

    get_execution_details(sys.argv[1])
