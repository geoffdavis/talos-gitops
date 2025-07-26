#!/bin/bash

# Generate Talos Custom Schematic with Extensions
# This script creates a custom Talos installer image with required system extensions

set -euo pipefail

# Configuration
FACTORY_URL="https://factory.talos.dev"
SCHEMATIC_FILE="talos/generated/schematic.yaml"
SCHEMATIC_ID_FILE="talos/generated/schematic-id.txt"

# Create generated directory if it doesn't exist
mkdir -p "$(dirname "${SCHEMATIC_FILE}")"

# Generate schematic configuration
cat > "${SCHEMATIC_FILE}" << 'EOF'
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/iscsi-tools    # Required for Longhorn storage
      - siderolabs/ext-lldpd      # Network discovery protocol
      - siderolabs/usb-modem-drivers  # Mac mini USB device support
      - siderolabs/thunderbolt    # Mac mini Thunderbolt support
EOF

echo "Generated schematic configuration:"
cat "${SCHEMATIC_FILE}"

# Create schematic via Image Factory API
echo "Creating schematic via Talos Image Factory..."
SCHEMATIC_ID=$(curl -s -X POST "${FACTORY_URL}/schematics" \
  -H "Content-Type: application/yaml" \
  --data-binary @"${SCHEMATIC_FILE}" | jq -r '.id')

if [ -z "${SCHEMATIC_ID}" ] || [ "${SCHEMATIC_ID}" = "null" ]; then
  echo "❌ Failed to create schematic"
  exit 1
fi

echo "✅ Schematic created successfully!"
echo "Schematic ID: ${SCHEMATIC_ID}"

# Save schematic ID
echo "${SCHEMATIC_ID}" > "${SCHEMATIC_ID_FILE}"

# Generate installer image URLs
TALOS_VERSION="v1.10.5"
INSTALLER_URL="${FACTORY_URL}/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-amd64.tar.gz"
INSTALLER_ISO_URL="${FACTORY_URL}/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-amd64.iso"

echo ""
echo "Custom Talos installer URLs:"
echo "  Installer: ${INSTALLER_URL}"
echo "  ISO: ${INSTALLER_ISO_URL}"
echo ""
echo "Add this installer URL to your machine configuration:"
echo "  install:"
echo "    image: ${INSTALLER_URL}"
echo ""
echo "Schematic ID saved to: ${SCHEMATIC_ID_FILE}"
