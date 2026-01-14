#!/bin/bash
# Location: scripts/enable_sensor_features.sh
# Purpose: Enable standard sensor features (HTTP, YARA, Suricata, SmartPCAP)

# Don't use set -e as we want to capture errors properly
set -uo pipefail

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
    echo "Error: sensor_ip required" >&2
    usage
fi

# Validate IP address format
if ! echo "$SENSOR_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Invalid IP address format: $SENSOR_IP" >&2
    exit 1
fi

log_init
log_info "=== Enabling Sensor Features: $SENSOR_IP ==="

# Test connectivity first
log_info "Testing connectivity to $SENSOR_IP..."
if ! nc -z -w 5 "$SENSOR_IP" 22 2>/dev/null; then
    echo "Error: Cannot reach $SENSOR_IP on port 22" >&2
    echo "  - Check if sensor is running" >&2
    echo "  - Check network connectivity" >&2
    echo "  - Check firewall rules" >&2
    exit 1
fi
log_info "Port 22 is reachable"

# Remote commands to run on the sensor
# Using a function-based approach to avoid heredoc escaping issues
REMOTE_COMMANDS='set +u
set -e
echo "Enabling sensor features and licenses..."
for cmd in \
    "sudo /opt/broala/bin/broala-config set http.access.enable=1" \
    "sudo /opt/broala/bin/broala-config set license.yara.enable=1" \
    "sudo /opt/broala/bin/broala-config set license.suricata.enable=1" \
    "sudo /opt/broala/bin/broala-config set license.smartpcap.enable=1" \
    "sudo /opt/broala/bin/broala-config set corelight.yara.enable=1" \
    "sudo /opt/broala/bin/broala-config set suricata.enable=1" \
    "sudo /opt/broala/bin/broala-config set smartpcap.enable=1" \
    "sudo /opt/broala/bin/broala-config set bro.pkgs.corelight.smartpcap.loaded=1" \
    "sudo /opt/broala/bin/broala-config set smartpcap.query.access_mode=deny" \
    "sudo /opt/broala/bin/broala-config set smartpcap.local_store.enable=1"; do
    echo "Running: $cmd"
    if ! eval "$cmd"; then
        echo "Failed: $cmd" >&2
        exit 1
    fi
done
echo "Applying configuration..."

# Get admin password for corelight-client authentication
ADMIN_PASSWORD=$(sudo grep "password:" /etc/corelight/corelightctl.yaml | awk "{print \$2}")
if [ -z "$ADMIN_PASSWORD" ]; then
    echo "Failed to read admin password from corelightctl.yaml" >&2
    exit 1
fi
echo "Got admin password for corelight-client authentication"

# Configure corelight-client with default sensor address (required for broala-apply-config)
# The Ansible playbook calls corelight-client internally and needs to know the sensor address
export CORELIGHT_DEVICE="192.0.2.1:30443"

# Create a wrapper for corelight-client that adds:
# 1. --ssl-no-verify-certificate (for self-signed certs)
# 2. -u admin -p <password> (for authentication)
# 3. Strips --dynamic_backfill which is not supported in some versions
# This is needed because broala-apply-config runs Ansible which calls corelight-client
# without these options, causing SSL and authentication failures
WRAPPER_DIR="/tmp/corelight-wrapper-$$"
mkdir -p "$WRAPPER_DIR"
cat > "$WRAPPER_DIR/corelight-client" << EOF
#!/bin/bash
# Wrapper to add SSL bypass, authentication, and filter unsupported args
ARGS=()
for arg in "\$@"; do
    # Skip --dynamic_backfill which is not supported in some versions
    if [[ "\$arg" != --dynamic_backfill* ]]; then
        ARGS+=("\$arg")
    fi
done
exec /usr/bin/corelight-client --ssl-no-verify-certificate -u admin -p $ADMIN_PASSWORD "\${ARGS[@]}"
EOF
chmod +x "$WRAPPER_DIR/corelight-client"
export PATH="$WRAPPER_DIR:$PATH"

echo "Using corelight-client wrapper for SSL bypass..."
if ! sudo -E LC_ALL=en_US.utf8 LANG=en_US.utf8 PATH="$PATH" /opt/broala/bin/broala-apply-config -q; then
    rm -rf "$WRAPPER_DIR" 2>/dev/null
    echo "Failed to apply configuration" >&2
    exit 1
fi

# Clean up wrapper
rm -rf "$WRAPPER_DIR" 2>/dev/null
echo "Features enabled successfully"'

# Connect and enable features
log_info "Connecting to sensor to enable features..."

SSH_USERNAME="${SSH_USERNAME:-broala}"
SSH_EXIT_CODE=0
SSH_OUTPUT=""

# Try SSH with sshpass if password is available
if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
    log_info "Using password authentication as $SSH_USERNAME"
    SSH_OUTPUT=$(SSHPASS="${SSH_PASSWORD}" sshpass -e ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        "${SSH_USERNAME}@${SENSOR_IP}" "$REMOTE_COMMANDS" 2>&1) || SSH_EXIT_CODE=$?
else
    log_info "Using SSH key authentication as $SSH_USERNAME"
    SSH_OUTPUT=$(ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "${SSH_USERNAME}@${SENSOR_IP}" "$REMOTE_COMMANDS" 2>&1) || SSH_EXIT_CODE=$?
fi

# Check result
if [ $SSH_EXIT_CODE -ne 0 ]; then
    echo "" >&2
    echo "Error: Failed to enable features (exit code: $SSH_EXIT_CODE)" >&2
    
    # Check for specific error types
    if echo "$SSH_OUTPUT" | grep -qi "permission denied"; then
        echo "  SSH authentication failed for user '$SSH_USERNAME'" >&2
        echo "  Check SSH_PASSWORD or SSH keys" >&2
    elif echo "$SSH_OUTPUT" | grep -qi "connection refused"; then
        echo "  SSH connection refused - is sshd running?" >&2
    elif echo "$SSH_OUTPUT" | grep -qi "connection timed out\|timed out"; then
        echo "  SSH connection timed out" >&2
    elif echo "$SSH_OUTPUT" | grep -qi "host key verification"; then
        echo "  SSH host key verification failed" >&2
    elif echo "$SSH_OUTPUT" | grep -qi "command not found\|no such file"; then
        echo "  Required command not found on sensor" >&2
    fi
    
    # Show the actual output for debugging
    if [ -n "$SSH_OUTPUT" ]; then
        echo "" >&2
        echo "  Command output:" >&2
        echo "$SSH_OUTPUT" | sed 's/^/    /' >&2
    fi
    
    exit $SSH_EXIT_CODE
fi

# Show output on success too if verbose
if [ "${EC2SENSOR_DEBUG:-false}" = "true" ]; then
    echo "$SSH_OUTPUT"
fi

log_info "=== Features Enabled Successfully ==="
log_info "Sensor $SENSOR_IP is ready for use"
log_info ""
log_info "Enabled features:"
log_info "  ✓ HTTP access"
log_info "  ✓ YARA engine"
log_info "  ✓ Suricata IDS"
log_info "  ✓ SmartPCAP"

exit 0
