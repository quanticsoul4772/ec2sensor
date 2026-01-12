#!/bin/bash
#
# Performance Monitoring Tools Installation
# Installs comprehensive monitoring and profiling tools
#

set -euo pipefail

echo "[INFO] Installing performance monitoring tools..."

# Update package list
sudo apt-get update -qq

# Install monitoring tools
sudo apt-get install -y \
    htop \
    iotop \
    iftop \
    nethogs \
    nload \
    bmon \
    sysstat \
    dstat \
    atop \
    nmon \
    glances

# Install network performance tools
sudo apt-get install -y \
    iperf3 \
    netperf \
    mtr \
    traceroute

# Install system profiling tools
sudo apt-get install -y \
    strace \
    ltrace \
    perf-tools-unstable

echo "[INFO] ✅ Performance monitoring tools installed"

# Verify installations
echo "[INFO] Verifying installations..."
command -v htop >/dev/null && echo "  ✓ htop - Interactive process viewer"
command -v iotop >/dev/null && echo "  ✓ iotop - Disk I/O monitor"
command -v iftop >/dev/null && echo "  ✓ iftop - Network bandwidth monitor"
command -v nethogs >/dev/null && echo "  ✓ nethogs - Per-process network monitor"
command -v iperf3 >/dev/null && echo "  ✓ iperf3 - Network performance testing"
command -v mpstat >/dev/null && echo "  ✓ mpstat - CPU statistics (sysstat)"

echo "[INFO] Performance monitoring tools ready"
echo ""
echo "Common Commands:"
echo "  CPU:     htop, mpstat 1, top"
echo "  Memory:  free -h, vmstat 1"
echo "  Disk:    iotop, iostat -x 1"
echo "  Network: iftop -i eth1, nethogs eth1, nload eth1"
echo "  Overall: glances, dstat"
