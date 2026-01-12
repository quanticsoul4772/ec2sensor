#!/bin/bash
#
# Sensor Version Detection
# Detects which configuration API to use (broala-config vs corelightctl)
#
# Usage: source ./detect_sensor_version.sh <sensor_ip> <ssh_user>
#        Then use: $SENSOR_CONFIG_API (either "broala" or "corelightctl")
#

set -euo pipefail

SENSOR_IP="${1:-}"
SSH_USER="${2:-broala}"

if [ -z "$SENSOR_IP" ]; then
    echo "[ERROR] Sensor IP required" >&2
    exit 1
fi

# Determine SSH command (same logic as other scripts)
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

# Detect which configuration API is available
if $SSH_CMD "which corelightctl" >/dev/null 2>&1; then
    export SENSOR_CONFIG_API="corelightctl"
    export SENSOR_VERSION="modern"
elif $SSH_CMD "which broala-config" >/dev/null 2>&1; then
    export SENSOR_CONFIG_API="broala"
    export SENSOR_VERSION="legacy"
else
    echo "[ERROR] Could not detect sensor configuration API" >&2
    exit 1
fi

# Export the SSH command for reuse
export SENSOR_SSH_CMD="$SSH_CMD"
export SENSOR_IP
export SSH_USER

# Helper functions for configuration management
sensor_config_get() {
    local key="$1"
    if [ "$SENSOR_CONFIG_API" = "corelightctl" ]; then
        $SENSOR_SSH_CMD "sudo corelightctl sensor configuration get -o yaml | grep '^${key}:' | cut -d: -f2- | xargs"
    else
        $SENSOR_SSH_CMD "sudo broala-config get $key"
    fi
}

sensor_config_set() {
    local key="$1"
    local value="$2"

    if [ "$SENSOR_CONFIG_API" = "corelightctl" ]; then
        # For corelightctl, we need to get the current config, modify it, and put it back
        local temp_config="/tmp/sensor_config_$$.yaml"
        $SENSOR_SSH_CMD "sudo corelightctl sensor configuration get -o yaml > /tmp/config.yaml"
        $SENSOR_SSH_CMD "sudo sed -i 's/^${key}:.*/${key}: \"${value}\"/' /tmp/config.yaml"
        $SENSOR_SSH_CMD "sudo corelightctl sensor configuration put -f /tmp/config.yaml"
        $SENSOR_SSH_CMD "sudo rm -f /tmp/config.yaml"
    else
        $SENSOR_SSH_CMD "sudo broala-config set ${key}=${value}"
    fi
}

sensor_config_apply() {
    if [ "$SENSOR_CONFIG_API" = "corelightctl" ]; then
        # corelightctl applies config immediately with put
        echo "Configuration applied (corelightctl auto-applies)"
    else
        $SENSOR_SSH_CMD "sudo broala-apply-config -q"
    fi
}

# Export functions for use in calling scripts
export -f sensor_config_get sensor_config_set sensor_config_apply
