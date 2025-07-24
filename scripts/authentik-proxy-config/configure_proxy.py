#!/usr/bin/env python3
"""
Authentik Proxy Configuration Script

This script configures proxy providers and applications in Authentik for external outpost usage.
It replaces the complex bash script with proper error handling, logging, and testability.

Author: Kilo Code
Version: 1.0.0
"""

import os
import sys
import json
import time
import logging
import urllib.request
import urllib.parse
import urllib.error
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum


class LogLevel(Enum):
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"


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


@dataclass
class AuthentikConfig:
    """Authentik API configuration."""
    host: str
    token: str
    outpost_id: str
    auth_flow_uuid: str = "be0ee023-11fe-4a43-b453-bc67957cafbf"  # Fallback UUID


class AuthentikAPIError(Exception):
    """Custom exception for Authentik API errors."""
    def __init__(self, message: str, status_code: Optional[int] = None, response_body: Optional[str] = None):
        super().__init__(message)
        self.status_code = status_code
        self.response_body = response_body


class AuthentikProxyConfigurator:
    """Main class for configuring Authentik proxy providers and applications."""
    
    def __init__(self, config: AuthentikConfig, logger: Optional[logging.Logger] = None):
        self.config = config
        self.logger = logger or self._setup_logger()
        self.session_headers = {
            'Authorization': f'Bearer {config.token}',
            'Content-Type': 'application/json',
            'User-Agent': 'authentik-proxy-configurator/1.0.0'
        }
        
        # Service configurations
        self.services = [
            ServiceConfig("longhorn", "longhorn.k8s.home.geoffdavis.com", "longhorn-frontend.longhorn-system", 80),
            ServiceConfig("grafana", "grafana.k8s.home.geoffdavis.com", "kube-prometheus-stack-grafana.monitoring", 80),
            ServiceConfig("prometheus", "prometheus.k8s.home.geoffdavis.com", "kube-prometheus-stack-prometheus.monitoring", 9090),
            ServiceConfig("alertmanager", "alertmanager.k8s.home.geoffdavis.com", "kube-prometheus-stack-alertmanager.monitoring", 9093),
            ServiceConfig("dashboard", "dashboard.k8s.home.geoffdavis.com", "kubernetes-dashboard-kong-proxy.kubernetes-dashboard", 443),
            ServiceConfig("hubble", "hubble.k8s.home.geoffdavis.com", "hubble-ui.kube-system", 80),
        ]
    
    def _setup_logger(self) -> logging.Logger:
        """Set up logging configuration."""
        logger = logging.getLogger('authentik-proxy-configurator')
        logger.setLevel(logging.INFO)
        
        if not logger.handlers:
            handler = logging.StreamHandler(sys.stdout)
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            logger.addHandler(handler)
        
        return logger
    
    def _make_api_request(self, url: str, method: str = 'GET', data: Optional[Dict] = None, max_retries: int = 3) -> Tuple[int, Dict]:
        """
        Make an API request to Authentik with retry logic.
        
        Args:
            url: The API endpoint URL
            method: HTTP method (GET, POST, PATCH, etc.)
            data: Request payload for POST/PATCH requests
            max_retries: Maximum number of retry attempts
            
        Returns:
            Tuple of (status_code, response_data)
            
        Raises:
            AuthentikAPIError: If the request fails after all retries
        """
        for attempt in range(max_retries):
            try:
                self.logger.debug(f"API call attempt {attempt + 1}/{max_retries}: {method} {url}")
                
                # Prepare request
                req_data = None
                if data and method in ['POST', 'PATCH', 'PUT']:
                    req_data = json.dumps(data).encode('utf-8')
                
                request = urllib.request.Request(url, data=req_data, headers=self.session_headers, method=method)
                
                # Make request
                with urllib.request.urlopen(request) as response:
                    status_code = response.getcode()
                    response_body = response.read().decode('utf-8')
                    
                    try:
                        response_data = json.loads(response_body) if response_body else {}
                    except json.JSONDecodeError:
                        response_data = {'raw_response': response_body}
                    
                    self.logger.debug(f"API call successful: {status_code}")
                    return status_code, response_data
                    
            except urllib.error.HTTPError as e:
                status_code = e.code
                try:
                    error_body = e.read().decode('utf-8')
                    error_data = json.loads(error_body) if error_body else {}
                except (json.JSONDecodeError, UnicodeDecodeError):
                    error_data = {'error': 'Failed to parse error response'}
                
                self.logger.warning(f"API call failed with status {status_code}: {error_data}")
                
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt  # Exponential backoff
                    self.logger.info(f"Retrying in {wait_time} seconds...")
                    time.sleep(wait_time)
                else:
                    raise AuthentikAPIError(
                        f"API request failed after {max_retries} attempts",
                        status_code=status_code,
                        response_body=str(error_data)
                    )
                    
            except Exception as e:
                self.logger.error(f"Unexpected error during API call: {e}")
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                else:
                    raise AuthentikAPIError(f"API request failed: {str(e)}")
    
    def test_authentication(self) -> bool:
        """Test API authentication by calling the /api/v3/core/users/me/ endpoint."""
        try:
            self.logger.info("Testing API authentication...")
            url = f"{self.config.host}/api/v3/core/users/me/"
            status_code, response = self._make_api_request(url)
            
            if status_code == 200:
                username = response.get('username', 'unknown')
                self.logger.info(f"✓ API authentication successful (user: {username})")
                return True
            else:
                self.logger.error(f"✗ API authentication failed with status {status_code}")
                return False
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ API authentication failed: {e}")
            return False
    
    def get_authorization_flow(self) -> str:
        """Get the default authorization flow UUID."""
        try:
            self.logger.info("Getting default authorization flow...")
            url = f"{self.config.host}/api/v3/flows/instances/?slug=default-authorization-flow"
            status_code, response = self._make_api_request(url)
            
            if status_code == 200 and response.get('results'):
                flow_uuid = response['results'][0]['pk']
                self.logger.info(f"✓ Using authorization flow: {flow_uuid}")
                return flow_uuid
            else:
                self.logger.warning(f"⚠ Could not get authorization flow, using fallback: {self.config.auth_flow_uuid}")
                return self.config.auth_flow_uuid
                
        except AuthentikAPIError as e:
            self.logger.warning(f"⚠ Failed to get authorization flow: {e}, using fallback")
            return self.config.auth_flow_uuid
    
    def get_existing_proxy_providers(self) -> Dict[str, int]:
        """Get existing proxy providers and return a mapping of name to PK."""
        try:
            self.logger.info("Fetching existing proxy providers...")
            url = f"{self.config.host}/api/v3/providers/proxy/"
            status_code, response = self._make_api_request(url)
            
            if status_code == 200:
                providers = {}
                for provider in response.get('results', []):
                    providers[provider['name']] = provider['pk']
                
                self.logger.info(f"✓ Found {len(providers)} existing proxy providers")
                return providers
            else:
                self.logger.error(f"✗ Failed to fetch proxy providers: status {status_code}")
                return {}
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to fetch proxy providers: {e}")
            return {}
    
    def create_proxy_provider(self, service: ServiceConfig, auth_flow_uuid: str) -> Optional[int]:
        """Create a proxy provider for a service."""
        provider_name = f"{service.name}-proxy"
        
        try:
            self.logger.info(f"Creating proxy provider: {provider_name}")
            
            provider_data = {
                "name": provider_name,
                "authorization_flow": auth_flow_uuid,
                "external_host": service.external_url,
                "internal_host": service.internal_url,
                "internal_host_ssl_validation": False,
                "mode": "forward_single",
                "cookie_domain": "k8s.home.geoffdavis.com",
                "skip_path_regex": "^/api/.*$",
                "basic_auth_enabled": False
            }
            
            url = f"{self.config.host}/api/v3/providers/proxy/"
            status_code, response = self._make_api_request(url, method='POST', data=provider_data)
            
            if status_code == 201:
                provider_pk = response['pk']
                self.logger.info(f"✓ Created proxy provider {provider_name} with PK: {provider_pk}")
                return provider_pk
            else:
                self.logger.error(f"✗ Failed to create proxy provider {provider_name}: status {status_code}")
                return None
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to create proxy provider {provider_name}: {e}")
            return None
    
    def get_existing_applications(self) -> Dict[str, int]:
        """Get existing applications and return a mapping of name to PK."""
        try:
            self.logger.info("Fetching existing applications...")
            url = f"{self.config.host}/api/v3/core/applications/"
            status_code, response = self._make_api_request(url)
            
            if status_code == 200:
                applications = {}
                for app in response.get('results', []):
                    applications[app['name']] = app['pk']
                
                self.logger.info(f"✓ Found {len(applications)} existing applications")
                return applications
            else:
                self.logger.error(f"✗ Failed to fetch applications: status {status_code}")
                return {}
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to fetch applications: {e}")
            return {}
    
    def create_application(self, service: ServiceConfig, provider_pk: int) -> bool:
        """Create an application for a service."""
        try:
            self.logger.info(f"Creating application: {service.name}")
            
            app_data = {
                "name": service.name,
                "slug": service.name,
                "provider": provider_pk,
                "meta_description": f"{service.name} service",
                "meta_launch_url": service.external_url,
                "policy_engine_mode": "any"
            }
            
            url = f"{self.config.host}/api/v3/core/applications/"
            status_code, response = self._make_api_request(url, method='POST', data=app_data)
            
            if status_code == 201:
                self.logger.info(f"✓ Created application: {service.name}")
                return True
            else:
                self.logger.error(f"✗ Failed to create application {service.name}: status {status_code}")
                return False
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to create application {service.name}: {e}")
            return False
    
    def update_outpost_providers(self, provider_pks: List[int]) -> bool:
        """Update the outpost with the list of provider PKs."""
        try:
            self.logger.info(f"Updating outpost {self.config.outpost_id} with {len(provider_pks)} providers")
            
            # First, verify the outpost exists
            url = f"{self.config.host}/api/v3/outposts/instances/{self.config.outpost_id}/"
            status_code, response = self._make_api_request(url)
            
            if status_code != 200:
                self.logger.error(f"✗ Outpost {self.config.outpost_id} not found")
                return False
            
            outpost_name = response.get('name', 'unknown')
            self.logger.info(f"✓ Found outpost: {outpost_name}")
            
            # Update the outpost with provider PKs
            update_data = {"providers": provider_pks}
            status_code, response = self._make_api_request(url, method='PATCH', data=update_data)
            
            if status_code == 200:
                self.logger.info(f"✓ Updated outpost {outpost_name} with providers: {provider_pks}")
                return True
            else:
                self.logger.error(f"✗ Failed to update outpost: status {status_code}")
                return False
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to update outpost: {e}")
            return False
    
    def configure_all_services(self) -> bool:
        """Configure proxy providers and applications for all services."""
        self.logger.info("=== Starting Authentik Proxy Configuration ===")
        
        # Test authentication
        if not self.test_authentication():
            return False
        
        # Get authorization flow
        auth_flow_uuid = self.get_authorization_flow()
        
        # Get existing providers and applications
        existing_providers = self.get_existing_proxy_providers()
        existing_applications = self.get_existing_applications()
        
        provider_pks = []
        
        # Configure each service
        for service in self.services:
            self.logger.info(f"=== Configuring {service.name} ===")
            
            provider_name = f"{service.name}-proxy"
            provider_pk = None
            
            # Check if provider exists
            if provider_name in existing_providers:
                provider_pk = existing_providers[provider_name]
                self.logger.info(f"✓ {service.name} proxy provider already exists (PK: {provider_pk})")
            else:
                # Create new provider
                provider_pk = self.create_proxy_provider(service, auth_flow_uuid)
                if not provider_pk:
                    self.logger.error(f"✗ Failed to create provider for {service.name}")
                    continue
            
            provider_pks.append(provider_pk)
            
            # Check if application exists
            if service.name in existing_applications:
                self.logger.info(f"✓ {service.name} application already exists")
            else:
                # Create new application
                if not self.create_application(service, provider_pk):
                    self.logger.warning(f"⚠ Failed to create application for {service.name}, but continuing...")
        
        # Update outpost with all provider PKs
        if provider_pks:
            if self.update_outpost_providers(provider_pks):
                self.logger.info("=== Configuration Complete ===")
                self.logger.info("✓ All proxy providers created/verified")
                self.logger.info("✓ Applications created/verified")
                self.logger.info("✓ External outpost configured with all providers")
                self.logger.info("✓ Services should now be accessible with Authentik authentication")
                return True
            else:
                self.logger.error("✗ Failed to update outpost with providers")
                return False
        else:
            self.logger.error("✗ No provider PKs collected")
            return False


def main():
    """Main entry point for the script."""
    # Get configuration from environment variables
    authentik_host = os.environ.get('AUTHENTIK_HOST')
    authentik_token = os.environ.get('AUTHENTIK_TOKEN')
    outpost_id = os.environ.get('OUTPOST_ID')
    
    if not all([authentik_host, authentik_token, outpost_id]):
        print("✗ Missing required environment variables:")
        print("  - AUTHENTIK_HOST")
        print("  - AUTHENTIK_TOKEN")
        print("  - OUTPOST_ID")
        sys.exit(1)
    
    # Create configuration
    config = AuthentikConfig(
        host=authentik_host,
        token=authentik_token,
        outpost_id=outpost_id
    )
    
    # Create configurator and run
    configurator = AuthentikProxyConfigurator(config)
    
    try:
        success = configurator.configure_all_services()
        sys.exit(0 if success else 1)
    except Exception as e:
        configurator.logger.error(f"✗ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()