#!/bin/bash
#
# Enable Sensor Features
# Enables HTTP access, YARA, Suricata, and SmartPCAP on Corelight sensors
#
# Usage: ./enable_sensor_features.sh [sensor_ip] [ssh_user]
#

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source logging if available
if [ -f "${PROJECT_ROOT}/ec2sensor_logging.sh" ]; then
    source "${PROJECT_ROOT}/ec2sensor_logging.sh"
    log_init
else
    # Fallback logging functions
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARN] $1"; }
fi

# Parse arguments
SENSOR_IP="${1:-}"
SSH_USER="${2:-broala}"

# Load environment for sensor IP if not provided
if [ -z "$SENSOR_IP" ]; then
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        source "${PROJECT_ROOT}/.env"
        SENSOR_IP="${SSH_HOST:-}"
    fi
fi

# Validate we have a sensor IP
if [ -z "$SENSOR_IP" ]; then
    log_error "Sensor IP not provided and SSH_HOST not set in .env"
    echo ""
    echo "Usage: $0 [sensor_ip] [ssh_user]"
    echo ""
    echo "Examples:"
    echo "  $0 10.50.88.100"
    echo "  $0 10.50.88.100 broala"
    echo ""
    exit 1
fi

log_info "Enabling sensor features on: $SENSOR_IP"
log_info "SSH User: $SSH_USER"

# Configuration commands to enable features
ENABLE_COMMANDS=(
    "sudo broala-config set http.access.enable=1"
    "sudo broala-config set license.yara.enable=1"
    "sudo broala-config set license.suricata.enable=1"
    "sudo broala-config set license.smartpcap.enable=1"
    "sudo broala-apply-config -q"
)

log_info "----------------------------------------"
log_info "Enabling Features:"
log_info "  ✓ HTTP Access"
log_info "  ✓ YARA Scanning"
log_info "  ✓ Suricata IDS"
log_info "  ✓ SmartPCAP"
log_info "----------------------------------------"

# Determine SSH authentication method
SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Try SSH key first
if [ -f "$SSH_KEY_PATH" ]; then
    log_info "Using SSH key authentication: $SSH_KEY_PATH"
    SSH_CMD="ssh -i $SSH_KEY_PATH $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
elif [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    log_info "Using password authentication (sshpass)"
    SSH_CMD="sshpass -e ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    export SSHPASS="${SSH_PASSWORD}"
else
    log_info "Using standard SSH (manual password entry)"
    SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
fi

# Execute configuration commands
log_info "Connecting to sensor..."

# Combine all commands into a single SSH session
FULL_COMMAND=$(printf '%s; ' "${ENABLE_COMMANDS[@]}")

log_info "Executing configuration commands..."
if $SSH_CMD "$FULL_COMMAND"; then
    log_info "✅ Sensor features enabled successfully!"
    log_info ""
    log_info "Enabled features:"
    log_info "  • HTTP Access - API and web interface available"
    log_info "  • YARA - File scanning with YARA rules"
    log_info "  • Suricata - IDS/IPS engine for network detection"
    log_info "  • SmartPCAP - Intelligent packet capture"
    log_info ""
    log_info "Configuration applied. Sensor services may restart."
    log_info "Allow 1-2 minutes for services to stabilize."
else
    EXIT_CODE=$?
    log_error "Failed to enable sensor features (exit code: $EXIT_CODE)"
    log_error ""
    log_error "Troubleshooting:"
    log_error "  1. Verify sensor is accessible: ping $SENSOR_IP"
    log_error "  2. Check SSH connectivity: ssh ${SSH_USER}@${SENSOR_IP}"
    log_error "  3. Verify VPN connection: tailscale status"
    log_error "  4. Check sensor status: ./sensor_lifecycle.sh status"
    exit $EXIT_CODE
fi

# Optional: Verify features are enabled
log_info ""
log_info "Verifying configuration..."

VERIFY_CMD="sudo broala-config get http.access.enable; sudo broala-config get license.yara.enable; sudo broala-config get license.suricata.enable; sudo broala-config get license.smartpcap.enable"

if $SSH_CMD "$VERIFY_CMD" 2>/dev/null; then
    log_info "✅ Configuration verified"
else
    log_warning "Could not verify configuration (sensor may be restarting)"
fi

log_info ""
log_info "Next steps:"
log_info "  • Wait for sensor services to restart (~2 minutes)"
log_info "  • Verify sensor status: ./sensor_lifecycle.sh connect"
log_info "  • Check running services: sudo corelightctl sensor status"
log_info "  • View configuration: sudo broala-config all | grep -E 'yara|suricata|smartpcap|http.access'"

exit 0
