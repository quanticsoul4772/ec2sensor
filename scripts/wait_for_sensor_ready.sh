#!/bin/bash
# Location: scripts/wait_for_sensor_ready.sh
# Purpose: Wait for sensor to be fully initialized and ready for configuration
# Checks: API status=running → SSH available → Core services up → Ready for config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/ec2sensor_logging.sh"
source "$SCRIPT_DIR/load_env.sh"

usage() {
    cat <<EOF
Usage: $0 <sensor_ip> [--max-wait SECONDS]

Wait for sensor to be fully ready for configuration.

Arguments:
  sensor_ip         IP address of the sensor

Options:
  --max-wait SECONDS    Maximum time to wait (default: 5400 = 90 min)
  --verbose             Show detailed progress including system.seeded value

Readiness Checks:
  1. API reports sensor_status=running
  2. SSH port (22) is accessible
  3. Core services are operational
  4. Sensor can accept configuration changes

Example:
  $0 10.50.88.199
  $0 10.50.88.199 --max-wait 600
EOF
    exit 1
}

# Parse arguments
SENSOR_IP=""
MAX_WAIT=5400  # 90 minutes to account for seeding (can take 60+ min) + reboot
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --max-wait)
            MAX_WAIT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$SENSOR_IP" ]; then
                SENSOR_IP="$1"
            else
                echo "Unknown option: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [ -z "$SENSOR_IP" ]; then
    echo "Error: sensor_ip required"
    usage
fi

log_init
log_info "=== Waiting for Sensor Ready: $SENSOR_IP ==="

START_TIME=$(date +%s)

check_ssh_available() {
    local ip="$1"
    if nc -z -w 5 "$ip" 22 2>/dev/null; then
        return 0
    fi
    return 1
}

check_sensor_services() {
    local ip="$1"

    # Try to SSH and check basic readiness
    if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
        if sshpass -p "${SSH_PASSWORD}" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USERNAME}@${ip}" "echo 'SSH OK'" &>/dev/null; then
            return 0
        fi
    else
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "${SSH_USERNAME}@${ip}" "echo 'SSH OK'" &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

check_config_ready() {
    local ip="$1"
    local show_status="$2"  # Whether to show status on this check

    # Check if broala-config is responsive AND system is seeded
    local seeded
    if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
        seeded=$(sshpass -p "${SSH_PASSWORD}" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USERNAME}@${ip}" "sudo /opt/broala/bin/broala-config get system.seeded 2>/dev/null" 2>/dev/null || echo "error")
    else
        seeded=$(ssh -o ConnectTimeout=10 "${SSH_USERNAME}@${ip}" "sudo /opt/broala/bin/broala-config get system.seeded 2>/dev/null" 2>/dev/null || echo "error")
    fi

    # Always show status when requested or in verbose mode
    if [ "$show_status" = "true" ] || [ "$VERBOSE" = "true" ]; then
        if [ "$seeded" = "1" ]; then
            log_info "  ✓ system.seeded = 1 (READY)"
        elif [ "$seeded" = "0" ]; then
            log_info "  ⏳ system.seeded = 0 (seeding in progress...)"
        else
            log_info "  ⚠ system.seeded = $seeded (error or not available)"
        fi
    fi

    if [ "$seeded" = "1" ]; then
        return 0
    fi
    return 1
}

# Phase 1: Wait for SSH port to open
log_info "[Phase 1/3] Waiting for SSH port to be accessible..."
PHASE1_START=$(date +%s)
CHECK_COUNT=0
while true; do
    if check_ssh_available "$SENSOR_IP"; then
        PHASE1_DURATION=$(($(date +%s) - PHASE1_START))
        log_info "[Phase 1/3] SSH port accessible after ${PHASE1_DURATION}s"
        break
    fi

    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -gt $MAX_WAIT ]; then
        log_error "Timeout: SSH port never became accessible after ${ELAPSED}s"
        exit 1
    fi

    CHECK_COUNT=$((CHECK_COUNT + 1))
    if [ $((CHECK_COUNT % 3)) -eq 0 ]; then
        log_info "  [${ELAPSED}s] Still waiting for SSH port..."
    fi
    sleep 10
done

# Phase 2: Wait for SSH service to accept connections
log_info "[Phase 2/3] Waiting for SSH service to be fully operational..."
PHASE2_START=$(date +%s)
CHECK_COUNT=0
while true; do
    if check_sensor_services "$SENSOR_IP"; then
        PHASE2_DURATION=$(($(date +%s) - PHASE2_START))
        log_info "[Phase 2/3] SSH service ready after ${PHASE2_DURATION}s"
        break
    fi

    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -gt $MAX_WAIT ]; then
        log_error "Timeout: SSH service never became operational after ${ELAPSED}s"
        exit 1
    fi

    CHECK_COUNT=$((CHECK_COUNT + 1))
    if [ $((CHECK_COUNT % 3)) -eq 0 ]; then
        log_info "  [${ELAPSED}s] Still waiting for SSH service..."
    fi
    sleep 10
done

# Phase 3: Wait for sensor to be fully seeded
log_info "[Phase 3/3] Waiting for sensor to complete seeding (system.seeded=1)..."
log_info "This can take 60+ minutes for initial seeding..."
log_info "Checking every 15 seconds..."
PHASE3_START=$(date +%s)
CHECK_COUNT=0
while true; do
    ELAPSED=$(($(date +%s) - START_TIME))

    # Determine if we should show status on this check
    SHOW_STATUS="false"
    if [ $ELAPSED -lt 300 ]; then
        # First 5 minutes: show every 30 seconds (every 2 checks)
        if [ $((CHECK_COUNT % 2)) -eq 0 ]; then
            SHOW_STATUS="true"
        fi
    else
        # After 5 minutes: show every 60 seconds (every 4 checks)
        if [ $((CHECK_COUNT % 4)) -eq 0 ]; then
            SHOW_STATUS="true"
        fi
    fi

    # Show progress message before check
    if [ "$SHOW_STATUS" = "true" ]; then
        log_info "  [${ELAPSED}s] Checking seeding status..."
    fi

    # Check seeding status
    if check_config_ready "$SENSOR_IP" "$SHOW_STATUS"; then
        PHASE3_DURATION=$(($(date +%s) - PHASE3_START))
        log_info "[Phase 3/3] ✓ Configuration system ready after ${PHASE3_DURATION}s"
        break
    fi

    if [ $ELAPSED -gt $MAX_WAIT ]; then
        log_error "Timeout: Configuration system never became ready after ${ELAPSED}s"
        log_error "Sensor seeding did not complete within ${MAX_WAIT}s (90 minutes)"
        log_error "Check sensor logs: ssh ${SSH_USERNAME}@${SENSOR_IP} 'sudo corelightctl sensor logs'"
        exit 1
    fi

    CHECK_COUNT=$((CHECK_COUNT + 1))
    sleep 15
done

TOTAL_DURATION=$(($(date +%s) - START_TIME))
log_info "=== Sensor Ready: $SENSOR_IP ==="
log_info "Total wait time: ${TOTAL_DURATION}s"
log_info "  Phase 1 (SSH port):      ${PHASE1_DURATION}s"
log_info "  Phase 2 (SSH service):   ${PHASE2_DURATION}s"
log_info "  Phase 3 (Config ready):  ${PHASE3_DURATION}s"
log_info ""
log_info "Sensor is now ready for feature enablement"
