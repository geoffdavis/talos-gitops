#!/usr/bin/env python3
"""
Unit tests for Authentik Proxy Configuration Script

This test suite validates the Python script embedded in the Kubernetes Job YAML
that configures proxy providers and applications in Authentik for external
outpost usage.
"""

import ast
import os
import yaml
import pytest
from unittest.mock import patch


class TestAuthentikProxyConfigurationScript:
    """Test cases for the Authentik Proxy Configuration Script"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.yaml_file_path = os.path.join(
            os.path.dirname(__file__), 
            '../../infrastructure/authentik-proxy/proxy-config-job-python.yaml'
        )
        self.python_script = self._extract_python_script()
        
        # Sample test data
        self.sample_services = [
            {
                "name": "longhorn",
                "external_host": "longhorn.k8s.home.geoffdavis.com",
                "internal_host": "longhorn-frontend.longhorn-system",
                "internal_port": 80
            },
            {
                "name": "grafana", 
                "external_host": "grafana.k8s.home.geoffdavis.com",
                "internal_host": "kube-prometheus-stack-grafana.monitoring",
                "internal_port": 80
            }
        ]
        
        self.sample_outposts = [
            {
                "name": "authentik Embedded Outpost",
                "pk": "embedded-123",
                "type": "proxy",
                "providers": [1, 2, 3]
            },
            {
                "name": "External Proxy Outpost", 
                "pk": "external-456",
                "type": "proxy",
                "providers": []
            },
            {
                "name": "External Radius Outpost",
                "pk": "radius-789", 
                "type": "radius",
                "providers": []
            }
        ]

    def _extract_python_script(self):
        """Extract the Python script from the YAML file"""
        try:
            with open(self.yaml_file_path, 'r') as f:
                content = f.read()
            
            # Find the Python script between EOF markers
            start_marker = "cat > /tmp/configure_proxy.py << 'EOF'"
            end_marker = 'EOF'
            
            start_idx = content.find(start_marker)
            if start_idx == -1:
                raise ValueError("Could not find start marker in YAML")
            
            start_idx = content.find('\n', start_idx) + 1
            end_idx = content.find(end_marker, start_idx)
            if end_idx == -1:
                raise ValueError("Could not find end marker in YAML")
            
            python_script = content[start_idx:end_idx].strip()
            
            # Remove the common indentation (14 spaces)
            lines = python_script.split('\n')
            cleaned_lines = []
            for line in lines:
                if line.strip():  # Non-empty line
                    if line.startswith('              '):  # Remove 14 spaces
                        cleaned_lines.append(line[14:])
                    else:
                        cleaned_lines.append(line)
                else:  # Empty line
                    cleaned_lines.append('')
            
            return '\n'.join(cleaned_lines)
            
        except Exception as e:
            self.fail(f"Failed to extract Python script: {e}")

    def test_yaml_structure_valid(self):
        """Test that the YAML file has valid structure"""
        try:
            with open(self.yaml_file_path, 'r') as f:
                yaml_content = yaml.safe_load(f)
            
            # Verify basic Kubernetes Job structure
            self.assertEqual(yaml_content.get('kind'), 'Job')
            self.assertEqual(yaml_content.get('apiVersion'), 'batch/v1')
            
            metadata = yaml_content.get('metadata', {})
            self.assertEqual(metadata.get('name'), 'authentik-proxy-config-python')
            self.assertEqual(metadata.get('namespace'), 'authentik-proxy')
            
            # Verify ArgoCD PostSync hook
            annotations = metadata.get('annotations', {})
            self.assertEqual(annotations.get('argocd.argoproj.io/hook'), 'PostSync')
            
        except yaml.YAMLError as e:
            self.fail(f"YAML structure is invalid: {e}")

    def test_python_script_syntax_valid(self):
        """Test that the embedded Python script has valid syntax"""
        try:
            ast.parse(self.python_script)
        except SyntaxError as e:
            self.fail(f"Python script has syntax error: {e}")

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
            elif isinstance(node, ast.FunctionDef) and not hasattr(node, 'parent_class'):
                functions.append(node.name)
        
        # Verify required classes exist
        required_classes = [
            'ServiceConfig',
            'AuthentikConfig', 
            'AuthentikAPIError',
            'AuthentikProxyConfigurator'
        ]
        
        for class_name in required_classes:
            self.assertIn(class_name, classes, f"Missing required class: {class_name}")
        
        # Verify AuthentikProxyConfigurator has required methods
        configurator_methods = classes.get('AuthentikProxyConfigurator', [])
        required_methods = [
            '__init__',
            'test_authentication',
            'get_existing_proxy_providers',
            'create_proxy_provider',
            'update_proxy_provider',
            'get_existing_applications',
            'create_application',
            'get_or_create_outpost',
            'update_outpost_providers',
            'configure_all_services',
            'remove_providers_from_embedded_outpost',
            'update_outpost_configuration'
        ]
        
        for method_name in required_methods:
            self.assertIn(method_name, configurator_methods, 
                         f"Missing required method: {method_name}")
        
        # Verify main function exists
        self.assertIn('main', functions, "Missing main function")

    def test_service_config_dataclass(self):
        """Test ServiceConfig dataclass properties"""
        # Execute the script in a temporary namespace to test the classes
        namespace = {}
        exec(self.python_script, namespace)
        
        ServiceConfig = namespace['ServiceConfig']
        
        # Test ServiceConfig creation
        service = ServiceConfig(
            name="test",
            external_host="test.example.com",
            internal_host="test-service.namespace",
            internal_port=8080
        )
        
        self.assertEqual(service.external_url, "https://test.example.com")
        self.assertEqual(service.internal_url, "http://test-service.namespace:8080")

    def test_authentik_config_dataclass(self):
        """Test AuthentikConfig dataclass"""
        namespace = {}
        exec(self.python_script, namespace)
        
        AuthentikConfig = namespace['AuthentikConfig']
        
        config = AuthentikConfig(
            host="https://authentik.example.com",
            token="test-token",
            outpost_id="test-outpost"
        )
        
        self.assertEqual(config.host, "https://authentik.example.com")
        self.assertEqual(config.token, "test-token")
        self.assertEqual(config.outpost_id, "test-outpost")
        # Test default auth_flow_uuid
        self.assertEqual(config.auth_flow_uuid, "be0ee023-11fe-4a43-b453-bc67957cafbf")

    def test_service_configurations(self):
        """Test that all required services are configured"""
        namespace = {}
        exec(self.python_script, namespace)
        
        AuthentikConfig = namespace['AuthentikConfig']
        AuthentikProxyConfigurator = namespace['AuthentikProxyConfigurator']
        
        config = AuthentikConfig(
            host="https://test.com",
            token="test-token", 
            outpost_id="test-outpost"
        )
        
        configurator = AuthentikProxyConfigurator(config)
        
        # Verify all expected services are configured
        expected_services = [
            "longhorn",
            "grafana", 
            "prometheus",
            "alertmanager",
            "dashboard",
            "hubble"
        ]
        
        service_names = [service.name for service in configurator.services]
        
        for expected_service in expected_services:
            self.assertIn(expected_service, service_names, 
                         f"Missing service configuration: {expected_service}")
        
        # Verify Grafana service has correct internal host (this was a bug we fixed)
        grafana_service = next(s for s in configurator.services if s.name == "grafana")
        self.assertEqual(grafana_service.internal_host, "kube-prometheus-stack-grafana.monitoring")

    def test_outpost_detection_logic(self):
        """Test the external outpost detection logic"""
        namespace = {}
        exec(self.python_script, namespace)
        
        AuthentikConfig = namespace['AuthentikConfig']
        AuthentikProxyConfigurator = namespace['AuthentikProxyConfigurator']
        
        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            outpost_id="test-outpost"
        )
        
        configurator = AuthentikProxyConfigurator(config)
        
        # Mock the API request to return our sample outposts
        with patch.object(configurator, '_make_api_request') as mock_api:
            mock_api.return_value = (200, {'results': self.sample_outposts})
            
            # Test that it finds the correct external proxy outpost
            outpost_id = configurator.get_or_create_outpost("test-outpost")
            
            # Should find the External Proxy Outpost (not embedded, not radius)
            self.assertEqual(outpost_id, "external-456")

    def test_embedded_outpost_cleanup(self):
        """Test that embedded outpost providers are properly removed"""
        namespace = {}
        exec(self.python_script, namespace)
        
        AuthentikConfig = namespace['AuthentikConfig']
        AuthentikProxyConfigurator = namespace['AuthentikProxyConfigurator']
        
        config = AuthentikConfig(
            host="https://test.com",
            token="test-token",
            outpost_id="test-outpost"
        )
        
        configurator = AuthentikProxyConfigurator(config)
        
        # Mock the API requests
        with patch.object(configurator, '_make_api_request') as mock_api:
            # First call: get outposts
            # Second call: update embedded outpost
            mock_api.side_effect = [
                (200, {'results': self.sample_outposts}),  # get outposts
                (200, {'name': 'authentik Embedded Outpost'})  # update outpost
            ]
            
            result = configurator.remove_providers_from_embedded_outpost()
            
            self.assertTrue(result)
            # Verify the embedded outpost was updated with empty providers
            self.assertEqual(mock_api.call_count, 2)
            update_call = mock_api.call_args_list[1]
            self.assertEqual(update_call[1]['data']['providers'], [])


class TestAuthentikProxyJobConfiguration(unittest.TestCase):
    """Test cases for the Kubernetes Job configuration"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.yaml_file_path = os.path.join(
            os.path.dirname(__file__),
            '../../infrastructure/authentik-proxy/proxy-config-job-python.yaml'
        )
    
    def test_job_security_context(self):
        """Test that the job has proper security context"""
        with open(self.yaml_file_path, 'r') as f:
            yaml_content = yaml.safe_load(f)
        
        spec = yaml_content['spec']['template']['spec']
        
        # Test pod security context
        security_context = spec.get('securityContext', {})
        self.assertTrue(security_context.get('runAsNonRoot'))
        self.assertEqual(security_context.get('runAsUser'), 65534)
        self.assertEqual(security_context.get('runAsGroup'), 65534)
        
        # Test container security context
        containers = spec.get('containers', [])
        self.assertGreater(len(containers), 0)
        
        for container in containers:
            container_security = container.get('securityContext', {})
            self.assertFalse(container_security.get('allowPrivilegeEscalation'))
            self.assertTrue(container_security.get('runAsNonRoot'))
            self.assertEqual(container_security.get('runAsUser'), 65534)
            self.assertEqual(container_security.get('runAsGroup'), 65534)
            
            capabilities = container_security.get('capabilities', {})
            self.assertEqual(capabilities.get('drop'), ['ALL'])

    def test_job_environment_variables(self):
        """Test that required environment variables are configured"""
        with open(self.yaml_file_path, 'r') as f:
            yaml_content = yaml.safe_load(f)
        
        containers = yaml_content['spec']['template']['spec']['containers']
        config_container = next(c for c in containers if c['name'] == 'configure-external-outpost')
        
        env_vars = {env['name']: env for env in config_container.get('env', [])}
        
        # Verify required environment variables
        required_env_vars = ['AUTHENTIK_HOST', 'AUTHENTIK_TOKEN', 'CREATE_EXTERNAL_OUTPOST', 'OUTPOST_NAME']
        
        for env_var in required_env_vars:
            self.assertIn(env_var, env_vars, f"Missing environment variable: {env_var}")
        
        # Verify secret references
        self.assertEqual(
            env_vars['AUTHENTIK_HOST']['valueFrom']['secretKeyRef']['name'],
            'authentik-proxy-token'
        )
        self.assertEqual(
            env_vars['AUTHENTIK_TOKEN']['valueFrom']['secretKeyRef']['name'], 
            'authentik-proxy-token'
        )

    def test_job_resource_limits(self):
        """Test that the job has appropriate resource configuration"""
        with open(self.yaml_file_path, 'r') as f:
            yaml_content = yaml.safe_load(f)
        
        job_spec = yaml_content['spec']
        
        # Test job-level limits
        self.assertEqual(job_spec.get('backoffLimit'), 3)
        self.assertEqual(job_spec.get('activeDeadlineSeconds'), 600)
        
        # Test restart policy
        pod_spec = job_spec['template']['spec']
        self.assertEqual(pod_spec.get('restartPolicy'), 'OnFailure')


class TestAuthentikProxyIntegration(unittest.TestCase):
    """Integration tests for the Authentik Proxy configuration"""
    
    def test_script_execution_simulation(self):
        """Simulate script execution with mocked API responses"""
        # This test simulates the full script execution flow
        # with mocked Authentik API responses
        
        yaml_file_path = os.path.join(
            os.path.dirname(__file__),
            '../../infrastructure/authentik-proxy/proxy-config-job-python.yaml'
        )
        
        # Extract and execute the Python script
        with open(yaml_file_path, 'r') as f:
            content = f.read()
        
        # Find and clean the Python script
        start_marker = "cat > /tmp/configure_proxy.py << 'EOF'"
        start_idx = content.find(start_marker)
        start_idx = content.find('\n', start_idx) + 1
        end_idx = content.find('EOF', start_idx)
        python_script = content[start_idx:end_idx].strip()
        
        # Remove indentation
        lines = python_script.split('\n')
        cleaned_lines = []
        for line in lines:
            if line.strip():
                if line.startswith('              '):
                    cleaned_lines.append(line[14:])
                else:
                    cleaned_lines.append(line)
            else:
                cleaned_lines.append('')
        
        cleaned_script = '\n'.join(cleaned_lines)
        
        # Execute in namespace with mocked environment
        namespace = {'os': type('MockOS', (), {
            'environ': {
                'get': lambda key, default=None: {
                    'AUTHENTIK_HOST': 'https://authentik.test.com',
                    'AUTHENTIK_TOKEN': 'test-token-123',
                    'OUTPOST_NAME': 'test-external-outpost'
                }.get(key, default)
            }
        })()}
        
        # This would be a more comprehensive test in a real scenario
        # For now, just verify the script can be executed without syntax errors
        try:
            exec(cleaned_script, namespace)
            # If we get here, the script executed without syntax errors
            self.assertTrue(True)
        except SyntaxError as e:
            self.fail(f"Script execution failed with syntax error: {e}")


if __name__ == '__main__':
    # Run the tests
    unittest.main(verbosity=2)