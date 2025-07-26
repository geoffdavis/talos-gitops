#!/usr/bin/env python3
"""
Pytest-based tests for OAuth2 Redirect URL Fix Script

This test suite validates the Python script that fixes OAuth2 redirect URLs
in Authentik applications to use external hostnames instead of internal cluster URLs.
"""

import ast
import os
from unittest.mock import MagicMock, patch

import pytest
import yaml


class TestOAuth2RedirectFixScript:
    """Test cases for the OAuth2 Redirect URL Fix Script"""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Set up test fixtures"""
        self.yaml_file_path = os.path.join(
            os.path.dirname(__file__),
            "../../infrastructure/authentik-proxy/fix-oauth2-redirect-urls-job.yaml",
        )
        self.python_script = self._extract_python_script()

        # Sample test data
        self.sample_services = [
            {
                "name": "longhorn",
                "external_host": "longhorn.k8s.home.geoffdavis.com",
                "internal_host": "longhorn-frontend.longhorn-system",
                "internal_port": 80,
            },
            {
                "name": "grafana",
                "external_host": "grafana.k8s.home.geoffdavis.com",
                "internal_host": "kube-prometheus-stack-grafana.monitoring",
                "internal_port": 80,
            },
        ]

        self.sample_applications = {
            "longhorn": {
                "pk": "app-123",
                "name": "longhorn",
                "meta_launch_url": "http://authentik-server.authentik.svc.cluster.local:80",
                "provider": 1,
            },
            "grafana": {
                "pk": "app-456",
                "name": "grafana",
                "meta_launch_url": "http://authentik-server.authentik.svc.cluster.local:80",
                "provider": 2,
            },
        }

        self.sample_providers = {
            "longhorn-proxy": {
                "pk": 1,
                "name": "longhorn-proxy",
                "provider_type": "proxy",
                "external_host": "http://authentik-server.authentik.svc.cluster.local:80",
                "internal_host": "http://longhorn-frontend.longhorn-system:80",
            },
            "grafana-oauth2": {
                "pk": 2,
                "name": "grafana-oauth2",
                "provider_type": "oauth2",
                "redirect_uris": "http://authentik-server.authentik.svc.cluster.local:80/callback",
            },
        }

    def _extract_python_script(self):
        """Extract the Python script from the YAML file"""
        with open(self.yaml_file_path, "r") as f:
            content = f.read()

        # Find the Python script between EOF markers
        start_marker = "cat > /tmp/fix_oauth2_redirects.py << 'EOF'"
        end_marker = "EOF"

        start_idx = content.find(start_marker)
        assert start_idx != -1, "Could not find start marker in YAML"

        start_idx = content.find("\n", start_idx) + 1
        end_idx = content.find(end_marker, start_idx)
        assert end_idx != -1, "Could not find end marker in YAML"

        python_script = content[start_idx:end_idx].strip()

        # Remove the common indentation (14 spaces)
        lines = python_script.split("\n")
        cleaned_lines = []
        for line in lines:
            if line.strip():  # Non-empty line
                if line.startswith("              "):  # Remove 14 spaces
                    cleaned_lines.append(line[14:])
                else:
                    cleaned_lines.append(line)
            else:  # Empty line
                cleaned_lines.append("")

        return "\n".join(cleaned_lines)

    @pytest.mark.syntax
    def test_yaml_structure_valid(self):
        """Test that the YAML file has valid structure"""
        with open(self.yaml_file_path, "r") as f:
            yaml_content = yaml.safe_load(f)

        # Verify basic Kubernetes Job structure
        assert yaml_content.get("kind") == "Job"
        assert yaml_content.get("apiVersion") == "batch/v1"

        metadata = yaml_content.get("metadata", {})
        assert metadata.get("name") == "fix-oauth2-redirect-urls"
        assert metadata.get("namespace") == "authentik-proxy"

        # Verify ArgoCD PostSync hook
        annotations = metadata.get("annotations", {})
        assert annotations.get("argocd.argoproj.io/hook") == "PostSync"
        assert annotations.get("argocd.argoproj.io/hook-weight") == "25"

    @pytest.mark.syntax
    def test_python_script_syntax_valid(self):
        """Test that the embedded Python script has valid syntax"""
        try:
            ast.parse(self.python_script)
        except SyntaxError as e:
            pytest.fail(f"Python script has syntax error: {e}")

    @pytest.mark.unit
    def test_python_script_contains_required_classes(self):
        """Test that the script contains all required classes and methods"""
        # Parse the AST to find class and method definitions
        tree = ast.parse(self.python_script)

        classes = {}
        functions = []

        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                methods = [n.name for n in node.body if isinstance(n, ast.FunctionDef)]
                classes[node.name] = methods
            elif isinstance(node, ast.FunctionDef):
                functions.append(node.name)

        # Verify required classes exist
        required_classes = [
            "ServiceConfig",
            "AuthentikConfig",
            "AuthentikAPIError",
            "OAuth2RedirectFixer",
        ]

        for class_name in required_classes:
            assert class_name in classes, f"Missing required class: {class_name}"

        # Verify OAuth2RedirectFixer has required methods
        fixer_methods = classes.get("OAuth2RedirectFixer", [])
        required_methods = [
            "__init__",
            "test_authentication",
            "get_oauth2_applications",
            "get_oauth2_providers",
            "fix_proxy_provider_external_host",
            "fix_oauth2_provider_redirect_uris",
            "fix_application_launch_url",
            "fix_all_oauth2_redirects",
        ]

        for method_name in required_methods:
            assert (
                method_name in fixer_methods
            ), f"Missing required method: {method_name}"

        # Verify main function exists
        assert "main" in functions, "Missing main function"

    @pytest.mark.unit
    def test_service_config_oauth2_redirect_uris(self):
        """Test ServiceConfig OAuth2 redirect URI generation"""
        # Execute the script in a temporary namespace to test the classes
        namespace = {}
        exec(self.python_script, namespace)

        ServiceConfig = namespace["ServiceConfig"]

        # Test ServiceConfig creation
        service = ServiceConfig(
            name="test",
            external_host="test.k8s.home.geoffdavis.com",
            internal_host="test-service.namespace",
            internal_port=8080,
        )

        # Test OAuth2 redirect URIs
        expected_uris = [
            "https://test.k8s.home.geoffdavis.com/akprox/callback",
            "https://test.k8s.home.geoffdavis.com/outpost.goauthentik.io/callback",
            "https://test.k8s.home.geoffdavis.com/auth/callback",
            "https://test.k8s.home.geoffdavis.com/oauth/callback",
        ]

        assert service.oauth2_redirect_uris == expected_uris

    @pytest.mark.unit
    def test_authentik_config_dataclass(self):
        """Test AuthentikConfig dataclass"""
        namespace = {}
        exec(self.python_script, namespace)

        AuthentikConfig = namespace["AuthentikConfig"]

        config = AuthentikConfig(
            host="https://authentik.example.com",
            token="test-token",
            external_domain="k8s.example.com",
            authentik_external_url="https://authentik.k8s.example.com",
        )

        assert config.host == "https://authentik.example.com"
        assert config.token == "test-token"
        assert config.external_domain == "k8s.example.com"
        assert config.authentik_external_url == "https://authentik.k8s.example.com"

    @pytest.mark.unit
    def test_service_configurations(self):
        """Test that all required services are configured"""
        namespace = {}
        exec(self.python_script, namespace)

        AuthentikConfig = namespace["AuthentikConfig"]
        OAuth2RedirectFixer = namespace["OAuth2RedirectFixer"]

        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            external_domain="k8s.test.com",
            authentik_external_url="https://authentik.k8s.test.com",
        )

        fixer = OAuth2RedirectFixer(config)

        # Verify all expected services are configured
        expected_services = [
            "longhorn",
            "grafana",
            "prometheus",
            "alertmanager",
            "dashboard",
            "hubble",
        ]

        service_names = [service.name for service in fixer.services]

        for expected_service in expected_services:
            assert (
                expected_service in service_names
            ), f"Missing service configuration: {expected_service}"

    @pytest.mark.unit
    def test_proxy_provider_external_host_fix(self):
        """Test fixing proxy provider external host"""
        namespace = {}
        exec(self.python_script, namespace)

        AuthentikConfig = namespace["AuthentikConfig"]
        OAuth2RedirectFixer = namespace["OAuth2RedirectFixer"]
        ServiceConfig = namespace["ServiceConfig"]

        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            external_domain="k8s.test.com",
            authentik_external_url="https://authentik.k8s.test.com",
        )

        fixer = OAuth2RedirectFixer(config)

        # Test service
        service = ServiceConfig(
            name="test",
            external_host="test.k8s.home.geoffdavis.com",
            internal_host="test-service.namespace",
            internal_port=8080,
        )

        # Mock provider with incorrect external host
        provider = {
            "pk": 123,
            "name": "test-proxy",
            "external_host": "http://wrong-host.com",
            "internal_host": "http://test-service.namespace:8080",
        }

        # Mock the API request
        with patch.object(fixer, "_make_api_request") as mock_api:
            mock_api.return_value = (200, {"pk": 123, "name": "test-proxy"})

            result = fixer.fix_proxy_provider_external_host(provider, service)

            assert result is True
            # Verify the API was called with correct data
            assert mock_api.called
            call_args = mock_api.call_args
            assert call_args[1]["data"]["external_host"] == service.external_url

    @pytest.mark.unit
    def test_oauth2_provider_redirect_uris_fix(self):
        """Test fixing OAuth2 provider redirect URIs"""
        namespace = {}
        exec(self.python_script, namespace)

        AuthentikConfig = namespace["AuthentikConfig"]
        OAuth2RedirectFixer = namespace["OAuth2RedirectFixer"]
        ServiceConfig = namespace["ServiceConfig"]

        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            external_domain="k8s.test.com",
            authentik_external_url="https://authentik.k8s.test.com",
        )

        fixer = OAuth2RedirectFixer(config)

        # Test service
        service = ServiceConfig(
            name="test",
            external_host="test.k8s.home.geoffdavis.com",
            internal_host="test-service.namespace",
            internal_port=8080,
        )

        # Mock provider with incorrect redirect URIs
        provider = {
            "pk": 456,
            "name": "test-oauth2",
            "redirect_uris": "http://wrong-host.com/callback",
        }

        # Mock the API request
        with patch.object(fixer, "_make_api_request") as mock_api:
            mock_api.return_value = (200, {"pk": 456, "name": "test-oauth2"})

            result = fixer.fix_oauth2_provider_redirect_uris(provider, service)

            assert result is True
            # Verify the API was called with correct redirect URIs
            assert mock_api.called
            call_args = mock_api.call_args
            expected_uris = "\n".join(service.oauth2_redirect_uris)
            assert call_args[1]["data"]["redirect_uris"] == expected_uris

    @pytest.mark.unit
    def test_application_launch_url_fix(self):
        """Test fixing application launch URL"""
        namespace = {}
        exec(self.python_script, namespace)

        AuthentikConfig = namespace["AuthentikConfig"]
        OAuth2RedirectFixer = namespace["OAuth2RedirectFixer"]
        ServiceConfig = namespace["ServiceConfig"]

        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            external_domain="k8s.test.com",
            authentik_external_url="https://authentik.k8s.test.com",
        )

        fixer = OAuth2RedirectFixer(config)

        # Test service
        service = ServiceConfig(
            name="test",
            external_host="test.k8s.home.geoffdavis.com",
            internal_host="test-service.namespace",
            internal_port=8080,
        )

        # Mock application with incorrect launch URL
        application = {
            "pk": 789,
            "name": "test",
            "meta_launch_url": "http://wrong-host.com",
            "provider": 1,
        }

        # Mock the API request
        with patch.object(fixer, "_make_api_request") as mock_api:
            mock_api.return_value = (200, {"pk": 789, "name": "test"})

            result = fixer.fix_application_launch_url(application, service)

            assert result is True
            # Verify the API was called with correct launch URL
            assert mock_api.called
            call_args = mock_api.call_args
            assert call_args[1]["data"]["meta_launch_url"] == service.external_url

    @pytest.mark.integration
    def test_fix_all_oauth2_redirects_integration(self):
        """Test the complete OAuth2 redirect fix process"""
        namespace = {}
        exec(self.python_script, namespace)

        AuthentikConfig = namespace["AuthentikConfig"]
        OAuth2RedirectFixer = namespace["OAuth2RedirectFixer"]

        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            external_domain="k8s.test.com",
            authentik_external_url="https://authentik.k8s.test.com",
        )

        fixer = OAuth2RedirectFixer(config)

        # Mock all the API calls
        with patch.object(fixer, "_make_api_request") as mock_api:
            # Mock authentication test
            mock_api.side_effect = [
                (200, {"username": "test-user"}),  # authentication test
                (
                    200,
                    {"results": list(self.sample_applications.values())},
                ),  # get applications
                (200, {"results": []}),  # get proxy providers
                (
                    200,
                    {"results": list(self.sample_providers.values())},
                ),  # get oauth2 providers
                # Mock successful updates for each service
                (200, {"pk": 1}),  # update proxy provider
                (200, {"pk": 789}),  # update application
                (200, {"pk": 2}),  # update oauth2 provider
                (200, {"pk": 456}),  # update application
            ]

            result = fixer.fix_all_oauth2_redirects()

            # Should succeed
            assert result is True
            # Should have made multiple API calls
            assert mock_api.call_count >= 4


class TestOAuth2RedirectFixJobConfiguration:
    """Test cases for the Kubernetes Job configuration"""

    @pytest.fixture(autouse=True)
    def setup(self):
        """Set up test fixtures"""
        self.yaml_file_path = os.path.join(
            os.path.dirname(__file__),
            "../../infrastructure/authentik-proxy/fix-oauth2-redirect-urls-job.yaml",
        )

    @pytest.mark.security
    def test_job_security_context(self):
        """Test that the job has proper security context"""
        with open(self.yaml_file_path, "r") as f:
            yaml_content = yaml.safe_load(f)

        spec = yaml_content["spec"]["template"]["spec"]

        # Test pod security context
        security_context = spec.get("securityContext", {})
        assert security_context.get("runAsNonRoot") is True
        assert security_context.get("runAsUser") == 65534
        assert security_context.get("runAsGroup") == 65534

        # Test container security context
        containers = spec.get("containers", [])
        assert len(containers) > 0

        for container in containers:
            container_security = container.get("securityContext", {})
            assert container_security.get("allowPrivilegeEscalation") is False
            assert container_security.get("runAsNonRoot") is True
            assert container_security.get("runAsUser") == 65534
            assert container_security.get("runAsGroup") == 65534

            capabilities = container_security.get("capabilities", {})
            assert capabilities.get("drop") == ["ALL"]

    @pytest.mark.unit
    def test_job_environment_variables(self):
        """Test that required environment variables are configured"""
        with open(self.yaml_file_path, "r") as f:
            yaml_content = yaml.safe_load(f)

        containers = yaml_content["spec"]["template"]["spec"]["containers"]
        config_container = next(
            c for c in containers if c["name"] == "fix-oauth2-redirects"
        )

        env_vars = {env["name"]: env for env in config_container.get("env", [])}

        # Verify required environment variables
        required_env_vars = [
            "AUTHENTIK_HOST",
            "AUTHENTIK_TOKEN",
            "EXTERNAL_DOMAIN",
            "AUTHENTIK_EXTERNAL_URL",
        ]

        for env_var in required_env_vars:
            assert env_var in env_vars, f"Missing environment variable: {env_var}"

        # Verify secret references
        host_secret = env_vars["AUTHENTIK_HOST"]["valueFrom"]["secretKeyRef"]
        assert host_secret["name"] == "authentik-proxy-token"

        token_secret = env_vars["AUTHENTIK_TOKEN"]["valueFrom"]["secretKeyRef"]
        assert token_secret["name"] == "authentik-proxy-token"

        # Verify default values
        assert env_vars["EXTERNAL_DOMAIN"]["value"] == "k8s.home.geoffdavis.com"
        assert (
            env_vars["AUTHENTIK_EXTERNAL_URL"]["value"]
            == "https://authentik.k8s.home.geoffdavis.com"
        )

    @pytest.mark.unit
    def test_job_resource_limits(self):
        """Test that the job has appropriate resource configuration"""
        with open(self.yaml_file_path, "r") as f:
            yaml_content = yaml.safe_load(f)

        job_spec = yaml_content["spec"]

        # Test job-level limits
        assert job_spec.get("backoffLimit") == 3
        assert job_spec.get("activeDeadlineSeconds") == 600

        # Test restart policy
        pod_spec = job_spec["template"]["spec"]
        assert pod_spec.get("restartPolicy") == "OnFailure"

    @pytest.mark.unit
    def test_job_hook_configuration(self):
        """Test that the job has correct ArgoCD hook configuration"""
        with open(self.yaml_file_path, "r") as f:
            yaml_content = yaml.safe_load(f)

        annotations = yaml_content["metadata"]["annotations"]

        # Should run after the main proxy configuration job
        assert annotations.get("argocd.argoproj.io/hook") == "PostSync"
        assert annotations.get("argocd.argoproj.io/hook-weight") == "25"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
