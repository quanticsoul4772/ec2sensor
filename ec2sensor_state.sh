#!/bin/bash
# ec2sensor_state.sh - Session state and cache management
# Manages sensor data cache, operation history, and session metrics

# ============================================
# Session State Variables
# ============================================

SESSION_START_TIME=$(date +%s)
LAST_REFRESH_TIME=0
REFRESH_COUNT=0

# Cache directory for sensor data (bash 3.x compatible)
CACHE_DIR="${TMPDIR:-/tmp}/ec2sensor_cache_$$"
mkdir -p "$CACHE_DIR" 2>/dev/null

# Operation history
OPERATION_HISTORY=()
MAX_HISTORY=50

# Statistics
TOTAL_API_CALLS=0
TOTAL_API_TIME_MS=0

# Cache TTL (seconds) - increased from 30s for better performance
CACHE_TTL=60

# SSH ControlMaster settings for connection reuse
# Use short path to avoid Unix socket path length limit (104 chars on macOS)
SSH_CONTROL_DIR="/tmp/ec2ssh_$$"
SSH_CONTROL_PERSIST=120  # Keep connections alive for 2 minutes

# ============================================
# Session Management Functions
# ============================================

# Initialize session state
init_session_state() {
    SESSION_START_TIME=$(date +%s)
    LAST_REFRESH_TIME=0
    REFRESH_COUNT=0
    TOTAL_API_CALLS=0
    TOTAL_API_TIME_MS=0
    OPERATION_HISTORY=()
    
    # Create SSH control directory
    mkdir -p "$SSH_CONTROL_DIR" 2>/dev/null
}

# ============================================
# SSH ControlMaster Functions
# ============================================

# Get SSH options for ControlMaster (connection reuse)
# Usage: opts=$(get_ssh_control_opts)
# Note: Uses short path format to avoid Unix socket 104-char limit on macOS
get_ssh_control_opts() {
    echo "-o ControlMaster=auto -o ControlPath=$SSH_CONTROL_DIR/%C -o ControlPersist=$SSH_CONTROL_PERSIST"
}

# Close all SSH control connections
close_ssh_connections() {
    # Find and close all control sockets
    if [ -d "$SSH_CONTROL_DIR" ]; then
        for socket in "$SSH_CONTROL_DIR"/*; do
            [ -S "$socket" ] && ssh -O exit -o ControlPath="$socket" dummy 2>/dev/null
        done
        rm -rf "$SSH_CONTROL_DIR" 2>/dev/null
    fi
}

# Get session duration in seconds
get_session_duration() {
    echo $(($(date +%s) - SESSION_START_TIME))
}

# Get time since last refresh
get_refresh_age() {
    if [ "$LAST_REFRESH_TIME" -eq 0 ]; then
        echo 999999  # Never refreshed
    else
        echo $(($(date +%s) - LAST_REFRESH_TIME))
    fi
}

# Mark refresh occurred
mark_refresh() {
    LAST_REFRESH_TIME=$(date +%s)
    ((REFRESH_COUNT++))
}

# ============================================
# Cache Management Functions
# ============================================

# Encode sensor name for safe filename
_encode_sensor_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}

# Cache sensor data
# Usage: cache_sensor_data "sensor-name" "$json_response"
cache_sensor_data() {
    local sensor_name="$1"
    local json_data="$2"
    local timestamp=$(date +%s)
    local encoded=$(_encode_sensor_name "$sensor_name")

    # Ensure cache directory exists
    mkdir -p "$CACHE_DIR" 2>/dev/null

    echo "$json_data" > "$CACHE_DIR/${encoded}.data" 2>/dev/null
    echo "$timestamp" > "$CACHE_DIR/${encoded}.time" 2>/dev/null

    TOTAL_API_CALLS=$((TOTAL_API_CALLS + 1))
}

# Get cached sensor data
# Usage: get_cached_sensor "sensor-name"
get_cached_sensor() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")

    if [ -f "$CACHE_DIR/${encoded}.data" ]; then
        cat "$CACHE_DIR/${encoded}.data"
        return 0
    fi

    return 1
}

# Check if cache is fresh
# Usage: if is_cache_fresh "sensor-name"; then ...
is_cache_fresh() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")

    if [ ! -f "$CACHE_DIR/${encoded}.time" ]; then
        return 1  # No cache
    fi

    local cache_time=$(cat "$CACHE_DIR/${encoded}.time")
    local age=$(($(date +%s) - cache_time))

    if [ "$age" -lt "$CACHE_TTL" ]; then
        return 0  # Fresh
    fi

    return 1  # Stale
}

# Invalidate all caches (force refresh)
invalidate_cache() {
    rm -rf "$CACHE_DIR"
    mkdir -p "$CACHE_DIR" 2>/dev/null
}

# ============================================
# Sensor Metrics Cache
# ============================================

# Cache sensor metrics
# Usage: cache_sensor_metrics "sensor-name" "45" "3.2" "67" "8/8"
cache_sensor_metrics() {
    local sensor_name="$1"
    local cpu="$2"
    local memory="$3"
    local disk="$4"
    local pods="$5"
    local encoded=$(_encode_sensor_name "$sensor_name")

    echo "${cpu}|${memory}|${disk}|${pods}" > "$CACHE_DIR/${encoded}.metrics"
}

# Get cached sensor metric
# Usage: cpu=$(get_sensor_metric "sensor-name" "cpu")
get_sensor_metric() {
    local sensor_name="$1"
    local metric_type="$2"
    local encoded=$(_encode_sensor_name "$sensor_name")

    if [ ! -f "$CACHE_DIR/${encoded}.metrics" ]; then
        echo "unknown"
        return 1
    fi

    local metrics=$(cat "$CACHE_DIR/${encoded}.metrics")
    IFS='|' read -r cpu memory disk pods <<< "$metrics"

    case "$metric_type" in
        cpu) echo "$cpu" ;;
        memory) echo "$memory" ;;
        disk) echo "$disk" ;;
        pods) echo "$pods" ;;
        *) echo "unknown" ;;
    esac
}

# ============================================
# Operation History Functions
# ============================================

# Add operation to history
# Usage: add_operation_history "DELETE" "sensor-123" "success" "3.2"
add_operation_history() {
    local operation="$1"
    local target="$2"
    local result="$3"
    local duration="${4:-0}"
    local timestamp=$(date +%s)

    OPERATION_HISTORY+=("$timestamp|$operation|$target|$result|$duration")

    # Keep only last MAX_HISTORY items
    if [ ${#OPERATION_HISTORY[@]} -gt $MAX_HISTORY ]; then
        OPERATION_HISTORY=("${OPERATION_HISTORY[@]: -$MAX_HISTORY}")
    fi
}

# Get recent operations
# Usage: get_recent_operations 5
get_recent_operations() {
    local count="${1:-5}"
    local history_len=${#OPERATION_HISTORY[@]}
    local start=$((history_len - count))
    [ $start -lt 0 ] && start=0

    for i in $(seq $start $((history_len - 1))); do
        echo "${OPERATION_HISTORY[$i]}"
    done
}

# Get operation count
get_operation_count() {
    echo "${#OPERATION_HISTORY[@]}"
}

# ============================================
# Statistics Functions
# ============================================

# Get stats summary
get_stats_summary() {
    local session_duration=$(get_session_duration)
    local refresh_age=$(get_refresh_age)

    echo "SESSION:$session_duration"
    echo "REFRESH_AGE:$refresh_age"
    echo "REFRESH_COUNT:$REFRESH_COUNT"
    echo "API_CALLS:$TOTAL_API_CALLS"
    echo "OPERATIONS:${#OPERATION_HISTORY[@]}"
}

# Record API call timing
# Usage: record_api_call 45  # 45ms
record_api_call() {
    local duration_ms="$1"
    TOTAL_API_TIME_MS=$((TOTAL_API_TIME_MS + duration_ms))
}

# Get average API latency
get_avg_api_latency() {
    if [ "$TOTAL_API_CALLS" -eq 0 ]; then
        echo "0"
        return
    fi

    echo $((TOTAL_API_TIME_MS / TOTAL_API_CALLS))
}

# ============================================
# Resource Metrics Collection
# ============================================

# Collect resource metrics from sensor via SSH (with ControlMaster support)
# Usage: collect_sensor_metrics "10.50.88.154"
# Returns: "cpu|memory|disk|pods"
collect_sensor_metrics() {
    local sensor_ip="$1"
    local ssh_user="${SSH_USERNAME:-broala}"
    local ssh_pass="${SSH_PASSWORD}"
    local ssh_control_opts=$(get_ssh_control_opts)

    # Use /proc-based commands for portable metrics across Linux distributions
    # This is more reliable than parsing 'top' which varies by distro
    # For pods/services: Use corelightctl to count services in "Ok" status (Corelight sensors)
    # Falls back to kubectl for standard k8s if corelightctl not available
    local remote_cmd='cpu=$(awk "/^cpu / {printf \"%.0f\", (\$2+\$4)*100/(\$2+\$4+\$5)}" /proc/stat 2>/dev/null || echo "0"); \
        mem=$(free 2>/dev/null | awk "/Mem:/ {printf \"%.0f\", \$3/\$2*100}" || echo "0"); \
        disk=$(df / 2>/dev/null | awk "NR==2 {gsub(/%/,\"\"); print \$5}" || echo "0"); \
        pods=$(sudo corelightctl sensor status 2>/dev/null | grep -c "Ok" || sudo kubectl get pods --all-namespaces 2>/dev/null | grep -c Running || echo "0"); \
        echo "${cpu}|${mem}|${disk}|${pods}"'

    # Single SSH command to gather all metrics (batched for efficiency)
    local metrics
    if [ "${SSH_USE_KEYS:-}" = true ]; then
        metrics=$(ssh $ssh_control_opts -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes \
            "$ssh_user@$sensor_ip" "$remote_cmd" 2>/dev/null)
    elif command -v sshpass &> /dev/null && [ -n "$ssh_pass" ]; then
        metrics=$(sshpass -p "$ssh_pass" ssh $ssh_control_opts -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
            "$ssh_user@$sensor_ip" "$remote_cmd" 2>/dev/null)
    else
        metrics=$(ssh $ssh_control_opts -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
            "$ssh_user@$sensor_ip" "$remote_cmd" 2>/dev/null)
    fi

    # Validate metrics format (should be 4 pipe-separated values)
    if [ -n "$metrics" ] && echo "$metrics" | grep -q '|.*|.*|'; then
        echo "$metrics"
    else
        echo "n/a|n/a|n/a|n/a"
    fi
}

# Collect metrics in background and save to cache file
# Usage: collect_sensor_metrics_async "sensor-name" "10.50.88.154"
collect_sensor_metrics_async() {
    local sensor_name="$1"
    local sensor_ip="$2"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    # Collect metrics and save to cache
    local metrics=$(collect_sensor_metrics "$sensor_ip")
    echo "$metrics" > "$CACHE_DIR/${encoded}.metrics" 2>/dev/null
    echo "$(date +%s)" > "$CACHE_DIR/${encoded}.metrics.time" 2>/dev/null
}

# Get cached or fresh metrics for sensor
# Usage: get_sensor_metrics_cached "sensor-name" "ip"
get_sensor_metrics_cached() {
    local sensor_name="$1"
    local sensor_ip="$2"
    local encoded=$(_encode_sensor_name "$sensor_name")

    # Check cache freshness
    if is_cache_fresh "$sensor_name"; then
        # Return cached metrics
        if [ -f "$CACHE_DIR/${encoded}.metrics" ]; then
            cat "$CACHE_DIR/${encoded}.metrics"
            return 0
        fi
    fi

    # Ensure cache directory exists
    mkdir -p "$CACHE_DIR" 2>/dev/null

    # Collect fresh metrics
    local metrics=$(collect_sensor_metrics "$sensor_ip")
    echo "$metrics" > "$CACHE_DIR/${encoded}.metrics" 2>/dev/null
    echo "$(date +%s)" > "$CACHE_DIR/${encoded}.time" 2>/dev/null
    echo "$metrics"
}

# Cleanup cache and SSH connections on exit
cleanup_cache() {
    close_ssh_connections
    rm -rf "$CACHE_DIR" 2>/dev/null
    rm -rf "$SSH_CONTROL_DIR" 2>/dev/null
}

# ============================================
# Parallel API Fetch Functions
# ============================================

# Fetch sensor data from API in background
# Usage: fetch_sensor_async "sensor-name" "base_url" "api_key"
fetch_sensor_async() {
    local sensor_name="$1"
    local base_url="$2"
    local api_key="$3"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    # Fetch and save to cache file
    local response=$(curl -s "${base_url}/${sensor_name}" -H "x-api-key: ${api_key}" 2>/dev/null || echo '{}')
    echo "$response" > "$CACHE_DIR/${encoded}.api_response" 2>/dev/null
}

# Wait for all background jobs and collect results
# Usage: wait_for_fetches
wait_for_fetches() {
    wait
}

# Get fetched sensor response from cache
# Usage: get_fetched_response "sensor-name"
get_fetched_response() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    if [ -f "$CACHE_DIR/${encoded}.api_response" ]; then
        cat "$CACHE_DIR/${encoded}.api_response"
    else
        echo '{}'
    fi
}

# Check if metrics cache is fresh (separate from data cache)
# Usage: if is_metrics_cache_fresh "sensor-name"; then ...
is_metrics_cache_fresh() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    if [ ! -f "$CACHE_DIR/${encoded}.metrics.time" ]; then
        return 1  # No cache
    fi
    
    local cache_time=$(cat "$CACHE_DIR/${encoded}.metrics.time" 2>/dev/null || echo "0")
    local age=$(($(date +%s) - cache_time))
    
    if [ "$age" -lt "$CACHE_TTL" ]; then
        return 0  # Fresh
    fi
    
    return 1  # Stale
}

# Get cached metrics if fresh, otherwise return empty
# Usage: metrics=$(get_cached_metrics "sensor-name")
get_cached_metrics() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    if is_metrics_cache_fresh "$sensor_name"; then
        if [ -f "$CACHE_DIR/${encoded}.metrics" ]; then
            cat "$CACHE_DIR/${encoded}.metrics"
            return 0
        fi
    fi
    
    echo ""
    return 1
}

# Export functions
export -f init_session_state
export -f get_session_duration
export -f get_refresh_age
export -f mark_refresh
export -f _encode_sensor_name
export -f cache_sensor_data
export -f get_cached_sensor
export -f is_cache_fresh
export -f invalidate_cache
export -f cache_sensor_metrics
export -f get_sensor_metric
export -f add_operation_history
export -f get_recent_operations
export -f get_operation_count
export -f get_stats_summary
export -f record_api_call
export -f get_avg_api_latency
export -f collect_sensor_metrics
export -f collect_sensor_metrics_async
export -f get_sensor_metrics_cached
export -f cleanup_cache
export -f get_ssh_control_opts
export -f close_ssh_connections
export -f fetch_sensor_async
export -f wait_for_fetches
export -f get_fetched_response
export -f is_metrics_cache_fresh
export -f get_cached_metrics

# Set trap to clean up cache only on normal exit (not on Ctrl+C)
trap cleanup_cache EXIT TERM

# Initialize on load
init_session_state
