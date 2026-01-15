#!/bin/bash
# ec2sensor_state.sh - Session state and cache management
# Manages sensor data cache, operation history, and session metrics

# ============================================
# Debug Mode Configuration
# ============================================

# Set EC2SENSOR_DEBUG=true to enable verbose debug output
DEBUG_MODE="${EC2SENSOR_DEBUG:-false}"

# Debug log function - only outputs when DEBUG_MODE is true
# Usage: debug_log "message"
debug_log() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[DEBUG $(date '+%H:%M:%S')] $1" >&2
    fi
}

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

# Offline mode persistent cache
OFFLINE_CACHE_DIR="${HOME}/.ec2sensor/cache"
mkdir -p "$OFFLINE_CACHE_DIR" 2>/dev/null

# Retry settings for API calls
API_MAX_RETRIES=3
API_RETRY_DELAY=1  # seconds, will be doubled each retry (exponential backoff)

# API status tracking
API_ONLINE=true
LAST_API_ERROR=""
LAST_COMMAND_OUTPUT=""
LAST_COMMAND_EXIT_CODE=0

# SSH ControlMaster settings for connection reuse
# Use short path to avoid Unix socket path length limit (104 chars on macOS)
# Use a fixed directory name (not $$) to persist across menu navigations
SSH_CONTROL_DIR="/tmp/ec2ssh_${USER:-$(id -u)}"
SSH_CONTROL_PERSIST=300  # Keep connections alive for 5 minutes (persistent across menus)

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
    API_ONLINE=true
    LAST_API_ERROR=""
    
    # Create SSH control directory (persistent across sessions)
    mkdir -p "$SSH_CONTROL_DIR" 2>/dev/null
    chmod 700 "$SSH_CONTROL_DIR" 2>/dev/null
    
    # Create offline cache directory
    mkdir -p "$OFFLINE_CACHE_DIR" 2>/dev/null
}

# ============================================
# Startup Validation Functions
# ============================================

# Validate required environment variables
# Usage: validate_startup_requirements
# Returns: 0 if all requirements met, 1 otherwise
validate_startup_requirements() {
    local errors=0
    local warnings=0
    
    # Check required API credentials
    if [ -z "${EC2_SENSOR_BASE_URL:-}" ]; then
        echo "  [ERROR] EC2_SENSOR_BASE_URL not set" >&2
        ((errors++))
    fi
    
    if [ -z "${EC2_SENSOR_API_KEY:-}" ]; then
        echo "  [ERROR] EC2_SENSOR_API_KEY not set" >&2
        ((errors++))
    fi
    
    # Check SSH credentials (warning only - can use keys)
    if [ -z "${SSH_USERNAME:-}" ]; then
        echo "  [WARN] SSH_USERNAME not set, will use default 'broala'" >&2
        ((warnings++))
    fi
    
    if [ -z "${SSH_PASSWORD:-}" ]; then
        # Check for SSH keys
        if [ ! -f "$HOME/.ssh/id_rsa" ] && [ ! -f "$HOME/.ssh/id_ed25519" ]; then
            echo "  [WARN] SSH_PASSWORD not set and no SSH keys found" >&2
            echo "         Password will be prompted when needed" >&2
            ((warnings++))
        fi
    fi
    
    # Check for required tools
    if ! command -v curl &> /dev/null; then
        echo "  [ERROR] curl not found - required for API calls" >&2
        ((errors++))
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "  [ERROR] jq not found - required for JSON parsing" >&2
        ((errors++))
    fi
    
    # Return status
    if [ $errors -gt 0 ]; then
        echo "" >&2
        echo "  Missing required configuration. Please check your .env file." >&2
        echo "  Example .env file:" >&2
        echo "    EC2_SENSOR_BASE_URL=https://api.example.com/sensors" >&2
        echo "    EC2_SENSOR_API_KEY=your_api_key_here" >&2
        echo "    SSH_USERNAME=broala" >&2
        echo "    SSH_PASSWORD=your_password_here" >&2
        return 1
    fi
    
    return 0
}

# Test API connectivity
# Usage: test_api_connectivity
# Returns: 0 if API is reachable, 1 otherwise
# Note: The API returns 400 for base URL without sensor name, and 404 for non-existent sensors
#       Both indicate the API is reachable and responding, so we treat them as "online"
test_api_connectivity() {
    local response
    # Test with a dummy sensor name - API returns 404 if reachable but sensor doesn't exist
    # This is better than hitting base URL which returns 400 "Missing Authentication Token"
    response=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "${EC2_SENSOR_BASE_URL}/test-connectivity-check" -H "x-api-key: ${EC2_SENSOR_API_KEY}" 2>/dev/null)
    
    if [ "$response" = "000" ]; then
        API_ONLINE=false
        LAST_API_ERROR="Network unreachable"
        return 1
    elif [ "$response" -ge 500 ]; then
        API_ONLINE=false
        LAST_API_ERROR="Server error (HTTP $response)"
        return 1
    fi
    
    # Any response from 2xx-4xx means API is reachable
    # 404 = sensor not found (expected for test), 403 = auth issue but API is up
    API_ONLINE=true
    LAST_API_ERROR=""
    return 0
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
        metrics=$(SSHPASS="$ssh_pass" sshpass -e ssh $ssh_control_opts -o StrictHostKeyChecking=no \
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

# ============================================
# Retry Logic Functions
# ============================================

# Execute API call with retry logic and exponential backoff
# Usage: api_call_with_retry "url" "api_key"
# Returns: Response body via echo, sets API_ONLINE status
api_call_with_retry() {
    local url="$1"
    local api_key="$2"
    local retries=0
    local delay=$API_RETRY_DELAY
    local response
    local http_code
    
    while [ $retries -lt $API_MAX_RETRIES ]; do
        # Make request and capture both body and HTTP code
        response=$(curl -s --max-time 10 -w "\n%{http_code}" "$url" -H "x-api-key: $api_key" 2>/dev/null)
        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | sed '$d')
        
        # Check for success
        if [ -n "$http_code" ] && [ "$http_code" != "000" ] && [ "$http_code" -lt 500 ]; then
            API_ONLINE=true
            LAST_API_ERROR=""
            echo "$response"
            return 0
        fi
        
        # Retry with exponential backoff
        ((retries++))
        if [ $retries -lt $API_MAX_RETRIES ]; then
            sleep $delay
            delay=$((delay * 2))
        fi
    done
    
    # All retries failed
    API_ONLINE=false
    LAST_API_ERROR="API unreachable after $API_MAX_RETRIES attempts"
    echo '{}'
    return 1
}

# ============================================
# Offline Mode Functions
# ============================================

# Save sensor data to persistent offline cache
# Usage: save_offline_cache "sensor-name" "$json_data"
save_offline_cache() {
    local sensor_name="$1"
    local json_data="$2"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    echo "$json_data" > "$OFFLINE_CACHE_DIR/${encoded}.json" 2>/dev/null
    echo "$(date +%s)" > "$OFFLINE_CACHE_DIR/${encoded}.time" 2>/dev/null
}

# Load sensor data from persistent offline cache
# Usage: load_offline_cache "sensor-name"
load_offline_cache() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    if [ -f "$OFFLINE_CACHE_DIR/${encoded}.json" ]; then
        cat "$OFFLINE_CACHE_DIR/${encoded}.json"
        return 0
    fi
    
    echo '{}'
    return 1
}

# Get offline cache age in seconds
# Usage: get_offline_cache_age "sensor-name"
get_offline_cache_age() {
    local sensor_name="$1"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    if [ -f "$OFFLINE_CACHE_DIR/${encoded}.time" ]; then
        local cache_time=$(cat "$OFFLINE_CACHE_DIR/${encoded}.time")
        echo $(($(date +%s) - cache_time))
    else
        echo "999999"
    fi
}

# Check if we're in offline mode
# Usage: if is_offline_mode; then ...
is_offline_mode() {
    [ "$API_ONLINE" = false ]
}

# Get all sensors from offline cache
# Usage: sensors=($(get_offline_sensors))
get_offline_sensors() {
    if [ -d "$OFFLINE_CACHE_DIR" ]; then
        for f in "$OFFLINE_CACHE_DIR"/*.json; do
            [ -f "$f" ] || continue
            local basename=$(basename "$f" .json)
            # Decode sensor name (reverse of _encode_sensor_name)
            echo "$basename" | sed 's/_/-/g'
        done
    fi
}

# Fetch sensor data from API in background with retry and offline fallback
# Usage: fetch_sensor_async "sensor-name" "base_url" "api_key"
fetch_sensor_async() {
    local sensor_name="$1"
    local base_url="$2"
    local api_key="$3"
    local encoded=$(_encode_sensor_name "$sensor_name")
    
    # Try API with retry logic
    local response
    response=$(api_call_with_retry "${base_url}/${sensor_name}" "$api_key")
    
    # Check if response is valid JSON
    if echo "$response" | jq empty 2>/dev/null; then
        # Save to both session cache and persistent offline cache
        echo "$response" > "$CACHE_DIR/${encoded}.api_response" 2>/dev/null
        save_offline_cache "$sensor_name" "$response"
    else
        # Try loading from offline cache
        response=$(load_offline_cache "$sensor_name")
        echo "$response" > "$CACHE_DIR/${encoded}.api_response" 2>/dev/null
    fi
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
export -f validate_startup_requirements
export -f test_api_connectivity
export -f api_call_with_retry
export -f save_offline_cache
export -f load_offline_cache
export -f get_offline_cache_age
export -f is_offline_mode
export -f get_offline_sensors
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
export -f debug_log
export DEBUG_MODE

# Store main process PID to prevent subshells from cleaning up
MAIN_PID=$$

# Cleanup only runs in main process (not background subshells)
# Background jobs inherit traps, so without this check they would delete the cache when they exit
safe_cleanup_cache() {
    if [ "$$" = "$MAIN_PID" ]; then
        cleanup_cache
    fi
}

# Set trap to clean up cache only on normal exit from main process
trap safe_cleanup_cache EXIT TERM

# ============================================
# Error Capture Functions
# ============================================

# Run command with error capture - captures output, exit code, and provides detailed error info
# Usage: run_with_error_capture "description" "command" [args...]
# Returns: Exit code of command, sets LAST_COMMAND_OUTPUT and LAST_COMMAND_EXIT_CODE
# Example: 
#   if ! run_with_error_capture "Feature enablement" ./scripts/enable_sensor_features.sh "$ip"; then
#       echo "Error: $LAST_COMMAND_OUTPUT"
#   fi
run_with_error_capture() {
    local description="$1"
    shift
    local cmd="$@"
    
    debug_log "Running: $description"
    debug_log "Command: $cmd"
    
    # Capture both stdout and stderr
    LAST_COMMAND_OUTPUT=$(eval "$cmd" 2>&1)
    LAST_COMMAND_EXIT_CODE=$?
    
    if [ $LAST_COMMAND_EXIT_CODE -ne 0 ]; then
        debug_log "Command failed with exit code $LAST_COMMAND_EXIT_CODE"
        debug_log "Output: $LAST_COMMAND_OUTPUT"
        return $LAST_COMMAND_EXIT_CODE
    fi
    
    debug_log "Command succeeded"
    return 0
}

# Get error details from last command
# Usage: error_details=$(get_last_error_details)
get_last_error_details() {
    if [ -n "$LAST_COMMAND_OUTPUT" ]; then
        # Truncate long output and clean up for display
        echo "$LAST_COMMAND_OUTPUT" | head -5 | sed 's/^/  /'
    else
        echo "  No output captured"
    fi
}

# Format error message with details
# Usage: format_error_message "Operation failed" "$output" "$exit_code"
format_error_message() {
    local description="$1"
    local output="${2:-No output}"
    local exit_code="${3:-1}"
    
    echo "$description (exit code: $exit_code)"
    if [ -n "$output" ] && [ "$output" != "No output" ]; then
        echo "$output" | head -10 | sed 's/^/    /'
    fi
}

# ============================================
# SSH Error Diagnostics
# ============================================

# Diagnose SSH connection failure and return specific error message
# Usage: error_msg=$(diagnose_ssh_error "ip_address")
diagnose_ssh_error() {
    local ip="$1"
    local ssh_user="${SSH_USERNAME:-broala}"
    
    debug_log "Diagnosing SSH error for $ip"
    
    # Check if port 22 is reachable
    if ! nc -z -w 3 "$ip" 22 2>/dev/null; then
        echo "Port 22 not reachable on $ip - sensor may be offline or firewall blocking"
        return 1
    fi
    
    # Port is reachable, try SSH connection
    local ssh_output
    local ssh_control_opts=$(get_ssh_control_opts 2>/dev/null || echo "")
    
    if [ "${SSH_USE_KEYS:-}" = true ]; then
        ssh_output=$(ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 -o BatchMode=yes "$ssh_user@$ip" "echo ok" 2>&1)
    elif command -v sshpass &> /dev/null && [ -n "${SSH_PASSWORD:-}" ]; then
        ssh_output=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh $ssh_control_opts -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$ssh_user@$ip" "echo ok" 2>&1)
    else
        ssh_output=$(ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 "$ssh_user@$ip" "echo ok" 2>&1)
    fi
    
    if [ $? -eq 0 ] && echo "$ssh_output" | grep -q "ok"; then
        echo "SSH connection successful (transient error?)"
        return 0
    fi
    
    # Check for specific error patterns
    if echo "$ssh_output" | grep -qi "permission denied"; then
        echo "SSH authentication failed - check SSH_PASSWORD or SSH keys for user '$ssh_user'"
    elif echo "$ssh_output" | grep -qi "connection refused"; then
        echo "SSH connection refused - sshd may not be running on $ip"
    elif echo "$ssh_output" | grep -qi "connection timed out"; then
        echo "SSH connection timed out - network issue or firewall"
    elif echo "$ssh_output" | grep -qi "host key verification"; then
        echo "SSH host key verification failed"
    elif echo "$ssh_output" | grep -qi "no route to host"; then
        echo "No route to host $ip - check network connectivity"
    else
        # Generic error with actual output
        echo "SSH error: ${ssh_output:-Unknown error}"
    fi
    
    return 1
}

# Test SSH connectivity with detailed diagnostics
# Usage: if test_ssh_connection "ip"; then echo "connected"; fi
test_ssh_connection() {
    local ip="$1"
    local ssh_user="${SSH_USERNAME:-broala}"
    local ssh_control_opts=$(get_ssh_control_opts 2>/dev/null || echo "")
    
    debug_log "Testing SSH connection to $ip"
    
    local result
    if [ "${SSH_USE_KEYS:-}" = true ]; then
        result=$(ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 -o BatchMode=yes "$ssh_user@$ip" "echo connected" 2>&1)
    elif command -v sshpass &> /dev/null && [ -n "${SSH_PASSWORD:-}" ]; then
        result=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh $ssh_control_opts -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$ssh_user@$ip" "echo connected" 2>&1)
    else
        result=$(ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 "$ssh_user@$ip" "echo connected" 2>&1)
    fi
    
    if echo "$result" | grep -q "connected"; then
        debug_log "SSH connection to $ip successful"
        return 0
    fi
    
    debug_log "SSH connection to $ip failed: $result"
    LAST_COMMAND_OUTPUT="$result"
    return 1
}

# Export error capture functions (must be after function definitions)
export -f run_with_error_capture
export -f get_last_error_details
export -f format_error_message
export -f diagnose_ssh_error
export -f test_ssh_connection
export LAST_COMMAND_OUTPUT
export LAST_COMMAND_EXIT_CODE

# Initialize on load
init_session_state
