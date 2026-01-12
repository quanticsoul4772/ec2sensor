#!/bin/bash
#
# Suricata Testing Tools Installation
# Installs utilities for Suricata rule testing and validation
#

set -euo pipefail

echo "[INFO] Installing Suricata testing tools..."

# Install Suricata utilities if not already installed
if ! command -v suricata &> /dev/null; then
    echo "[INFO] Suricata not found, installing..."
    sudo add-apt-repository ppa:oisf/suricata-stable -y
    sudo apt-get update -qq
    sudo apt-get install -y suricata
fi

# Install rule management tools
sudo apt-get install -y \
    python3-yaml \
    python3-pip

# Install suricata-update if not present
if ! command -v suricata-update &> /dev/null; then
    pip3 install --user suricata-update
fi

echo "[INFO] ✅ Suricata testing tools installed"

# Verify Suricata installation
echo "[INFO] Verifying Suricata installation..."
suricata_version=$(suricata -V 2>&1 | head -n1)
echo "  ✓ $suricata_version"

# Check Suricata configuration
echo "[INFO] Checking Suricata configuration..."
if sudo suricata -T -c /etc/suricata/suricata.yaml 2>&1 | grep -q "successfully"; then
    echo "  ✓ Suricata configuration valid"
else
    echo "  ⚠ Suricata configuration has issues"
fi

# Check if Suricata is running
if ps aux | grep -q "[s]uricata"; then
    echo "  ✓ Suricata process running"
else
    echo "  ⚠ Suricata not running"
fi

# Check Suricata sensor configuration
suricata_enabled=$(sudo broala-config get suricata.enable 2>/dev/null || echo "0")
if [ "$suricata_enabled" = "1" ]; then
    echo "  ✓ Suricata enabled in sensor config"
else
    echo "  ⚠ Suricata not enabled (run sensor_prep/enable_sensor_features_v2.sh)"
fi

# Create test rules directory if it doesn't exist
sudo mkdir -p /etc/suricata/rules/test
sudo chown $(whoami):$(whoami) /etc/suricata/rules/test

echo "[INFO] Suricata testing tools ready"
echo "[INFO] Test rules directory: /etc/suricata/rules/test"
echo "[INFO] Main config: /etc/suricata/suricata.yaml"
echo "[INFO] Logs: /var/log/suricata/"
