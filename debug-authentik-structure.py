#!/usr/bin/env python3
"""
Debug script to investigate actual Authentik API structure
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def make_api_request(url, headers):
    """Make an API request to Authentik."""
    try:
        request = urllib.request.Request(url, headers=headers)
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
        return status_code, error_data


def main():
    # Configuration
    authentik_host = "http://authentik-server.authentik.svc.cluster.local:80"

    # This would need to be set from the secret in a real deployment
    print("ERROR: This script needs to be run inside the cluster with proper token")
    print("Use kubectl exec to run this inside an authentik pod or create a job")
    return

    headers = {
        "Authorization": f"Bearer {authentik_token}",
        "Content-Type": "application/json",
    }

    print("=== Investigating Authentik API Structure ===")

    # 1. Check all applications
    print("\n=== Applications ===")
    status_code, response = make_api_request(
        f"{authentik_host}/api/v3/core/applications/", headers
    )
    if status_code == 200:
        apps = response.get("results", [])
        print(f"Found {len(apps)} applications:")
        for app in apps:
            print(f"  - Name: {app.get('name')}")
            print(f"    Slug: {app.get('slug')}")
            print(f"    Provider: {app.get('provider')}")
            print(f"    Launch URL: {app.get('meta_launch_url')}")
            print()

    # 2. Check all proxy providers
    print("\n=== Proxy Providers ===")
    status_code, response = make_api_request(
        f"{authentik_host}/api/v3/providers/proxy/", headers
    )
    if status_code == 200:
        providers = response.get("results", [])
        print(f"Found {len(providers)} proxy providers:")
        for provider in providers:
            print(f"  - Name: {provider.get('name')}")
            print(f"    PK: {provider.get('pk')}")
            print(f"    Mode: {provider.get('mode')}")
            print(f"    External Host: {provider.get('external_host')}")
            print(f"    Internal Host: {provider.get('internal_host')}")
            print()

    # 3. Check all OAuth2 providers
    print("\n=== OAuth2 Providers ===")
    status_code, response = make_api_request(
        f"{authentik_host}/api/v3/providers/oauth2/", headers
    )
    if status_code == 200:
        providers = response.get("results", [])
        print(f"Found {len(providers)} OAuth2 providers:")
        for provider in providers:
            print(f"  - Name: {provider.get('name')}")
            print(f"    PK: {provider.get('pk')}")
            print(f"    Client Type: {provider.get('client_type')}")
            print(f"    Redirect URIs: {provider.get('redirect_uris')}")
            print()

    # 4. Check all outposts
    print("\n=== Outposts ===")
    status_code, response = make_api_request(
        f"{authentik_host}/api/v3/outposts/instances/", headers
    )
    if status_code == 200:
        outposts = response.get("results", [])
        print(f"Found {len(outposts)} outposts:")
        for outpost in outposts:
            print(f"  - Name: {outpost.get('name')}")
            print(f"    PK: {outpost.get('pk')}")
            print(f"    Type: {outpost.get('type')}")
            print(f"    Providers: {outpost.get('providers')}")
            config = outpost.get("config", {})
            print(f"    Browser URL: {config.get('authentik_host_browser')}")
            print()


if __name__ == "__main__":
    main()
