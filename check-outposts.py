#!/usr/bin/env python3
import os
import json
import urllib.request
import urllib.parse
import urllib.error

# Get credentials from environment or use defaults
authentik_host = os.environ.get('AUTHENTIK_HOST', 'http://authentik-server.authentik.svc.cluster.local:80')
authentik_token = os.environ.get('AUTHENTIK_TOKEN')

if not authentik_token:
    print("ERROR: AUTHENTIK_TOKEN environment variable not set")
    print("Please get the token from the authentik-proxy-token secret")
    exit(1)

headers = {
    'Authorization': f'Bearer {authentik_token}',
    'Content-Type': 'application/json'
}

try:
    print("=== Querying Authentik API for all outposts ===")
    url = f'{authentik_host}/api/v3/outposts/instances/'
    request = urllib.request.Request(url, headers=headers)
    
    with urllib.request.urlopen(request) as response:
        data = json.loads(response.read().decode('utf-8'))
        
        print(f"Found {len(data.get('results', []))} outposts:")
        print()
        
        for i, outpost in enumerate(data.get('results', []), 1):
            print(f"Outpost {i}:")
            print(f"  Name: {outpost['name']}")
            print(f"  ID: {outpost['pk']}")
            print(f"  Type: {outpost.get('type', 'unknown')}")
            print(f"  Providers: {len(outpost.get('providers', []))} assigned")
            print(f"  Provider IDs: {outpost.get('providers', [])}")
            
            # Show config details
            config = outpost.get('config', {})
            if config:
                print(f"  Config:")
                print(f"    authentik_host: {config.get('authentik_host', 'not set')}")
                print(f"    authentik_host_browser: {config.get('authentik_host_browser', 'not set')}")
            
            print()

except urllib.error.HTTPError as e:
    print(f"HTTP Error {e.code}: {e.reason}")
    try:
        error_body = e.read().decode('utf-8')
        print(f"Error details: {error_body}")
    except:
        pass
except Exception as e:
    print(f"Error: {e}")