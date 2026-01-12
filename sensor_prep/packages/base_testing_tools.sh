#!/bin/bash
#
# Base Testing Tools Installation
# Installs common utilities needed for sensor testing
#

set -euo pipefail

echo "[INFO] Installing base testing tools..."

# Update package list
sudo apt-get update -qq

# Install essential testing utilities
sudo apt-get install -y \
    jq \
    wget \
    curl \
    netcat \
    tcpdump \
    vim \
    git \
    htop \
    iotop \
    nload \
    iftop \
    net-tools \
    iputils-ping \
    dnsutils \
    telnet \
    screen \
    tmux

echo "[INFO] ✅ Base testing tools installed successfully"

# Verify installations
echo "[INFO] Verifying installations..."
command -v jq >/dev/null && echo "  ✓ jq"
command -v wget >/dev/null && echo "  ✓ wget"
command -v curl >/dev/null && echo "  ✓ curl"
command -v tcpdump >/dev/null && echo "  ✓ tcpdump"
command -v htop >/dev/null && echo "  ✓ htop"

echo "[INFO] Base testing tools ready"
