#!/bin/bash
#
# SmartPCAP Testing Tools Installation
# Installs utilities for SmartPCAP testing and verification
#

set -euo pipefail

echo "[INFO] Installing SmartPCAP testing tools..."

# SmartPCAP is built into the sensor, but we can install utilities for testing

# Install PCAP analysis tools
sudo apt-get update -qq
sudo apt-get install -y \
    wireshark-common \
    tshark \
    editcap \
    mergecap \
    capinfos

# Install Python tools for SmartPCAP API testing
if ! command -v pip3 &> /dev/null; then
    sudo apt-get install -y python3-pip
fi

pip3 install --user requests pyyaml

echo "[INFO] ✅ SmartPCAP testing tools installed"

# Verify SmartPCAP processes are running
echo "[INFO] Verifying SmartPCAP processes..."
if ps aux | grep -q "[s]pcap-esm"; then
    echo "  ✓ spcap-esm running"
else
    echo "  ⚠ spcap-esm not running (may need broala-apply-config)"
fi

if ps aux | grep -q "[s]pcap-query-mgr"; then
    echo "  ✓ spcap-query-mgr running"
else
    echo "  ⚠ spcap-query-mgr not running"
fi

if ps aux | grep -q "[s]pcap-get-server"; then
    echo "  ✓ spcap-get-server running"
else
    echo "  ⚠ spcap-get-server not running"
fi

# Check SmartPCAP configuration
echo "[INFO] Checking SmartPCAP configuration..."
smartpcap_enabled=$(sudo broala-config get smartpcap.enable 2>/dev/null || echo "0")
smartpcap_loaded=$(sudo broala-config get bro.pkgs.corelight.smartpcap.loaded 2>/dev/null || echo "0")

if [ "$smartpcap_enabled" = "1" ]; then
    echo "  ✓ SmartPCAP enabled"
else
    echo "  ⚠ SmartPCAP not enabled (run sensor_prep/enable_sensor_features_v2.sh)"
fi

if [ "$smartpcap_loaded" = "1" ]; then
    echo "  ✓ SmartPCAP package loaded"
else
    echo "  ⚠ SmartPCAP package not loaded"
fi

echo "[INFO] SmartPCAP testing tools ready"
echo "[INFO] Use 'tshark -r <pcap>' to analyze PCAP files"
echo "[INFO] Use 'capinfos <pcap>' for PCAP statistics"
