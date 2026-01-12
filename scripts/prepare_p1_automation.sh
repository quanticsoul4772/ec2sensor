#!/bin/bash
# Prepare sensor for P1 automation testing
# Usage: ./scripts/prepare_p1_automation.sh <sensor_ip> [--upgrade] [--fleet-ip 192.168.22.239]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/ec2sensor_logging.sh"
log_init

# Defaults
SENSOR_IP=""
UPGRADE=false
FLEET_IP="192.168.22.239"
FLEET_PORT="1443"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"  # Set via environment or --password flag

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --upgrade)
            UPGRADE=true
            shift
            ;;
        --fleet-ip)
            FLEET_IP="$2"
            shift 2
            ;;
        --password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 <sensor_ip> [OPTIONS]

Prepare EC2 sensor for P1 automation testing.

Options:
  --upgrade           Apply latest updates before preparation
  --fleet-ip IP       Fleet manager IP (default: 192.168.22.239)
  --password PASS     Admin password (required, or set ADMIN_PASSWORD env var)
  -h, --help          Show this help

Examples:
  $0 10.50.88.206
  $0 10.50.88.206 --upgrade
  $0 10.50.88.206 --fleet-ip 192.168.22.228

EOF
            exit 0
            ;;
        *)
            if [ -z "$SENSOR_IP" ]; then
                SENSOR_IP="$1"
            else
                echo "Unknown option: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$SENSOR_IP" ]; then
    echo "Error: sensor_ip required"
    echo "Usage: $0 <sensor_ip> [--upgrade] [--fleet-ip IP]"
    exit 1
fi

if [ -z "$ADMIN_PASSWORD" ]; then
    echo "Error: Admin password required"
    echo "Set via: --password <password> or export ADMIN_PASSWORD='your_password'"
    exit 1
fi

# Load SSH credentials
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

SSH_USERNAME="${SSH_USERNAME:-broala}"
SSH_PASSWORD="${SSH_PASSWORD:-${SSH_PASSWORD}}"

# Check SSH connectivity
log_info "=== Preparing Sensor for P1 Automation: $SENSOR_IP ==="
log_info ""
log_info "Checking connectivity..."

if ! command -v sshpass &> /dev/null; then
    log_error "sshpass not installed. Install with: brew install sshpass"
    exit 1
fi

if ! SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" "echo 'Connected'" &>/dev/null; then
    log_error "Cannot connect to sensor at $SENSOR_IP"
    exit 1
fi

log_info "OK: Connected to sensor"
log_info ""

# Step 1: Check for system.seeded
log_info "[Step 1/7] Checking if sensor is fully seeded..."
seeded=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" "sudo /opt/broala/bin/broala-config get system.seeded 2>/dev/null" 2>/dev/null || echo "0")

if [ "$seeded" != "1" ]; then
    log_warning "Sensor not fully seeded (system.seeded=$seeded)"
    log_warning "Configuration changes may fail. Wait for full initialization."
    log_info ""
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi
else
    log_info "OK: Sensor is fully seeded"
fi
log_info ""

# Step 2: Upgrade if requested
if [ "$UPGRADE" = true ]; then
    log_info "[Step 2/7] Checking for updates..."

    SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" << 'EOF'
echo "Listing available updates..."
sudo corelightctl sensor updates list

if sudo corelightctl sensor updates list 2>/dev/null | grep -q "No updates available"; then
    echo "No updates available"
else
    echo "Updates available. Applying..."
    sudo corelightctl sensor updates apply

    echo "Waiting for update to complete (this may take 15-30 minutes)..."
    while true; do
        status=$(sudo corelightctl sensor updates status 2>/dev/null || echo "unknown")
        echo "[$(date +%H:%M:%S)] Update status: $status"

        if echo "$status" | grep -qi "complete\|idle\|not updating"; then
            echo "Update complete"
            break
        fi

        sleep 30
    done
fi
EOF
    log_info "OK: Updates applied"
else
    log_info "[Step 2/7] Skipping updates (use --upgrade to enable)"
fi
log_info ""

# Step 3: Configure admin password
log_info "[Step 3/7] Configuring admin password..."
SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" << EOF
sudo /opt/broala/bin/broala-config set security.user.admin.password='$ADMIN_PASSWORD'
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config 2>&1 | grep -E "(ok=|changed=|failed=)" || true
EOF
log_info "OK: Admin password configured"
log_info ""

# Step 4: Disable PCAP replay mode
log_info "[Step 4/7] Disabling PCAP replay mode..."
SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" << 'EOF'
sudo /opt/broala/bin/broala-config set bro.pcap_replay_mode=0
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config 2>&1 | grep -E "(ok=|changed=|failed=)" || true
EOF
log_info "OK: PCAP replay mode disabled"
log_info ""

# Step 5: Verify Suricata is enabled
log_info "[Step 5/7] Verifying Suricata is enabled..."
suricata_status=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" \
    "sudo /opt/broala/bin/broala-config get suricata.enable 2>/dev/null" 2>/dev/null || echo "0")

if [ "$suricata_status" = "1" ]; then
    log_info "OK: Suricata is enabled"
else
    log_warning "Suricata may not be enabled. Check feature enablement with: ./sensor_lifecycle.sh enable-features"
fi
log_info ""

# Step 6: Verify SmartPCAP is enabled
log_info "[Step 6/7] Verifying SmartPCAP is enabled..."
smartpcap_status=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" \
    "sudo /opt/broala/bin/broala-config get smartpcap.enable 2>/dev/null" 2>/dev/null || echo "0")

if [ "$smartpcap_status" = "1" ]; then
    log_info "OK: SmartPCAP is enabled"
else
    log_warning "SmartPCAP may not be enabled. Check feature enablement with: ./sensor_lifecycle.sh enable-features"
fi
log_info ""

# Step 7: Add to fleet manager
log_info "[Step 7/7] Adding sensor to fleet manager ($FLEET_IP:$FLEET_PORT)..."
SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" << EOF
sudo /opt/broala/bin/broala-config set fleet.community_string=broala
sudo /opt/broala/bin/broala-config set fleet.server=$FLEET_IP:$FLEET_PORT
sudo /opt/broala/bin/broala-config set fleet.enable=1
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config 2>&1 | grep -E "(ok=|changed=|failed=)" || true
echo ""
echo "Restarting fleet daemon to establish connection..."
sudo sv restart corelight-fleetd
sleep 5
EOF

log_info "OK: Sensor added to fleet manager"
log_info ""

# Verify configuration
log_info "=== Verifying Configuration ==="
log_info ""

SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" << 'EOF'
echo "Fleet status:"
sudo /opt/broala/bin/broala-config get fleet.enable 2>/dev/null || echo "  Unable to verify"

echo ""
echo "Suricata status:"
sudo /opt/broala/bin/broala-config get suricata.enable 2>/dev/null || echo "  Unable to verify"

echo ""
echo "SmartPCAP status:"
sudo /opt/broala/bin/broala-config get smartpcap.enable 2>/dev/null || echo "  Unable to verify"

echo ""
echo "PCAP replay mode:"
sudo /opt/broala/bin/broala-config get bro.pcap_replay_mode 2>/dev/null || echo "  Unable to verify"

echo ""
echo "Sensor version:"
sudo corelightctl sensor status 2>/dev/null | grep -i version || echo "  Unable to verify"
EOF

log_info ""
log_info "=== Preparation Complete ==="
log_info ""
log_info "Sensor is ready for P1 automation testing"
log_info ""
log_info "Next steps:"
log_info "  1. Verify sensor appears in fleet manager at https://$FLEET_IP"
log_info "  2. Configure pipeline in GitLab api_automation project"
log_info "  3. Update TEST_MARKER variable with sensor IP: $SENSOR_IP"
log_info ""
log_info "Admin credentials:"
log_info "  Username: admin"
log_info "  Password: $ADMIN_PASSWORD"
log_info ""
log_info "For more details, see: docs/P1_AUTOMATION_PREP.md"

exit 0
