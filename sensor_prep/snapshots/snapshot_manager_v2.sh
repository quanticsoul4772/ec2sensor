#!/bin/bash
#
# Snapshot Management Tool v2
# Multi-API support for both legacy (broala-snapshot) and modern (corelightctl) sensors
# Simplifies sensor snapshot and configuration backup operations
#
# Usage: ./snapshot_manager_v2.sh [command] [options]
#

set -euo pipefail

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# Source logging
if [ -f "${PROJECT_ROOT}/ec2sensor_logging.sh" ]; then
    export SENSOR_NAME="${SENSOR_NAME:-unknown}"
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
SENSOR_API=""
AUTO_YES=false

# Show usage
show_usage() {
    cat << EOF
Snapshot Management Tool v2 (Multi-API Support)

Usage: $0 <command> [options]

Commands:
  list                 List all snapshots/backups
  create <name>        Create a new snapshot/backup
  delete <name>        Delete a snapshot/backup
  restore <name>       Restore a snapshot/backup
  exists <name>        Check if snapshot/backup exists
  info <name>          Show snapshot/backup information

Options:
  --sensor <ip>        Sensor IP address (default: from .env)
  --user <username>    SSH username (default: broala)
  --yes, -y            Skip confirmation prompts
  --help               Show this help message

API Detection:
  This script automatically detects whether the sensor uses:
  - Legacy API: broala-snapshot (full system snapshots with reboot)
  - Modern API: corelightctl (configuration backups, no reboot)

Examples:
  # List all snapshots/backups
  $0 list

  # Create a backup
  $0 create baseline-$(date +%Y%m%d)

  # Restore from backup
  $0 restore baseline-20251010

  # Check if backup exists
  $0 exists baseline-20251010

Notes:
  - Legacy sensors: Uses broala-snapshot (requires reboot for restore)
  - Modern sensors: Exports/imports configuration (fast, no reboot)
  - Backups stored in: ${BACKUP_DIR}

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
if [[ "$COMMAND" =~ ^(create|delete|restore|exists|info)$ ]] && [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
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
        --yes|-y)
            AUTO_YES=true
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

# Get sensor IP if not provided
if [ -z "$SENSOR_IP" ]; then
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        set +u
        source "${PROJECT_ROOT}/.env"
        set -u
        SENSOR_IP="${SSH_HOST:-}"
    fi
fi

if [ -z "$SENSOR_IP" ]; then
    log_error "Sensor IP not provided and SSH_HOST not set in .env"
    log_info "Please specify --sensor <ip> or ensure SSH_HOST is set in .env"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Determine SSH command
SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Load SSH_PASSWORD from .env if available
if [ -z "${SSH_PASSWORD:-}" ] && [ -f "${PROJECT_ROOT}/.env" ]; then
    set +u
    source "${PROJECT_ROOT}/.env"
    set -u
fi

# Try password first if available (most reliable for test sensors)
if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    SSH_CMD="sshpass -e ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    SCP_CMD="sshpass -e scp $SSH_OPTS"
    export SSHPASS="${SSH_PASSWORD}"
elif [ -f "$SSH_KEY_PATH" ]; then
    SSH_CMD="ssh -i $SSH_KEY_PATH $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    SCP_CMD="scp -i $SSH_KEY_PATH $SSH_OPTS"
else
    SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SENSOR_IP}"
    SCP_CMD="scp $SSH_OPTS"
fi

# Detect sensor API
log_info "Detecting sensor API..."
if $SSH_CMD "which corelightctl" >/dev/null 2>&1; then
    SENSOR_API="modern"
    log_info "✓ Detected modern API (corelightctl) - configuration backups"
elif $SSH_CMD "which broala-snapshot" >/dev/null 2>&1; then
    SENSOR_API="legacy"
    log_info "✓ Detected legacy API (broala-snapshot) - full snapshots"
else
    log_error "Could not detect sensor snapshot/backup capability"
    log_error "Neither corelightctl nor broala-snapshot found"
    exit 1
fi

# Execute command based on API
case "$COMMAND" in
    list)
        log_info "Listing snapshots/backups..."

        if [ "$SENSOR_API" = "modern" ]; then
            # List local backup files
            if [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
                log_info "Configuration backups (stored locally):"
                echo ""
                ls -lh "$BACKUP_DIR"/*.yaml 2>/dev/null | awk '{
                    size=$5
                    date=$6" "$7" "$8
                    file=$9
                    gsub(/.*\//, "", file)
                    gsub(/.yaml$/, "", file)
                    printf "  %-40s %8s  %s\n", file, size, date
                }' || log_info "  (no backups found)"
            else
                log_info "  (no configuration backups found)"
                log_info "  Backups are stored in: $BACKUP_DIR"
            fi
        else
            # List sensor-side snapshots
            $SSH_CMD "sudo broala-snapshot -l"
        fi
        ;;

    create)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for create command"
            show_usage
            exit 1
        fi

        if [ "$SENSOR_API" = "modern" ]; then
            log_info "Creating configuration backup: $SNAPSHOT_NAME"

            # Export configuration from sensor
            BACKUP_FILE="${BACKUP_DIR}/${SNAPSHOT_NAME}.yaml"

            if $SSH_CMD "sudo corelightctl sensor configuration get -o yaml" > "$BACKUP_FILE"; then
                BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
                log_info "✅ Configuration backup created successfully"
                log_info "   Name: $SNAPSHOT_NAME"
                log_info "   Location: $BACKUP_FILE"
                log_info "   Size: $BACKUP_SIZE"
                log_info ""
                log_info "To restore: $0 restore $SNAPSHOT_NAME"
            else
                log_error "❌ Configuration backup failed"
                rm -f "$BACKUP_FILE"
                exit 1
            fi
        else
            log_info "Creating snapshot: $SNAPSHOT_NAME"

            if $SSH_CMD "sudo broala-snapshot -c $SNAPSHOT_NAME"; then
                log_info "✅ Snapshot created successfully"
            else
                log_error "❌ Snapshot creation failed"
                exit 1
            fi
        fi
        ;;

    delete)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for delete command"
            show_usage
            exit 1
        fi

        if [ "$SENSOR_API" = "modern" ]; then
            BACKUP_FILE="${BACKUP_DIR}/${SNAPSHOT_NAME}.yaml"

            if [ ! -f "$BACKUP_FILE" ]; then
                log_error "Backup not found: $SNAPSHOT_NAME"
                log_info "Available backups:"
                ls -1 "$BACKUP_DIR"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//' | sed 's/^/  - /' || echo "  (none)"
                exit 1
            fi

            log_warning "Deleting backup: $SNAPSHOT_NAME"
            read -p "Are you sure? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deletion cancelled"
                exit 0
            fi

            if rm "$BACKUP_FILE"; then
                log_info "✅ Backup deleted: $SNAPSHOT_NAME"
            else
                log_error "❌ Backup deletion failed"
                exit 1
            fi
        else
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
        fi
        ;;

    restore)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for restore command"
            show_usage
            exit 1
        fi

        if [ "$SENSOR_API" = "modern" ]; then
            BACKUP_FILE="${BACKUP_DIR}/${SNAPSHOT_NAME}.yaml"

            if [ ! -f "$BACKUP_FILE" ]; then
                log_error "Backup not found: $SNAPSHOT_NAME"
                log_info "Available backups:"
                ls -1 "$BACKUP_DIR"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//' | sed 's/^/  - /' || echo "  (none)"
                exit 1
            fi

            log_warning "WARNING: Restoring configuration from: $SNAPSHOT_NAME"
            log_warning "This will:"
            log_warning "  - Apply configuration from backup"
            log_warning "  - Restart affected sensor services"
            log_warning "  - OVERWRITE current configuration"
            echo ""

            if [ "$AUTO_YES" = false ]; then
                read -p "Are you sure? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Restore cancelled"
                    exit 0
                fi
            else
                log_info "Auto-confirming restore (--yes flag)"
            fi

            log_info "Copying configuration to sensor..."
            if $SCP_CMD "$BACKUP_FILE" "${SSH_USER}@${SENSOR_IP}:/tmp/restore_config.yaml"; then
                log_info "Applying configuration..."
                if $SSH_CMD "sudo corelightctl sensor configuration put -f /tmp/restore_config.yaml"; then
                    log_info "✅ Configuration restored successfully"
                    log_info "Sensor services are restarting..."
                    log_info "Wait 30-60 seconds for services to stabilize"

                    # Cleanup
                    $SSH_CMD "sudo rm -f /tmp/restore_config.yaml" || true
                else
                    log_error "❌ Configuration restore failed"
                    $SSH_CMD "sudo rm -f /tmp/restore_config.yaml" || true
                    exit 1
                fi
            else
                log_error "❌ Failed to copy configuration to sensor"
                exit 1
            fi
        else
            log_warning "WARNING: Reverting to snapshot: $SNAPSHOT_NAME"
            log_warning "This will:"
            log_warning "  - Restore sensor to the snapshot state"
            log_warning "  - LOSE all changes made after snapshot"
            log_warning "  - REBOOT the sensor"
            echo ""
            read -p "Are you absolutely sure? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Restore cancelled"
                exit 0
            fi

            log_info "Reverting to snapshot..."
            if $SSH_CMD "sudo broala-snapshot -R $SNAPSHOT_NAME && sudo reboot"; then
                log_info "✅ Snapshot restore initiated"
                log_info "Sensor is rebooting..."
                log_info "Wait 2-3 minutes before reconnecting"
            else
                log_error "❌ Snapshot restore failed"
                exit 1
            fi
        fi
        ;;

    exists)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for exists command"
            show_usage
            exit 1
        fi

        if [ "$SENSOR_API" = "modern" ]; then
            BACKUP_FILE="${BACKUP_DIR}/${SNAPSHOT_NAME}.yaml"

            if [ -f "$BACKUP_FILE" ]; then
                log_info "✅ Backup exists: $SNAPSHOT_NAME"
                log_info "   Location: $BACKUP_FILE"
                log_info "   Size: $(du -h "$BACKUP_FILE" | cut -f1)"
                exit 0
            else
                log_info "❌ Backup does not exist: $SNAPSHOT_NAME"
                exit 1
            fi
        else
            if $SSH_CMD "sudo broala-snapshot -e $SNAPSHOT_NAME" >/dev/null 2>&1; then
                log_info "✅ Snapshot exists: $SNAPSHOT_NAME"
                exit 0
            else
                log_info "❌ Snapshot does not exist: $SNAPSHOT_NAME"
                exit 1
            fi
        fi
        ;;

    info)
        if [ -z "$SNAPSHOT_NAME" ]; then
            log_error "Snapshot name required for info command"
            show_usage
            exit 1
        fi

        if [ "$SENSOR_API" = "modern" ]; then
            BACKUP_FILE="${BACKUP_DIR}/${SNAPSHOT_NAME}.yaml"

            if [ -f "$BACKUP_FILE" ]; then
                log_info "Backup information: $SNAPSHOT_NAME"
                echo ""
                echo "  Location: $BACKUP_FILE"
                echo "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"
                echo "  Modified: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$BACKUP_FILE" 2>/dev/null || stat -c "%y" "$BACKUP_FILE" 2>/dev/null | cut -d. -f1)"
                echo ""
                echo "Configuration preview (first 20 lines):"
                head -n 20 "$BACKUP_FILE" | sed 's/^/  /'
            else
                log_error "Backup not found: $SNAPSHOT_NAME"
                exit 1
            fi
        else
            log_info "Snapshot information: $SNAPSHOT_NAME"
            if $SSH_CMD "sudo broala-snapshot -l" | grep -q "$SNAPSHOT_NAME"; then
                $SSH_CMD "sudo broala-snapshot -l" | grep "$SNAPSHOT_NAME"
            else
                log_error "Snapshot not found: $SNAPSHOT_NAME"
                exit 1
            fi
        fi
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

exit 0
