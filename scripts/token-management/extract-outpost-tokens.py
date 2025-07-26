#!/usr/bin/env python3
"""
Authentik External Outpost Token Extraction Script

This script extracts the correct API tokens for external outposts from Authentik
and prepares them for 1Password storage.

The issue: External outpost pods are using admin tokens instead of their specific
external outpost tokens, causing them to connect to wrong outpost IDs.

Author: Kilo Code
Version: 1.0.0
"""

import os
import sys
import json
import logging
import urllib.request
import urllib.parse
import urllib.error
from typing import Dict, List, Optional, Tuple


class AuthentikAPIError(Exception):
    """Custom exception for Authentik API errors."""
    def __init__(self, message: str, status_code: Optional[int] = None, response_body: Optional[str] = None):
        super().__init__(message)
        self.status_code = status_code
        self.response_body = response_body


class OutpostTokenExtractor:
    """Extract external outpost tokens from Authentik API."""
    
    def __init__(self, authentik_host: str, admin_token: str):
        self.authentik_host = authentik_host
        self.session_headers = {
            'Authorization': f'Bearer {admin_token}',
            'Content-Type': 'application/json',
            'User-Agent': 'authentik-outpost-token-extractor/1.0.0'
        }
        
        # Set up logging
        self.logger = logging.getLogger('outpost-token-extractor')
        self.logger.setLevel(logging.INFO)
        
        if not self.logger.handlers:
            handler = logging.StreamHandler(sys.stdout)
            formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)
        
        # Target external outpost IDs
        self.target_outposts = {
            "3f0970c5-d6a3-43b2-9a36-d74665c6b24e": "k8s-external-proxy-outpost",
            "9d94c493-d7bb-47b4-aae9-d579c69b2ea5": "radius-outpost"
        }
    
    def _make_api_request(self, url: str, method: str = 'GET', data: Optional[Dict] = None) -> Tuple[int, Dict]:
        """Make an API request to Authentik."""
        try:
            self.logger.debug(f"API call: {method} {url}")
            
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
                
                return status_code, response_data
                
        except urllib.error.HTTPError as e:
            status_code = e.code
            try:
                error_body = e.read().decode('utf-8')
                error_data = json.loads(error_body) if error_body else {}
            except (json.JSONDecodeError, UnicodeDecodeError):
                error_data = {'error': 'Failed to parse error response'}
            
            raise AuthentikAPIError(
                f"API request failed with status {status_code}",
                status_code=status_code,
                response_body=str(error_data)
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
                username = response.get('username', 'unknown')
                self.logger.info(f"✓ API authentication successful (user: {username})")
                return True
            else:
                self.logger.error(f"✗ API authentication failed with status {status_code}")
                return False
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ API authentication failed: {e}")
            return False
    
    def get_all_outposts(self) -> Dict[str, Dict]:
        """Get all outposts with their details."""
        try:
            self.logger.info("Fetching all outposts...")
            url = f"{self.authentik_host}/api/v3/outposts/instances/"
            status_code, response = self._make_api_request(url)
            
            if status_code == 200:
                outposts = {}
                for outpost in response.get('results', []):
                    outpost_id = outpost['pk']
                    outposts[outpost_id] = outpost
                
                self.logger.info(f"✓ Found {len(outposts)} outposts")
                return outposts
            else:
                self.logger.error(f"✗ Failed to fetch outposts: status {status_code}")
                return {}
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to fetch outposts: {e}")
            return {}
    
    def get_outpost_tokens(self) -> Dict[str, Dict]:
        """Get tokens for all outposts."""
        try:
            self.logger.info("Fetching outpost tokens...")
            url = f"{self.authentik_host}/api/v3/core/tokens/"
            status_code, response = self._make_api_request(url)
            
            if status_code == 200:
                tokens = {}
                for token in response.get('results', []):
                    # Look for tokens with outpost-related identifiers
                    identifier = token.get('identifier', '')
                    description = token.get('description', '')
                    
                    # Check if this token is associated with an outpost
                    if 'outpost' in identifier.lower() or 'outpost' in description.lower():
                        tokens[token['pk']] = token
                
                self.logger.info(f"✓ Found {len(tokens)} outpost-related tokens")
                return tokens
            else:
                self.logger.error(f"✗ Failed to fetch tokens: status {status_code}")
                return {}
                
        except AuthentikAPIError as e:
            self.logger.error(f"✗ Failed to fetch tokens: {e}")
            return {}
    
    def extract_target_outpost_tokens(self) -> Dict[str, str]:
        """Extract tokens for the target external outposts."""
        self.logger.info("=== Starting External Outpost Token Extraction ===")
        
        # Test authentication
        if not self.test_authentication():
            return {}
        
        # Get all outposts
        outposts = self.get_all_outposts()
        if not outposts:
            self.logger.error("✗ No outposts found")
            return {}
        
        # Get all tokens
        tokens = self.get_outpost_tokens()
        if not tokens:
            self.logger.error("✗ No outpost tokens found")
            return {}
        
        # Analyze outposts and find target ones
        self.logger.info("=== Analyzing Outposts ===")
        found_outposts = {}
        
        for outpost_id, outpost_data in outposts.items():
            outpost_name = outpost_data.get('name', 'unknown')
            outpost_type = outpost_data.get('type', 'unknown')
            
            self.logger.info(f"Outpost: {outpost_name} (ID: {outpost_id}, Type: {outpost_type})")
            
            if outpost_id in self.target_outposts:
                expected_name = self.target_outposts[outpost_id]
                found_outposts[outpost_id] = {
                    'name': outpost_name,
                    'expected_name': expected_name,
                    'data': outpost_data
                }
                self.logger.info(f"  → TARGET OUTPOST FOUND: {expected_name}")
        
        if not found_outposts:
            self.logger.error("✗ No target external outposts found")
            return {}
        
        # Extract tokens for target outposts
        self.logger.info("=== Extracting Outpost Tokens ===")
        extracted_tokens = {}
        
        for outpost_id, outpost_info in found_outposts.items():
            outpost_name = outpost_info['name']
            expected_name = outpost_info['expected_name']
            
            self.logger.info(f"Looking for token for outpost: {outpost_name} (ID: {outpost_id})")
            
            # Try to find the token for this outpost
            # Method 1: Look for tokens with matching outpost ID in identifier or description
            found_token = None
            for token_id, token_data in tokens.items():
                identifier = token_data.get('identifier', '')
                description = token_data.get('description', '')
                
                if outpost_id in identifier or outpost_id in description:
                    found_token = token_data
                    break
                
                # Also check if the outpost name is mentioned
                if outpost_name.lower() in identifier.lower() or outpost_name.lower() in description.lower():
                    found_token = token_data
                    break
            
            if found_token:
                token_key = found_token.get('key', '')
                if token_key:
                    extracted_tokens[outpost_id] = {
                        'outpost_name': outpost_name,
                        'expected_name': expected_name,
                        'token': token_key,
                        'token_identifier': found_token.get('identifier', ''),
                        'token_description': found_token.get('description', '')
                    }
                    self.logger.info(f"✓ Found token for {outpost_name}: {found_token.get('identifier', 'no-identifier')}")
                else:
                    self.logger.warning(f"⚠ Found token record but no key for {outpost_name}")
            else:
                self.logger.warning(f"⚠ No token found for outpost {outpost_name} (ID: {outpost_id})")
        
        return extracted_tokens
    
    def generate_1password_entries(self, extracted_tokens: Dict[str, str]) -> Dict[str, Dict]:
        """Generate 1Password entry format for the extracted tokens."""
        self.logger.info("=== Generating 1Password Entry Format ===")
        
        onepassword_entries = {}
        
        for outpost_id, token_info in extracted_tokens.items():
            outpost_name = token_info['outpost_name']
            expected_name = token_info['expected_name']
            token = token_info['token']
            
            # Create 1Password entry name
            entry_name = f"Authentik External Outpost Token - {expected_name}"
            
            onepassword_entries[entry_name] = {
                'title': entry_name,
                'category': 'API_CREDENTIAL',
                'fields': {
                    'token': token,
                    'outpost_id': outpost_id,
                    'outpost_name': outpost_name,
                    'expected_name': expected_name,
                    'authentik_host': self.authentik_host,
                    'notes': f'External outpost token for {expected_name} (ID: {outpost_id})'
                }
            }
            
            self.logger.info(f"✓ Generated 1Password entry: {entry_name}")
        
        return onepassword_entries
    
    def run_extraction(self) -> bool:
        """Run the complete token extraction process."""
        try:
            # Extract tokens
            extracted_tokens = self.extract_target_outpost_tokens()
            
            if not extracted_tokens:
                self.logger.error("✗ No tokens extracted")
                return False
            
            # Generate 1Password entries
            onepassword_entries = self.generate_1password_entries(extracted_tokens)
            
            # Output results
            self.logger.info("=== Extraction Results ===")
            self.logger.info(f"✓ Successfully extracted {len(extracted_tokens)} outpost tokens")
            
            # Save results to file
            results = {
                'extracted_tokens': extracted_tokens,
                'onepassword_entries': onepassword_entries,
                'extraction_timestamp': '2025-07-26T12:31:00Z'
            }
            
            output_file = '/tmp/outpost-tokens-extraction.json'
            with open(output_file, 'w') as f:
                json.dump(results, f, indent=2)
            
            self.logger.info(f"✓ Results saved to: {output_file}")
            
            # Print summary
            self.logger.info("=== Summary ===")
            for entry_name, entry_data in onepassword_entries.items():
                self.logger.info(f"1Password Entry: {entry_name}")
                self.logger.info(f"  Outpost ID: {entry_data['fields']['outpost_id']}")
                self.logger.info(f"  Token: {entry_data['fields']['token'][:20]}...")
                self.logger.info("")
            
            return True
            
        except Exception as e:
            self.logger.error(f"✗ Extraction failed: {e}")
            return False


def main():
    """Main entry point for the script."""
    # Get configuration from environment variables
    authentik_host = os.environ.get('AUTHENTIK_HOST')
    admin_token = os.environ.get('AUTHENTIK_ADMIN_TOKEN')
    
    if not all([authentik_host, admin_token]):
        print("✗ Missing required environment variables:")
        print("  - AUTHENTIK_HOST")
        print("  - AUTHENTIK_ADMIN_TOKEN")
        sys.exit(1)
    
    # Create extractor and run
    extractor = OutpostTokenExtractor(authentik_host, admin_token)
    
    try:
        success = extractor.run_extraction()
        sys.exit(0 if success else 1)
    except Exception as e:
        extractor.logger.error(f"✗ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()