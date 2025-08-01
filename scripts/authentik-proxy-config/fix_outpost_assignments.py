#!/usr/bin/env python3
"""
Authentik Outpost Assignment Fix Script

This script fixes the proxy provider assignment issue by:
1. Removing all 6 proxy providers from the embedded outpost
2. Ensuring all 6 proxy providers are assigned exclusively to the external outpost

Author: Kilo Code
Version: 1.0.0
"""

import json
import logging
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Optional, Tuple


class AuthentikAPIError(Exception):
    """Custom exception for Authentik API errors."""

    def __init__(
        self,
        message: str,
        status_code: Optional[int] = None,
        response_body: Optional[str] = None,
    ):
        super().__init__(message)
        self.status_code = status_code
        self.response_body = response_body


class OutpostAssignmentFixer:
    """Fix proxy provider assignments between embedded and external outposts."""

    def __init__(
        self, authentik_host: str, authentik_token: str, external_outpost_id: str
    ):
        self.authentik_host = authentik_host
        self.external_outpost_id = external_outpost_id
        self.session_headers = {
            "Authorization": f"Bearer {authentik_token}",
            "Content-Type": "application/json",
            "User-Agent": "authentik-outpost-assignment-fixer/1.0.0",
        }

        # Set up logging
        self.logger = logging.getLogger("outpost-assignment-fixer")
        self.logger.setLevel(logging.INFO)

        if not self.logger.handlers:
            handler = logging.StreamHandler(sys.stdout)
            formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)

        # Expected proxy provider names
        self.expected_providers = [
            "longhorn-proxy",
            "grafana-proxy",
            "prometheus-proxy",
            "alertmanager-proxy",
            "dashboard-proxy",
            "hubble-proxy",
        ]

    def _make_api_request(
        self, url: str, method: str = "GET", data: Optional[Dict] = None
    ) -> Tuple[int, Dict]:
        """Make an API request to Authentik."""
        try:
            self.logger.debug(f"API call: {method} {url}")

            # Prepare request
            req_data = None
            if data and method in ["POST", "PATCH", "PUT"]:
                req_data = json.dumps(data).encode("utf-8")

            request = urllib.request.Request(
                url, data=req_data, headers=self.session_headers, method=method
            )

            # Make request
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

            raise AuthentikAPIError(
                f"API request failed with status {status_code}",
                status_code=status_code,
                response_body=str(error_data),
            )
        except Exception as e:
            raise AuthentikAPIError(f"API request failed: {str(e)}")

    def test_authentication(self) -> bool:
        """Test API authentication."""
        try:
            self.logger.info("Testing API authentication...")
            url = f"{self.authentik_host}/api/v3/core/users/me/"
            status_code, response = self._make_api_request(url)

            if status_code == 200:
                username = response.get("username", "unknown")
                self.logger.info(f"✓ API authentication successful (user: {username})")
                return True
            else:
                self.logger.error(
                    f"✗ API authentication failed with status {status_code}"
                )
                return False

        except AuthentikAPIError as e:
            self.logger.error(f"✗ API authentication failed: {e}")
            return False

    def get_all_outposts(self) -> Dict[str, Dict]:
        """Get all outposts and their current provider assignments."""
        try:
            self.logger.info("Fetching all outposts...")
            url = f"{self.authentik_host}/api/v3/outposts/instances/"
            status_code, response = self._make_api_request(url)

            if status_code == 200:
                outposts = {}
                for outpost in response.get("results", []):
                    outpost_id = outpost["pk"]
                    outpost_name = outpost["name"]
                    providers = outpost.get("providers", [])
                    outposts[outpost_id] = {
                        "name": outpost_name,
                        "providers": providers,
                        "data": outpost,
                    }

                self.logger.info(f"✓ Found {len(outposts)} outposts")
                return outposts
            else:
                self.logger.error(f"✗ Failed to fetch outposts: status {status_code}")
                return {}

        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to fetch outposts: {e}")
            return {}

    def get_proxy_providers(self) -> Dict[str, int]:
        """Get all proxy providers and return name to PK mapping."""
        try:
            self.logger.info("Fetching proxy providers...")
            url = f"{self.authentik_host}/api/v3/providers/proxy/"
            status_code, response = self._make_api_request(url)

            if status_code == 200:
                providers = {}
                for provider in response.get("results", []):
                    providers[provider["name"]] = provider["pk"]

                self.logger.info(f"✓ Found {len(providers)} proxy providers")
                return providers
            else:
                self.logger.error(
                    f"✗ Failed to fetch proxy providers: status {status_code}"
                )
                return {}

        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to fetch proxy providers: {e}")
            return {}

    def update_outpost_providers(
        self, outpost_id: str, provider_pks: List[int]
    ) -> bool:
        """Update an outpost with the specified provider PKs."""
        try:
            self.logger.info(
                f"Updating outpost {outpost_id} with providers: {provider_pks}"
            )

            url = f"{self.authentik_host}/api/v3/outposts/instances/{outpost_id}/"
            update_data = {"providers": provider_pks}
            status_code, response = self._make_api_request(
                url, method="PATCH", data=update_data
            )

            if status_code == 200:
                self.logger.info(f"✓ Successfully updated outpost {outpost_id}")
                return True
            else:
                self.logger.error(
                    f"✗ Failed to update outpost {outpost_id}: status {status_code}"
                )
                return False

        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to update outpost {outpost_id}: {e}")
            return False

    def fix_outpost_assignments(self) -> bool:
        """Fix the outpost assignments by removing providers from embedded outpost and ensuring they're on external outpost."""
        self.logger.info("=== Starting Outpost Assignment Fix ===")

        # Test authentication
        if not self.test_authentication():
            return False

        # Get all outposts
        outposts = self.get_all_outposts()
        if not outposts:
            self.logger.error("✗ No outposts found")
            return False

        # Get proxy providers
        proxy_providers = self.get_proxy_providers()
        if not proxy_providers:
            self.logger.error("✗ No proxy providers found")
            return False

        # Find the expected provider PKs
        expected_provider_pks = []
        missing_providers = []

        for provider_name in self.expected_providers:
            if provider_name in proxy_providers:
                expected_provider_pks.append(proxy_providers[provider_name])
                self.logger.info(
                    f"✓ Found provider: {provider_name} (PK: {proxy_providers[provider_name]})"
                )
            else:
                missing_providers.append(provider_name)
                self.logger.warning(f"⚠ Missing provider: {provider_name}")

        if missing_providers:
            self.logger.error(f"✗ Missing providers: {missing_providers}")
            return False

        # Analyze current assignments
        self.logger.info("=== Current Outpost Assignments ===")
        embedded_outpost_id = None
        external_outpost_found = False

        for outpost_id, outpost_info in outposts.items():
            outpost_name = outpost_info["name"]
            assigned_providers = outpost_info["providers"]

            self.logger.info(f"Outpost: {outpost_name} (ID: {outpost_id})")
            self.logger.info(f"  Assigned providers: {assigned_providers}")

            # Check if this is the embedded outpost (usually named "authentik Embedded Outpost")
            if "embedded" in outpost_name.lower():
                embedded_outpost_id = outpost_id
                self.logger.info(f"  → This is the EMBEDDED outpost")

            # Check if this is our external outpost
            if outpost_id == self.external_outpost_id:
                external_outpost_found = True
                self.logger.info(f"  → This is the EXTERNAL outpost (target)")

        if not external_outpost_found:
            self.logger.error(
                f"✗ External outpost {self.external_outpost_id} not found"
            )
            return False

        if not embedded_outpost_id:
            self.logger.warning("⚠ Embedded outpost not found (may already be fixed)")

        # Fix assignments
        self.logger.info("=== Fixing Assignments ===")

        success = True

        # Remove providers from embedded outpost (if found)
        if embedded_outpost_id:
            self.logger.info(
                f"Removing all providers from embedded outpost: {embedded_outpost_id}"
            )
            if not self.update_outpost_providers(embedded_outpost_id, []):
                self.logger.error("✗ Failed to remove providers from embedded outpost")
                success = False
            else:
                self.logger.info("✓ Removed all providers from embedded outpost")

        # Assign all providers to external outpost
        self.logger.info(
            f"Assigning all providers to external outpost: {self.external_outpost_id}"
        )
        if not self.update_outpost_providers(
            self.external_outpost_id, expected_provider_pks
        ):
            self.logger.error("✗ Failed to assign providers to external outpost")
            success = False
        else:
            self.logger.info("✓ Assigned all providers to external outpost")

        if success:
            self.logger.info("=== Fix Complete ===")
            self.logger.info("✓ All proxy providers removed from embedded outpost")
            self.logger.info(
                "✓ All proxy providers assigned exclusively to external outpost"
            )
            self.logger.info("✓ Services should now work correctly without 404 errors")
        else:
            self.logger.error("✗ Fix failed - some operations were unsuccessful")

        return success


def main():
    """Main entry point for the script."""
    # Get configuration from environment variables
    authentik_host = os.environ.get("AUTHENTIK_HOST")
    authentik_token = os.environ.get("AUTHENTIK_TOKEN")
    external_outpost_id = os.environ.get("EXTERNAL_OUTPOST_ID")

    if not all([authentik_host, authentik_token, external_outpost_id]):
        print("✗ Missing required environment variables:")
        print("  - AUTHENTIK_HOST")
        print("  - AUTHENTIK_TOKEN")
        print("  - EXTERNAL_OUTPOST_ID")
        sys.exit(1)

    # Create fixer and run
    fixer = OutpostAssignmentFixer(authentik_host, authentik_token, external_outpost_id)

    try:
        success = fixer.fix_outpost_assignments()
        sys.exit(0 if success else 1)
    except Exception as e:
        fixer.logger.error(f"✗ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
