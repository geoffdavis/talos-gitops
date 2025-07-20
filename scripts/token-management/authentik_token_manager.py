#!/usr/bin/env python3
"""
Authentik Token Manager

A comprehensive Python-based token management system for Authentik with
support for:
- Creating long-lived tokens (1 year expiry)
- Token validation and health checks
- Automated token rotation
- 1Password integration
- Kubernetes secret management

Usage:
    python authentik_token_manager.py create --expiry-days 365
    python authentik_token_manager.py validate --token <token>
    python authentik_token_manager.py rotate --dry-run
    python authentik_token_manager.py update-1password --token <token>
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime
from typing import List, Optional, Tuple
from dataclasses import dataclass

import requests


@dataclass
class TokenInfo:
    """Token information structure"""
    key: str
    expires: Optional[datetime]
    description: str
    user: str
    created: datetime
    days_remaining: Optional[int] = None
    
    def __post_init__(self):
        if self.expires:
            self.days_remaining = (self.expires - datetime.now()).days


class AuthentikTokenManager:
    """Main token management class"""
    
    def __init__(self, namespace: str = "authentik", dry_run: bool = False):
        self.namespace = namespace
        self.dry_run = dry_run
        self.logger = self._setup_logging()
        self.authentik_host = (
            "http://authentik-server.authentik.svc.cluster.local"
        )
        
    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        return logging.getLogger(__name__)
    
    def _run_kubectl_command(self, cmd: List[str]) -> Tuple[bool, str]:
        """Execute kubectl command and return success status and output"""
        try:
            result = subprocess.run(
                ["kubectl"] + cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return True, result.stdout.strip()
        except subprocess.CalledProcessError as e:
            self.logger.error(f"kubectl command failed: {e}")
            return False, e.stderr.strip()
    
    def _check_prerequisites(self) -> bool:
        """Check if all prerequisites are met"""
        self.logger.info("Checking prerequisites...")
        
        # Check kubectl
        try:
            subprocess.run(
                ["kubectl", "version", "--client"],
                capture_output=True, check=True
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.logger.error("kubectl is not installed or not accessible")
            return False
        
        # Check cluster connectivity
        success, _ = self._run_kubectl_command(["cluster-info"])
        if not success:
            self.logger.error("Cannot connect to Kubernetes cluster")
            return False
        
        # Check namespace exists
        success, _ = self._run_kubectl_command([
            "get", "namespace", self.namespace
        ])
        if not success:
            self.logger.error(f"Namespace '{self.namespace}' does not exist")
            return False
        
        # Check Authentik deployment
        success, _ = self._run_kubectl_command([
            "get", "deployment", "authentik-server", "-n", self.namespace
        ])
        if not success:
            self.logger.error(
                f"Authentik server deployment not found in "
                f"namespace '{self.namespace}'"
            )
            return False
        
        self.logger.info("Prerequisites check passed")
        return True
    
    def _wait_for_authentik(self, timeout: int = 300) -> bool:
        """Wait for Authentik server to be ready"""
        self.logger.info("Waiting for Authentik server to be ready...")
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            # Check if we can reach the Authentik health endpoint
            success, _ = self._run_kubectl_command([
                "exec", "-n", self.namespace, "deployment/authentik-server",
                "--", "curl", "-f", "-s",
                "http://localhost:9000/if/flow/initial-setup/"
            ])
            
            if success:
                self.logger.info("Authentik server is ready")
                return True
            
            self.logger.info("Authentik not ready yet, waiting 10 seconds...")
            time.sleep(10)
        
        self.logger.error(
            f"Authentik server did not become ready within {timeout} seconds"
        )
        return False
    
    def _execute_authentik_shell(self, python_code: str) -> Tuple[bool, str]:
        """Execute Python code in Authentik shell"""
        if self.dry_run:
            self.logger.info("DRY RUN: Would execute Authentik shell command")
            return True, "DRY RUN MODE"
        
        # Create a temporary job to execute the shell command
        job_name = f"token-manager-{int(time.time())}"
        job_manifest = self._create_shell_job_manifest(job_name, python_code)
        
        try:
            # Apply the job
            with open(f"/tmp/{job_name}.yaml", "w") as f:
                f.write(job_manifest)
            
            success, _ = self._run_kubectl_command(["apply", "-f", f"/tmp/{job_name}.yaml"])
            if not success:
                return False, "Failed to create job"
            
            # Wait for job completion
            success, _ = self._run_kubectl_command([
                "wait", "--for=condition=complete", f"job/{job_name}",
                "-n", self.namespace, "--timeout=300s"
            ])
            
            if not success:
                return False, "Job did not complete successfully"
            
            # Get job output
            success, pod_name = self._run_kubectl_command([
                "get", "pods", "-n", self.namespace,
                "-l", f"job-name={job_name}",
                "-o", "jsonpath={.items[0].metadata.name}"
            ])
            
            if success:
                success, output = self._run_kubectl_command([
                    "logs", "-n", self.namespace, pod_name
                ])
                
                # Cleanup
                self._run_kubectl_command([
                    "delete", "job", job_name, "-n", self.namespace
                ])
                os.unlink(f"/tmp/{job_name}.yaml")
                
                return success, output
            
            return False, "Could not get job output"
            
        except Exception as e:
            self.logger.error(f"Error executing Authentik shell: {e}")
            return False, str(e)
    
    def _create_shell_job_manifest(
        self, job_name: str, python_code: str
    ) -> str:
        """Create Kubernetes job manifest for executing Authentik shell
        commands"""
        return f"""
apiVersion: batch/v1
kind: Job
metadata:
  name: {job_name}
  namespace: {self.namespace}
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 300
  template:
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
      containers:
        - name: authentik-shell
          image: ghcr.io/goauthentik/server:2024.8.3
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
            capabilities:
              drop:
                - ALL
          env:
            - name: AUTHENTIK_REDIS__HOST
              value: "authentik-redis-master.authentik.svc.cluster.local"
            - name: AUTHENTIK_POSTGRESQL__HOST
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__HOST
            - name: AUTHENTIK_POSTGRESQL__NAME
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__NAME
            - name: AUTHENTIK_POSTGRESQL__USER
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__USER
            - name: AUTHENTIK_POSTGRESQL__PASSWORD
              valueFrom:
                secretKeyRef:
                  name: authentik-database-credentials
                  key: AUTHENTIK_POSTGRESQL__PASSWORD
            - name: AUTHENTIK_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: authentik-config
                  key: AUTHENTIK_SECRET_KEY
          command:
            - /bin/bash
            - -c
            - |
              set -e
              ak shell -c "{python_code.replace('"', '\\"')}"
"""
    
    def create_long_lived_token(
        self, expiry_days: int = 365, force: bool = False
    ) -> Optional[TokenInfo]:
        """Create a long-lived API token"""
        self.logger.info(
            f"Creating long-lived token with {expiry_days} days expiry..."
        )
        
        if not self._check_prerequisites():
            return None
        
        if not self._wait_for_authentik():
            return None
        
        python_code = f"""
from authentik.core.models import User, Token
from datetime import datetime, timedelta
import secrets
import json

# Get admin user
try:
    user = User.objects.get(username='akadmin')
    print(f'FOUND_USER:{{user.username}}')
except User.DoesNotExist:
    print('ERROR:Admin user akadmin not found')
    exit(1)

# Calculate expiry
expiry_date = datetime.now() + timedelta(days={expiry_days})

# Check existing tokens
existing_tokens = Token.objects.filter(user=user, intent='api')
valid_long_term_tokens = []

for token in existing_tokens:
    if token.expires and token.expires > datetime.now():
        days_remaining = (token.expires - datetime.now()).days
        if days_remaining > 300:  # Consider long-term if > 300 days
            valid_long_term_tokens.append(token)
            print(f'EXISTING_TOKEN:{{token.key[:8]}}...:{{days_remaining}}')

# Create new token if needed
force_create = {str(force).lower()}
if not valid_long_term_tokens or force_create:
    if force_create and valid_long_term_tokens:
        print('FORCE_MODE:Creating new token despite existing valid tokens')
    
    # Generate new token
    token_key = secrets.token_hex(32)
    description = (
        f'Long-lived RADIUS Outpost Token ({expiry_days} days) - '
        f'Created {{datetime.now().strftime("%Y-%m-%d")}}'
    )
    token = Token.objects.create(
        user=user,
        intent='api',
        key=token_key,
        description=description,
        expires=expiry_date,
        expiring=True
    )
    
    token_info = {{
        'key': token.key,
        'expires': expiry_date.isoformat(),
        'created': datetime.now().isoformat(),
        'description': token.description,
        'user': user.username
    }}
    
    print('SUCCESS:Created new token')
    print(f'TOKEN_INFO:{{json.dumps(token_info)}}')
else:
    token = valid_long_term_tokens[0]
    created_iso = (
        token.created.isoformat() if hasattr(token, 'created')
        else datetime.now().isoformat()
    )
    token_info = {{
        'key': token.key,
        'expires': token.expires.isoformat(),
        'created': created_iso,
        'description': token.description,
        'user': user.username
    }}
    print('SUCCESS:Using existing valid token')
    print(f'TOKEN_INFO:{{json.dumps(token_info)}}')
"""
        
        success, output = self._execute_authentik_shell(python_code)
        
        if not success:
            self.logger.error(f"Failed to create token: {output}")
            return None
        
        # Parse output
        if "SUCCESS:" in output:
            for line in output.split('\n'):
                if line.startswith('TOKEN_INFO:'):
                    token_data = json.loads(line.split('TOKEN_INFO:', 1)[1])
                    return TokenInfo(
                        key=token_data['key'],
                        expires=datetime.fromisoformat(token_data['expires']),
                        description=token_data['description'],
                        user=token_data['user'],
                        created=datetime.fromisoformat(token_data['created'])
                    )
        
        self.logger.error("Could not parse token creation output")
        return None
    
    def validate_token(self, token: str) -> bool:
        """Validate a token by making an API call"""
        self.logger.info(f"Validating token: {token[:8]}...")
        
        try:
            response = requests.get(
                f"{self.authentik_host}/api/v3/core/users/me/",
                headers={"Authorization": f"Bearer {token}"},
                timeout=30
            )
            
            if response.status_code == 200:
                self.logger.info("Token validation successful")
                return True
            else:
                self.logger.error(
                    f"Token validation failed: HTTP {response.status_code}"
                )
                return False
                
        except requests.RequestException as e:
            self.logger.error(f"Token validation failed: {e}")
            return False
    
    def list_tokens(self) -> List[TokenInfo]:
        """List all API tokens for the admin user"""
        self.logger.info("Listing all API tokens...")
        
        if not self._check_prerequisites():
            return []
        
        python_code = """
from authentik.core.models import User, Token
from datetime import datetime
import json

try:
    user = User.objects.get(username='akadmin')
    tokens = Token.objects.filter(user=user, intent='api')
    
    token_list = []
    for token in tokens:
        created_iso = (
            token.created.isoformat() if hasattr(token, 'created')
            else datetime.now().isoformat()
        )
        token_info = {
            'key': token.key,
            'expires': token.expires.isoformat() if token.expires else None,
            'description': token.description,
            'user': user.username,
            'created': created_iso
        }
        token_list.append(token_info)
    
    print(f'TOKEN_LIST:{json.dumps(token_list)}')
    
except User.DoesNotExist:
    print('ERROR:Admin user akadmin not found')
"""
        
        success, output = self._execute_authentik_shell(python_code)
        
        if not success:
            self.logger.error(f"Failed to list tokens: {output}")
            return []
        
        # Parse output
        for line in output.split('\n'):
            if line.startswith('TOKEN_LIST:'):
                token_data_list = json.loads(line.split('TOKEN_LIST:', 1)[1])
                tokens = []
                for token_data in token_data_list:
                    expires = None
                    if token_data['expires']:
                        expires = datetime.fromisoformat(token_data['expires'])
                    tokens.append(TokenInfo(
                        key=token_data['key'],
                        expires=expires,
                        description=token_data['description'],
                        user=token_data['user'],
                        created=datetime.fromisoformat(token_data['created'])
                    ))
                return tokens
        
        return []
    
    def update_1password_token(self, token_info: TokenInfo) -> bool:
        """Update 1Password with new token information"""
        self.logger.info("Updating 1Password with new token...")
        
        if self.dry_run:
            self.logger.info("DRY RUN: Would update 1Password entry")
            return True
        
        try:
            # Use op CLI to update the token
            expires_str = (
                token_info.expires.isoformat() if token_info.expires
                else 'never'
            )
            cmd = [
                "op", "item", "edit", "Authentik RADIUS Token - home-ops",
                "--vault=homelab",
                f"token={token_info.key}",
                f"expires={expires_str}",
                f"created={token_info.created.isoformat()}",
                f"description={token_info.description}"
            ]
            
            subprocess.run(cmd, capture_output=True, text=True, check=True)
            self.logger.info("Successfully updated 1Password entry")
            return True
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to update 1Password: {e}")
            return False
        except FileNotFoundError:
            self.logger.error(
                "1Password CLI (op) not found. Please install it first."
            )
            return False
    
    def rotate_tokens(self, overlap_days: int = 30) -> bool:
        """Rotate tokens with overlap period"""
        self.logger.info(
            f"Starting token rotation with {overlap_days} days overlap..."
        )
        
        # List current tokens
        tokens = self.list_tokens()
        if not tokens:
            self.logger.error("No tokens found")
            return False
        
        # Find tokens that need rotation (expiring within overlap period)
        tokens_to_rotate = []
        for token in tokens:
            if (token.expires and token.days_remaining and
                    token.days_remaining <= overlap_days):
                tokens_to_rotate.append(token)
        
        if not tokens_to_rotate:
            self.logger.info("No tokens need rotation at this time")
            return True
        
        self.logger.info(
            f"Found {len(tokens_to_rotate)} tokens that need rotation"
        )
        
        # Create new token
        new_token = self.create_long_lived_token(force=True)
        if not new_token:
            self.logger.error("Failed to create new token for rotation")
            return False
        
        # Validate new token
        if not self.validate_token(new_token.key):
            self.logger.error("New token validation failed")
            return False
        
        # Update 1Password
        if not self.update_1password_token(new_token):
            self.logger.error("Failed to update 1Password with new token")
            return False
        
        self.logger.info("Token rotation completed successfully")
        return True


def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description="Authentik Token Manager")
    parser.add_argument(
        "--namespace", default="authentik", help="Kubernetes namespace"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Show what would be done"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Verbose output"
    )
    
    subparsers = parser.add_subparsers(
        dest="command", help="Available commands"
    )
    
    # Create command
    create_parser = subparsers.add_parser(
        "create", help="Create a long-lived token"
    )
    create_parser.add_argument(
        "--expiry-days", type=int, default=365, help="Token expiry in days"
    )
    create_parser.add_argument(
        "--force", action="store_true",
        help="Force creation even if valid tokens exist"
    )
    
    # Validate command
    validate_parser = subparsers.add_parser(
        "validate", help="Validate a token"
    )
    validate_parser.add_argument(
        "--token", required=True, help="Token to validate"
    )
    
    # List command
    list_parser = subparsers.add_parser("list", help="List all tokens")
    list_parser.add_argument(
        "--json", action="store_true", help="Output in JSON format"
    )
    
    # Rotate command
    rotate_parser = subparsers.add_parser("rotate", help="Rotate tokens")
    rotate_parser.add_argument(
        "--overlap-days", type=int, default=30, help="Overlap period in days"
    )
    
    # Update 1Password command
    update_parser = subparsers.add_parser(
        "update-1password", help="Update 1Password with token"
    )
    update_parser.add_argument(
        "--token", required=True, help="Token to update in 1Password"
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    manager = AuthentikTokenManager(
        namespace=args.namespace, dry_run=args.dry_run
    )
    
    if args.command == "create":
        token = manager.create_long_lived_token(
            expiry_days=args.expiry_days, force=args.force
        )
        if token:
            print("Token created successfully:")
            print(f"  Key: {token.key[:8]}...{token.key[-8:]}")
            print(f"  Expires: {token.expires}")
            print(f"  Description: {token.description}")
        else:
            sys.exit(1)
    
    elif args.command == "validate":
        if manager.validate_token(args.token):
            print("Token is valid")
        else:
            print("Token is invalid")
            sys.exit(1)
    
    elif args.command == "list":
        tokens = manager.list_tokens()
        if args.json:
            token_data = []
            for token in tokens:
                token_data.append({
                    "key": f"{token.key[:8]}...{token.key[-8:]}",
                    "expires": (
                        token.expires.isoformat() if token.expires else None
                    ),
                    "days_remaining": token.days_remaining,
                    "description": token.description,
                    "user": token.user,
                    "created": token.created.isoformat()
                })
            print(json.dumps(token_data, indent=2))
        else:
            print(f"Found {len(tokens)} tokens:")
            for token in tokens:
                if token.days_remaining and token.days_remaining < 0:
                    status = "EXPIRED"
                else:
                    status = f"{token.days_remaining} days remaining"
                print(
                    f"  {token.key[:8]}...{token.key[-8:]} - {status} - "
                    f"{token.description}"
                )
    
    elif args.command == "rotate":
        if manager.rotate_tokens(overlap_days=args.overlap_days):
            print("Token rotation completed successfully")
        else:
            print("Token rotation failed")
            sys.exit(1)
    
    elif args.command == "update-1password":
        # Create a TokenInfo object for the provided token
        token_info = TokenInfo(
            key=args.token,
            expires=None,  # Will be updated by the script
            description="Updated via CLI",
            user="akadmin",
            created=datetime.now()
        )
        if manager.update_1password_token(token_info):
            print("1Password updated successfully")
        else:
            print("Failed to update 1Password")
            sys.exit(1)
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()