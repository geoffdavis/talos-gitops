#!/usr/bin/env python3
"""
Unit tests for the Authentik Proxy Configuration Script

Author: Kilo Code
Version: 1.0.0
"""

import io
import json
import logging
import unittest
from unittest.mock import MagicMock, Mock, patch
from urllib.error import HTTPError

# Import the module under test
from configure_proxy import (AuthentikAPIError, AuthentikConfig,
                             AuthentikProxyConfigurator, ServiceConfig)


class TestServiceConfig(unittest.TestCase):
    """Test cases for ServiceConfig dataclass."""

    def test_service_config_creation(self):
        """Test ServiceConfig creation and properties."""
        service = ServiceConfig(
            name="test-service",
            external_host="test.example.com",
            internal_host="test-service.namespace",
            internal_port=8080,
        )

        self.assertEqual(service.name, "test-service")
        self.assertEqual(service.external_host, "test.example.com")
        self.assertEqual(service.internal_host, "test-service.namespace")
        self.assertEqual(service.internal_port, 8080)
        self.assertEqual(service.external_url, "https://test.example.com")
        self.assertEqual(service.internal_url, "http://test-service.namespace:8080")


class TestAuthentikConfig(unittest.TestCase):
    """Test cases for AuthentikConfig dataclass."""

    def test_authentik_config_creation(self):
        """Test AuthentikConfig creation."""
        config = AuthentikConfig(
            host="https://auth.example.com",
            token="test-token",
            outpost_id="test-outpost-id",
        )

        self.assertEqual(config.host, "https://auth.example.com")
        self.assertEqual(config.token, "test-token")
        self.assertEqual(config.outpost_id, "test-outpost-id")
        self.assertEqual(config.auth_flow_uuid, "be0ee023-11fe-4a43-b453-bc67957cafbf")


class TestAuthentikAPIError(unittest.TestCase):
    """Test cases for AuthentikAPIError exception."""

    def test_api_error_creation(self):
        """Test AuthentikAPIError creation."""
        error = AuthentikAPIError(
            "Test error", status_code=400, response_body='{"error": "test"}'
        )

        self.assertEqual(str(error), "Test error")
        self.assertEqual(error.status_code, 400)
        self.assertEqual(error.response_body, '{"error": "test"}')


class TestAuthentikProxyConfigurator(unittest.TestCase):
    """Test cases for AuthentikProxyConfigurator class."""

    def setUp(self):
        """Set up test fixtures."""
        self.config = AuthentikConfig(
            host="https://auth.example.com",
            token="test-token",
            outpost_id="test-outpost-id",
        )

        # Create a logger that captures output
        self.log_stream = io.StringIO()
        self.logger = logging.getLogger("test-logger")
        self.logger.setLevel(logging.DEBUG)
        handler = logging.StreamHandler(self.log_stream)
        self.logger.addHandler(handler)

        self.configurator = AuthentikProxyConfigurator(self.config, logger=self.logger)

    def test_configurator_initialization(self):
        """Test configurator initialization."""
        self.assertEqual(self.configurator.config, self.config)
        self.assertEqual(len(self.configurator.services), 6)

        # Check service names
        service_names = [s.name for s in self.configurator.services]
        expected_names = [
            "longhorn",
            "grafana",
            "prometheus",
            "alertmanager",
            "dashboard",
            "hubble",
        ]
        self.assertEqual(service_names, expected_names)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_make_api_request_success(self, mock_urlopen):
        """Test successful API request."""
        # Mock response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 200
        mock_response.read.return_value = b'{"result": "success"}'
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        status_code, response = self.configurator._make_api_request(
            "https://auth.example.com/api/test"
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response, {"result": "success"})

    @patch("configure_proxy.urllib.request.urlopen")
    def test_make_api_request_http_error(self, mock_urlopen):
        """Test API request with HTTP error."""
        # Mock HTTP error
        error = HTTPError(
            url="https://auth.example.com/api/test",
            code=400,
            msg="Bad Request",
            hdrs={},
            fp=io.BytesIO(b'{"error": "bad request"}'),
        )
        mock_urlopen.side_effect = error

        with self.assertRaises(AuthentikAPIError) as context:
            self.configurator._make_api_request("https://auth.example.com/api/test")

        self.assertIn("API request failed after 3 attempts", str(context.exception))
        self.assertEqual(context.exception.status_code, 400)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_test_authentication_success(self, mock_urlopen):
        """Test successful authentication test."""
        # Mock response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 200
        mock_response.read.return_value = b'{"username": "testuser"}'
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        result = self.configurator.test_authentication()

        self.assertTrue(result)
        log_output = self.log_stream.getvalue()
        self.assertIn("API authentication successful", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_test_authentication_failure(self, mock_urlopen):
        """Test failed authentication test."""
        # Mock HTTP error
        error = HTTPError(
            url="https://auth.example.com/api/v3/core/users/me/",
            code=401,
            msg="Unauthorized",
            hdrs={},
            fp=io.BytesIO(b'{"error": "unauthorized"}'),
        )
        mock_urlopen.side_effect = error

        result = self.configurator.test_authentication()

        self.assertFalse(result)
        log_output = self.log_stream.getvalue()
        self.assertIn("API authentication failed", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_get_authorization_flow_success(self, mock_urlopen):
        """Test successful authorization flow retrieval."""
        # Mock response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 200
        mock_response.read.return_value = b'{"results": [{"pk": "test-flow-uuid"}]}'
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        flow_uuid = self.configurator.get_authorization_flow()

        self.assertEqual(flow_uuid, "test-flow-uuid")
        log_output = self.log_stream.getvalue()
        self.assertIn("Using authorization flow: test-flow-uuid", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_get_authorization_flow_fallback(self, mock_urlopen):
        """Test authorization flow fallback."""
        # Mock empty response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 200
        mock_response.read.return_value = b'{"results": []}'
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        flow_uuid = self.configurator.get_authorization_flow()

        self.assertEqual(flow_uuid, self.config.auth_flow_uuid)
        log_output = self.log_stream.getvalue()
        self.assertIn("using fallback", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_get_existing_proxy_providers(self, mock_urlopen):
        """Test getting existing proxy providers."""
        # Mock response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 200
        mock_response.read.return_value = b"""
        {
            "results": [
                {"name": "provider1", "pk": 1},
                {"name": "provider2", "pk": 2}
            ]
        }
        """
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        providers = self.configurator.get_existing_proxy_providers()

        expected = {"provider1": 1, "provider2": 2}
        self.assertEqual(providers, expected)
        log_output = self.log_stream.getvalue()
        self.assertIn("Found 2 existing proxy providers", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_create_proxy_provider_success(self, mock_urlopen):
        """Test successful proxy provider creation."""
        # Mock response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 201
        mock_response.read.return_value = b'{"pk": 123}'
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        service = ServiceConfig("test", "test.example.com", "test-service", 8080)

        provider_pk = self.configurator.create_proxy_provider(service, "test-flow-uuid")

        self.assertEqual(provider_pk, 123)
        log_output = self.log_stream.getvalue()
        self.assertIn("Created proxy provider test-proxy with PK: 123", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_create_application_success(self, mock_urlopen):
        """Test successful application creation."""
        # Mock response
        mock_response = MagicMock()
        mock_response.getcode.return_value = 201
        mock_response.read.return_value = b'{"pk": 456}'
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        service = ServiceConfig("test", "test.example.com", "test-service", 8080)

        result = self.configurator.create_application(service, 123)

        self.assertTrue(result)
        log_output = self.log_stream.getvalue()
        self.assertIn("Created application: test", log_output)

    @patch("configure_proxy.urllib.request.urlopen")
    def test_update_outpost_providers_success(self, mock_urlopen):
        """Test successful outpost update."""
        # Mock responses for GET and PATCH
        get_response = MagicMock()
        get_response.getcode.return_value = 200
        get_response.read.return_value = b'{"name": "test-outpost"}'
        get_response.__enter__.return_value = get_response

        patch_response = MagicMock()
        patch_response.getcode.return_value = 200
        patch_response.read.return_value = b'{"providers": [1, 2, 3]}'
        patch_response.__enter__.return_value = patch_response

        mock_urlopen.side_effect = [get_response, patch_response]

        result = self.configurator.update_outpost_providers([1, 2, 3])

        self.assertTrue(result)
        log_output = self.log_stream.getvalue()
        self.assertIn(
            "Updated outpost test-outpost with providers: [1, 2, 3]", log_output
        )

    @patch.object(AuthentikProxyConfigurator, "test_authentication")
    @patch.object(AuthentikProxyConfigurator, "get_authorization_flow")
    @patch.object(AuthentikProxyConfigurator, "get_existing_proxy_providers")
    @patch.object(AuthentikProxyConfigurator, "get_existing_applications")
    @patch.object(AuthentikProxyConfigurator, "create_proxy_provider")
    @patch.object(AuthentikProxyConfigurator, "create_application")
    @patch.object(AuthentikProxyConfigurator, "update_outpost_providers")
    def test_configure_all_services_success(
        self,
        mock_update_outpost,
        mock_create_app,
        mock_create_provider,
        mock_get_apps,
        mock_get_providers,
        mock_get_flow,
        mock_test_auth,
    ):
        """Test successful configuration of all services."""
        # Mock all dependencies
        mock_test_auth.return_value = True
        mock_get_flow.return_value = "test-flow-uuid"
        mock_get_providers.return_value = {}
        mock_get_apps.return_value = {}
        mock_create_provider.return_value = 123
        mock_create_app.return_value = True
        mock_update_outpost.return_value = True

        result = self.configurator.configure_all_services()

        self.assertTrue(result)

        # Verify all services were processed
        self.assertEqual(mock_create_provider.call_count, 6)
        self.assertEqual(mock_create_app.call_count, 6)
        mock_update_outpost.assert_called_once_with([123, 123, 123, 123, 123, 123])

    @patch.object(AuthentikProxyConfigurator, "test_authentication")
    def test_configure_all_services_auth_failure(self, mock_test_auth):
        """Test configuration failure due to authentication."""
        mock_test_auth.return_value = False

        result = self.configurator.configure_all_services()

        self.assertFalse(result)


class TestMainFunction(unittest.TestCase):
    """Test cases for the main function."""

    @patch.dict(
        "os.environ",
        {
            "AUTHENTIK_HOST": "https://auth.example.com",
            "AUTHENTIK_TOKEN": "test-token",
            "OUTPOST_ID": "test-outpost-id",
        },
    )
    @patch.object(AuthentikProxyConfigurator, "configure_all_services")
    def test_main_success(self, mock_configure):
        """Test successful main function execution."""
        mock_configure.return_value = True

        # Import and run main
        from configure_proxy import main

        with patch("sys.exit") as mock_exit:
            main()
            mock_exit.assert_called_once_with(0)

    @patch.dict("os.environ", {})
    def test_main_missing_env_vars(self):
        """Test main function with missing environment variables."""
        from configure_proxy import main

        with patch("sys.exit") as mock_exit:
            with patch("builtins.print"):
                main()
                mock_exit.assert_called_once_with(1)


if __name__ == "__main__":
    # Run the tests
    unittest.main(verbosity=2)
