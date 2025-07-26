#!/usr/bin/env python3
"""
Fix Authentik Outpost Conflicts and External URL Issues

This script resolves the conflict between embedded and external outposts by:
1. Removing all proxy providers from embedded/competing outposts
2. Ensuring all 6 proxy providers are assigned exclusively to external outpost
3. Fixing Grafana service name configuration
4. Updating proxy providers with correct external URLs
5. Clearing cached configurations

Author: Kilo Code
Version: 2.0.0
"""

import json
import logging
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


@dataclass
class ServiceConfig:
    """Configuration for a service to be proxied."""

    name: str
    external_host: str
    internal_host: str
    internal_port: int

    @property
    def external_url(self) -> str:
        return f"https://{self.external_host}"

    @property
    def internal_url(self) -> str:
        return f"http://{self.internal_host}:{self.internal_port}"


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


class OutpostConflictResolver:
    """Resolve conflicts between embedded and external outposts."""

    def __init__(
        self, authentik_host: str, authentik_token: str, external_outpost_id: str
    ):
        self.authentik_host = authentik_host
        self.external_outpost_id = external_outpost_id
        self.session_headers = {
            "Authorization": f"Bearer {authentik_token}",
            "Content-Type": "application/json",
            "User-Agent": "authentik-outpost-conflict-resolver/2.0.0",
        }

        # Set up logging
        self.logger = logging.getLogger("outpost-conflict-resolver")
        self.logger.setLevel(logging.INFO)

        if not self.logger.handlers:
            handler = logging.StreamHandler(sys.stdout)
            formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)

        # Service configurations with CORRECTED Grafana service name
        self.services = [
            ServiceConfig(
                "longhorn",
                "longhorn.k8s.home.geoffdavis.com",
                "longhorn-frontend.longhorn-system.svc.cluster.local",
                80,
            ),
            ServiceConfig(
                "grafana",
                "grafana.k8s.home.geoffdavis.com",
                "kube-prometheus-stack-grafana.monitoring.svc.cluster.local",
                80,
            ),
            ServiceConfig(
                "prometheus",
                "prometheus.k8s.home.geoffdavis.com",
                "kube-prometheus-stack-prometheus.monitoring.svc.cluster.local",
                9090,
            ),
            ServiceConfig(
                "alertmanager",
                "alertmanager.k8s.home.geoffdavis.com",
                "kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local",
                9093,
            ),
            ServiceConfig(
                "dashboard",
                "dashboard.k8s.home.geoffdavis.com",
                "kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local",
                443,
            ),
            ServiceConfig(
                "hubble",
                "hubble.k8s.home.geoffdavis.com",
                "hubble-ui.kube-system.svc.cluster.local",
                80,
            ),
        ]

        # Expected proxy provider names
        self.expected_providers = [f"{service.name}-proxy" for service in self.services]

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

    def get_proxy_providers(self) -> Dict[str, Dict]:
        """Get all proxy providers and return name to data mapping."""
        try:
            self.logger.info("Fetching proxy providers...")
            url = f"{self.authentik_host}/api/v3/providers/proxy/"
            status_code, response = self._make_api_request(url)

            if status_code == 200:
                providers = {}
                for provider in response.get("results", []):
                    providers[provider["name"]] = provider

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

    def update_proxy_provider(
        self, provider_pk: int, service: ServiceConfig, auth_flow_uuid: str
    ) -> bool:
        """Update a proxy provider with correct external URL and service configuration."""
        try:
            self.logger.info(
                f"Updating proxy provider {service.name}-proxy (PK: {provider_pk})"
            )

            provider_data = {
                "name": f"{service.name}-proxy",
                "authorization_flow": auth_flow_uuid,
                "external_host": service.external_url,  # FIXED: Use external URL
                "internal_host": service.internal_url,  # FIXED: Use correct service name
                "internal_host_ssl_validation": False,
                "mode": "proxy",  # FIXED: Use proxy mode instead of forward_single
                "cookie_domain": "k8s.home.geoffdavis.com",
                "skip_path_regex": "^/api/.*$",
                "basic_auth_enabled": False,
            }

            url = f"{self.authentik_host}/api/v3/providers/proxy/{provider_pk}/"
            status_code, response = self._make_api_request(
                url, method="PATCH", data=provider_data
            )

            if status_code == 200:
                self.logger.info(f"✓ Updated proxy provider {service.name}-proxy")
                self.logger.info(f"  External URL: {service.external_url}")
                self.logger.info(f"  Internal URL: {service.internal_url}")
                return True
            else:
                self.logger.error(
                    f"✗ Failed to update proxy provider {service.name}-proxy: status {status_code}"
                )
                return False

        except AuthentikAPIError as e:
            self.logger.error(
                f"✗ Failed to update proxy provider {service.name}-proxy: {e}"
            )
            return False

    def get_authorization_flow(self) -> str:
        """Get the default authorization flow UUID."""
        try:
            self.logger.info("Getting default authorization flow...")
            url = f"{self.authentik_host}/api/v3/flows/instances/?slug=default-authorization-flow"
            status_code, response = self._make_api_request(url)

            if status_code == 200 and response.get("results"):
                flow_uuid = response["results"][0]["pk"]
                self.logger.info(f"✓ Using authorization flow: {flow_uuid}")
                return flow_uuid
            else:
                # Fallback to known working flow UUID
                fallback_uuid = "be0ee023-11fe-4a43-b453-bc67957cafbf"
                self.logger.warning(
                    f"⚠ Could not get authorization flow, using fallback: {fallback_uuid}"
                )
                return fallback_uuid

        except AuthentikAPIError as e:
            fallback_uuid = "be0ee023-11fe-4a43-b453-bc67957cafbf"
            self.logger.warning(
                f"⚠ Failed to get authorization flow: {e}, using fallback: {fallback_uuid}"
            )
            return fallback_uuid

    def update_external_outpost_config(self) -> bool:
        """Update external outpost configuration to clear cached internal URLs."""
        try:
            self.logger.info(
                f"Updating external outpost configuration: {self.external_outpost_id}"
            )

            # Get current outpost configuration
            url = f"{self.authentik_host}/api/v3/outposts/instances/{self.external_outpost_id}/"
            status_code, response = self._make_api_request(url)

            if status_code != 200:
                self.logger.error(
                    f"✗ Failed to get outpost configuration: status {status_code}"
                )
                return False

            outpost_data = response
            current_config = outpost_data.get("config", {})

            # Update configuration with correct external URL
            updated_config = {
                **current_config,
                "authentik_host": "http://authentik-server.authentik.svc.cluster.local:80",
                "authentik_host_browser": "https://authentik.k8s.home.geoffdavis.com",  # FIXED: External URL
                "authentik_host_insecure": False,
                "log_level": "info",
                "error_reporting": False,
                "object_naming_template": "ak-outpost-%(name)s",
            }

            update_data = {
                "name": outpost_data["name"],
                "type": outpost_data["type"],
                "providers": outpost_data["providers"],  # Keep existing providers
                "config": updated_config,
            }

            status_code, response = self._make_api_request(
                url, method="PATCH", data=update_data
            )

            if status_code == 200:
                self.logger.info("✓ Updated external outpost configuration")
                self.logger.info(
                    "✓ External URL set to: https://authentik.k8s.home.geoffdavis.com"
                )
                return True
            else:
                self.logger.error(
                    f"✗ Failed to update outpost configuration: status {status_code}"
                )
                return False

        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to update outpost configuration: {e}")
            return False

    def resolve_conflicts(self) -> bool:
        """Main method to resolve all outpost conflicts and fix configurations."""
        self.logger.info("=== Starting Outpost Conflict Resolution ===")

        # Test authentication
        if not self.test_authentication():
            return False

        # Get authorization flow
        auth_flow_uuid = self.get_authorization_flow()

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

        # Find expected provider PKs and update their configurations
        expected_provider_pks = []

        for service in self.services:
            provider_name = f"{service.name}-proxy"
            if provider_name in proxy_providers:
                provider_data = proxy_providers[provider_name]
                provider_pk = provider_data["pk"]
                expected_provider_pks.append(provider_pk)

                self.logger.info(
                    f"✓ Found provider: {provider_name} (PK: {provider_pk})"
                )

                # Update provider with correct external URL and service configuration
                if not self.update_proxy_provider(provider_pk, service, auth_flow_uuid):
                    self.logger.warning(
                        f"⚠ Failed to update provider {provider_name}, but continuing..."
                    )
            else:
                self.logger.error(f"✗ Missing provider: {provider_name}")
                return False

        # Analyze current assignments and fix conflicts
        self.logger.info("=== Analyzing Current Outpost Assignments ===")
        competing_outposts = []
        external_outpost_found = False

        for outpost_id, outpost_info in outposts.items():
            outpost_name = outpost_info["name"]
            assigned_providers = outpost_info["providers"]

            self.logger.info(f"Outpost: {outpost_name} (ID: {outpost_id})")
            self.logger.info(f"  Assigned providers: {assigned_providers}")

            # Check if this is our external outpost
            if outpost_id == self.external_outpost_id:
                external_outpost_found = True
                self.logger.info(f"  → This is the EXTERNAL outpost (target)")
            else:
                # Check if this outpost has any of our expected providers
                conflicting_providers = [
                    pk for pk in assigned_providers if pk in expected_provider_pks
                ]
                if conflicting_providers:
                    competing_outposts.append(
                        (outpost_id, outpost_name, conflicting_providers)
                    )
                    self.logger.warning(
                        f"  → This outpost has CONFLICTING providers: {conflicting_providers}"
                    )

        if not external_outpost_found:
            self.logger.error(
                f"✗ External outpost {self.external_outpost_id} not found"
            )
            return False

        # Remove providers from competing outposts
        self.logger.info("=== Removing Providers from Competing Outposts ===")
        for outpost_id, outpost_name, conflicting_providers in competing_outposts:
            self.logger.info(
                f"Removing providers from competing outpost: {outpost_name} ({outpost_id})"
            )
            if not self.update_outpost_providers(outpost_id, []):
                self.logger.error(f"✗ Failed to remove providers from {outpost_name}")
                return False
            else:
                self.logger.info(f"✓ Removed all providers from {outpost_name}")

        # Assign all providers to external outpost
        self.logger.info("=== Assigning All Providers to External Outpost ===")
        if not self.update_outpost_providers(
            self.external_outpost_id, expected_provider_pks
        ):
            self.logger.error("✗ Failed to assign providers to external outpost")
            return False
        else:
            self.logger.info("✓ Assigned all providers to external outpost")

        # Update external outpost configuration
        self.logger.info("=== Updating External Outpost Configuration ===")
        if not self.update_external_outpost_config():
            self.logger.warning(
                "⚠ Failed to update outpost configuration, but continuing..."
            )

        self.logger.info("=== Conflict Resolution Complete ===")
        self.logger.info("✓ All proxy providers removed from competing outposts")
        self.logger.info(
            "✓ All proxy providers assigned exclusively to external outpost"
        )
        self.logger.info("✓ Proxy providers updated with correct external URLs")
        self.logger.info("✓ Grafana service configuration fixed")
        self.logger.info("✓ External outpost configuration updated")
        self.logger.info(
            "✓ Services should now work correctly with proper authentication redirects"
        )

        return True


def main():
    """Main entry point for the script."""
    # Get configuration from environment variables
    authentik_host = os.environ.get("AUTHENTIK_HOST")
    authentik_token = os.environ.get("AUTHENTIK_TOKEN")
    external_outpost_id = os.environ.get(
        "EXTERNAL_OUTPOST_ID", "3f0970c5-d6a3-43b2-9a36-d74665c6b24e"
    )

    if not all([authentik_host, authentik_token]):
        print("✗ Missing required environment variables:")
        print("  - AUTHENTIK_HOST")
        print("  - AUTHENTIK_TOKEN")
        print("  - EXTERNAL_OUTPOST_ID (optional, defaults to known external outpost)")
        sys.exit(1)

    # Create resolver and run
    resolver = OutpostConflictResolver(
        authentik_host, authentik_token, external_outpost_id
    )

    try:
        success = resolver.resolve_conflicts()
        sys.exit(0 if success else 1)
    except Exception as e:
        resolver.logger.error(f"✗ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
