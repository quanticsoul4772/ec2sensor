#!/bin/bash
# Send tcpreplay traffic from one sensor to another
# Usage: ./send_tcpreplay_traffic.sh <source_ip> <target_ip> [mbps] [pcap_file]

set -euo pipefail

# Change to script directory
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# Source logging and environment
source "$PROJECT_ROOT/ec2sensor_logging.sh"
source "$PROJECT_ROOT/scripts/load_env.sh"

log_init "send_tcpreplay_traffic"

# Parse arguments
SOURCE_IP="${1:-}"
TARGET_IP="${2:-}"
MBPS="${3:-100}"
PCAP_FILE="${4:-}"

if [ -z "$SOURCE_IP" ] || [ -z "$TARGET_IP" ]; then
    log_error "Usage: $0 <source_ip> <target_ip> [mbps] [pcap_file]"
    log_error "Example: $0 10.50.88.80 10.50.88.156 100"
    exit 2
fi

log_info "Starting tcpreplay traffic generation"
log_info "Source sensor: $SOURCE_IP"
log_info "Target sensor: $TARGET_IP"
log_info "Speed: ${MBPS} Mbps"

# SSH credentials
SSH_USERNAME="${SSH_USERNAME:-broala}"
SSH_PASSWORD="${SSH_PASSWORD:-This#ahNg9Pi}"

# Remote paths
REMOTE_PCAP_DIR="/tmp/pcaps"
REMOTE_PCAP_FILE="$REMOTE_PCAP_DIR/traffic.pcap"

# Step 1: Prepare PCAP file
if [ -z "$PCAP_FILE" ]; then
    log_info "No PCAP file specified, will download sample PCAP"
    PCAP_FILE="$PROJECT_ROOT/pcaps/sample_traffic.pcap"

    # Create local pcaps directory
    mkdir -p "$PROJECT_ROOT/pcaps"

    if [ ! -f "$PCAP_FILE" ]; then
        log_info "Downloading sample PCAP file..."
        # Download a small sample PCAP (this is a public sample from tcpreplay)
        curl -s -L "https://s3.amazonaws.com/tcpreplay-pcap-files/smallFlows.pcap" \
            -o "$PCAP_FILE" || {
            log_error "Failed to download sample PCAP"
            exit 1
        }
        log_info "Downloaded sample PCAP: $(ls -lh "$PCAP_FILE" | awk '{print $5}')"
    else
        log_info "Using existing PCAP: $PCAP_FILE"
    fi
elif [ ! -f "$PCAP_FILE" ]; then
    log_error "Specified PCAP file not found: $PCAP_FILE"
    exit 1
fi

# Step 2: Check if sensor services are running
log_info "Checking sensor status on $SOURCE_IP..."
sensor_status=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SOURCE_IP" \
    "sudo corelightctl sensor status 2>/dev/null | grep -o 'Status:.*' | awk '{print \$2}' || echo 'unknown'" 2>/dev/null)

log_info "Current sensor status: $sensor_status"

if [ "$sensor_status" = "running" ]; then
    log_warning "Sensor services are running. They must be stopped to use eth1 for traffic generation."
    log_info "Stopping sensor services..."

    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
        "$SSH_USERNAME@$SOURCE_IP" \
        "sudo corelightctl sensor stop" 2>/dev/null || {
        log_error "Failed to stop sensor services"
        exit 1
    }

    log_info "Waiting for services to stop..."
    sleep 5

    # Verify stopped
    sensor_status=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
        "$SSH_USERNAME@$SOURCE_IP" \
        "sudo corelightctl sensor status 2>/dev/null | grep -o 'Status:.*' | awk '{print \$2}' || echo 'stopped'" 2>/dev/null)

    log_info "Sensor status after stop: $sensor_status"
fi

# Step 3: Create remote directory and upload PCAP
log_info "Creating remote PCAP directory..."
sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SOURCE_IP" \
    "mkdir -p $REMOTE_PCAP_DIR" 2>/dev/null || {
    log_error "Failed to create remote directory"
    exit 1
}

log_info "Uploading PCAP file to $SOURCE_IP..."
sshpass -p "$SSH_PASSWORD" scp -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$PCAP_FILE" "$SSH_USERNAME@$SOURCE_IP:$REMOTE_PCAP_FILE" 2>/dev/null || {
    log_error "Failed to upload PCAP file"
    exit 1
}

log_info "PCAP file uploaded successfully"

# Step 4: Configure eth1 interface with an IP (required for routing)
log_info "Configuring eth1 interface..."
sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SOURCE_IP" \
    "sudo ip addr add 10.50.88.81/26 dev eth1 2>/dev/null || true && \
     sudo ip link set eth1 up" 2>/dev/null || {
    log_warning "Failed to configure eth1, may already be configured"
}

# Step 5: Get interface info
log_info "Checking network interfaces..."
interfaces=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SOURCE_IP" \
    "ip addr show | grep -E '^[0-9]+: (eth|ens)' | cut -d: -f2 | tr -d ' '" 2>/dev/null)

log_info "Available interfaces:"
echo "$interfaces" | while read -r iface; do
    log_info "  - $iface"
done

# Step 6: Display traffic generation info
log_info "Traffic generation configuration:"
log_info "  Source interface: eth1 on $SOURCE_IP"
log_info "  Speed: ${MBPS} Mbps"
log_info "  Mode: Continuous loop"
log_info "  PCAP file: $REMOTE_PCAP_FILE"
echo ""
log_info "Note: Traffic will be replayed on eth1. Target sensor $TARGET_IP"
log_info "should be configured to capture traffic on its monitoring interface."
echo ""
log_info "Starting tcpreplay traffic generation..."
log_info "Press Ctrl+C to stop"
echo ""

# Run tcpreplay with statistics
# --loop=0 means infinite loop
# --stats=1 prints stats every 1 second
sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SOURCE_IP" \
    "sudo tcpreplay --intf1=eth1 --mbps=${MBPS} --loop=0 --stats=1 $REMOTE_PCAP_FILE" 2>&1 | \
    while IFS= read -r line; do
        echo "$line"
        log_info "$line"
    done

# Cleanup happens on interrupt
trap cleanup INT TERM

cleanup() {
    log_info "Stopping traffic generation..."
    log_info "Note: Sensor services are still stopped. To restart:"
    log_info "  ssh $SSH_USERNAME@$SOURCE_IP"
    log_info "  sudo corelightctl sensor start"
    exit 0
}

log_info "Traffic generation completed"
