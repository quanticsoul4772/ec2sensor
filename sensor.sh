#!/bin/bash
# EC2 SENSOR - Simple automation
# Just run: ./sensor.sh

cd "$(dirname "$0")"
source ec2sensor_ui.sh
source ec2sensor_state.sh
source .env 2>/dev/null || true

# ============================================
# Startup Validation
# ============================================

echo ""
echo "  Initializing EC2 Sensor Manager..."

# Show debug mode status
if [ "${EC2SENSOR_DEBUG:-false}" = "true" ]; then
    echo "  [DEBUG MODE ENABLED - verbose output active]"
fi

# Validate startup requirements
if ! validate_startup_requirements; then
    echo ""
    echo "  Startup validation failed. Please configure your environment."
    echo "  Copy env.example to .env and fill in your credentials."
    exit 1
fi

echo "  ✓ Configuration validated"

# Test API connectivity (non-blocking - just sets status)
if test_api_connectivity; then
    echo "  ✓ API connected"
else
    echo "  ⚠ API offline - using cached data"
fi

echo ""

# Graceful exit handler for Ctrl+C
graceful_exit() {
    echo ""
    ui_info "Goodbye!"
    cleanup_cache
    exit 0
}

# Set up trap for graceful exit on Ctrl+C (SIGINT) and SIGTERM
trap graceful_exit SIGINT SIGTERM

# Get SSH credentials from environment or prompt user
get_ssh_credentials() {
    # Check if SSH_USERNAME is set, otherwise use default
    if [ -z "${SSH_USERNAME:-}" ]; then
        SSH_USERNAME="broala"
    fi

    # Check if SSH_PASSWORD is set
    if [ -z "${SSH_PASSWORD:-}" ]; then
        # Check if we can use SSH keys instead
        if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
            SSH_USE_KEYS=true
            SSH_PASSWORD=""
        else
            # Prompt for password if not set and no SSH keys
            ui_warning "SSH_PASSWORD not set in environment"
            echo "  You can set it in .env file or export SSH_PASSWORD='yourpassword'"
            SSH_PASSWORD=$(ui_read_password "Enter SSH password for $SSH_USERNAME")
        fi
    fi
}

# Check if sshpass is available when password auth is needed
check_ssh_requirements() {
    if [ -z "${SSH_USE_KEYS:-}" ] && [ -n "${SSH_PASSWORD:-}" ]; then
        if ! command -v sshpass &> /dev/null; then
            ui_warning "sshpass not installed - password authentication may not work"
            echo "  Install with: brew install hudochenkov/sshpass/sshpass (macOS)"
            echo "  Or: apt-get install sshpass (Linux)"
        fi
    fi
}

# SSH connection helper - uses keys or password based on configuration
# Now with ControlMaster support for connection reuse
ssh_connect() {
    local target_ip="$1"
    shift
    local ssh_cmd="$@"
    local ssh_control_opts=$(get_ssh_control_opts)

    if [ "${SSH_USE_KEYS:-}" = true ]; then
        ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$target_ip" $ssh_cmd
    elif command -v sshpass &> /dev/null && [ -n "${SSH_PASSWORD:-}" ]; then
        SSHPASS="$SSH_PASSWORD" sshpass -e ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$target_ip" $ssh_cmd
    else
        ssh $ssh_control_opts "$SSH_USERNAME@$target_ip" $ssh_cmd
    fi
}

# SSH connection helper for interactive sessions (exec)
# Uses ControlMaster for faster connection if socket exists
ssh_connect_exec() {
    local target_ip="$1"
    local ssh_control_opts=$(get_ssh_control_opts)

    if [ "${SSH_USE_KEYS:-}" = true ]; then
        exec ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$target_ip"
    elif command -v sshpass &> /dev/null && [ -n "${SSH_PASSWORD:-}" ]; then
        export SSHPASS="$SSH_PASSWORD"
        exec sshpass -e ssh $ssh_control_opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$target_ip"
    else
        exec ssh $ssh_control_opts "$SSH_USERNAME@$target_ip"
    fi
}

# Initialize SSH credentials at startup
get_ssh_credentials
check_ssh_requirements

# Bulk selection state
BULK_MODE=false
SELECTED_SENSORS=()

# Toggle sensor selection for bulk operations
toggle_sensor_selection() {
    local sensor="$1"
    local found=false
    local new_selection=()
    
    for s in "${SELECTED_SENSORS[@]}"; do
        if [ "$s" = "$sensor" ]; then
            found=true
        else
            new_selection+=("$s")
        fi
    done
    
    if [ "$found" = false ]; then
        new_selection+=("$sensor")
    fi
    
    SELECTED_SENSORS=("${new_selection[@]}")
}

# Check if sensor is selected
is_sensor_selected() {
    local sensor="$1"
    for s in "${SELECTED_SENSORS[@]}"; do
        [ "$s" = "$sensor" ] && return 0
    done
    return 1
}

# Select all sensors
select_all_sensors() {
    SELECTED_SENSORS=("${ACTIVE_SENSORS[@]}")
}

# Deselect all sensors
deselect_all_sensors() {
    SELECTED_SENSORS=()
}

# Load all sensors from file
SENSORS_FILE=".sensors"
SENSORS=()
if [ -f "$SENSORS_FILE" ]; then
    while IFS= read -r line; do
        SENSORS+=("$line")
    done < "$SENSORS_FILE"
fi

# If we have a current sensor in .env, add it to the list if not already there
if [ -n "${SENSOR_NAME:-}" ]; then
    if [[ ! " ${SENSORS[@]} " =~ " ${SENSOR_NAME} " ]]; then
        SENSORS+=("$SENSOR_NAME")
        printf "%s\n" "${SENSORS[@]}" > "$SENSORS_FILE"
    fi
fi

# Helper function to extract numeric ID from sensor name for sorting
_get_sensor_id() {
    local sensor="$1"
    # Extract the last numeric portion after the final dash
    echo "${sensor##*-}"
}

# Main loop - show sensor list and handle operations
while true; do
    # Reload sensors from file in case of changes
    SENSORS=()
    if [ -f "$SENSORS_FILE" ]; then
        # Read and sort sensors by their numeric ID (ascending)
        # This ensures oldest sensors (lower IDs) appear at the top
        # and newest sensors (higher IDs) appear at the bottom
        while IFS= read -r line; do
            [ -n "$line" ] && SENSORS+=("$line")
        done < <(sort -t'-' -k6 -n "$SENSORS_FILE" 2>/dev/null || cat "$SENSORS_FILE")
    fi

    ui_header "EC2 SENSOR MANAGER" "v1.0"

    echo ""
    ui_breadcrumb "Home"

    # Show all sensors and filter out deleted ones
    if [ ${#SENSORS[@]} -gt 0 ]; then
        # Track active sensors and detect deleted ones
        ACTIVE_SENSORS=()
        DELETED_COUNT=0
        running_count=0
        error_count=0
        
        # Arrays to track running sensors for parallel metrics collection
        RUNNING_SENSORS=()
        RUNNING_IPS=()

        ui_section "Available Sensors"
        echo ""
        
        # Show offline mode indicator if API is down
        if is_offline_mode; then
            # Get the oldest cache age from stored sensors
            oldest_cache_age=0
            for sensor in "${SENSORS[@]}"; do
                age=$(get_offline_cache_age "$sensor")
                [ "$age" -gt "$oldest_cache_age" ] && oldest_cache_age="$age"
            done
            ui_offline_indicator "$LAST_API_ERROR" "$oldest_cache_age"
            echo ""
        fi
        
        # Phase 1: Parallel API fetch for all sensors (with clearing spinner)
        # Uses retry logic and falls back to offline cache
        echo -ne "  Scanning ${#SENSORS[@]} sensor(s)...\r"
        for sensor in "${SENSORS[@]}"; do
            fetch_sensor_async "$sensor" "$EC2_SENSOR_BASE_URL" "$EC2_SENSOR_API_KEY" &
        done
        wait_for_fetches
        # Clear the scanning message
        echo -ne "                                        \r"
        
        ui_table_header_enhanced "ID" "SENSOR" "STATUS" "CPU%" "MEM%" "DISK%" "PODS" "IP"

        # Phase 2: Process API responses and identify running sensors
        for i in "${!SENSORS[@]}"; do
            sensor="${SENSORS[$i]}"
            response=$(get_fetched_response "$sensor")

            # Check if response is a valid JSON object with sensor data
            # API returns error strings like "Error: Ec2 Instances does not exist: []" for deleted sensors
            # fetch_sensor_async now marks deleted sensors with {"_deleted": true}
            is_valid_sensor=false
            if echo "$response" | jq empty 2>/dev/null; then
                # Check if marked as deleted by fetch_sensor_async
                if echo "$response" | jq -e '._deleted == true' >/dev/null 2>&1; then
                    is_valid_sensor=false
                # Check it's an object (not a string/array) and has sensor_status
                elif echo "$response" | jq -e 'type == "object" and has("sensor_status")' >/dev/null 2>&1; then
                    is_valid_sensor=true
                fi
            fi
            
            # Also check for error message in response (backup check for edge cases)
            if echo "$response" | grep -qi 'Error:.*does not exist' 2>/dev/null; then
                is_valid_sensor=false
            fi

            if [ "$is_valid_sensor" = true ]; then
                status=$(echo "$response" | jq -r '.sensor_status // "unknown"' 2>/dev/null)
                ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"' 2>/dev/null)

                # Cache sensor data
                cache_sensor_data "$sensor" "$response"

                # Count running sensors and track for metrics
                if [ "$status" = "running" ]; then
                    ((running_count++))
                    if [ "$ip" != "no-ip" ] && [ "$ip" != "null" ]; then
                        RUNNING_SENSORS+=("$sensor")
                        RUNNING_IPS+=("$ip")
                    fi
                fi

                # Keep active sensors
                ACTIVE_SENSORS+=("$sensor")
            else
                # API returned an error (sensor deleted) - skip it
                ((DELETED_COUNT++))
            fi
        done
        
        # Phase 3: Parallel metrics collection for running sensors (only if cache is stale)
        METRICS_PIDS=()
        for i in "${!RUNNING_SENSORS[@]}"; do
            sensor="${RUNNING_SENSORS[$i]}"
            sensor_ip="${RUNNING_IPS[$i]}"
            
            # Only fetch if cache is stale
            if ! is_metrics_cache_fresh "$sensor"; then
                collect_sensor_metrics_async "$sensor" "$sensor_ip" &
                METRICS_PIDS+=($!)
            fi
        done
        
        # Wait for all metrics collection to complete
        if [ ${#METRICS_PIDS[@]} -gt 0 ]; then
            wait "${METRICS_PIDS[@]}" 2>/dev/null
        fi
        
        # Phase 4: Display all active sensors with their data
        display_idx=0
        for sensor in "${ACTIVE_SENSORS[@]}"; do
            ((display_idx++))
            response=$(get_fetched_response "$sensor")
            
            status=$(echo "$response" | jq -r '.sensor_status // "unknown"' 2>/dev/null)
            ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"' 2>/dev/null)

            # Format row with status icon only
            status_display="$(ui_status_icon "$status")"

            # Get cached metrics for running sensors
            cpu="n/a"
            mem="n/a"
            disk="n/a"
            pods="n/a"
            if [ "$status" = "running" ] && [ "$ip" != "no-ip" ] && [ "$ip" != "null" ]; then
                cached_metrics=$(get_cached_metrics "$sensor")
                if [ -n "$cached_metrics" ]; then
                    IFS='|' read -r cpu mem disk pods <<< "$cached_metrics"
                fi
            fi

            # Truncate sensor name to last 8 characters
            sensor_short="${sensor##*-}"
            sensor_short="${sensor_short: -8}"

            ui_table_row_enhanced "$display_idx" "$sensor_short" "$status_display" \
                "$cpu" "$mem" "$disk" "$pods" "$ip"
        done
        
        # Close the table with bottom border
        ui_table_footer_enhanced

        # Mark that we refreshed
        mark_refresh

        # Display status bar with session stats (after scan)
        session_duration=$(get_session_duration)
        last_refresh_age=$(get_refresh_age)
        echo ""
        ui_status_bar "$running_count" "$error_count" "$session_duration" "$last_refresh_age"

        # Update .sensors file with only active sensors
        if [ $DELETED_COUNT -gt 0 ]; then
            printf "%s\n" "${ACTIVE_SENSORS[@]}" > "$SENSORS_FILE"
            echo ""
            ui_warning "Removed $DELETED_COUNT deleted sensor(s) from list"
        fi

        # Use active sensors for selection
        SENSORS=("${ACTIVE_SENSORS[@]}")

        echo ""
        ui_menu_header "Options"
        ui_menu_item "$((${#SENSORS[@]}+1))" "" "Deploy NEW sensor" "Create and configure new sensor (~20 min)"
        ui_menu_footer "Select sensor or option [1-$((${#SENSORS[@]}+1))] or [q] to quit"
        ui_shortcuts_footer "main"

        choice=$(ui_read_choice_with_shortcuts "Select" 1 "$((${#SENSORS[@]}+1))" "main")

        # Handle shortcut actions
        case "$choice" in
            REFRESH)
                # Force refresh by invalidating cache
                invalidate_cache
                continue
                ;;
            QUIT)
                graceful_exit
                ;;
            NEW)
                choice="$((${#SENSORS[@]}+1))"
                ;;
            HELP)
                ui_show_help "main"
                continue
                ;;
            THEME)
                # Cycle through themes - call directly, not in subshell
                # (subshell would lose the variable changes)
                ui_cycle_theme > /dev/null
                new_theme=$(ui_get_theme)
                ui_info "Theme changed to: $new_theme"
                sleep 0.5
                continue
                ;;
            MULTISELECT)
                # Enter bulk operations mode
                BULK_MODE=true
                SELECTED_SENSORS=()
                
                # Bulk operations loop
                while [ "$BULK_MODE" = true ]; do
                    ui_header "BULK OPERATIONS" "Multi-Select"
                    ui_breadcrumb "Home" "Bulk Operations"
                    
                    # Show offline indicator if needed
                    if is_offline_mode; then
                        oldest_cache_age=0
                        for sensor in "${ACTIVE_SENSORS[@]}"; do
                            age=$(get_offline_cache_age "$sensor")
                            [ "$age" -gt "$oldest_cache_age" ] && oldest_cache_age="$age"
                        done
                        ui_offline_indicator "$LAST_API_ERROR" "$oldest_cache_age"
                        echo ""
                    fi
                    
                    ui_section "Select Sensors"
                    echo "  Toggle selection by entering sensor number. Selected: ${#SELECTED_SENSORS[@]}"
                    echo ""
                    
                    ui_table_header_bulk_select
                    
                    display_idx=0
                    for sensor in "${ACTIVE_SENSORS[@]}"; do
                        ((display_idx++))
                        response=$(get_fetched_response "$sensor")
                        
                        status=$(echo "$response" | jq -r '.sensor_status // "unknown"' 2>/dev/null)
                        ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"' 2>/dev/null)
                        status_display="$(ui_status_icon "$status")"
                        
                        # Get cached metrics
                        cpu="n/a"; mem="n/a"; disk="n/a"; pods="n/a"
                        if [ "$status" = "running" ] && [ "$ip" != "no-ip" ]; then
                            cached_metrics=$(get_cached_metrics "$sensor")
                            if [ -n "$cached_metrics" ]; then
                                IFS='|' read -r cpu mem disk pods <<< "$cached_metrics"
                            fi
                        fi
                        
                        sensor_short="${sensor##*-}"
                        sensor_short="${sensor_short: -8}"
                        
                        is_selected=false
                        is_sensor_selected "$sensor" && is_selected=true
                        
                        ui_table_row_bulk_select "$display_idx" "$sensor_short" "$status_display" \
                            "$cpu" "$mem" "$disk" "$pods" "$ip" "$is_selected"
                    done
                    
                    ui_table_footer_enhanced
                    
                    echo ""
                    ui_menu_header "Bulk Actions"
                    ui_menu_item "a" "" "Select ALL sensors"
                    ui_menu_item "n" "" "Deselect all (NONE)"
                    ui_menu_item "d" "" "DELETE selected (${#SELECTED_SENSORS[@]})"
                    ui_menu_item "f" "" "Enable FEATURES on selected"
                    ui_menu_item "b" "" "Back to main menu"
                    
                    ui_shortcuts_footer "bulk"
                    
                    bulk_choice=$(ui_read_choice_with_shortcuts "Toggle or action" 1 "${#ACTIVE_SENSORS[@]}" "bulk")
                    
                    case "$bulk_choice" in
                        QUIT)
                            graceful_exit
                            ;;
                        ALL)
                            select_all_sensors
                            ;;
                        NEW|NONE)
                            deselect_all_sensors
                            ;;
                        DELETE)
                            if [ ${#SELECTED_SENSORS[@]} -eq 0 ]; then
                                ui_warning "No sensors selected"
                                sleep 1
                                continue
                            fi
                            
                            echo ""
                            ui_warning "About to delete ${#SELECTED_SENSORS[@]} sensor(s):"
                            for s in "${SELECTED_SENSORS[@]}"; do
                                echo "    - ${s##*-}"
                            done
                            echo ""
                            
                            if ui_read_confirm "Delete these sensors permanently?" "This action cannot be undone"; then
                                for s in "${SELECTED_SENSORS[@]}"; do
                                    ui_info "Deleting ${s##*-}..."
                                    curl -s -X DELETE "${EC2_SENSOR_BASE_URL}/${s}" -H "x-api-key: ${EC2_SENSOR_API_KEY}" > /dev/null
                                    grep -v "^${s}$" "$SENSORS_FILE" > "${SENSORS_FILE}.tmp" 2>/dev/null || true
                                    mv "${SENSORS_FILE}.tmp" "$SENSORS_FILE" 2>/dev/null || true
                                done
                                ui_success "Deleted ${#SELECTED_SENSORS[@]} sensor(s)"
                                SELECTED_SENSORS=()
                                invalidate_cache
                                sleep 1
                            fi
                            ;;
                        FEATURES)
                            if [ ${#SELECTED_SENSORS[@]} -eq 0 ]; then
                                ui_warning "No sensors selected"
                                sleep 1
                                continue
                            fi
                            
                            echo ""
                            ui_info "Enabling features on ${#SELECTED_SENSORS[@]} sensor(s)..."
                            for s in "${SELECTED_SENSORS[@]}"; do
                                response=$(get_fetched_response "$s")
                                sensor_ip=$(echo "$response" | jq -r '.sensor_ip // ""' 2>/dev/null)
                                if [ -n "$sensor_ip" ] && [ "$sensor_ip" != "null" ]; then
                                    ui_info "Enabling features on ${s##*-} ($sensor_ip)..."
                                    ./scripts/enable_sensor_features.sh "$sensor_ip" 2>/dev/null && \
                                        ui_success "Features enabled on ${s##*-}" || \
                                        ui_warning "Failed on ${s##*-}" "$(echo "$LAST_COMMAND_OUTPUT" | head -1)"
                                fi
                            done
                            echo ""
                            read -p "Press Enter to continue..." -r
                            ;;
                        BACK)
                            BULK_MODE=false
                            ;;
                        HELP)
                            ui_show_help "bulk"
                            ;;
                        *)
                            # Numeric choice - toggle selection
                            if [[ "$bulk_choice" =~ ^[0-9]+$ ]] && [ "$bulk_choice" -ge 1 ] && [ "$bulk_choice" -le "${#ACTIVE_SENSORS[@]}" ]; then
                                toggle_sensor_selection "${ACTIVE_SENSORS[$((bulk_choice-1))]}"
                            fi
                            ;;
                    esac
                done
                continue
                ;;
        esac

        if [ "$choice" -eq "$((${#SENSORS[@]}+1))" ] 2>/dev/null; then
            # Deploy new sensor - waits and auto-connects
            echo ""
            ui_info "Creating new sensor..."
            ui_info "This will take ~20 minutes and auto-connect when ready."
            echo ""
            exec ./sensor_lifecycle.sh create --no-auto-enable
        elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#SENSORS[@]}" ] 2>/dev/null; then
        # Selected a sensor - show operations menu
        SELECTED_SENSOR="${SENSORS[$((choice-1))]}"

        # Use cached sensor data instead of re-fetching (Performance: Phase 1.3)
        response=$(get_cached_sensor "$SELECTED_SENSOR")
        
        # Only fetch if cache miss
        if [ -z "$response" ] || [ "$response" = "{}" ]; then
            response=$(curl -s "${EC2_SENSOR_BASE_URL}/${SELECTED_SENSOR}" -H "x-api-key: ${EC2_SENSOR_API_KEY}" 2>/dev/null || echo '{}')
            cache_sensor_data "$SELECTED_SENSOR" "$response"
        fi

        # Check if response is valid JSON
        if echo "$response" | jq empty 2>/dev/null; then
            status=$(echo "$response" | jq -r '.sensor_status // "unknown"' 2>/dev/null)
            ip=$(echo "$response" | jq -r '.sensor_ip // "no-ip"' 2>/dev/null)
        else
            # API returned an error (likely deleted sensor)
            status="deleted"
            ip="n/a"
        fi

        # Operations menu loop
        while true; do
            ui_header "SENSOR OPERATIONS" "${SELECTED_SENSOR##*-}"
            ui_breadcrumb "Home" "Sensors" "${SELECTED_SENSOR##*-}"

            # Sensor status dashboard
            ui_section "Sensor Information"
            ui_key_value "Sensor ID" "${SELECTED_SENSOR##*-}"
            ui_key_value "Status" "$(ui_status_icon "$status") $status"
            ui_key_value "IP Address" "$ip"

            echo ""
            ui_menu_header "Operations"
            ui_menu_item 1 "" "Connect (SSH)" "Open SSH terminal session"
            ui_menu_item 2 "" "Enable features" "HTTP, YARA, Suricata, SmartPCAP"
            ui_menu_item 3 "" "Add to fleet manager" "Register with fleet management"
            ui_menu_item 4 "" "Traffic Generator" "Configure and control traffic generation"
            ui_menu_item 5 "" "Upgrade sensor" "Update to latest version"
            ui_menu_item 6 "" "Delete sensor" "Permanently remove sensor" "$RED"
            ui_menu_item 7 "" "Health Dashboard" "Detailed health & service view"
            ui_menu_item 8 "" "Back to sensor list" "Return to main menu"
            ui_menu_footer "Select operation [1-8]"
            ui_shortcuts_footer "operations"

            op_choice=$(ui_read_choice_with_shortcuts "Select operation" 1 8 "operations")

            # Handle shortcut actions
            case "$op_choice" in
                QUIT) graceful_exit ;;
                CONNECT) op_choice=1 ;;
                FEATURES) op_choice=2 ;;
                UPGRADE) op_choice=5 ;;
                DELETE) op_choice=6 ;;
                BACK) op_choice=8 ;;
                HEALTH)
                    # Show detailed health dashboard
                    if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                        ui_error "Sensor not ready for health check"
                        sleep 1
                        continue
                    fi
                    
                    # Collect detailed metrics
                    ui_info "Collecting detailed health data..."
                    
                    # Get metrics from cache or collect fresh
                    cached_metrics=$(get_cached_metrics "$SELECTED_SENSOR")
                    if [ -n "$cached_metrics" ]; then
                        IFS='|' read -r cpu mem disk pods <<< "$cached_metrics"
                    else
                        metrics=$(collect_sensor_metrics "$ip")
                        IFS='|' read -r cpu mem disk pods <<< "$metrics"
                    fi
                    
                    # Get uptime
                    uptime_str=$(ssh_connect "$ip" "uptime -p 2>/dev/null || uptime | awk '{print \$3,\$4}'" 2>/dev/null)
                    [ -z "$uptime_str" ] && uptime_str="unknown"
                    
                    # Get service details
                    services_raw=$(ssh_connect "$ip" "sudo corelightctl sensor status 2>/dev/null | grep -E '^[a-z]' | head -15" 2>/dev/null)
                    
                    # Display health dashboard
                    clear
                    ui_health_dashboard "$SELECTED_SENSOR" "$ip" "$status" "$cpu" "$mem" "$disk" "$pods" "$uptime_str" ""
                    
                    # Show services if available
                    if [ -n "$services_raw" ]; then
                        echo ""
                        ui_section "Service Details"
                        echo "$services_raw" | while read -r line; do
                            svc=$(echo "$line" | awk '{print $1}')
                            svc_status=$(echo "$line" | awk '{print $2}')
                            if [ "$svc_status" = "Ok" ]; then
                                echo "  $(_ui_color "$GREEN" "●") $svc: $svc_status"
                            else
                                echo "  $(_ui_color "$RED" "●") $svc: $svc_status"
                            fi
                        done
                    fi
                    
                    echo ""
                    read -p "  Press Enter to return to operations..." -r
                    continue
                    ;;
                HELP)
                    ui_show_help "operations"
                    continue
                    ;;
            esac

            case $op_choice in
            1)
                # Connect via SSH
                if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                    echo ""
                    ui_error "Sensor not ready (status: $status)" "Wait for sensor to reach 'running' state"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                echo ""
                ui_info "Connecting to $ip..."
                ssh_connect_exec "$ip"
                ;;
            2)
                # Enable features
                if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                    echo ""
                    ui_error "Sensor not ready (status: $status)" "Wait for sensor to reach 'running' state"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                echo ""
                ui_info "Enabling features on $ip..."
                feature_output=$(./scripts/enable_sensor_features.sh "$ip" 2>&1)
                feature_exit=$?
                if [ $feature_exit -eq 0 ]; then
                    ui_success "Features enabled successfully"
                else
                    ui_error "Feature enablement failed" "Exit code: $feature_exit"
                    # Show actual error output
                    if [ -n "$feature_output" ]; then
                        echo "  Error details:"
                        echo "$feature_output" | tail -10 | sed 's/^/    /'
                    fi
                    # Provide SSH diagnostic if it looks like SSH failure
                    if echo "$feature_output" | grep -qi "ssh\|connection\|permission denied\|timeout"; then
                        echo ""
                        echo "  SSH Diagnosis:"
                        diagnose_ssh_error "$ip" | sed 's/^/    /'
                    fi
                fi
                echo ""
                read -p "Press Enter to continue..." -r
                ;;
            3)
                # Add to fleet manager
                if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                    echo ""
                    ui_error "Sensor not ready (status: $status)" "Wait for sensor to reach 'running' state"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                echo ""
                ui_info "Adding sensor to fleet manager..."
                fleet_output=$(./scripts/prepare_p1_automation.sh "$ip" 2>&1)
                fleet_exit=$?
                if [ $fleet_exit -eq 0 ]; then
                    ui_success "Sensor added to fleet manager"
                else
                    ui_error "Fleet registration failed" "Exit code: $fleet_exit"
                    # Show actual error output
                    if [ -n "$fleet_output" ]; then
                        echo "  Error details:"
                        echo "$fleet_output" | tail -10 | sed 's/^/    /'
                    fi
                    # Provide SSH diagnostic if it looks like SSH failure
                    if echo "$fleet_output" | grep -qi "ssh\|connection\|permission denied\|timeout"; then
                        echo ""
                        echo "  SSH Diagnosis:"
                        diagnose_ssh_error "$ip" | sed 's/^/    /'
                    fi
                fi
                echo ""
                read -p "Press Enter to continue..." -r
                ;;
            4)
                # Traffic Generator
                if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                    echo ""
                    ui_error "Sensor not ready (status: $status)" "Wait for sensor to reach 'running' state"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                # Traffic generator submenu loop
                while true; do
                    ui_header "TRAFFIC GENERATOR" "$ip"
                    ui_breadcrumb "Home" "Sensors" "${SELECTED_SENSOR##*-}" "Traffic"

                    echo ""
                    ui_menu_header "Traffic Operations"
                    ui_menu_item 1 "" "Configure sensor as traffic generator" "Install traffic generation tools"
                    ui_menu_item 2 "" "Start traffic generation" "Begin sending traffic"
                    ui_menu_item 3 "" "Stop traffic generation" "Halt all traffic generation"
                    ui_menu_item 4 "" "View traffic statistics" "Show active processes"
                    ui_menu_item 5 "" "Back to main menu" "Return to operations"
                    ui_menu_footer "Select operation [1-5]"
                    ui_shortcuts_footer "traffic"

                    traffic_choice=$(ui_read_choice_with_shortcuts "Select traffic operation" 1 5 "traffic")

                    # Handle shortcut actions
                    case "$traffic_choice" in
                        QUIT) graceful_exit ;;
                        START) traffic_choice=2 ;;
                        STOP) traffic_choice=3 ;;
                        BACK) traffic_choice=5 ;;
                        HELP)
                            ui_show_help "traffic"
                            continue
                            ;;
                    esac

                    case $traffic_choice in
                        1)
                            echo ""
                            ui_info "Configuring sensor as traffic generator..."
                            traffic_config_output=$(./scripts/convert_sensor_to_traffic_generator.sh "$ip" simple 2>&1)
                            traffic_config_exit=$?
                            if [ $traffic_config_exit -eq 0 ]; then
                                ui_success "Configuration complete"
                            else
                                ui_error "Traffic generator configuration failed" "Exit code: $traffic_config_exit"
                                # Show actual error output
                                if [ -n "$traffic_config_output" ]; then
                                    echo "  Error details:"
                                    echo "$traffic_config_output" | tail -10 | sed 's/^/    /'
                                fi
                                # Provide SSH diagnostic if it looks like SSH failure
                                if echo "$traffic_config_output" | grep -qi "ssh\|connection\|permission denied\|timeout"; then
                                    echo ""
                                    echo "  SSH Diagnosis:"
                                    diagnose_ssh_error "$ip" | sed 's/^/    /'
                                fi
                            fi
                            echo ""
                            read -p "Press Enter to continue..." -r
                            ;;
                        2)
                            echo ""
                            ui_section "Traffic Generation Configuration"
                            echo ""

                            target_ip=$(ui_read_text "Target IP address" "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$")

                            echo -ne "$(_ui_color "$BOLD" "  Target port [5555]: ")"
                            read -r target_port
                            target_port="${target_port:-5555}"

                            echo -ne "$(_ui_color "$BOLD" "  Traffic type (udp/tcp/http/mixed) [udp]: ")"
                            read -r protocol
                            protocol="${protocol:-udp}"

                            echo -ne "$(_ui_color "$BOLD" "  Packets per second (100-5000) [1000]: ")"
                            read -r pps
                            pps="${pps:-1000}"

                            echo -ne "$(_ui_color "$BOLD" "  Duration in seconds [0=continuous]: ")"
                            read -r duration
                            duration="${duration:-0}"

                            echo ""
                            ui_info "Starting traffic generation..."
                            ui_key_value "Source" "$ip"
                            ui_key_value "Target" "$target_ip:$target_port"
                            ui_key_value "Protocol" "$protocol"
                            ui_key_value "Rate" "$pps pps"
                            ui_key_value "Duration" "${duration}s (0=continuous)"
                            echo ""
                            ui_warning "Max throughput: ~3,500 pps (27.5 Mbps)"
                            echo ""

                            if [ "$duration" = "0" ]; then
                                ui_info "Starting continuous traffic (Press Ctrl+C to stop)..."
                                echo ""
                                ssh_connect "$ip" \
                                    "cd /tmp && python3 simple_traffic_generator.py -t $target_ip -p $target_port --protocol $protocol -r $pps -D 999999 2>&1" || ui_warning "Traffic generation stopped"
                            else
                                ssh_connect "$ip" \
                                    "cd /tmp && python3 simple_traffic_generator.py -t $target_ip -p $target_port --protocol $protocol -r $pps -D $duration 2>&1"
                            fi
                            echo ""
                            read -p "Press Enter to continue..." -r
                            ;;
                        3)
                            echo ""
                            ui_info "Stopping traffic generation..."
                            ssh_connect "$ip" \
                                "sudo pkill -f simple_traffic_generator.py" 2>/dev/null && ui_success "Traffic generation stopped" || ui_warning "No traffic generation running"
                            echo ""
                            read -p "Press Enter to continue..." -r
                            ;;
                        4)
                            echo ""
                            ui_section "Traffic Generation Processes"
                            echo ""
                            ssh_connect "$ip" \
                                "ps aux | grep simple_traffic_generator | grep -v grep" || ui_warning "No traffic generation running"
                            echo ""
                            read -p "Press Enter to continue..." -r
                            ;;
                        5)
                            # Exit traffic generator submenu
                            break
                            ;;
                        *)
                            ui_error "Invalid choice"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            5)
                # Upgrade sensor
                if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                    echo ""
                    ui_error "Sensor not ready (status: $status)" "Wait for sensor to reach 'running' state"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                ui_header "SENSOR UPGRADE" "${SELECTED_SENSOR##*-}"
                ui_breadcrumb "Home" "Sensors" "${SELECTED_SENSOR##*-}" "Upgrade"

                # Get admin password from sensor's corelightctl.yaml
                ui_info "Reading sensor configuration..."
                ADMIN_PASSWORD=$(ssh_connect "$ip" \
                    "sudo grep -A5 'api:' /etc/corelight/corelightctl.yaml 2>/dev/null | grep password | awk '{print \$2}'" 2>/dev/null)

                if [ -z "$ADMIN_PASSWORD" ]; then
                    # Fallback to old method
                    ADMIN_PASSWORD=$(ssh_connect "$ip" \
                        "sudo grep 'password:' /etc/corelight/corelightctl.yaml 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
                fi

                if [ -z "$ADMIN_PASSWORD" ]; then
                    echo ""
                    ui_error "Could not read admin password from sensor" "Check sensor connectivity and permissions"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                # Detect release channel (dev/testing/release)
                release_channel=$(ssh_connect "$ip" \
                    "sudo grep 'release_channel:' /etc/corelight/corelightctl.yaml 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
                release_channel="${release_channel:-testing}"
                
                # Map channel to brolin repository name
                case "$release_channel" in
                    dev|development) brolin_repo="brolin-development" ;;
                    testing) brolin_repo="brolin-testing" ;;
                    release|stable) brolin_repo="brolin-release" ;;
                    *) brolin_repo="brolin-testing" ;;
                esac

                # Get current version using corelight-client information get
                ui_info "Checking current version..."
                sensor_info=$(ssh_connect "$ip" \
                    "corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p $ADMIN_PASSWORD information get 2>&1" 2>/dev/null)
                
                # Extract version from sensor info or fallback to corelightctl
                current_version=$(echo "$sensor_info" | grep -i version | head -1 | awk '{print $NF}' 2>/dev/null)
                if [ -z "$current_version" ] || [ "$current_version" = "unknown" ]; then
                    current_version=$(ssh_connect "$ip" \
                        "sudo corelightctl version 2>/dev/null | jq -r '.version // \"unknown\"'" 2>/dev/null)
                fi

                if [ -z "$current_version" ] || [ "$current_version" = "unknown" ]; then
                    echo ""
                    ui_error "Could not determine current version" "Check sensor connectivity"
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi

                echo ""
                ui_section "Sensor Information"
                ui_key_value "Current Version" "$current_version"
                ui_key_value "Release Channel" "$release_channel"
                ui_key_value "Repository" "$brolin_repo"
                echo ""

                # List available versions
                ui_info "Checking available versions..."
                # Fix corelight-client cache permissions (may be owned by root from previous sudo runs)
                ssh_connect "$ip" "mkdir -p ~/.corelight-client && sudo chown -R \$(whoami) ~/.corelight-client 2>/dev/null" 2>/dev/null
                updates_output=$(ssh_connect "$ip" \
                    "corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p $ADMIN_PASSWORD updates list 2>&1" 2>/dev/null)
                updates_exit_code=$?
                
                # Check for errors first
                if [ $updates_exit_code -ne 0 ]; then
                    echo ""
                    # Detect specific error: API service not running
                    if echo "$updates_output" | grep -q "URL not pointing to API base address"; then
                        ui_error "Sensor API service is not running" "The internal API at 192.0.2.1:30443 is unreachable"
                        echo ""
                        echo "  This sensor's API service appears to be down."
                        echo "  To diagnose, SSH to the sensor and run:"
                        echo "    sudo corelightctl sensor status"
                        echo "    sudo kubectl get pods -A | grep api"
                        echo ""
                        echo "  You may need to restart the sensor or contact support."
                    else
                        ui_error "Failed to check for updates" "Command failed with exit code $updates_exit_code"
                        echo "  Output: $updates_output"
                    fi
                    echo ""
                    read -p "Press Enter to continue..." -r
                    continue
                fi
                
                # Check if updates list returned "No entries" (meaning no updates available)
                if echo "$updates_output" | grep -q "No entries"; then
                    echo ""
                    ui_section "Available Versions"
                    ui_success "Sensor is up to date!" "No newer versions available via corelight-client"
                    ui_key_value "Current Version" "$current_version"
                    echo ""
                    ui_info "To upgrade to a specific version, use option [2] below."
                fi
                
                # Extract version lines from output
                available_versions=$(echo "$updates_output" | grep version)
                
                if [ -n "$available_versions" ]; then
                    echo ""
                    ui_section "Available Versions (via corelight-client)"
                    echo "$available_versions" | while read -r line; do
                        echo "    $line"
                    done
                fi

                echo ""
                ui_menu_header "Upgrade Options"
                ui_menu_item 1 "" "Upgrade to LATEST version" "corelight-client updates apply"
                ui_menu_item 2 "" "Upgrade to SPECIFIC version" "broala-update-repository"
                ui_menu_item 3 "" "Back" "Return to operations menu"
                ui_menu_footer "Select upgrade option [1-3]"

                echo -ne "$(_ui_color "$BOLD" "  Select upgrade option [1-3]: ")" 
                read -r upgrade_option

                upgrade_started=false
                case "$upgrade_option" in
                    1)
                        # Upgrade to latest using corelight-client updates apply
                        if echo "$updates_output" | grep -q "No entries"; then
                            echo ""
                            ui_warning "No updates available via corelight-client"
                            ui_info "Use option [2] to upgrade to a specific version instead."
                            echo ""
                            read -p "Press Enter to continue..." -r
                            continue
                        fi

                        echo ""
                        if ! ui_read_confirm "Proceed with upgrade to latest version?" "Sensor will restart and be unavailable for 2-3 minutes"; then
                            echo ""
                            ui_warning "Upgrade cancelled"
                            echo ""
                            read -p "Press Enter to continue..." -r
                            continue
                        fi

                        # Apply upgrade using corelight-client
                        echo ""
                        ui_info "Starting upgrade via corelight-client updates apply..."
                        upgrade_output=$(ssh_connect "$ip" \
                            "corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p $ADMIN_PASSWORD updates apply 2>&1" 2>/dev/null)

                        if echo "$upgrade_output" | grep -q "success.*True"; then
                            ui_success "Upgrade started successfully"
                            upgrade_started=true
                        else
                            echo ""
                            ui_error "Upgrade may have failed to start"
                            echo "  Output: $upgrade_output"
                            echo ""
                            read -p "Press Enter to continue..." -r
                            continue
                        fi
                        ;;
                    2)
                        # Upgrade to specific version using broala-update-repository
                        echo ""
                        ui_section "Upgrade to Specific Version"
                        echo ""
                        ui_info "This uses: sudo broala-update-repository -r $brolin_repo -R -U <version>"
                        echo ""
                        echo "  Examples:"
                        echo "    - 28.4.1 (for testing channel)"
                        echo "    - 29.0.0-t12 (for testing channel)"
                        echo "    - 28.4.0 (for release channel)"
                        echo ""

                        echo -ne "$(_ui_color "$BOLD" "  Enter target version (e.g., 28.4.1): ")" 
                        read -r target_version

                        if [ -z "$target_version" ]; then
                            echo ""
                            ui_warning "No version specified - upgrade cancelled"
                            echo ""
                            read -p "Press Enter to continue..." -r
                            continue
                        fi

                        echo ""
                        ui_key_value "Target Version" "$target_version"
                        ui_key_value "Repository" "$brolin_repo"
                        ui_key_value "Command" "sudo broala-update-repository -r $brolin_repo -R -U $target_version"
                        echo ""

                        if ! ui_read_confirm "Proceed with upgrade to version $target_version?" "Sensor will restart and be unavailable for several minutes"; then
                            echo ""
                            ui_warning "Upgrade cancelled"
                            echo ""
                            read -p "Press Enter to continue..." -r
                            continue
                        fi

                        # Apply upgrade using broala-update-repository
                        echo ""
                        ui_info "Starting upgrade to $target_version..."
                        ui_info "Running: sudo broala-update-repository -r $brolin_repo -R -U $target_version"
                        echo ""
                        
                        upgrade_output=$(ssh_connect "$ip" \
                            "sudo broala-update-repository -r $brolin_repo -R -U $target_version 2>&1" 2>/dev/null)
                        upgrade_exit=$?

                        if [ $upgrade_exit -eq 0 ]; then
                            ui_success "Upgrade command completed"
                            echo "  Output:"
                            echo "$upgrade_output" | tail -10 | sed 's/^/    /'
                            upgrade_started=true
                        else
                            ui_error "Upgrade command failed" "Exit code: $upgrade_exit"
                            echo "  Output:"
                            echo "$upgrade_output" | tail -15 | sed 's/^/    /'
                            echo ""
                            read -p "Press Enter to continue..." -r
                            continue
                        fi
                        ;;
                    3|*)
                        # Back to operations menu
                        continue
                        ;;
                esac

                # Only monitor if upgrade was actually started
                if [ "$upgrade_started" != true ]; then
                    continue
                fi

                # Monitor upgrade progress (common for both methods)
                echo ""
                ui_info "Sensor is upgrading... This may take 5-10 minutes"
                ui_info "Monitoring upgrade progress..."
                echo ""

                # Monitor the actual upgrade progress
                max_wait=600  # 10 minutes max
                elapsed=0
                interval=10
                upgrade_complete=false
                start_time=$(date +%s)

                while [ $elapsed -lt $max_wait ]; do
                    # Sleep first, then check status
                    sleep $interval
                    elapsed=$(( $(date +%s) - start_time ))
                    
                    # Show progress bar with current status
                    ui_progress_bar "$elapsed" "$max_wait" "Upgrading..."
                    
                    # Check if SSH is available
                    if ! ssh_connect "$ip" "echo online" 2>/dev/null | grep -q "online"; then
                        # Sensor is rebooting - continue waiting
                        continue
                    fi
                    
                    # SSH is available - check actual upgrade status
                    # Check for running upgrade processes (dpkg, apt, update scripts, broala-update)
                    upgrade_running=$(ssh_connect "$ip" \
                        "pgrep -f 'dpkg|apt|update-system|corelight.*update|broala-update' 2>/dev/null | head -1" 2>/dev/null)
                    
                    # Check for any active installation/update processes
                    active_updates=$(ssh_connect "$ip" \
                        "ps aux 2>/dev/null | grep -E 'dpkg|apt-get|update|upgrade|broala' | grep -v grep | wc -l" 2>/dev/null)
                    active_updates="${active_updates:-0}"
                    
                    if [ -n "$upgrade_running" ] || [ "$active_updates" -gt 0 ]; then
                        # Upgrade still in progress - continue waiting
                        continue
                    fi
                    
                    # No upgrade processes found - wait a bit more then verify
                    sleep 5
                    elapsed=$(( $(date +%s) - start_time ))
                    
                    # Double-check no upgrade processes
                    final_check=$(ssh_connect "$ip" \
                        "pgrep -f 'dpkg|apt|update-system|broala-update' 2>/dev/null | wc -l" 2>/dev/null)
                    final_check="${final_check:-0}"
                    
                    if [ "$final_check" -eq 0 ]; then
                        # Get the new version
                        new_version=$(ssh_connect "$ip" \
                            "sudo corelightctl version 2>/dev/null | jq -r '.version // \"unknown\"'" 2>/dev/null)
                        
                        if [ -n "$new_version" ] && [ "$new_version" != "unknown" ]; then
                            upgrade_complete=true
                            # Show 100% progress bar before success message
                            ui_progress_bar "$elapsed" "$elapsed" "Complete"
                            echo ""
                            if [ "$new_version" != "$current_version" ]; then
                                ui_success "Upgraded from $current_version to $new_version" "Completed in $(ui_elapsed_time $elapsed)"
                            else
                                ui_success "Upgrade complete: $new_version" "Completed in $(ui_elapsed_time $elapsed)"
                                ui_info "Note: Version number may be unchanged if already at target"
                            fi
                            break
                        fi
                    fi
                done

                # Final verification if loop completed without success
                if [ "$upgrade_complete" = false ]; then
                    echo ""
                    ui_warning "Verification timeout after $(ui_elapsed_time $max_wait)"
                    ui_info "The upgrade may still be in progress."
                    echo ""
                    ui_info "To check upgrade status manually:"
                    echo "    ssh ${SSH_USERNAME}@${ip}"
                    echo "    ps aux | grep -E 'dpkg|apt|update|broala'"
                    echo "    sudo corelightctl version"
                    echo "    corelight-client information get"
                fi

                echo ""
                read -p "Press Enter to continue..." -r
                ;;
            6)
                # Delete sensor
                echo ""
                ui_section "Delete Sensor"
                ui_key_value "Sensor ID" "${SELECTED_SENSOR##*-}"
                ui_key_value "IP Address" "$ip"
                echo ""

                if ui_read_confirm "Delete this sensor permanently?" "This action cannot be undone"; then
                    echo ""
                    ui_info "Deleting sensor $SELECTED_SENSOR..."
                    curl -s -X DELETE "${EC2_SENSOR_BASE_URL}/${SELECTED_SENSOR}" -H "x-api-key: ${EC2_SENSOR_API_KEY}"

                    # Remove from .sensors file
                    grep -v "^${SELECTED_SENSOR}$" "$SENSORS_FILE" > "${SENSORS_FILE}.tmp" 2>/dev/null || true
                    mv "${SENSORS_FILE}.tmp" "$SENSORS_FILE" 2>/dev/null || true

                    ui_success "Sensor deleted"
                    # Exit operations loop after deletion
                    break
                else
                    echo ""
                    ui_info "Deletion cancelled"
                fi
                ;;
            7)
                # Health Dashboard
                if [ "$status" != "running" ] || [ -z "$ip" ] || [ "$ip" = "null" ] || [ "$ip" = "no-ip" ]; then
                    ui_error "Sensor not ready for health check"
                    sleep 1
                    continue
                fi
                
                # Collect detailed metrics
                ui_info "Collecting detailed health data..."
                
                # Get metrics from cache or collect fresh
                cached_metrics=$(get_cached_metrics "$SELECTED_SENSOR")
                if [ -n "$cached_metrics" ]; then
                    IFS='|' read -r cpu mem disk pods <<< "$cached_metrics"
                else
                    metrics=$(collect_sensor_metrics "$ip")
                    IFS='|' read -r cpu mem disk pods <<< "$metrics"
                fi
                
                # Get uptime
                uptime_str=$(ssh_connect "$ip" "uptime -p 2>/dev/null || uptime | awk '{print \$3,\$4}'" 2>/dev/null)
                [ -z "$uptime_str" ] && uptime_str="unknown"
                
                # Get service details
                services_raw=$(ssh_connect "$ip" "sudo corelightctl sensor status 2>/dev/null | grep -E '^[a-z]' | head -15" 2>/dev/null)
                
                # Display health dashboard
                clear
                ui_health_dashboard "$SELECTED_SENSOR" "$ip" "$status" "$cpu" "$mem" "$disk" "$pods" "$uptime_str" ""
                
                # Show services if available
                if [ -n "$services_raw" ]; then
                    echo ""
                    ui_section "Service Details"
                    echo "$services_raw" | while read -r line; do
                        svc=$(echo "$line" | awk '{print $1}')
                        svc_status=$(echo "$line" | awk '{print $2}')
                        if [ "$svc_status" = "Ok" ]; then
                            echo "  $(_ui_color "$GREEN" "●") $svc: $svc_status"
                        else
                            echo "  $(_ui_color "$RED" "●") $svc: $svc_status"
                        fi
                    done
                fi
                
                echo ""
                read -p "  Press Enter to return to operations..." -r
                ;;
            8)
                # Back to sensor list
                break
                ;;
            *)
                ui_error "Invalid operation"
                sleep 1
                ;;
            esac
        done
        # After operations menu, return to sensor list
        continue
    else
        ui_error "Invalid choice"
        sleep 1
    fi
    else
        ui_warning "No sensors found" "Get started by deploying your first sensor"
        echo ""
        ui_menu_header "Options"
        ui_menu_item 1 "" "Deploy NEW sensor" "Create and configure new sensor (~20 min)"
        ui_menu_footer "Select option [1] or [q] to quit"
        ui_shortcuts_footer "main"

        choice=$(ui_read_choice_with_shortcuts "Select" 1 1 "main")

        # Handle shortcut actions
        case "$choice" in
            QUIT)
                graceful_exit
                ;;
            NEW)
                choice=1
                ;;
            HELP)
                ui_show_help "main"
                continue
                ;;
        esac

        if [ "$choice" = "1" ]; then
            echo ""
            ui_info "Creating new sensor..."
            ui_info "This will take ~20 minutes and auto-connect when ready."
            echo ""
            exec ./sensor_lifecycle.sh create --no-auto-enable
        fi
    fi
done
