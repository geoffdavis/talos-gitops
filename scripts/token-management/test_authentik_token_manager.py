#!/usr/bin/env python3
"""
Unit tests for Authentik Token Manager

Run with: python -m pytest test_authentik_token_manager.py -v
"""

import json
import unittest
from datetime import datetime, timedelta
from unittest.mock import Mock, patch

from authentik_token_manager import AuthentikTokenManager, TokenInfo


class TestAuthentikTokenManager(unittest.TestCase):
    """Test cases for AuthentikTokenManager"""

    def setUp(self):
        """Set up test fixtures"""
        self.manager = AuthentikTokenManager(namespace="test", dry_run=True)

    def test_token_info_creation(self):
        """Test TokenInfo dataclass creation"""
        expires = datetime.now() + timedelta(days=365)
        token = TokenInfo(
            key="test_token_key",
            expires=expires,
            description="Test token",
            user="testuser",
            created=datetime.now(),
        )

        self.assertEqual(token.key, "test_token_key")
        self.assertEqual(token.user, "testuser")
        self.assertIsNotNone(token.days_remaining)

    @patch("subprocess.run")
    def test_run_kubectl_command_success(self, mock_run):
        """Test successful kubectl command execution"""
        mock_run.return_value = Mock(stdout="success output", returncode=0)

        success, output = self.manager._run_kubectl_command(["get", "pods"])

        self.assertTrue(success)
        self.assertEqual(output, "success output")

    @patch("subprocess.run")
    def test_run_kubectl_command_failure(self, mock_run):
        """Test failed kubectl command execution"""
        from subprocess import CalledProcessError

        mock_run.side_effect = CalledProcessError(1, "kubectl", stderr="Command failed")

        success, output = self.manager._run_kubectl_command(["get", "pods"])

        self.assertFalse(success)
        self.assertEqual(output, "Command failed")

    @patch.object(AuthentikTokenManager, "_run_kubectl_command")
    def test_check_prerequisites_success(self, mock_kubectl):
        """Test successful prerequisites check"""
        mock_kubectl.side_effect = [
            (True, "cluster info"),  # cluster-info
            (True, "namespace exists"),  # get namespace
            (True, "deployment exists"),  # get deployment
        ]

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = Mock(returncode=0)
            result = self.manager._check_prerequisites()

        self.assertTrue(result)

    @patch.object(AuthentikTokenManager, "_run_kubectl_command")
    def test_check_prerequisites_failure(self, mock_kubectl):
        """Test failed prerequisites check"""
        mock_kubectl.return_value = (False, "error")

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = Mock(returncode=0)
            result = self.manager._check_prerequisites()

        self.assertFalse(result)

    @patch("requests.get")
    def test_validate_token_success(self, mock_get):
        """Test successful token validation"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response

        result = self.manager.validate_token("test_token")

        self.assertTrue(result)

    @patch("requests.get")
    def test_validate_token_failure(self, mock_get):
        """Test failed token validation"""
        mock_response = Mock()
        mock_response.status_code = 403
        mock_get.return_value = mock_response

        result = self.manager.validate_token("test_token")

        self.assertFalse(result)

    @patch.object(AuthentikTokenManager, "_execute_authentik_shell")
    @patch.object(AuthentikTokenManager, "_check_prerequisites")
    @patch.object(AuthentikTokenManager, "_wait_for_authentik")
    def test_create_long_lived_token_success(self, mock_wait, mock_prereq, mock_shell):
        """Test successful token creation"""
        mock_prereq.return_value = True
        mock_wait.return_value = True

        token_data = {
            "key": "test_token_key_12345",
            "expires": (datetime.now() + timedelta(days=365)).isoformat(),
            "created": datetime.now().isoformat(),
            "description": "Test token",
            "user": "akadmin",
        }

        mock_shell.return_value = (
            True,
            f"SUCCESS:Created new token\nTOKEN_INFO:{json.dumps(token_data)}",
        )

        result = self.manager.create_long_lived_token()

        self.assertIsNotNone(result)
        self.assertEqual(result.key, "test_token_key_12345")
        self.assertEqual(result.user, "akadmin")

    @patch.object(AuthentikTokenManager, "_execute_authentik_shell")
    @patch.object(AuthentikTokenManager, "_check_prerequisites")
    @patch.object(AuthentikTokenManager, "_wait_for_authentik")
    def test_list_tokens_success(self, mock_wait, mock_prereq, mock_shell):
        """Test successful token listing"""
        mock_prereq.return_value = True
        mock_wait.return_value = True

        token_list = [
            {
                "key": "token1",
                "expires": (datetime.now() + timedelta(days=365)).isoformat(),
                "created": datetime.now().isoformat(),
                "description": "Token 1",
                "user": "akadmin",
            }
        ]

        mock_shell.return_value = (True, f"TOKEN_LIST:{json.dumps(token_list)}")

        result = self.manager.list_tokens()

        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].key, "token1")

    @patch("subprocess.run")
    def test_update_1password_token_success(self, mock_run):
        """Test successful 1Password update"""
        mock_run.return_value = Mock(returncode=0)

        token_info = TokenInfo(
            key="test_token",
            expires=datetime.now() + timedelta(days=365),
            description="Test token",
            user="akadmin",
            created=datetime.now(),
        )

        # Set dry_run to False for this test
        self.manager.dry_run = False
        result = self.manager.update_1password_token(token_info)

        self.assertTrue(result)

    @patch.object(AuthentikTokenManager, "list_tokens")
    @patch.object(AuthentikTokenManager, "create_long_lived_token")
    @patch.object(AuthentikTokenManager, "validate_token")
    @patch.object(AuthentikTokenManager, "update_1password_token")
    def test_rotate_tokens_success(
        self, mock_update, mock_validate, mock_create, mock_list
    ):
        """Test successful token rotation"""
        # Mock existing token that needs rotation
        expiring_token = TokenInfo(
            key="expiring_token",
            expires=datetime.now() + timedelta(days=15),  # Expires soon
            description="Expiring token",
            user="akadmin",
            created=datetime.now() - timedelta(days=350),
        )

        # Mock new token
        new_token = TokenInfo(
            key="new_token",
            expires=datetime.now() + timedelta(days=365),
            description="New token",
            user="akadmin",
            created=datetime.now(),
        )

        mock_list.return_value = [expiring_token]
        mock_create.return_value = new_token
        mock_validate.return_value = True
        mock_update.return_value = True

        result = self.manager.rotate_tokens(overlap_days=30)

        self.assertTrue(result)
        mock_create.assert_called_once_with(force=True)
        mock_validate.assert_called_once_with(new_token.key)
        mock_update.assert_called_once_with(new_token)

    @patch.object(AuthentikTokenManager, "list_tokens")
    def test_rotate_tokens_no_rotation_needed(self, mock_list):
        """Test token rotation when no tokens need rotation"""
        # Mock token that doesn't need rotation
        valid_token = TokenInfo(
            key="valid_token",
            expires=datetime.now() + timedelta(days=300),
            description="Valid token",
            user="akadmin",
            created=datetime.now(),
        )

        mock_list.return_value = [valid_token]

        result = self.manager.rotate_tokens(overlap_days=30)

        self.assertTrue(result)

    def test_create_shell_job_manifest(self):
        """Test Kubernetes job manifest creation"""
        python_code = "print('test')"
        manifest = self.manager._create_shell_job_manifest("test-job", python_code)

        self.assertIn("test-job", manifest)
        self.assertIn("authentik-shell", manifest)
        self.assertIn("print('test')", manifest)


class TestTokenInfo(unittest.TestCase):
    """Test cases for TokenInfo dataclass"""

    def test_days_remaining_calculation(self):
        """Test days remaining calculation"""
        future_date = datetime.now() + timedelta(days=30)
        token = TokenInfo(
            key="test",
            expires=future_date,
            description="test",
            user="test",
            created=datetime.now(),
        )

        self.assertAlmostEqual(token.days_remaining, 30, delta=1)

    def test_days_remaining_expired(self):
        """Test days remaining for expired token"""
        past_date = datetime.now() - timedelta(days=5)
        token = TokenInfo(
            key="test",
            expires=past_date,
            description="test",
            user="test",
            created=datetime.now(),
        )

        self.assertLess(token.days_remaining, 0)

    def test_days_remaining_no_expiry(self):
        """Test days remaining when no expiry is set"""
        token = TokenInfo(
            key="test",
            expires=None,
            description="test",
            user="test",
            created=datetime.now(),
        )

        self.assertIsNone(token.days_remaining)


if __name__ == "__main__":
    unittest.main()
