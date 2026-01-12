#!/bin/bash
# Location: scripts/enable_sensor_features.sh
# Purpose: Enable standard sensor features (HTTP, YARA, Suricata, SmartPCAP)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/ec2sensor_logging.sh"
source "$SCRIPT_DIR/load_env.sh"

usage() {
    cat <<EOF
Usage: $0 <sensor_ip>

Enable standard sensor features for testing.

Features enabled:
  - HTTP access (API/UI)
  - YARA engine
  - Suricata IDS
  - SmartPCAP

Example:
  $0 10.50.88.199
EOF
    exit 1
}

SENSOR_IP="${1:-}"
if [ -z "$SENSOR_IP" ]; then
    echo "Error: sensor_ip required"
    usage
fi

log_init
log_info "=== Enabling Sensor Features: $SENSOR_IP ==="

# Connect and enable features
log_info "Connecting to sensor to enable features..."

# Try SSH with sshpass if password is available
if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    log_info "Using password authentication"
    sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USERNAME}@${SENSOR_IP}" << 'EOF'
echo "Enabling sensor features and licenses..."
sudo /opt/broala/bin/broala-config set http.access.enable=1
sudo /opt/broala/bin/broala-config set license.yara.enable=1
sudo /opt/broala/bin/broala-config set license.suricata.enable=1
sudo /opt/broala/bin/broala-config set license.smartpcap.enable=1
sudo /opt/broala/bin/broala-config set corelight.yara.enable=1
sudo /opt/broala/bin/broala-config set suricata.enable=1
sudo /opt/broala/bin/broala-config set smartpcap.enable=1
echo "Applying configuration..."
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
echo "Features enabled successfully"
EOF
else
    log_info "Using SSH key authentication"
    SSH_USERNAME="${SSH_USERNAME:-broala}"
    ssh "${SSH_USERNAME}@${SENSOR_IP}" << 'EOF'
echo "Enabling sensor features and licenses..."
sudo /opt/broala/bin/broala-config set http.access.enable=1
sudo /opt/broala/bin/broala-config set license.yara.enable=1
sudo /opt/broala/bin/broala-config set license.suricata.enable=1
sudo /opt/broala/bin/broala-config set license.smartpcap.enable=1
sudo /opt/broala/bin/broala-config set corelight.yara.enable=1
sudo /opt/broala/bin/broala-config set suricata.enable=1
sudo /opt/broala/bin/broala-config set smartpcap.enable=1
echo "Applying configuration..."
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
echo "Features enabled successfully"
EOF
fi

log_info "=== Features Enabled Successfully ==="
log_info "Sensor $SENSOR_IP is ready for use"
log_info ""
log_info "Enabled features:"
log_info "  ✓ HTTP access"
log_info "  ✓ YARA engine"
log_info "  ✓ Suricata IDS"
log_info "  ✓ SmartPCAP"
