#!/bin/bash
#
# Enable Sensor Features (Version 2 - Multi-API Support)
# Enables HTTP access, YARA, Suricata, and SmartPCAP on Corelight sensors
# Supports both legacy (broala-*) and modern (corelightctl) APIs
#
# Usage: ./enable_sensor_features_v2.sh [sensor_ip] [ssh_user]
#

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Set defaults for logging
export SENSOR_NAME="${SENSOR_NAME:-unknown}"

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

# Determine SSH authentication method
SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"

# Load SSH_PASSWORD from .env if available
if [ -z "${SSH_PASSWORD:-}" ] && [ -f "${PROJECT_ROOT}/.env" ]; then
    set +u  # Temporarily disable unbound variable check
    source "${PROJECT_ROOT}/.env"
    set -u
fi

# Try password first if available (most reliable for test sensors)
if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    log_info "Using password authentication (sshpass)"
    SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${SSH_USER}@${SENSOR_IP}"
    export SSHPASS="${SSH_PASSWORD}"
elif [ -f "$SSH_KEY_PATH" ]; then
    log_info "Using SSH key authentication: $SSH_KEY_PATH"
    SSH_CMD="ssh -i $SSH_KEY_PATH $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
else
    log_info "Using standard SSH (manual password entry)"
    SSH_CMD="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${SSH_USER}@${SENSOR_IP}"
fi

# Detect which configuration API is available
log_info "Detecting sensor configuration API..."

if $SSH_CMD "which corelightctl" >/dev/null 2>&1; then
    SENSOR_API="corelightctl"
    log_info "✓ Detected modern API: corelightctl"
elif $SSH_CMD "which broala-config" >/dev/null 2>&1; then
    SENSOR_API="broala"
    log_info "✓ Detected legacy API: broala-config"
else
    log_error "Could not detect sensor configuration API"
    log_error "Neither corelightctl nor broala-config found on sensor"
    exit 1
fi

log_info "----------------------------------------"
log_info "Enabling Features:"
log_info "  ✓ YARA Scanning"
log_info "  ✓ Suricata IDS"
log_info "  ✓ SmartPCAP"
log_info "----------------------------------------"

# Execute configuration based on detected API
if [ "$SENSOR_API" = "corelightctl" ]; then
    log_info "Using corelightctl configuration method..."

    # Get current configuration
    log_info "Retrieving current configuration..."
    $SSH_CMD "sudo corelightctl sensor configuration get -o yaml > /tmp/sensor_config.yaml"

    # Check current values
    YARA_CURRENT=$($SSH_CMD "grep '^corelight.yara.enable:' /tmp/sensor_config.yaml | cut -d: -f2 | xargs" || echo "unknown")
    SURICATA_CURRENT=$($SSH_CMD "grep '^suricata.enable:' /tmp/sensor_config.yaml | cut -d: -f2 | xargs" || echo "unknown")
    SMARTPCAP_CURRENT=$($SSH_CMD "grep '^smartpcap.enable:' /tmp/sensor_config.yaml | cut -d: -f2 | xargs" || echo "unknown")

    log_info "Current configuration:"
    log_info "  YARA: $YARA_CURRENT"
    log_info "  Suricata: $SURICATA_CURRENT"
    log_info "  SmartPCAP: $SMARTPCAP_CURRENT"

    # Modify configuration file
    log_info "Updating configuration..."
    $SSH_CMD "sudo sed -i 's/^corelight.yara.enable:.*/corelight.yara.enable: \"True\"/' /tmp/sensor_config.yaml"
    $SSH_CMD "sudo sed -i 's/^suricata.enable:.*/suricata.enable: \"True\"/' /tmp/sensor_config.yaml"
    $SSH_CMD "sudo sed -i 's/^smartpcap.enable:.*/smartpcap.enable: \"True\"/' /tmp/sensor_config.yaml"

    # Apply configuration
    log_info "Applying configuration changes..."
    if $SSH_CMD "sudo corelightctl sensor configuration put -f /tmp/sensor_config.yaml"; then
        log_info "✅ Configuration applied successfully"
    else
        log_error "Failed to apply configuration"
        $SSH_CMD "sudo rm -f /tmp/sensor_config.yaml" || true
        exit 1
    fi

    # Cleanup
    $SSH_CMD "sudo rm -f /tmp/sensor_config.yaml"

else
    # Legacy broala-config method
    log_info "Using broala-config configuration method..."

    ENABLE_COMMANDS=(
        "sudo broala-config set http.access.enable=1"
        "sudo broala-config set license.yara.enable=1"
        "sudo broala-config set license.suricata.enable=1"
        "sudo broala-config set license.smartpcap.enable=1"
        "sudo broala-apply-config -q"
    )

    # Combine all commands into a single SSH session
    FULL_COMMAND=$(printf '%s; ' "${ENABLE_COMMANDS[@]}")

    log_info "Executing configuration commands..."
    if $SSH_CMD "$FULL_COMMAND"; then
        log_info "✅ Configuration applied successfully"
    else
        EXIT_CODE=$?
        log_error "Failed to enable sensor features (exit code: $EXIT_CODE)"
        exit $EXIT_CODE
    fi
fi

log_info ""
log_info "✅ Sensor features enabled successfully!"
log_info ""
log_info "Enabled features:"
log_info "  • YARA - File scanning with YARA rules"
log_info "  • Suricata - IDS/IPS engine for network detection"
log_info "  • SmartPCAP - Intelligent packet capture"
log_info ""
log_info "Configuration applied. Sensor services may restart."
log_info "Allow 1-2 minutes for services to stabilize."

# Verify configuration
log_info ""
log_info "Verifying configuration..."

if [ "$SENSOR_API" = "corelightctl" ]; then
    YARA_ENABLED=$($SSH_CMD "sudo corelightctl sensor configuration get -o yaml | grep '^corelight.yara.enable:' | cut -d: -f2 | xargs" 2>/dev/null || echo "unknown")
    SURICATA_ENABLED=$($SSH_CMD "sudo corelightctl sensor configuration get -o yaml | grep '^suricata.enable:' | cut -d: -f2 | xargs" 2>/dev/null || echo "unknown")
    SMARTPCAP_ENABLED=$($SSH_CMD "sudo corelightctl sensor configuration get -o yaml | grep '^smartpcap.enable:' | cut -d: -f2 | xargs" 2>/dev/null || echo "unknown")

    log_info "  YARA: $YARA_ENABLED"
    log_info "  Suricata: $SURICATA_ENABLED"
    log_info "  SmartPCAP: $SMARTPCAP_ENABLED"
else
    if $SSH_CMD "sudo broala-config get license.yara.enable; sudo broala-config get license.suricata.enable; sudo broala-config get license.smartpcap.enable" 2>/dev/null; then
        log_info "✅ Configuration verified"
    else
        log_warning "Could not verify configuration (sensor may be restarting)"
    fi
fi

log_info ""
log_info "Next steps:"
log_info "  • Wait for sensor services to restart (~2 minutes)"
log_info "  • Check sensor status: sudo corelightctl sensor status"
if [ "$SENSOR_API" = "corelightctl" ]; then
    log_info "  • View configuration: sudo corelightctl sensor configuration get -o yaml | grep -E 'yara|suricata|smartpcap'"
else
    log_info "  • View configuration: sudo broala-config all | grep -E 'yara|suricata|smartpcap'"
fi

exit 0
