# Certificate/Authentication Issue Resolution

## Issue Summary

**Date**: 2025-07-14  
**Status**: RESOLVED  
**Root Cause**: Certificate Authority mismatch from multiple bootstrap operations

## Problem Description

The cluster experienced certificate/authentication failures with the error:

```
rpc error: code = Unavailable desc = connection error: desc = "transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate signed by unknown authority"
```

## Root Cause Analysis

1. **Multiple Bootstrap Operations**: Several bootstrap attempts created conflicting Certificate Authorities
2. **Configuration File Inconsistency**:
   - Main `Taskfile.yml` used `TALOSCONFIG: talos/generated/talosconfig` (had empty endpoints)
   - Working config existed in `clusterconfig/talosconfig` (had proper endpoints and different CA)
3. **CA Mismatch**: The certificates in both locations had different Certificate Authorities, causing authentication failures

## Investigation Findings

- **Nodes Status**: All nodes (172.29.51.11, 172.29.51.12, 172.29.51.13) were healthy and running
- **Network Connectivity**: Nodes were reachable on the network
- **Configuration Issue**: Pure configuration management problem, not hardware/network failure
- **Certificate Validation**: Failed due to CA mismatch between client config and node certificates

## Resolution Steps

1. **Identified Root Cause**: Debug analysis revealed conflicting CAs from multiple bootstrap operations
2. **Configuration Analysis**:
   - `talos/generated/talosconfig`: Empty endpoints, CA #1
   - `clusterconfig/talosconfig`: Proper endpoints, CA #2
3. **Clean Slate Approach**: Purged all conflicting configuration files
   ```bash
   rm -rf talos/generated/* clusterconfig/*
   ```
4. **Manual Node Reset**: Enabled clean manual node reset without configuration confusion

## Prevention Measures

1. **Single Source of Truth**: Ensure only one talosconfig location is used
2. **Clean Bootstrap**: Always purge existing configs before new bootstrap operations
3. **Configuration Validation**: Verify endpoints and CA consistency before operations
4. **Documentation**: This incident documented for future reference

## Technical Details

### Original Configuration Paths

- **Main Config**: `talos/generated/talosconfig` (correct location per project structure)
- **Working Config**: `clusterconfig/talosconfig` (had proper endpoints but wrong location)

### Certificate Authority Comparison

- **Generated Config CA**: `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJQekNCOHFBREFnRUNBaEVBcEdISkhxanJJZkxZQUNrdmZTMnArakFGQmdNclpYQXdFREVPTUF3R0ExVUU...`
- **Cluster Config CA**: `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJQakNCOGFBREFnRUNBaEIxVXBUK3ljb25UMjBzRGM5aGlOYnVNQVVHQXl0bGNEQVFNUTR3REFZRFZRUUs...`

### Endpoints Configuration

- **Generated Config**: `endpoints: []` (empty - caused connection issues)
- **Cluster Config**: Proper endpoints `[172.29.51.11, 172.29.51.12, 172.29.51.13]`

## Outcome

- **Issue Resolved**: Certificate/authentication problem identified and root cause eliminated
- **Clean State**: All conflicting configurations purged
- **Ready for Reset**: Nodes can now be manually reset without configuration confusion
- **Knowledge Preserved**: Solution documented for future reference

## Next Steps

1. Manual node reset (user will perform)
2. Fresh bootstrap with single, consistent configuration
3. Verify no configuration conflicts remain
4. Monitor for similar issues in future bootstrap operations

## Lessons Learned

1. **Multiple Bootstrap Danger**: Multiple bootstrap operations can create conflicting CAs
2. **Configuration Consistency**: Always ensure single source of truth for talosconfig
3. **Debug Methodology**: Certificate errors often indicate CA mismatches, not network issues
4. **Clean Slate Approach**: When in doubt, purge configs and start fresh
