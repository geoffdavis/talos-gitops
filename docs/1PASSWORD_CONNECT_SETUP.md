# 1Password Connect Credentials Setup

## Regenerating 1Password Connect Credentials (Version 2)

The 1Password Connect server requires credentials in the newer version 2 format. If you're seeing the error "credentials file is not version 2", follow these steps:

### Prerequisites

1. Access to your 1Password account with administrative privileges
2. 1Password CLI installed locally (optional but recommended)

### Steps to Generate New Credentials

1. **Log into your 1Password account** at https://my.1password.com/

2. **Navigate to Integrations**:
   - Click on your account name in the top right
   - Select "Integrations" from the dropdown
   - Or go directly to: https://my.1password.com/integrations/directory/

3. **Set up 1Password Connect Server**:
   - Find "1Password Connect Server" in the integrations list
   - Click "Set Up" or "Manage" if already configured

4. **Create New Credentials**:
   - Click "New Connect Server" or "Add Connect Server"
   - Give it a descriptive name (e.g., "Kubernetes Cluster")
   - Select the vaults you want to access:
     - "Automation" (vault ID: 1)
     - "Shared" (vault ID: 2)
   - Click "Save" or "Create"

5. **Download Credentials**:
   - After creation, you'll see options to download:
     - `1password-credentials.json` - This is what we need
     - A token file (we don't need this for Kubernetes setup)
   - Download the `1password-credentials.json` file

6. **Verify the Credentials Format**:
   The file should look similar to this structure:
   ```json
   {
     "verifier": {
       "salt": "...",
       "localHash": "..."
     },
     "encCredentials": {
       "kid": "...",
       "enc": "A256GCM",
       "cty": "b5+jwk+json",
       "iv": "...",
       "data": "..."
     },
     "version": "2",
     "deviceUuid": "...",
     "uniqueKey": {
       "alg": "A256GCM",
       "ext": true,
       "k": "...",
       "key_ops": ["encrypt", "decrypt"],
       "kty": "oct",
       "kid": "..."
     }
   }
   ```
   Note the `"version": "2"` field.

### Updating the Kubernetes Secret

Once you have the new credentials file:

1. **Backup the existing secret** (optional):
   ```bash
   kubectl get secret -n onepassword-connect onepassword-connect-credentials -o yaml > onepassword-credentials-backup.yaml
   ```

2. **Delete the existing secret**:
   ```bash
   kubectl delete secret -n onepassword-connect onepassword-connect-credentials
   ```

3. **Create the new secret**:
   ```bash
   kubectl create secret generic onepassword-connect-credentials \
     --from-file=1password-credentials.json=/path/to/your/downloaded/1password-credentials.json \
     --namespace=onepassword-connect
   ```

4. **Restart the 1Password Connect deployment**:
   ```bash
   kubectl rollout restart deployment -n onepassword-connect onepassword-connect
   ```

### Alternative: Using the Bootstrap Script

If you have the bootstrap script set up, you can also update it:

1. Place the new `1password-credentials.json` file in the expected location
2. Run the bootstrap script:
   ```bash
   ./scripts/bootstrap-k8s-secrets.sh
   ```

### Troubleshooting

- **"credentials file is not version 2" error**: The credentials are from an older 1Password Connect setup. You must regenerate them.
- **"failed to FindCredentialsUniqueKey" error**: The credentials file is corrupted or incomplete.
- **Connection timeouts**: Check that the vaults selected during credential creation match what's configured in the ClusterSecretStore.

### Security Notes

- Keep the `1password-credentials.json` file secure - it provides access to your vaults
- Don't commit this file to Git
- Consider using a secure method to transfer the file to your cluster
- Rotate credentials periodically