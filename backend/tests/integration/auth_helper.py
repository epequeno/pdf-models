"""
Helper functions for Cognito authentication and API requests.
"""
import requests
from typing import Dict, Optional


class APIClient:
    """
    Client for making authenticated requests to the pdf-models API.

    Handles authentication headers and provides typed methods for each endpoint.
    """

    def __init__(self, base_url: str, access_token: str):
        """
        Initialize API client.

        Args:
            base_url: Base URL of the API (e.g., https://api.example.com/v1)
            access_token: Cognito access token for API Gateway authorization
        """
        self.base_url = base_url.rstrip("/")
        self.access_token = access_token
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        })

    def submit_job(
        self,
        model: str,
        s3_input_key: str,
        start_processing: bool = True,
        prompt: Optional[str] = None,
    ) -> Dict:
        """
        Submit a new processing job with existing S3 key.

        Args:
            model: Model name (e.g., "marker", "dolphin", "deepseek-ocr")
            s3_input_key: S3 key of the input file
            start_processing: Whether to start processing immediately (default: True)
            prompt: Optional custom prompt for VLM models (dolphin, deepseek-ocr).
                   If not provided, the model uses its default prompt.

        Returns:
            Job details including job_id

        Raises:
            requests.HTTPError: If the request fails
        """
        url = f"{self.base_url}/models/{model}/jobs"
        payload = {
            "s3_input_key": s3_input_key,
            "start_processing": start_processing
        }

        # Add prompt if provided (for VLM models)
        if prompt is not None:
            payload["prompt"] = prompt

        response = self.session.post(url, json=payload)
        response.raise_for_status()

        return response.json()

    def submit_job_for_upload(self, model: str) -> Dict:
        """
        Submit a new processing job and get upload URL.

        Args:
            model: Model name (e.g., "marker")

        Returns:
            Job details including job_id, s3_input_key, and upload_url

        Raises:
            requests.HTTPError: If the request fails
        """
        url = f"{self.base_url}/models/{model}/jobs"
        payload = {}  # Empty payload - let API generate S3 key

        response = self.session.post(url, json=payload)
        response.raise_for_status()

        return response.json()

    def get_job(self, model: str, job_id: str) -> Dict:
        """
        Get job status and details.

        Args:
            model: Model name (e.g., "marker")
            job_id: UUID of the job

        Returns:
            Job details including status

        Raises:
            requests.HTTPError: If the request fails
        """
        url = f"{self.base_url}/models/{model}/jobs/{job_id}"

        response = self.session.get(url)
        response.raise_for_status()

        return response.json()

    def list_jobs(self, model: str) -> Dict:
        """
        List all jobs for the authenticated user.

        Args:
            model: Model name (e.g., "marker")

        Returns:
            Dictionary with "jobs" key containing list of jobs

        Raises:
            requests.HTTPError: If the request fails
        """
        url = f"{self.base_url}/models/{model}/jobs"

        response = self.session.get(url)
        response.raise_for_status()

        return response.json()


def wait_for_job_completion(
    api_client: APIClient,
    model: str,
    job_id: str,
    timeout_seconds: int = 600,
    poll_interval: int = 5,
) -> Dict:
    """
    Poll job status until completion or timeout.

    Args:
        api_client: Authenticated API client
        model: Model name
        job_id: Job UUID
        timeout_seconds: Maximum time to wait (default: 10 minutes)
        poll_interval: Seconds between polls (default: 5 seconds)

    Returns:
        Final job details

    Raises:
        TimeoutError: If job doesn't complete within timeout
        RuntimeError: If job fails
    """
    import time

    start_time = time.time()
    last_status = None

    while True:
        elapsed = time.time() - start_time
        if elapsed > timeout_seconds:
            raise TimeoutError(
                f"Job {job_id} did not complete within {timeout_seconds} seconds. "
                f"Last status: {last_status}"
            )

        job = api_client.get_job(model, job_id)
        status = job["status"]

        # Print status changes
        if status != last_status:
            print(f"Job {job_id} status: {status} (elapsed: {elapsed:.1f}s)")
            last_status = status

        if status == "completed":
            return job
        elif status == "failed":
            error_msg = job.get("error", "Unknown error")
            raise RuntimeError(f"Job {job_id} failed: {error_msg}")
        elif status in ["created", "processing"]:
            time.sleep(poll_interval)
        else:
            raise RuntimeError(f"Unknown job status: {status}")
