#!/usr/bin/env python3
"""
Update existing external outpost configuration with correct external URL
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def make_api_request(url, method="GET", data=None, headers=None):
    """Make an API request to Authentik."""
    try:
        req_data = None
        if data and method in ["POST", "PATCH", "PUT"]:
            req_data = json.dumps(data).encode("utf-8")

        request = urllib.request.Request(
            url, data=req_data, headers=headers, method=method
        )

        with urllib.request.urlopen(request) as response:
            status_code = response.getcode()
            response_body = response.read().decode("utf-8")

            try:
                response_data = json.loads(response_body) if response_body else {}
            except json.JSONDecodeError:
                response_data = {"raw_response": response_body}

            return status_code, response_data

    except urllib.error.HTTPError as e:
        status_code = e.code
        try:
            error_body = e.read().decode("utf-8")
            error_data = json.loads(error_body) if error_body else {}
        except (json.JSONDecodeError, UnicodeDecodeError):
            error_data = {"error": "Failed to parse error response"}

        print(f"API call failed with status {status_code}: {error_data}")
        return status_code, error_data


def main():
    # Get configuration from environment variables
    authentik_host = os.environ.get(
        "AUTHENTIK_HOST", "http://authentik-server.authentik.svc.cluster.local:80"
    )
    authentik_token = os.environ.get("AUTHENTIK_TOKEN")
    outpost_name = os.environ.get("OUTPOST_NAME", "k8s-external-proxy-outpost")

    if not authentik_token:
        print("ERROR: AUTHENTIK_TOKEN environment variable is required")
        sys.exit(1)

    headers = {
        "Authorization": f"Bearer {authentik_token}",
        "Content-Type": "application/json",
    }

    print(f"Updating outpost configuration: {outpost_name}")

    # Get existing outpost
    print("Getting existing outpost...")
    url = f"{authentik_host}/api/v3/outposts/instances/?name={outpost_name}"
    status_code, response = make_api_request(url, headers=headers)

    if status_code != 200 or not response.get("results"):
        print(f"ERROR: Could not find outpost {outpost_name}")
        sys.exit(1)

    outpost = response["results"][0]
    outpost_id = outpost["pk"]
    print(f"Found outpost: {outpost_name} (ID: {outpost_id})")

    # Update outpost configuration
    print("Updating outpost configuration...")

    # Get current config and update it
    current_config = outpost.get("config", {})

    # Update the configuration with correct external URL
    updated_config = {
        **current_config,
        "authentik_host": "http://authentik-server.authentik.svc.cluster.local:80",
        "authentik_host_browser": "https://authentik.k8s.home.geoffdavis.com",
        "authentik_host_insecure": False,
        "log_level": "info",
        "error_reporting": False,
        "object_naming_template": "ak-outpost-%(name)s",
    }

    update_data = {
        "name": outpost["name"],
        "type": outpost["type"],
        "providers": outpost["providers"],
        "config": updated_config,
    }

    url = f"{authentik_host}/api/v3/outposts/instances/{outpost_id}/"
    status_code, response = make_api_request(
        url, method="PATCH", data=update_data, headers=headers
    )

    if status_code == 200:
        print("✓ Successfully updated outpost configuration")
        print("✓ External URL now set to: https://authentik.k8s.home.geoffdavis.com")
        print(
            "✓ Outpost should now redirect to external URL instead of internal cluster DNS"
        )
        return True
    else:
        print(f"ERROR: Failed to update outpost configuration: status {status_code}")
        print(f"Response: {response}")
        return False


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
