#!/bin/bash
#
# Snapshot Management Tool
# Simplifies sensor snapshot operations
#
# Usage: ./snapshot_manager.sh [command] [options]
#

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source logging
if [ -f "${PROJECT_ROOT}/ec2sensor_logging.sh" ]; then
    source "${PROJECT_ROOT}/ec2sensor_logging.sh"
    log_init
else
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARN] $1"; }
fi

# Default values
SENSOR_IP=""
SSH_USER="broala"
COMMAND=""
SNAPSHOT_NAME=""

# Show usage
show_usage() {
    cat << EOF
Snapshot Management Tool

Usage: $0 <command> [options]

Commands:
  list                 List all snapshots
  create <name>        Create a new snapshot
  delete <name>        Delete a snapshot
  revert <name>        Revert to a snapshot (requires reboot)
  exists <name>        Check if snapshot exists
  info <name>          Show snapshot information

Options:
  --sensor <ip>        Sensor IP address (default: from .env)
  --user <username>    SSH username (default: broala)
  --help               Show this help message

Examples:
  # List all snapshots
  $0 list

  # Create a snapshot
  $0 create before-test-$(date +%Y%m%d)

  # Revert to a snapshot
  $0 revert baseline-20251010

  # Check if snapshot exists
  $0 exists baseline-20251010

EOF
}

# Parse arguments
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

COMMAND="$1"
shift

# Parse snapshot name if provided
if [[ "$COMMAND" =~ ^(create|delete|revert|exists|info)$ ]] && [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
    SNAPSHOT_NAME="$1"
    shift
fi

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --sensor)
            SENSOR_IP="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
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

# Determine SSH command
SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

if [ -f "$SSH_KEY_PATH" ]; then
    SSH_CMD="ssh -i $SSH_KEY_PATH $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
elif [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    SSH_CMD="sshpass -e ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    export SSHPASS="${SSH_PASSWORD}"
else
    SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
fi

# Execute command
case "$COMMAND" in
    list)
        log_info "Listing snapshots on $SENSOR_IP..."
        $SSH_CMD "sudo broala-snapshot -l"
        ;;

    create)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for create command"
            show_usage
            exit 1
        fi

        log_info "Creating snapshot: $SNAPSHOT_NAME"
        if $SSH_CMD "sudo broala-snapshot -c $SNAPSHOT_NAME"; then
            log_info "✅ Snapshot created successfully"
        else
            log_error "❌ Snapshot creation failed"
            exit 1
        fi
        ;;

    delete)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for delete command"
            show_usage
            exit 1
        fi

        log_warning "Deleting snapshot: $SNAPSHOT_NAME"
        read -p "Are you sure? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deletion cancelled"
            exit 0
        fi

        if $SSH_CMD "sudo broala-snapshot -r $SNAPSHOT_NAME"; then
            log_info "✅ Snapshot deleted"
        else
            log_error "❌ Snapshot deletion failed"
            exit 1
        fi
        ;;

    revert)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for revert command"
            show_usage
            exit 1
        fi

        log_warning "WARNING: Reverting to snapshot: $SNAPSHOT_NAME"
        log_warning "This will:"
        log_warning "  - Restore sensor to the snapshot state"
        log_warning "  - LOSE all changes made after snapshot"
        log_warning "  - REBOOT the sensor"
        echo ""
        read -p "Are you absolutely sure? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Revert cancelled"
            exit 0
        fi

        log_info "Reverting to snapshot..."
        if $SSH_CMD "sudo broala-snapshot -R $SNAPSHOT_NAME && sudo reboot"; then
            log_info "✅ Snapshot revert initiated"
            log_info "Sensor is rebooting..."
            log_info "Wait 2-3 minutes before reconnecting"
        else
            log_error "❌ Snapshot revert failed"
            exit 1
        fi
        ;;

    exists)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for exists command"
            show_usage
            exit 1
        fi

        if $SSH_CMD "sudo broala-snapshot -e $SNAPSHOT_NAME" >/dev/null 2>&1; then
            log_info "✅ Snapshot exists: $SNAPSHOT_NAME"
            exit 0
        else
            log_info "❌ Snapshot does not exist: $SNAPSHOT_NAME"
            exit 1
        fi
        ;;

    info)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for info command"
            show_usage
            exit 1
        fi

        log_info "Snapshot information: $SNAPSHOT_NAME"
        if $SSH_CMD "sudo broala-snapshot -l" | grep -q "$SNAPSHOT_NAME"; then
            $SSH_CMD "sudo broala-snapshot -l" | grep "$SNAPSHOT_NAME"
        else
            log_error "Snapshot not found: $SNAPSHOT_NAME"
            exit 1
        fi
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

exit 0
