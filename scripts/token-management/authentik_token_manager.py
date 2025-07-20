#!/usr/bin/env python3
"""
Authentik Token Manager - Updates 1Password with current Authentik tokens
"""
import json
import sys
import argparse
import subprocess
from datetime import datetime, timedelta

def run_command(cmd, capture_output=True):
    """Run a shell command and return the result"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=capture_output, text=True, check=True)
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {cmd}")
        print(f"Error: {e.stderr}")
        raise

def get_current_token():
    """Get the current token from the enhanced token setup job logs"""
    try:
        # Get the most recent enhanced token setup job
        cmd = "kubectl get jobs -n authentik -l app.kubernetes.io/name=authentik-enhanced-token-setup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}'"
        job_name = run_command(cmd)
        
        if not job_name:
            print("No enhanced token setup job found")
            return None
        
        # Get the logs from the job
        cmd = f"kubectl logs job/{job_name} -n authentik"
        logs = run_command(cmd)
        
        # Extract token from logs
        for line in logs.split('\n'):
            if 'Token (base64):' in line:
                token_b64 = line.split('Token (base64): ')[1].strip()
                # Decode base64 token
                import base64
                token = base64.b64decode(token_b64).decode()
                return token
                
        print("Token not found in job logs")
        return None
        
    except Exception as e:
        print(f"Error getting current token: {e}")
        return None

def update_onepassword(token):
    """Update 1Password with the new token using 1Password Connect API"""
    try:
        # Use kubectl to get the 1Password Connect service
        connect_url = "http://onepassword-connect.onepassword-connect.svc.cluster.local:8080"
        
        # Get the connect token from the secret
        cmd = "kubectl get secret onepassword-connect-token -n onepassword-connect -o jsonpath='{.data.token}' | base64 -d"
        connect_token = run_command(cmd)
        
        if not connect_token:
            print("Could not get 1Password Connect token")
            return False
        
        # Update the item using curl (since requests isn't available yet)
        item_id = "Authentik RADIUS Token - home-ops"
        
        # Create the update payload
        update_data = {
            "fields": [
                {
                    "id": "token",
                    "value": token
                }
            ]
        }
        
        # Write the data to a temp file
        with open('/tmp/update_data.json', 'w') as f:
            json.dump(update_data, f)
        
        # Use curl to update the item
        cmd = f"""curl -s -X PATCH "{connect_url}/v1/vaults/homelab/items/{item_id}" \
            -H "Authorization: Bearer {connect_token}" \
            -H "Content-Type: application/json" \
            -d @/tmp/update_data.json"""
        
        result = run_command(cmd)
        print(f"1Password update result: {result}")
        return True
        
    except Exception as e:
        print(f"Error updating 1Password: {e}")
        return False

def list_tokens():
    """List current token status"""
    token = get_current_token()
    if token:
        # For now, just return basic info
        return [{
            "key": token[:8] + "...",
            "days_remaining": 365,  # New tokens have 1 year
            "status": "active"
        }]
    return []

def rotate_tokens(overlap_days=30):
    """Rotate tokens by updating 1Password with current token"""
    print("Starting token rotation...")
    
    # Get current token
    token = get_current_token()
    if not token:
        print("Could not get current token")
        return False
    
    print(f"Found token: {token[:8]}...")
    
    # Update 1Password
    if update_onepassword(token):
        print("Successfully updated 1Password with new token")
        return True
    else:
        print("Failed to update 1Password")
        return False

def main():
    parser = argparse.ArgumentParser(description='Authentik Token Manager')
    parser.add_argument('command', choices=['list', 'rotate'], help='Command to execute')
    parser.add_argument('--json', action='store_true', help='Output in JSON format')
    parser.add_argument('--overlap-days', type=int, default=30, help='Overlap days for rotation')
    
    args = parser.parse_args()
    
    if args.command == 'list':
        tokens = list_tokens()
        if args.json:
            print(json.dumps(tokens))
        else:
            for token in tokens:
                print(f"Token: {token['key']}, Days remaining: {token['days_remaining']}")
    
    elif args.command == 'rotate':
        success = rotate_tokens(args.overlap_days)
        sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()