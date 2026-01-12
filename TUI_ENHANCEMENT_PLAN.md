# EC2 Sensor Manager - Professional TUI Enhancement Plan

**Goal**: Transform the sensor manager into a professional-grade terminal interface with rich metadata, keyboard shortcuts, health monitoring, and advanced operations.

**Estimated Time**: 8-12 hours total
**Priority**: High - Significantly improves UX and operational efficiency

---

## Phase 1: Foundation & State Management (2-3 hours)

### 1.1 Session State Management

**File**: `ec2sensor_state.sh` (NEW)

**Purpose**: Track session state, operation history, sensor metadata cache

**Components**:
```bash
# Session tracking
SESSION_START_TIME=$(date +%s)
LAST_REFRESH_TIME=0
REFRESH_COUNT=0

# Sensor data cache with timestamps
declare -A SENSOR_CACHE        # sensor_name -> json_data
declare -A SENSOR_CACHE_TIME   # sensor_name -> timestamp
declare -A SENSOR_METADATA     # sensor_name -> "version|uptime|age|created"

# Operation history
declare -a OPERATION_HISTORY   # Array of "timestamp|operation|sensor|result"
MAX_HISTORY=50

# Statistics
TOTAL_API_CALLS=0
TOTAL_API_TIME_MS=0

# Functions
init_session_state()
cache_sensor_data()
get_cached_sensor()
is_cache_fresh()
add_operation_history()
get_session_duration()
get_stats_summary()
```

**Integration Point**: Source in sensor.sh after ec2sensor_ui.sh

---

### 1.2 Time Utilities

**File**: `ec2sensor_ui.sh` (MODIFY - add functions)

**New Functions**:
```bash
# Format seconds into human-readable duration
# Usage: ui_format_duration 7265
# Output: "2h 1m"
ui_format_duration()

# Format timestamp to relative time
# Usage: ui_format_age 1704729791
# Output: "3d 4h ago"
ui_format_age()

# Calculate uptime from timestamp
# Usage: ui_calc_uptime "$start_time"
# Output: "2h 15m"
ui_calc_uptime()

# Format timestamp to human date
# Usage: ui_format_datetime 1704729791
# Output: "2025-01-05 14:23:11"
ui_format_datetime()
```

**Lines to Add**: ~100 lines

---

### 1.3 API Response Enrichment

**File**: `sensor.sh` (MODIFY - enhance API calls)

**Changes**:
```bash
# Before: Just parse status and IP
status=$(echo "$response" | jq -r '.sensor_status // "unknown"')
ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"')

# After: Extract all metadata
status=$(echo "$response" | jq -r '.sensor_status // "unknown"')
ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"')
version=$(echo "$response" | jq -r '.brolin_version // "unknown"')
created=$(echo "$response" | jq -r '.created_at // "unknown"')
last_restart=$(echo "$response" | jq -r '.last_restart // "unknown"')

# Cache the data
cache_sensor_data "$sensor" "$response" "$status" "$ip" "$version" "$created" "$last_restart"
```

**Lines Modified**: ~20 lines in sensor list loop

---

## Phase 2: Status Bar & Summary (1-2 hours)

### 2.1 Status Bar Function

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display status bar with session stats
# Usage: ui_status_bar "3" "0" "5"
# Args: running_count, error_count, session_duration_seconds
ui_status_bar() {
    local running="$1"
    local errors="$2"
    local session_duration="$3"
    local last_refresh_age="$4"

    local duration_str=$(ui_format_duration "$session_duration")
    local refresh_str=""

    if [ "$last_refresh_age" -lt 10 ]; then
        refresh_str="$(_ui_color "$GREEN" "[Last Updated: ${last_refresh_age}s ago]")"
    elif [ "$last_refresh_age" -lt 60 ]; then
        refresh_str="$(_ui_color "$YELLOW" "[Last Updated: ${last_refresh_age}s ago]")"
    else
        refresh_str="$(_ui_color "$RED" "[Last Updated: ${last_refresh_age}s ago]")"
    fi

    echo -n "$refresh_str "

    if [ "$running" -gt 0 ]; then
        echo -n "$(_ui_color "$GREEN" "[$running Running]") "
    fi

    if [ "$errors" -gt 0 ]; then
        echo -n "$(_ui_color "$RED" "[$errors Errors]") "
    else
        echo -n "[0 Errors] "
    fi

    echo "[Session: $duration_str]"
}
```

**Lines to Add**: ~40 lines

---

### 2.2 Integrate Status Bar

**File**: `sensor.sh` (MODIFY - main loop)

**Changes**:
```bash
# After header, before "Available Sensors"
ui_header "EC2 SENSOR MANAGER" "v1.0"

# Add status bar
session_duration=$(($(date +%s) - SESSION_START_TIME))
last_refresh_age=$(($(date +%s) - LAST_REFRESH_TIME))
running_count=$(echo "${SENSORS[@]}" | grep -c "running" || echo "0")
error_count=0  # Calculate from sensor statuses

ui_status_bar "$running_count" "$error_count" "$session_duration" "$last_refresh_age"

echo ""
ui_breadcrumb "Home"
```

**Lines Modified**: ~10 lines

---

## Phase 3: Enhanced Table with Rich Metadata (2-3 hours)

### 3.1 Fetch Additional Sensor Data

**File**: `sensor.sh` (MODIFY - sensor data loop)

**Changes**:
```bash
# Current loop just gets status and IP
# Need to:
# 1. Extract version from API response
# 2. Calculate uptime (need last_restart timestamp from API)
# 3. Calculate age (need created_at timestamp from API)
# 4. Truncate sensor name to last 4 digits

for i in "${!SENSORS[@]}"; do
    sensor="${SENSORS[$i]}"
    response=$(curl -s "${EC2_SENSOR_BASE_URL}/${sensor}" ...)

    if echo "$response" | jq empty 2>/dev/null; then
        status=$(echo "$response" | jq -r '.sensor_status // "unknown"')
        ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"')
        version=$(echo "$response" | jq -r '.brolin_version // "unknown"')
        created_at=$(echo "$response" | jq -r '.created_at // "0"')
        last_restart=$(echo "$response" | jq -r '.last_restart // "0"')

        # Calculate uptime and age
        if [ "$last_restart" != "0" ]; then
            uptime=$(ui_calc_uptime "$last_restart")
        else
            uptime="unknown"
        fi

        if [ "$created_at" != "0" ]; then
            age=$(ui_format_age "$created_at")
        else
            age="unknown"
        fi

        # Truncate sensor name
        sensor_short="${sensor: -7}"  # Last 7 chars

        ACTIVE_SENSORS+=("$sensor")
        status_display="$(ui_status_icon "$status")"

        # Enhanced table row with new columns
        ui_table_row_enhanced "$((${#ACTIVE_SENSORS[@]}))" "$sensor_short" \
            "$status_display" "$version" "$uptime" "$age" "$ip"
    fi
done
```

**Lines Modified**: ~30 lines

---

### 3.2 Enhanced Table Functions

**File**: `ec2sensor_ui.sh` (MODIFY - add new table functions)

**New Functions**:
```bash
# Enhanced table header with more columns
# Usage: ui_table_header_enhanced "ID" "SENSOR" "STATUS" "VERSION" "UPTIME" "AGE" "IP"
ui_table_header_enhanced() {
    echo ""
    printf "  %-6s%-12s%-14s%-12s%-10s%-10s%-15s\n" \
        "${1}" "${2}" "${3}" "${4}" "${5}" "${6}" "${7}"
    ui_divider "$BOX_SIMPLE_H" "$GRAY"
}

# Enhanced table row with more columns
# Usage: ui_table_row_enhanced "1" "...8249" "[RUNNING]" "29.0.0-t2" "2h 15m" "3d 4h" "10.50.88.154"
ui_table_row_enhanced() {
    printf "  %-6s%-12s%s            %-12s%-10s%-10s%s\n" \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}
```

**Lines to Add**: ~20 lines

---

### 3.3 Update Table Header Call

**File**: `sensor.sh` (MODIFY - table display)

**Changes**:
```bash
# Before:
ui_table_header "ID" "SENSOR" "STATUS" "IP ADDRESS"

# After:
ui_table_header_enhanced "ID" "SENSOR" "STATUS" "VERSION" "UPTIME" "AGE" "IP"
```

**Lines Modified**: 1 line

---

## Phase 4: Keyboard Shortcuts & Footer (2-3 hours)

### 4.1 Footer Function

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display keyboard shortcuts footer
# Usage: ui_shortcuts_footer "main"  # Context: main, operations, traffic
ui_shortcuts_footer() {
    local context="${1:-main}"

    echo ""
    echo -n "  "

    case "$context" in
        main)
            echo -n "$(_ui_color "$GRAY" "[r]")"
            echo -n "efresh  "
            echo -n "$(_ui_color "$GRAY" "[n]")"
            echo -n "ew sensor  "
            echo -n "$(_ui_color "$GRAY" "[i]")"
            echo -n "nfo  "
            echo -n "$(_ui_color "$GRAY" "[q]")"
            echo -n "uit  "
            echo -n "$(_ui_color "$GRAY" "[?]")"
            echo "help"
            ;;
        operations)
            echo -n "$(_ui_color "$GRAY" "[c]")"
            echo -n "onnect  "
            echo -n "$(_ui_color "$GRAY" "[f]")"
            echo -n "eatures  "
            echo -n "$(_ui_color "$GRAY" "[u]")"
            echo -n "pgrade  "
            echo -n "$(_ui_color "$GRAY" "[d]")"
            echo -n "elete  "
            echo -n "$(_ui_color "$GRAY" "[b]")"
            echo "ack"
            ;;
        traffic)
            echo -n "$(_ui_color "$GRAY" "[s]")"
            echo -n "tart  "
            echo -n "$(_ui_color "$GRAY" "[x]")"
            echo -n " stop  "
            echo -n "$(_ui_color "$GRAY" "[v]")"
            echo -n "iew  "
            echo -n "$(_ui_color "$GRAY" "[b]")"
            echo "ack"
            ;;
    esac
    echo ""
}
```

**Lines to Add**: ~50 lines

---

### 4.2 Keyboard Input Handler

**File**: `ec2sensor_ui.sh` (MODIFY - enhance ui_read_choice)

**New Function**:
```bash
# Read choice with keyboard shortcuts
# Usage: ui_read_choice_with_shortcuts "Select" 1 5 "main"
# Returns: Choice number OR shortcut action (e.g., "REFRESH", "QUIT", "INFO")
ui_read_choice_with_shortcuts() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local context="${4:-main}"
    local choice

    while true; do
        echo -ne "\n  ${prompt} [${min}-${max}]: > " >&2
        read -n 1 -r choice
        echo "" >&2  # Newline after single char

        # Check for keyboard shortcuts
        case "${choice,,}" in
            r) echo "REFRESH"; return 0 ;;
            q) echo "QUIT"; return 0 ;;
            n) echo "NEW"; return 0 ;;
            i) echo "INFO"; return 0 ;;
            c) echo "CONNECT"; return 0 ;;
            d) echo "DELETE"; return 0 ;;
            f) echo "FEATURES"; return 0 ;;
            u) echo "UPGRADE"; return 0 ;;
            b) echo "BACK"; return 0 ;;
            '?') echo "HELP"; return 0 ;;
        esac

        # Validate numeric and in range
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min" ] && [ "$choice" -le "$max" ]; then
            echo "$choice"
            return 0
        else
            echo "  [ERROR] Invalid choice. Please enter a number between $min and $max or a shortcut key." >&2
        fi
    done
}
```

**Lines to Add**: ~40 lines

---

### 4.3 Integrate Shortcuts in Main Menu

**File**: `sensor.sh` (MODIFY - main loop)

**Changes**:
```bash
# Before footer
ui_shortcuts_footer "main"

# Replace ui_read_choice with shortcuts version
choice=$(ui_read_choice_with_shortcuts "Select sensor or option" 1 "$((${#SENSORS[@]}+2))" "main")

# Handle shortcut actions
case "$choice" in
    REFRESH)
        # Force refresh by invalidating cache
        LAST_REFRESH_TIME=0
        continue
        ;;
    QUIT)
        echo ""
        ui_info "Goodbye!"
        exit 0
        ;;
    NEW)
        choice="$((${#SENSORS[@]}+1))"
        ;;
    INFO)
        # Show sensor details (implement in Phase 5)
        echo ""
        ui_info "Select a sensor first"
        sleep 2
        continue
        ;;
    HELP)
        # Show help screen
        show_help_screen
        continue
        ;;
esac

# Continue with numeric choice handling...
```

**Lines Modified/Added**: ~40 lines

---

## Phase 5: Sensor Details View (2-3 hours)

### 5.1 Fetch Detailed Sensor Info

**File**: `sensor.sh` (NEW function)

**New Function**:
```bash
# Get detailed sensor information
# Usage: get_sensor_details "sensor-name" "ip"
get_sensor_details() {
    local sensor_name="$1"
    local sensor_ip="$2"
    local details=""

    # Get basic info from API
    local response=$(curl -s "${EC2_SENSOR_BASE_URL}/${sensor_name}" \
        -H "x-api-key: ${EC2_SENSOR_API_KEY}" 2>/dev/null)

    if ! echo "$response" | jq empty 2>/dev/null; then
        echo "ERROR: Could not fetch sensor details"
        return 1
    fi

    # Extract all fields
    local status=$(echo "$response" | jq -r '.sensor_status // "unknown"')
    local ip=$(echo "$response" | jq -r '.sensor_ip // "unknown"')
    local version=$(echo "$response" | jq -r '.brolin_version // "unknown"')
    local created=$(echo "$response" | jq -r '.created_at // "unknown"')
    local last_restart=$(echo "$response" | jq -r '.last_restart // "unknown"')

    # Get features status via SSH
    local features=$(sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "$SSH_USERNAME@$sensor_ip" \
        "sudo broala-config get http.access.enable 2>/dev/null; \
         sudo broala-config get yara.enable 2>/dev/null; \
         sudo broala-config get suricata.enable 2>/dev/null; \
         sudo broala-config get smartpcap.v2.enable 2>/dev/null; \
         sudo broala-config get fleet.enable 2>/dev/null; \
         sudo broala-config get fleet.server 2>/dev/null" 2>/dev/null)

    # Store in associative array for display
    echo "STATUS:$status"
    echo "IP:$ip"
    echo "VERSION:$version"
    echo "CREATED:$created"
    echo "LAST_RESTART:$last_restart"
    echo "FEATURES:$features"
}
```

**Lines to Add**: ~50 lines

---

### 5.2 Display Sensor Details

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display detailed sensor information
# Usage: ui_sensor_details "sensor-name" "details-string"
ui_sensor_details() {
    local sensor_name="$1"
    local details="$2"

    clear
    ui_header "SENSOR DETAILS" "${sensor_name##*-}"

    echo ""
    ui_section "General"

    # Parse details string and display
    while IFS= read -r line; do
        key="${line%%:*}"
        value="${line#*:}"

        case "$key" in
            STATUS)
                ui_key_value "Status" "$(ui_status_icon "$value")"
                ;;
            IP)
                ui_key_value "IP Address" "$value"
                ;;
            VERSION)
                ui_key_value "Version" "$value"
                ;;
            CREATED)
                local age=$(ui_format_age "$value")
                local datetime=$(ui_format_datetime "$value")
                ui_key_value "Created" "$datetime ($age)"
                ;;
            LAST_RESTART)
                local uptime=$(ui_calc_uptime "$value")
                local datetime=$(ui_format_datetime "$value")
                ui_key_value "Last Restart" "$datetime ($uptime ago)"
                ;;
        esac
    done <<< "$details"

    echo ""
    ui_section "Features"
    # Parse features and display with [ON]/[OFF] indicators

    echo ""
    ui_section "Connection"
    ui_key_value "SSH" "ssh $SSH_USERNAME@$ip"
    ui_key_value "API" "https://192.0.2.1:30443"

    echo ""
    echo "  Press any key to return..."
    read -n 1 -r
}
```

**Lines to Add**: ~60 lines

---

### 5.3 Integrate Details View

**File**: `sensor.sh` (MODIFY - add to shortcut handler)

**Changes**:
```bash
case "$choice" in
    INFO)
        # Show sensor details
        if [ ${#SENSORS[@]} -eq 0 ]; then
            echo ""
            ui_error "No sensors available"
            sleep 2
            continue
        fi

        echo ""
        ui_info "Select sensor to view details"
        echo ""
        sensor_choice=$(ui_read_choice "Select sensor" 1 "${#SENSORS[@]}")

        SELECTED_SENSOR="${SENSORS[$((sensor_choice-1))]}"
        sensor_ip=$(get_sensor_ip "$SELECTED_SENSOR")

        details=$(get_sensor_details "$SELECTED_SENSOR" "$sensor_ip")
        ui_sensor_details "$SELECTED_SENSOR" "$details"
        continue
        ;;
esac
```

**Lines to Add**: ~25 lines

---

## Phase 6: Operation Summaries (1 hour)

### 6.1 Operation Summary Function

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display operation summary with timing
# Usage: ui_operation_summary "DELETE" "88.154" "success" "3.2"
ui_operation_summary() {
    local operation="$1"
    local target="$2"
    local result="$3"
    local duration="$4"
    shift 4
    local details=("$@")

    echo ""

    if [ "$result" = "success" ]; then
        ui_success "${operation} ${target} in ${duration}s"
    else
        ui_error "${operation} ${target} failed after ${duration}s"
    fi

    # Show details
    for detail in "${details[@]}"; do
        echo "     - $detail"
    done

    echo ""
}
```

**Lines to Add**: ~30 lines

---

### 6.2 Integrate Operation Tracking

**File**: `sensor.sh` (MODIFY - delete operation)

**Changes**:
```bash
# Before delete
start_time=$(date +%s)

# Perform delete
curl -s -X DELETE "${EC2_SENSOR_BASE_URL}/${SELECTED_SENSOR}" \
    -H "x-api-key: ${EC2_SENSOR_API_KEY}"

# After delete
end_time=$(date +%s)
duration=$((end_time - start_time))

# Show summary
ui_operation_summary "Deleted sensor" "${SELECTED_SENSOR##*-}" "success" "$duration" \
    "EC2 instance terminated" \
    "Removed from .sensors file" \
    "Freed resources: t3.medium (~\$0.04/hr)"

# Add to history
add_operation_history "DELETE" "$SELECTED_SENSOR" "success"
```

**Lines Modified**: ~15 lines (apply to all major operations)

---

## Phase 7: Recent Operations Log (1 hour)

### 7.1 Operation History Functions

**File**: `ec2sensor_state.sh` (MODIFY - add to state management)

**Functions**:
```bash
# Add operation to history
# Usage: add_operation_history "DELETE" "sensor-123" "success"
add_operation_history() {
    local operation="$1"
    local target="$2"
    local result="$3"
    local timestamp=$(date +%s)

    OPERATION_HISTORY+=("$timestamp|$operation|$target|$result")

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

    echo "${OPERATION_HISTORY[@]:$start}"
}
```

**Lines to Add**: ~30 lines

---

### 7.2 Display Recent Operations

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display recent operations log
# Usage: ui_recent_operations
ui_recent_operations() {
    local recent=$(get_recent_operations 5)

    if [ -z "$recent" ]; then
        return
    fi

    echo ""
    ui_section "Recent Operations"

    for entry in $recent; do
        IFS='|' read -r timestamp operation target result <<< "$entry"
        local age=$(ui_format_age "$timestamp")
        local icon="[OK]"
        [ "$result" != "success" ] && icon="[ERROR]"

        echo "  [$age] $icon $operation $target"
    done
}
```

**Lines to Add**: ~25 lines

---

### 7.3 Integrate Into Main Display

**File**: `sensor.sh` (MODIFY - add before menu footer)

**Changes**:
```bash
# After sensor table, before options menu
ui_recent_operations

echo ""
ui_menu_header "Options"
```

**Lines Modified**: 2 lines

---

## Phase 8: Better Progress Indicators (1-2 hours)

### 8.1 Multi-Phase Progress Function

**File**: `ec2sensor_ui.sh` (MODIFY - enhance progress)

**New Function**:
```bash
# Display multi-phase progress with estimates
# Usage: ui_progress_multi "Upgrading sensor" 45 300 "Installing packages" 2 5
ui_progress_multi() {
    local title="$1"
    local elapsed="$2"
    local total="$3"
    local phase="$4"
    local phase_num="$5"
    local phase_total="$6"

    local percent=$(( (elapsed * 100) / total ))
    local remaining=$((total - elapsed))

    echo ""
    echo "  $title... [$(ui_progress_bar $elapsed $total)] ${percent}%"
    echo "  Phase: $phase ($phase_num of $phase_total)"
    echo "  Elapsed: $(ui_format_duration $elapsed) | Remaining: ~$(ui_format_duration $remaining)"
}
```

**Lines to Add**: ~20 lines

---

### 8.2 Integrate Into Upgrade Workflow

**File**: `sensor.sh` (MODIFY - upgrade loop)

**Changes**:
```bash
# Define phases
PHASES=("Downloading update" "Installing packages" "Restarting services" "Verifying" "Complete")
current_phase=0

while [ $elapsed -lt $max_wait ]; do
    sleep $interval
    elapsed=$((elapsed + interval))

    # Determine current phase based on elapsed time
    progress_percent=$(( (elapsed * 100) / max_wait ))
    current_phase=$(( progress_percent / 20 ))  # 5 phases
    [ $current_phase -gt 4 ] && current_phase=4

    # Show multi-phase progress
    ui_progress_multi "Upgrading sensor" "$elapsed" "$max_wait" \
        "${PHASES[$current_phase]}" "$((current_phase + 1))" "${#PHASES[@]}"

    # Try to get version...
done
```

**Lines Modified**: ~20 lines

---

## Phase 9: Bulk Operations (3-4 hours)

### 9.1 Multi-Select Interface

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display multi-select interface
# Usage: selected=$(ui_multi_select "sensors" "${SENSORS[@]}")
# Returns: Space-separated indices of selected items
ui_multi_select() {
    local title="$1"
    shift
    local items=("$@")
    local selected=()
    local current=0

    # Initialize selected array
    for i in "${!items[@]}"; do
        selected[$i]=0
    done

    while true; do
        clear
        echo ""
        echo "  Select $title: [SPACE to mark, ENTER to confirm, ESC to cancel]"
        echo ""

        for i in "${!items[@]}"; do
            local mark=" "
            [ ${selected[$i]} -eq 1 ] && mark="X"

            if [ $i -eq $current ]; then
                echo -e "  $(_ui_color "$BOLD" "> [$mark] $((i+1))  ${items[$i]}")"
            else
                echo "    [$mark] $((i+1))  ${items[$i]}"
            fi
        done

        # Read single key
        read -n 1 -r key

        case "$key" in
            ' ')  # Space - toggle selection
                if [ ${selected[$current]} -eq 0 ]; then
                    selected[$current]=1
                else
                    selected[$current]=0
                fi
                ;;
            $'\e')  # ESC - cancel
                echo "CANCEL"
                return 1
                ;;
            '')  # Enter - confirm
                # Return indices of selected items
                local result=""
                for i in "${!selected[@]}"; do
                    [ ${selected[$i]} -eq 1 ] && result+="$i "
                done
                echo "${result% }"  # Remove trailing space
                return 0
                ;;
            # Arrow keys would require more complex handling
        esac
    done
}
```

**Lines to Add**: ~60 lines
**Note**: This is complex - might need arrow key support library

---

### 9.2 Bulk Actions Menu

**File**: `sensor.sh` (MODIFY - add bulk operations menu)

**New Menu Option**:
```bash
# Add to main menu options
echo "  $((${#SENSORS[@]}+3)) Bulk operations"

# Handle bulk operations
case "$choice" in
    "$((${#SENSORS[@]}+3))")
        # Multi-select sensors
        selected_indices=$(ui_multi_select "sensors" "${SENSORS[@]}")

        if [ "$selected_indices" = "CANCEL" ]; then
            continue
        fi

        # Show bulk actions menu
        echo ""
        echo "  Selected sensors: $(echo $selected_indices | wc -w)"
        echo ""
        echo "  Actions:"
        echo "    [u]pgrade all"
        echo "    [d]elete all"
        echo "    [f]eatures - enable on all"
        echo "    [ESC]cancel"

        read -n 1 -r action

        case "$action" in
            u)
                # Bulk upgrade
                for idx in $selected_indices; do
                    SELECTED_SENSOR="${SENSORS[$idx]}"
                    # Perform upgrade...
                done
                ;;
            d)
                # Bulk delete with confirmation
                echo ""
                if ui_read_confirm "Delete $(echo $selected_indices | wc -w) sensors?" "This cannot be undone"; then
                    for idx in $selected_indices; do
                        SELECTED_SENSOR="${SENSORS[$idx]}"
                        # Perform delete...
                    done
                fi
                ;;
        esac
        ;;
esac
```

**Lines to Add**: ~50 lines

---

## Phase 10: Health Monitoring Dashboard (2-3 hours)

### 10.1 Health Data Collection

**File**: `ec2sensor_state.sh` (MODIFY - add health functions)

**Functions**:
```bash
# Collect cluster health metrics
# Usage: collect_health_metrics
collect_health_metrics() {
    local running=0
    local stopped=0
    local errors=0
    local total_uptime=0
    local sensor_count=0
    local oldest_age=0
    local newest_age=999999
    local oldest_sensor=""
    local newest_sensor=""

    for sensor in "${SENSORS[@]}"; do
        local status=$(get_cached_sensor "$sensor" "status")
        local uptime_seconds=$(get_cached_sensor "$sensor" "uptime_seconds")
        local age_seconds=$(get_cached_sensor "$sensor" "age_seconds")

        [ "$status" = "running" ] && ((running++))
        [ "$status" = "stopped" ] && ((stopped++))

        ((sensor_count++))
        total_uptime=$((total_uptime + uptime_seconds))

        if [ $age_seconds -gt $oldest_age ]; then
            oldest_age=$age_seconds
            oldest_sensor="$sensor"
        fi

        if [ $age_seconds -lt $newest_age ]; then
            newest_age=$age_seconds
            newest_sensor="$sensor"
        fi
    done

    local avg_uptime=$((total_uptime / sensor_count))

    # Store metrics
    echo "RUNNING:$running"
    echo "STOPPED:$stopped"
    echo "ERRORS:$errors"
    echo "AVG_UPTIME:$avg_uptime"
    echo "OLDEST:$oldest_sensor:$oldest_age"
    echo "NEWEST:$newest_sensor:$newest_age"
}

# Check VPN status
check_vpn_status() {
    if command -v tailscale &> /dev/null; then
        if tailscale status &> /dev/null; then
            echo "Connected"
        else
            echo "Disconnected"
        fi
    else
        echo "Not installed"
    fi
}

# Measure API response time
measure_api_latency() {
    local start=$(date +%s%3N)  # Milliseconds
    curl -s "${EC2_SENSOR_BASE_URL}/health" -H "x-api-key: ${EC2_SENSOR_API_KEY}" > /dev/null 2>&1
    local end=$(date +%s%3N)
    echo $((end - start))
}
```

**Lines to Add**: ~80 lines

---

### 10.2 Health Dashboard Display

**File**: `ec2sensor_ui.sh` (MODIFY - add function)

**New Function**:
```bash
# Display health monitoring dashboard
# Usage: ui_health_dashboard
ui_health_dashboard() {
    clear
    ui_header "HEALTH DASHBOARD"

    echo ""

    # Collect metrics
    local health=$(collect_health_metrics)
    local vpn_status=$(check_vpn_status)
    local api_latency=$(measure_api_latency)

    # Parse metrics
    local running=$(echo "$health" | grep "RUNNING" | cut -d: -f2)
    local stopped=$(echo "$health" | grep "STOPPED" | cut -d: -f2)
    local errors=$(echo "$health" | grep "ERRORS" | cut -d: -f2)
    local avg_uptime=$(echo "$health" | grep "AVG_UPTIME" | cut -d: -f2)

    # Cluster health status
    local cluster_health="[OK] All systems operational"
    if [ $errors -gt 0 ]; then
        cluster_health="$(_ui_color "$RED" "[ERROR] $errors sensor(s) with errors")"
    elif [ $stopped -gt 0 ]; then
        cluster_health="$(_ui_color "$YELLOW" "[WARN] $stopped sensor(s) stopped")"
    else
        cluster_health="$(_ui_color "$GREEN" "[OK] All systems operational")"
    fi

    echo "  Cluster Health: $cluster_health"
    echo ""

    ui_section "Sensors"
    ui_key_value "Running" "$running"
    ui_key_value "Stopped" "$stopped"
    ui_key_value "Errors" "$errors"
    ui_key_value "Avg Uptime" "$(ui_format_duration $avg_uptime)"

    # Oldest/Newest
    local oldest_info=$(echo "$health" | grep "OLDEST")
    local newest_info=$(echo "$health" | grep "NEWEST")

    ui_key_value "Oldest" "$(ui_format_duration $(echo $oldest_info | cut -d: -f3))"
    ui_key_value "Newest" "$(ui_format_duration $(echo $newest_info | cut -d: -f3))"

    echo ""
    ui_section "System"

    # API latency with color coding
    local latency_display="$api_latency ms"
    if [ $api_latency -lt 100 ]; then
        latency_display="$(_ui_color "$GREEN" "$api_latency ms (healthy)")"
    elif [ $api_latency -lt 500 ]; then
        latency_display="$(_ui_color "$YELLOW" "$api_latency ms (degraded)")"
    else
        latency_display="$(_ui_color "$RED" "$api_latency ms (slow)")"
    fi

    ui_key_value "API Response" "$latency_display"

    # VPN status with color
    local vpn_display="$vpn_status"
    if [ "$vpn_status" = "Connected" ]; then
        vpn_display="$(_ui_color "$GREEN" "$vpn_status (tailscale)")"
    else
        vpn_display="$(_ui_color "$RED" "$vpn_status")"
    fi

    ui_key_value "VPN Status" "$vpn_display"

    local last_refresh_age=$(($(date +%s) - LAST_REFRESH_TIME))
    ui_key_value "Last Refresh" "$(ui_format_age $LAST_REFRESH_TIME)"

    echo ""
    echo "  Press any key to return..."
    read -n 1 -r
}
```

**Lines to Add**: ~90 lines

---

### 10.3 Integrate Health Dashboard

**File**: `sensor.sh` (MODIFY - add shortcut)

**Changes**:
```bash
# Add to shortcuts
case "$choice" in
    h|H)
        ui_health_dashboard
        continue
        ;;
esac

# Update footer to show health shortcut
ui_shortcuts_footer "main"
# Add: [h]ealth to the footer display
```

**Lines Modified**: ~10 lines

---

## Implementation Summary

### Files to Create (2 new files):
1. `ec2sensor_state.sh` - Session state and operation history (~200 lines)
2. None - all other changes are modifications

### Files to Modify (2 existing files):
1. `ec2sensor_ui.sh` - Add ~500 lines of new functions
2. `sensor.sh` - Modify ~200 lines, add ~200 lines

### Total Lines of Code:
- New: ~400 lines
- Modified: ~400 lines
- **Total Effort**: ~800 lines

---

## Testing Checklist

### Phase-by-Phase Testing:

**Phase 1 - Foundation**:
- [ ] Session state initializes correctly
- [ ] Time functions format durations properly
- [ ] API enrichment extracts all fields
- [ ] Cache stores and retrieves data

**Phase 2 - Status Bar**:
- [ ] Status bar displays with correct counts
- [ ] Refresh age updates correctly
- [ ] Color coding works (green/yellow/red)
- [ ] Session duration increments

**Phase 3 - Enhanced Table**:
- [ ] All 7 columns display correctly
- [ ] Version extracted from API
- [ ] Uptime calculated correctly
- [ ] Age shows "3d 4h" format
- [ ] Alignment maintained

**Phase 4 - Keyboard Shortcuts**:
- [ ] Single-key shortcuts work (r, q, n, i)
- [ ] Numeric choices still work (1-9)
- [ ] Footer displays in all contexts
- [ ] Shortcuts execute correct actions

**Phase 5 - Details View**:
- [ ] Details view shows all sensor info
- [ ] Features list displays correctly
- [ ] Timestamps formatted properly
- [ ] Press any key returns to menu

**Phase 6 - Operation Summaries**:
- [ ] Delete shows timing and details
- [ ] Upgrade shows summary
- [ ] Features show completion info
- [ ] All operations tracked

**Phase 7 - Recent Operations**:
- [ ] History tracks all operations
- [ ] Recent 5 operations display
- [ ] Ages format correctly
- [ ] Success/error icons show

**Phase 8 - Progress Indicators**:
- [ ] Multi-phase progress displays
- [ ] Phase names show correctly
- [ ] Time estimates reasonable
- [ ] Progress bar updates

**Phase 9 - Bulk Operations**:
- [ ] Multi-select interface works
- [ ] Space toggles selection
- [ ] Enter confirms selection
- [ ] ESC cancels
- [ ] Bulk actions execute on all selected

**Phase 10 - Health Dashboard**:
- [ ] Metrics calculated correctly
- [ ] VPN status detected
- [ ] API latency measured
- [ ] Color coding for health status
- [ ] All sections display properly

---

## Risk Mitigation

### Backwards Compatibility:
- All new features are additions, not replacements
- Original menu structure preserved
- Numeric selection still works
- Can disable features via flags if needed

### Performance:
- Cache API responses to reduce calls
- Limit history to 50 items
- Only collect metrics when dashboard opened
- Use efficient string operations

### Error Handling:
- Graceful degradation if API fails
- Default values for missing data
- Timeout on SSH operations
- Validate all user input

---

## Rollback Plan

If issues occur during implementation:

1. **Git Branching**: Create feature branch before starting
2. **Incremental Commits**: Commit after each phase
3. **Feature Flags**: Add `ENABLE_ENHANCED_UI=true` flag
4. **Fallback Mode**: Keep simple UI accessible

```bash
# Add to .env to disable features
ENABLE_STATUS_BAR=true
ENABLE_SHORTCUTS=true
ENABLE_HEALTH_DASHBOARD=true
```

---

## Timeline Estimate

**Conservative Estimate**: 12 hours
**Optimistic Estimate**: 8 hours

### Breakdown by Phase:
1. Foundation: 2-3 hours
2. Status Bar: 1-2 hours
3. Enhanced Table: 2-3 hours
4. Keyboard Shortcuts: 2-3 hours
5. Details View: 2-3 hours
6. Operation Summaries: 1 hour
7. Recent Operations: 1 hour
8. Progress Indicators: 1-2 hours
9. Bulk Operations: 3-4 hours
10. Health Dashboard: 2-3 hours

**Recommended Approach**: Implement Phases 1-8 first (core features), then add 9-10 as stretch goals.

---

## Success Criteria

### Must Have:
- ✅ Status bar with summary stats
- ✅ Enhanced table with version/uptime/age
- ✅ Keyboard shortcuts working
- ✅ Operation summaries with timing
- ✅ Sensor details view

### Should Have:
- ✅ Recent operations log
- ✅ Better progress indicators
- ✅ Health dashboard

### Nice to Have:
- ⭐ Bulk operations
- ⭐ Search/filter
- ⭐ Auto-refresh mode

---

Ready to implement? Should I start with **Phase 1 (Foundation & State Management)**?
