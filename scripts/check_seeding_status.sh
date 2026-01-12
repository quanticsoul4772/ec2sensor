#!/bin/bash
# Check sensor seeding status
# Usage: ./scripts/check_seeding_status.sh <sensor_ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/ec2sensor_logging.sh"
source "$SCRIPT_DIR/load_env.sh"

SENSOR_IP="${1:-}"

if [ -z "$SENSOR_IP" ]; then
    echo "Usage: $0 <sensor_ip>"
    exit 1
fi

log_init
log_info "Checking seeding status for $SENSOR_IP..."

SSH_USERNAME="${SSH_USERNAME:-broala}"
SSH_PASSWORD="${SSH_PASSWORD:-${SSH_PASSWORD}}"

echo ""
echo "=========================================="
echo "  Seeding Status Check"
echo "=========================================="
echo ""

# Check system.seeded
echo "Checking system.seeded..."
seeded=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" "sudo /opt/broala/bin/broala-config get system.seeded 2>/dev/null" 2>/dev/null || echo "error")
echo "  system.seeded = $seeded"

if [ "$seeded" = "1" ]; then
    echo "  ✓ Sensor is fully seeded"
else
    echo "  ⚠ Sensor is NOT fully seeded (value: $seeded)"
fi

echo ""
echo "Checking sensor status..."
status=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" "sudo corelightctl sensor status 2>/dev/null | grep -o 'Status:.*' | awk '{print \$2}' || echo 'unknown'" 2>/dev/null)
echo "  Sensor status = $status"

echo ""
echo "Checking broker process..."
broker=$(sshpass -p "$SSH_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SENSOR_IP" "pgrep -f zeek || echo 'not running'" 2>/dev/null)
if [ "$broker" = "not running" ]; then
    echo "  ⚠ Zeek/Broker not running"
else
    echo "  ✓ Zeek/Broker running (PID: $broker)"
fi

echo ""
echo "=========================================="
echo ""

if [ "$seeded" = "1" ]; then
    echo "Sensor is ready for configuration"
    exit 0
else
    echo "Sensor is still seeding - not ready yet"
    echo ""
    echo "To monitor seeding progress:"
    echo "  ssh $SSH_USERNAME@$SENSOR_IP"
    echo "  sudo corelightctl sensor logs | grep -i seed"
    exit 1
fi
