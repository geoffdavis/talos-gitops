#!/bin/bash

# Script to update 1Password with the current valid Authentik token
# This resolves the token synchronization issue

set -euo pipefail

echo "=== Authentik Token 1Password Update Script ==="
echo "This script will update 1Password with the current valid Authentik token"
echo ""

# Get the current valid token from Authentik database
echo "🔍 Retrieving current valid token from Authentik..."
CURRENT_TOKEN=$(kubectl exec -n authentik deployment/authentik-server -- ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token = Token.objects.filter(user=user, intent='api').first()
print(token.key)
" 2>/dev/null | tail -1)

if [[ -z "$CURRENT_TOKEN" ]]; then
    echo "❌ Failed to retrieve token from Authentik"
    exit 1
fi

echo "✅ Current valid token: ${CURRENT_TOKEN:0:8}..."

# Get token expiry information
echo "🔍 Getting token expiry information..."
TOKEN_INFO=$(kubectl exec -n authentik deployment/authentik-server -- ak shell -c "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token = Token.objects.filter(user=user, intent='api').first()
print(f'{token.key}|{token.expires}|{token.description}')
" 2>/dev/null | tail -1)

IFS='|' read -r TOKEN_KEY TOKEN_EXPIRES TOKEN_DESC <<< "$TOKEN_INFO"

echo "✅ Token expires: $TOKEN_EXPIRES"
echo "✅ Description: $TOKEN_DESC"

# Test the token to ensure it works
echo "🧪 Testing token validity..."
echo "🔍 DEBUG: About to test token: ${TOKEN_KEY:0:8}..."
echo "🔍 DEBUG: Using service URL: http://authentik-server.authentik.svc.cluster.local/api/v3/core/users/me/"

# Run the test with enhanced error capture
echo "🔍 DEBUG: Creating test pod..."
TEST_OUTPUT=$(kubectl run test-token-validity --rm -i --image=curlimages/curl:8.5.0 --restart=Never -- \
    sh -c "curl -v -w 'HTTP_CODE:%{http_code}\nRESPONSE_TIME:%{time_total}\n' \
    -H 'Authorization: Bearer $TOKEN_KEY' \
    'http://authentik-server.authentik.svc.cluster.local/api/v3/core/users/me/' 2>&1" 2>&1 || echo "KUBECTL_FAILED")

echo "🔍 DEBUG: Full test output:"
echo "$TEST_OUTPUT"
echo "🔍 DEBUG: End of test output"

# Extract just the HTTP code
TEST_RESULT=$(echo "$TEST_OUTPUT" | grep "HTTP_CODE:" | cut -d: -f2 | tr -d ' \n\r')

echo "🔍 DEBUG: Extracted HTTP code: '$TEST_RESULT'"
echo "🔍 DEBUG: Length of HTTP code: ${#TEST_RESULT}"
echo "🔍 DEBUG: HTTP code in hex: $(echo -n "$TEST_RESULT" | xxd -p)"

# Test with explicit string comparison
if [[ "$TEST_RESULT" == "200" ]]; then
    echo "✅ Token validation successful - HTTP 200 received"
elif [[ -z "$TEST_RESULT" ]]; then
    echo "❌ Token test failed - no HTTP code received"
    echo "🔍 DEBUG: This suggests a network or pod creation issue"
    exit 1
else
    echo "❌ Token test failed with HTTP $TEST_RESULT"
    echo "🔍 DEBUG: Expected '200', got '$TEST_RESULT'"
    exit 1
fi

echo ""
echo "=== Updating 1Password via Connect API ==="
echo ""

# Get 1Password Connect token
echo "🔍 Getting 1Password Connect token..."
OP_CONNECT_TOKEN=$(kubectl get secret onepassword-connect-token -n onepassword-connect -o jsonpath='{.data.token}' | base64 -d)

if [[ -z "$OP_CONNECT_TOKEN" ]]; then
    echo "❌ Failed to get 1Password Connect token"
    exit 1
fi

echo "✅ 1Password Connect token retrieved"

# First, let's find the vault ID for "homelab" or "Automation"
echo "🔍 Finding vault information..."
VAULT_RESPONSE=$(kubectl run op-vault-list --rm -i --image=curlimages/curl:8.5.0 --restart=Never -- \
    curl -s -H "Authorization: Bearer $OP_CONNECT_TOKEN" \
    "http://onepassword-connect.onepassword-connect.svc.cluster.local:8080/v1/vaults" 2>/dev/null)

echo "🔍 DEBUG: Vault response: $VAULT_RESPONSE"

# Extract vault ID (assuming we're using the first vault or "Automation" vault)
VAULT_ID=$(echo "$VAULT_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$VAULT_ID" ]]; then
    echo "❌ Failed to get vault ID"
    echo "🔍 Available vaults: $VAULT_RESPONSE"
    exit 1
fi

echo "✅ Using vault ID: $VAULT_ID"

# Search for the existing item "Authentik RADIUS Token - home-ops"
echo "🔍 Searching for existing token item..."
ITEM_SEARCH=$(kubectl run op-item-search --rm -i --image=curlimages/curl:8.5.0 --restart=Never -- \
    curl -s -H "Authorization: Bearer $OP_CONNECT_TOKEN" \
    "http://onepassword-connect.onepassword-connect.svc.cluster.local:8080/v1/vaults/$VAULT_ID/items?filter=title%20eq%20%22Authentik%20RADIUS%20Token%20-%20home-ops%22" 2>/dev/null)

echo "🔍 DEBUG: Item search response: $ITEM_SEARCH"

ITEM_ID=$(echo "$ITEM_SEARCH" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$ITEM_ID" ]]; then
    echo "✅ Found existing item with ID: $ITEM_ID"

    # First, get the current item structure
    echo "🔍 Getting current item structure..."
    CURRENT_ITEM=$(kubectl run op-item-get --rm -i --image=curlimages/curl:8.5.0 --restart=Never -- \
        curl -s -H "Authorization: Bearer $OP_CONNECT_TOKEN" \
        "http://onepassword-connect.onepassword-connect.svc.cluster.local:8080/v1/vaults/$VAULT_ID/items/$ITEM_ID" 2>/dev/null)

    echo "🔍 DEBUG: Current item structure: $CURRENT_ITEM"

    # Extract the current version for the update
    ITEM_VERSION=$(echo "$CURRENT_ITEM" | grep -o '"version":[0-9]*' | cut -d: -f2)

    echo "🔄 Updating existing item (version: $ITEM_VERSION)..."

    # Create a proper full item update with the correct structure
    # Based on the debug output, we need to update the password field while preserving all other fields
    UPDATED_ITEM_JSON=$(cat <<EOF
{
  "id": "$ITEM_ID",
  "title": "Authentik RADIUS Token - home-ops",
  "category": "PASSWORD",
  "vault": {
    "id": "$VAULT_ID"
  },
  "fields": [
    {
      "id": "password",
      "label": "password",
      "purpose": "PASSWORD",
      "type": "CONCEALED",
      "value": "$TOKEN_KEY"
    },
    {
      "id": "notesPlain",
      "label": "notesPlain",
      "purpose": "NOTES",
      "type": "STRING",
      "value": ""
    },
    {
      "id": "sup64o643hvw7hi6mh65bhjovu",
      "label": "token",
      "section": {
        "id": "Section_wtinhehbdu5murbfq4ut3wbdaa"
      },
      "type": "CONCEALED",
      "value": "9bdb7d99994c86e68ce99261473fdda436bd5eef48209a5a776f451411e7a252"
    }
  ],
  "sections": [
    {
      "id": "Section_wtinhehbdu5murbfq4ut3wbdaa"
    }
  ]
}
EOF
)

    echo "🔄 Attempting full item update with proper structure..."
    UPDATE_RESULT=$(kubectl run op-item-update --rm -i --image=curlimages/curl:8.5.0 --restart=Never -- \
        sh -c "curl -s -X PUT -H 'Authorization: Bearer $OP_CONNECT_TOKEN' -H 'Content-Type: application/json' \
        -d '$UPDATED_ITEM_JSON' \
        'http://onepassword-connect.onepassword-connect.svc.cluster.local:8080/v1/vaults/$VAULT_ID/items/$ITEM_ID'" 2>/dev/null)

    echo "🔍 DEBUG: Update result: $UPDATE_RESULT"

    if echo "$UPDATE_RESULT" | grep -q '"id"'; then
        echo "✅ Successfully updated 1Password item!"
    else
        echo "❌ 1Password API update failed"
        echo "🔍 Update response: $UPDATE_RESULT"
        echo ""
        echo "=== API Update Failed ==="
        echo "The 1Password Connect API is not accepting our update format."
        echo "This requires manual intervention:"
        echo "📝 Vault: Automation"
        echo "📝 Item: 'Authentik RADIUS Token - home-ops'"
        echo "📝 Field: password"
        echo "🔑 New value: $TOKEN_KEY"
        exit 1
    fi
else
    echo "⚠️  Item not found, creating new item..."

    # Create new item
    CREATE_PAYLOAD=$(cat <<EOF
{
  "title": "Authentik RADIUS Token - home-ops",
  "category": "PASSWORD",
  "fields": [
    {
      "type": "CONCEALED",
      "purpose": "PASSWORD",
      "label": "password",
      "value": "$TOKEN_KEY"
    },
    {
      "type": "STRING",
      "label": "expires",
      "value": "$TOKEN_EXPIRES"
    },
    {
      "type": "STRING",
      "label": "description",
      "value": "$TOKEN_DESC"
    },
    {
      "type": "STRING",
      "label": "last_rotation",
      "value": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  ]
}
EOF
)

    CREATE_RESULT=$(kubectl run op-item-create --rm -i --image=curlimages/curl:8.5.0 --restart=Never -- \
        sh -c "curl -s -X POST -H 'Authorization: Bearer $OP_CONNECT_TOKEN' -H 'Content-Type: application/json' \
        -d '$CREATE_PAYLOAD' \
        'http://onepassword-connect.onepassword-connect.svc.cluster.local:8080/v1/vaults/$VAULT_ID/items'" 2>/dev/null)

    echo "🔍 DEBUG: Create result: $CREATE_RESULT"

    if echo "$CREATE_RESULT" | grep -q '"id"'; then
        echo "✅ Successfully created 1Password item!"
    else
        echo "❌ Failed to create 1Password item"
        echo "🔍 Create response: $CREATE_RESULT"
        exit 1
    fi
fi

echo ""
echo "=== Verifying Token Update ==="

# Check if we bypassed 1Password (secret was updated directly)
CURRENT_SECRET=$(kubectl get secret authentik-radius-token -n authentik -o jsonpath='{.data.token}' | base64 -d)

if [[ "$CURRENT_SECRET" == "$TOKEN_KEY" ]]; then
    echo "✅ Token is now active in Kubernetes!"
    echo "🔍 Current token: ${CURRENT_SECRET:0:8}..."
else
    echo "⏳ Waiting for External Secrets to sync the updated token..."
    sleep 30

    echo "🔍 Checking if External Secrets has synced the new token..."
    SYNCED_TOKEN=$(kubectl get secret authentik-radius-token -n authentik -o jsonpath='{.data.token}' | base64 -d)

    if [[ "$SYNCED_TOKEN" == "$TOKEN_KEY" ]]; then
        echo "✅ External Secrets has successfully synced the new token!"
    else
        echo "⚠️  External Secrets hasn't synced yet. Current token: ${SYNCED_TOKEN:0:8}..."
        echo "💡 External Secrets syncs every hour, or you can force a sync by restarting the external-secrets pod"
        echo "💡 Command to force sync: kubectl delete pod -n external-secrets -l app.kubernetes.io/name=external-secrets"
    fi
fi

echo ""
echo "✅ 1Password token update completed successfully!"
echo ""
echo "=== Next Steps ==="
echo "1. Verify the proxy configuration works"
echo "2. Deploy the Helm chart for Authentik proxy configuration"
echo "3. Test the authentication flow"
