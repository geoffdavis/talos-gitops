#!/usr/bin/env python3
"""
Flux MCP Wrapper - Makes it easy to call Flux MCP tools from Claude Code
"""
import json
import subprocess
import sys
import os

class FluxMCPClient:
    def __init__(self):
        self.mcp_path = "/opt/homebrew/bin/flux-operator-mcp"
        self.kubeconfig = os.environ.get("KUBECONFIG", "/Users/geoff/.kube/config")
        self.initialized = False
        self.request_id = 0

    def _call_method(self, method, params=None):
        """Call an MCP method and return the result"""
        requests = []

        # Initialize if not done
        if not self.initialized:
            requests.append({
                "jsonrpc": "2.0",
                "method": "initialize",
                "params": {
                    "protocolVersion": "0.1.0",
                    "capabilities": {"tools": {}}
                },
                "id": self.request_id
            })
            self.request_id += 1
            self.initialized = True

        # Add the actual request
        requests.append({
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": self.request_id
        })
        current_id = self.request_id
        self.request_id += 1

        # Send requests
        input_data = "\n".join(json.dumps(r) for r in requests) + "\n"

        result = subprocess.run(
            [self.mcp_path, "serve"],
            input=input_data,
            capture_output=True,
            text=True,
            env={"KUBECONFIG": self.kubeconfig}
        )

        # Parse responses
        for line in result.stdout.split("\n"):
            if line.strip():
                try:
                    response = json.loads(line)
                    if response.get("id") == current_id:
                        return response
                except json.JSONDecodeError:
                    continue

        return {"error": "No valid response", "stderr": result.stderr}

    def call_tool(self, tool_name, params=None):
        """Call a specific tool"""
        return self._call_method(f"tools/call", {
            "name": tool_name,
            "arguments": params or {}
        })

    def get_flux_instance(self):
        """Get Flux instance status"""
        return self.call_tool("get_flux_instance")

    def get_kubernetes_resources(self, api_version, kind, namespace=None, name=None):
        """Get Kubernetes resources"""
        params = {"apiVersion": api_version, "kind": kind}
        if namespace:
            params["namespace"] = namespace
        if name:
            params["name"] = name
        return self.call_tool("get_kubernetes_resources", params)

    def reconcile_flux_kustomization(self, name, namespace="flux-system", with_source=True):
        """Reconcile a Flux Kustomization"""
        return self.call_tool("reconcile_flux_kustomization", {
            "name": name,
            "namespace": namespace,
            "with_source": with_source
        })

    def reconcile_flux_helmrelease(self, name, namespace, with_source=True):
        """Reconcile a Flux HelmRelease"""
        return self.call_tool("reconcile_flux_helmrelease", {
            "name": name,
            "namespace": namespace,
            "with_source": with_source
        })

def main():
    """Main function for CLI usage"""
    if len(sys.argv) < 2:
        print("Usage: flux_mcp_wrapper.py <command> [args...]")
        print("\nCommands:")
        print("  flux-status - Get Flux instance status")
        print("  kustomizations - List all Kustomizations")
        print("  helmreleases - List all HelmReleases")
        print("  reconcile-ks <name> [namespace] - Reconcile a Kustomization")
        print("  reconcile-hr <name> <namespace> - Reconcile a HelmRelease")
        return 1

    client = FluxMCPClient()
    command = sys.argv[1]

    if command == "flux-status":
        result = client.get_flux_instance()
    elif command == "kustomizations":
        result = client.get_kubernetes_resources("kustomize.toolkit.fluxcd.io/v1", "Kustomization")
    elif command == "helmreleases":
        result = client.get_kubernetes_resources("helm.toolkit.fluxcd.io/v2", "HelmRelease")
    elif command == "reconcile-ks":
        if len(sys.argv) < 3:
            print("Error: Missing kustomization name")
            return 1
        name = sys.argv[2]
        namespace = sys.argv[3] if len(sys.argv) > 3 else "flux-system"
        result = client.reconcile_flux_kustomization(name, namespace)
    elif command == "reconcile-hr":
        if len(sys.argv) < 4:
            print("Error: Missing helmrelease name and/or namespace")
            return 1
        name = sys.argv[2]
        namespace = sys.argv[3]
        result = client.reconcile_flux_helmrelease(name, namespace)
    else:
        print(f"Unknown command: {command}")
        return 1

    # Pretty print the result
    if "result" in result:
        print(json.dumps(result["result"], indent=2))
    elif "error" in result:
        print(f"Error: {result['error']}")
        if "stderr" in result:
            print(f"Details: {result['stderr']}")
    else:
        print(json.dumps(result, indent=2))

    return 0

if __name__ == "__main__":
    sys.exit(main())
