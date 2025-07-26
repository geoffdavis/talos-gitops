#!/bin/bash

# Update Talos machine configurations to use custom installer images
# This script reads the schematic ID and updates the installer image URLs

set -euo pipefail

# Configuration
SCHEMATIC_ID_FILE="talos/generated/schematic-id.txt"
FACTORY_URL="https://factory.talos.dev"
TALOS_VERSION="v1.10.5"
CONTROLPLANE_PATCH="talos/patches/controlplane.yaml"
WORKER_PATCH="talos/patches/worker.yaml"

# Check if schematic ID exists
if [ ! -f "${SCHEMATIC_ID_FILE}" ]; then
    echo "❌ Schematic ID file not found: ${SCHEMATIC_ID_FILE}"
    echo "Run 'task talos:generate-schematic' first to create a custom schematic"
    exit 1
fi

# Read schematic ID
SCHEMATIC_ID=$(cat "${SCHEMATIC_ID_FILE}")

if [ -z "${SCHEMATIC_ID}" ]; then
    echo "❌ Empty schematic ID in file: ${SCHEMATIC_ID_FILE}"
    exit 1
fi

echo "Using schematic ID: ${SCHEMATIC_ID}"

# Generate custom installer URL
INSTALLER_URL="${FACTORY_URL}/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-amd64.tar.gz"

echo "Custom installer URL: ${INSTALLER_URL}"

# Update controlplane patch
echo "Updating controlplane patch..."
sed -i.bak "s|image: ghcr.io/siderolabs/talos:v1.10.4  # Will be replaced with custom installer URL|image: ${INSTALLER_URL}|" "${CONTROLPLANE_PATCH}"

# Update worker patch
echo "Updating worker patch..."
sed -i.bak "s|image: ghcr.io/siderolabs/talos:v1.10.4  # Will be replaced with custom installer URL|image: ${INSTALLER_URL}|" "${WORKER_PATCH}"

# Clean up backup files
rm -f "${CONTROLPLANE_PATCH}.bak" "${WORKER_PATCH}.bak"

echo "✅ Updated machine configurations to use custom installer image with extensions:"
echo "  • iscsi-tools (Longhorn storage)"
echo "  • ext-lldpd (network discovery)"
echo "  • usb-modem-drivers (Mac mini USB devices)"
echo "  • thunderbolt (Mac mini Thunderbolt devices)"
echo ""
echo "Machine configurations updated:"
echo "  • ${CONTROLPLANE_PATCH}"
echo "  • ${WORKER_PATCH}"
echo ""
echo "Run 'task talos:generate-config' to generate updated Talos configuration files"
