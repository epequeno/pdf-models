#!/Users/steven/code/pdf-models/backend/.venv/bin/python3
"""List recent failed Step Functions executions."""

import boto3
import json

def list_failed_executions():
    """List recent failed executions with details."""
    session = boto3.Session(profile_name='arch', region_name='us-east-1')
    sfn = session.client('stepfunctions')

    state_machine_arn = 'arn:aws:states:us-east-1:496830984285:stateMachine:pdf-models-marker'

    # Get failed executions
    response = sfn.list_executions(
        stateMachineArn=state_machine_arn,
        statusFilter='FAILED',
        maxResults=10
    )

    executions = response.get('executions', [])

    if not executions:
        print("No failed executions found")
        return

    print("=" * 80)
    print(f"FAILED EXECUTIONS (last {len(executions)})")
    print("=" * 80)

    for execution in executions:
        print(f"\nExecution: {execution['name']}")
        print(f"Started: {execution['startDate']}")
        print(f"Stopped: {execution.get('stopDate', 'N/A')}")

        # Get execution details to see error
        execution_arn = execution['executionArn']
        details = sfn.describe_execution(executionArn=execution_arn)

        if 'error' in details:
            print(f"Error: {details.get('error', 'Unknown')}")

        if 'cause' in details:
            print(f"Cause: {details.get('cause', 'Unknown')}")

        # Get last event to see what failed
        history = sfn.get_execution_history(
            executionArn=execution_arn,
            maxResults=5,
            reverseOrder=True
        )

        for event in history['events']:
            if event['type'] == 'ExecutionFailed':
                event_details = event.get('executionFailedEventDetails', {})
                print(f"Failure reason: {event_details.get('error', 'Unknown')}")
                cause = event_details.get('cause', '')
                if cause:
                    try:
                        cause_json = json.loads(cause)
                        print(f"Detailed cause: {json.dumps(cause_json, indent=2)}")
                    except:
                        print(f"Cause: {cause}")
                break

        print("-" * 80)

if __name__ == '__main__':
    list_failed_executions()
