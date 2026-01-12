#!/bin/bash
#
# Sensor Preparation Orchestrator
# Prepares EC2 sensors for testing based on configuration profiles
#
# Usage: ./prepare_sensor.sh --config <config_name> [--sensor <sensor_ip>]
#

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source logging
if [ -f "${PROJECT_ROOT}/ec2sensor_logging.sh" ]; then
    source "${PROJECT_ROOT}/ec2sensor_logging.sh"
    log_init
else
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARN] $1"; }
    log_debug() { echo "[DEBUG] $1"; }
fi

# Default values
CONFIG_NAME=""
SENSOR_IP=""
SSH_USER="broala"
DRY_RUN=false
SKIP_SNAPSHOT=false

# Show usage
show_usage() {
    cat << EOF
Sensor Preparation Orchestrator

Usage: $0 --config <config_name> [options]

Required:
  --config <name>       Configuration profile name (from sensor_prep/configs/)

Optional:
  --sensor <ip>         Sensor IP address (default: from .env SSH_HOST)
  --user <username>     SSH username (default: broala)
  --dry-run            Show what would be done without executing
  --skip-snapshot      Don't create baseline snapshot
  --help               Show this help message

Examples:
  # Prepare with default config
  $0 --config default

  # Prepare specific sensor with SmartPCAP config
  $0 --config smartpcap_enabled --sensor 10.50.88.100

  # Dry run to see what would happen
  $0 --config suricata_test --dry-run

Available Configs:
EOF
    ls -1 "${SCRIPT_DIR}/configs/"*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//' | sed 's/^/  - /'
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_NAME="$2"
            shift 2
            ;;
        --sensor)
            SENSOR_IP="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-snapshot)
            SKIP_SNAPSHOT=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate config name provided
if [ -z "$CONFIG_NAME" ]; then
    log_error "Configuration name required"
    show_usage
    exit 1
fi

# Load config file
CONFIG_FILE="${SCRIPT_DIR}/configs/${CONFIG_NAME}.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info "Available configs:"
    ls -1 "${SCRIPT_DIR}/configs/"*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//' | sed 's/^/  - /'
    exit 1
fi

log_info "Using configuration: $CONFIG_NAME"
log_info "Config file: $CONFIG_FILE"

# Get sensor IP if not provided
if [ -z "$SENSOR_IP" ]; then
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        source "${PROJECT_ROOT}/.env"
        SENSOR_IP="${SSH_HOST:-}"
    fi
fi

if [ -z "$SENSOR_IP" ]; then
    log_error "Sensor IP not provided and SSH_HOST not set in .env"
    log_info "Please specify --sensor <ip> or ensure SSH_HOST is set in .env"
    exit 1
fi

log_info "Target sensor: $SSH_USER@$SENSOR_IP"

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No changes will be made"
fi

# Determine SSH command
SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

if [ -f "$SSH_KEY_PATH" ]; then
    SSH_CMD="ssh -i $SSH_KEY_PATH $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    SCP_CMD="scp -i $SSH_KEY_PATH $SSH_OPTS"
elif [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    SSH_CMD="sshpass -e ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    SCP_CMD="sshpass -e scp $SSH_OPTS"
    export SSHPASS="${SSH_PASSWORD}"
else
    SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    SCP_CMD="scp $SSH_OPTS"
fi

log_info "========================================"
log_info "Sensor Preparation Plan"
log_info "========================================"
log_info "Configuration: $CONFIG_NAME"
log_info "Sensor: $SENSOR_IP"
log_info "SSH User: $SSH_USER"
log_info ""

# Parse YAML config (simple grep-based parsing for now)
log_info "Configuration Details:"
grep "^description:" "$CONFIG_FILE" | sed 's/description: /  Description: /' || true
grep "^  ami_id:" "$CONFIG_FILE" | sed 's/  ami_id: /  AMI: /' || true
grep "^  instance_type:" "$CONFIG_FILE" | sed 's/  instance_type: /  Instance: /' || true

log_info ""
log_info "Preparation Steps:"
log_info "  1. Verify sensor connectivity"
log_info "  2. Create pre-preparation snapshot (if not skipped)"
log_info "  3. Enable sensor features"
log_info "  4. Install required packages"
log_info "  5. Apply additional configuration"
log_info "  6. Validate sensor status"
log_info "  7. Create baseline snapshot"
log_info ""

if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN complete - no changes made"
    exit 0
fi

read -p "Continue with sensor preparation? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Preparation cancelled"
    exit 0
fi

log_info "========================================"
log_info "Starting Sensor Preparation"
log_info "========================================"

# Step 1: Verify connectivity
log_info "[Step 1/7] Verifying sensor connectivity..."
if $SSH_CMD "echo 'Connection successful'" >/dev/null 2>&1; then
    log_info "✅ Sensor is reachable"
else
    log_error "❌ Cannot connect to sensor"
    log_error "Troubleshooting:"
    log_error "  - Verify VPN connection: tailscale status"
    log_error "  - Check sensor status: ./sensor_lifecycle.sh status"
    log_error "  - Test SSH: ssh ${SSH_USER}@${SENSOR_IP}"
    exit 1
fi

# Step 2: Create pre-preparation snapshot
if [ "$SKIP_SNAPSHOT" = false ]; then
    log_info "[Step 2/7] Creating pre-preparation snapshot..."
    SNAPSHOT_NAME="pre-prep-${CONFIG_NAME}-$(date +%Y%m%d-%H%M%S)"
    if $SSH_CMD "sudo broala-snapshot -c $SNAPSHOT_NAME" 2>&1 | grep -q "successfully\|created"; then
        log_info "✅ Snapshot created: $SNAPSHOT_NAME"
    else
        log_warning "⚠️ Snapshot creation may have failed (continuing anyway)"
    fi
else
    log_info "[Step 2/7] Skipping snapshot creation (--skip-snapshot)"
fi

# Step 3: Enable sensor features
log_info "[Step 3/7] Enabling sensor features..."
ENABLE_SCRIPT="${SCRIPT_DIR}/enable_sensor_features_v2.sh"
if [ -f "$ENABLE_SCRIPT" ]; then
    if bash "$ENABLE_SCRIPT" "$SENSOR_IP" "$SSH_USER" 2>&1 | tail -n 20; then
        log_info "✅ Sensor features enabled"
    else
        log_error "❌ Failed to enable sensor features"
        exit 1
    fi
else
    log_warning "⚠️ enable_sensor_features_v2.sh not found, skipping"
fi

# Step 4: Install required packages
log_info "[Step 4/7] Installing required packages..."

# Get list of packages from config
PACKAGES=$(grep -A 10 "^packages:" "$CONFIG_FILE" | grep "^  - " | sed 's/^  - //' || echo "")

if [ -n "$PACKAGES" ]; then
    for package in $PACKAGES; do
        PACKAGE_SCRIPT="${SCRIPT_DIR}/packages/${package}.sh"
        if [ -f "$PACKAGE_SCRIPT" ]; then
            log_info "Installing package: $package"

            # Copy script to sensor
            if $SCP_CMD "$PACKAGE_SCRIPT" "${SSH_USER}@${SENSOR_IP}:/tmp/${package}.sh"; then
                # Execute on sensor
                if $SSH_CMD "chmod +x /tmp/${package}.sh && /tmp/${package}.sh"; then
                    log_info "✅ Package installed: $package"
                else
                    log_warning "⚠️ Package installation may have failed: $package"
                fi
            else
                log_warning "⚠️ Could not copy package script: $package"
            fi
        else
            log_warning "⚠️ Package script not found: $PACKAGE_SCRIPT"
        fi
    done
else
    log_info "No packages specified in configuration"
fi

# Step 5: Apply additional configuration
log_info "[Step 5/7] Applying additional configuration..."

# Get brolin_config entries from YAML
BROLIN_CONFIGS=$(grep -A 20 "^brolin_config:" "$CONFIG_FILE" | grep "^  [a-z]" | sed 's/^  //' || echo "")

if [ -n "$BROLIN_CONFIGS" ]; then
    while IFS= read -r config_line; do
        if [ -n "$config_line" ]; then
            KEY=$(echo "$config_line" | cut -d: -f1 | tr -d ' ')
            VALUE=$(echo "$config_line" | cut -d: -f2- | tr -d ' ')

            log_info "Setting $KEY=$VALUE"
            $SSH_CMD "sudo broala-config set ${KEY}=${VALUE}" || log_warning "Failed to set $KEY"
        fi
    done <<< "$BROLIN_CONFIGS"

    log_info "Applying configuration..."
    $SSH_CMD "sudo broala-apply-config -q"
    log_info "✅ Configuration applied (services may restart)"
    log_info "Waiting 30 seconds for services to stabilize..."
    sleep 30
else
    log_info "No additional configuration to apply"
fi

# Step 6: Validate sensor status
log_info "[Step 6/7] Validating sensor status..."
if $SSH_CMD "sudo corelightctl sensor status" 2>&1 | grep -q "running\|active"; then
    log_info "✅ Sensor status: Running"
else
    log_warning "⚠️ Sensor may not be fully running yet"
fi

# Step 7: Create baseline snapshot
if [ "$SKIP_SNAPSHOT" = false ]; then
    log_info "[Step 7/7] Creating baseline snapshot..."
    BASELINE_NAME="baseline-${CONFIG_NAME}-$(date +%Y%m%d-%H%M%S)"
    if $SSH_CMD "sudo broala-snapshot -c $BASELINE_NAME" 2>&1 | grep -q "successfully\|created"; then
        log_info "✅ Baseline snapshot created: $BASELINE_NAME"
    else
        log_warning "⚠️ Baseline snapshot may have failed"
    fi
else
    log_info "[Step 7/7] Skipping baseline snapshot (--skip-snapshot)"
fi

log_info "========================================"
log_info "✅ Sensor Preparation Complete!"
log_info "========================================"
log_info "Configuration: $CONFIG_NAME"
log_info "Sensor: $SENSOR_IP"
log_info ""
log_info "Next Steps:"
log_info "  • Connect to sensor: ./sensor_lifecycle.sh connect"
log_info "  • Verify status: ssh ${SSH_USER}@${SENSOR_IP} 'sudo corelightctl sensor status'"
log_info "  • Run tests: ./testing/test_runner.sh --test <test_case>"
log_info ""
log_info "Snapshots created:"
if [ "$SKIP_SNAPSHOT" = false ]; then
    log_info "  • Pre-prep: $SNAPSHOT_NAME"
    log_info "  • Baseline: $BASELINE_NAME"
    log_info ""
    log_info "To revert: ssh ${SSH_USER}@${SENSOR_IP} 'sudo broala-snapshot -R <snapshot_name> && sudo reboot'"
fi

exit 0
