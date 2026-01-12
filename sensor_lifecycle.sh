#!/bin/bash

# EC2 Sensor Lifecycle Management
# This script manages the complete lifecycle of ephemeral EC2 sensors
# with secure credential handling, dynamic configuration, and logging

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load logging module
source "${SCRIPT_DIR}/ec2sensor_logging.sh"

# Initialize logging
log_init

# Function to show help
show_help() {
    log_info "EC2 Sensor Lifecycle Management"
    log_info "-------------------------------"
    log_info "Usage: $0 [command]"
    log_info ""
    log_info "Commands:"
    log_info "  setup                       - Initial credential setup (API keys, etc.)"
    log_info "  create                      - Create a new sensor (features auto-enabled)"
    log_info "  status                      - Check sensor status and update IP if available"
    log_info "  connect                     - SSH into the current sensor"
    log_info "  delete                      - Delete the current sensor"
    log_info ""
    log_info "Workflow:"
    log_info "  1. ./sensor_lifecycle.sh setup     # First-time setup"
    log_info "  2. ./sensor_lifecycle.sh create    # Create sensor (~20 min)"
    log_info "  3. ./sensor_lifecycle.sh status    # Check status"
    log_info "  4. ./sensor_lifecycle.sh connect   # SSH into sensor"
    log_info "  5. ./sensor_lifecycle.sh delete    # Delete when done"
    log_info ""
    log_info "Note: Sensors are automatically deleted after 4 days if not manually deleted."
}

# Function to setup initial credentials
setup_credentials() {
    log_info "Setting up EC2 Sensor credentials"
    log_info "---------------------------------"
    
    # Create .env from template if it doesn't exist
    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
        cp "${SCRIPT_DIR}/.env.template" "${SCRIPT_DIR}/.env"
        log_info "Created .env file from template"
    fi
    
    # Ask for API key if not already set
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    if [ -z "$EC2_SENSOR_API_KEY" ]; then
        read -p "Enter your EC2 Sensor API Key: " api_key
        echo "EC2_SENSOR_API_KEY=$api_key" >> "${SCRIPT_DIR}/.env"
        log_info "API Key saved to .env file"
    else
        log_info "API Key already configured"
    fi
    
    # Set default values if needed
    if ! grep -q "DEFAULT_USERNAME" "${SCRIPT_DIR}/.env"; then
        read -p "Enter your username: " username
        echo "DEFAULT_USERNAME=$username" >> "${SCRIPT_DIR}/.env"
        log_debug "Set DEFAULT_USERNAME to $username"
    fi
    
    if ! grep -q "DEFAULT_TEAM" "${SCRIPT_DIR}/.env"; then
        echo "DEFAULT_TEAM=cicd" >> "${SCRIPT_DIR}/.env"
        log_debug "Set DEFAULT_TEAM to cicd"
    fi
    
    if ! grep -q "DEFAULT_BRANCH" "${SCRIPT_DIR}/.env"; then
        echo "DEFAULT_BRANCH=testing" >> "${SCRIPT_DIR}/.env"
        log_debug "Set DEFAULT_BRANCH to testing"
    fi
    
    if ! grep -q "SSH_USERNAME" "${SCRIPT_DIR}/.env"; then
        echo "SSH_USERNAME=broala" >> "${SCRIPT_DIR}/.env"
        log_debug "Set SSH_USERNAME to broala"
    fi
    
    if [ -z "$SSH_PASSWORD" ]; then
        read -sp "Enter the SSH Password (from 1Password): " ssh_pwd
        echo ""
        echo "SSH_PASSWORD=$ssh_pwd" >> "${SCRIPT_DIR}/.env"
        log_info "SSH Password saved to .env file"
    fi
    
    # Secure the .env file
    chmod 600 "${SCRIPT_DIR}/.env"
    log_info "Secured .env file with restricted permissions"
    
    log_info "Credential setup complete"
}

# Function to create a new sensor
create_sensor() {
    local auto_enable=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-auto-enable)
                auto_enable=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Usage: $0 create [--no-auto-enable]"
                exit 1
                ;;
        esac
    done

    log_info "Creating new EC2 Sensor"
    log_info "----------------------"

    # Source environment and check credentials
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    if ! check_env; then
        log_error "Failed to load environment variables. Please run setup first."
        exit 1
    fi
    
    # Set defaults if not specified in .env
    DEVELOPMENT_BRANCH=${DEFAULT_BRANCH:-"testing"}
    TEAM_NAME=${DEFAULT_TEAM:-"cicd"}
    USERNAME=${DEFAULT_USERNAME:-"$(whoami)"}
    
    # Create temporary JSON file with configuration
    JSON_PAYLOAD=$(cat <<EOF
{
  "development_branch": "${DEVELOPMENT_BRANCH}",
  "team_name": "${TEAM_NAME}",
  "username": "${USERNAME}"
}
EOF
    )
    
    log_info "Creating sensor with configuration:"
    echo "$JSON_PAYLOAD" | jq '.' 2>/dev/null || echo "$JSON_PAYLOAD"
    log_info "----------------------------------------"
    
    # Make API request
    log_debug "Sending API request to create sensor..."
    response=$(curl -s -X POST "${EC2_SENSOR_BASE_URL}/create" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${EC2_SENSOR_API_KEY}" \
        -d "${JSON_PAYLOAD}")
    status=$?
    
    # Log API interaction
    log_api "POST" "${EC2_SENSOR_BASE_URL}/create" "${JSON_PAYLOAD}" "${response}" $status
    
    # Check if request was successful
    if [ $status -ne 0 ]; then
        log_error "Failed to make API request"
        exit 1
    fi
    
    # Parse response
    if command -v jq &> /dev/null; then
        echo "$response" | jq '.'
        
        # Extract sensor name and save it
        sensor_name=$(echo "$response" | jq -r '.ec2_sensor_name // empty')
        if [ -n "$sensor_name" ]; then
            log_debug "SCRIPT_DIR=$SCRIPT_DIR"
            log_debug "Writing to: ${SCRIPT_DIR}/.env and ${SCRIPT_DIR}/.sensors"

            # Update or add SENSOR_NAME to .env
            ENV_FILE="${SCRIPT_DIR}/.env"
            if grep -q "^SENSOR_NAME=" "$ENV_FILE"; then
                sed -i.bak "s/^SENSOR_NAME=.*/SENSOR_NAME=${sensor_name}/" "$ENV_FILE"
                # Verify it actually changed
                if grep -q "^SENSOR_NAME=${sensor_name}$" "$ENV_FILE"; then
                    log_info "Sensor name saved to .env file: $sensor_name"
                else
                    log_error "Failed to update SENSOR_NAME in .env (sed returned success but file not updated)"
                fi
            else
                echo "SENSOR_NAME=${sensor_name}" >> "$ENV_FILE"
                log_info "Sensor name added to .env file: $sensor_name"
            fi

            # Add to sensors list if not already there
            SENSORS_FILE="${SCRIPT_DIR}/.sensors"
            if [ ! -f "$SENSORS_FILE" ] || ! grep -q "^${sensor_name}$" "$SENSORS_FILE"; then
                echo "$sensor_name" >> "$SENSORS_FILE"
                # Verify it was added
                if grep -q "^${sensor_name}$" "$SENSORS_FILE"; then
                    log_info "Added sensor to .sensors file: $sensor_name"
                else
                    log_error "Failed to add sensor to .sensors file (echo returned success but not in file)"
                fi
            else
                log_info "Sensor already in .sensors file: $sensor_name"
            fi

            # Save creation timestamp to .env
            creation_time=$(date +%s)
            if grep -q "^SENSOR_CREATED_AT=" "${SCRIPT_DIR}/.env"; then
                sed -i.bak "s/^SENSOR_CREATED_AT=.*/SENSOR_CREATED_AT=${creation_time}/" "${SCRIPT_DIR}/.env"
            else
                echo "SENSOR_CREATED_AT=${creation_time}" >> "${SCRIPT_DIR}/.env"
            fi
            log_debug "Saved creation timestamp to .env: $creation_time"
            
            # Remove old SSH_HOST entry if it exists
            if grep -q "^SSH_HOST=" "${SCRIPT_DIR}/.env"; then
                sed -i.bak "/^SSH_HOST=/d" "${SCRIPT_DIR}/.env"
                log_debug "Removed old SSH_HOST entry from .env"
            fi
        else
            log_warning "Could not extract sensor name from response"
        fi
    else
        echo "$response"
        log_warning "jq not found, cannot parse JSON response"
    fi
    
    log_info "----------------------------------------"
    log_info "Waiting for sensor to be ready (~20 minutes)..."
    log_info ""

    # Wait for sensor to be running
    local sensor_ip=""
    local wait_count=0
    while true; do
        sleep 30
        wait_count=$((wait_count + 1))

        status_output=$(curl -s "${EC2_SENSOR_BASE_URL}/${sensor_name}" -H "x-api-key: ${EC2_SENSOR_API_KEY}" 2>/dev/null || echo '{}')
        sensor_status=$(echo "$status_output" | jq -r '.sensor_status // "unknown"' 2>/dev/null)
        sensor_ip=$(echo "$status_output" | jq -r '.sensor_ip // empty' 2>/dev/null)

        log_info "[$((wait_count * 30))s] Status: $sensor_status"

        if [ "$sensor_status" = "running" ] && [ -n "$sensor_ip" ] && [ "$sensor_ip" != "null" ]; then
            log_info "✓ Sensor is running at $sensor_ip"
            break
        fi

        if [ $wait_count -gt 60 ]; then
            log_error "Timeout waiting for sensor (30 minutes)"
            exit 1
        fi
    done

    # Enable features (only if auto_enable is true)
    if [ "$auto_enable" = true ]; then
        log_info "Enabling features..."
        export SSH_USERNAME="${SSH_USERNAME:-broala}"
        export SSH_PASSWORD="${SSH_PASSWORD:-This#ahNg9Pi}"

        # Get absolute paths
        WAIT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/wait_for_sensor_ready.sh"
        ENABLE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/enable_sensor_features.sh"

        # Wait for sensor readiness
        if "$WAIT_SCRIPT" "$sensor_ip"; then
            log_info "✓ Sensor ready"
        else
            log_error "Sensor readiness check failed"
            exit 1
        fi

        # Enable features
        if "$ENABLE_SCRIPT" "$sensor_ip"; then
            log_info "✓ Features enabled"
        else
            log_error "Feature enablement failed"
            exit 1
        fi

        # Optional: Prepare for P1 automation
        log_info ""
        log_info "Sensor is ready for use"
        log_info ""
        echo "Would you like to prepare this sensor for P1 automation testing?"
        echo "  - Configure admin password"
        echo "  - Disable PCAP replay mode"
        echo "  - Add to fleet manager"
        echo ""
        read -p "Prepare for P1 automation? (y/N): " prepare_p1

        if [[ "$prepare_p1" =~ ^[Yy]$ ]]; then
            log_info ""
            log_info "Preparing sensor for P1 automation..."

            P1_PREP_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/prepare_p1_automation.sh"

            if [ -f "$P1_PREP_SCRIPT" ]; then
                "$P1_PREP_SCRIPT" "$sensor_ip"
            else
                log_error "P1 preparation script not found: $P1_PREP_SCRIPT"
            fi
        fi
    fi

    # Wait for SSH to be ready
    log_info ""
    log_info "Waiting for SSH to be ready..."
    export SSH_USERNAME="${SSH_USERNAME:-broala}"
    export SSH_PASSWORD="${SSH_PASSWORD:-This#ahNg9Pi}"

    WAIT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/wait_for_sensor_ready.sh"
    if [ -f "$WAIT_SCRIPT" ]; then
        if ! "$WAIT_SCRIPT" "$sensor_ip" 2>&1 | grep -v "Logging initialized"; then
            log_error "Sensor readiness check failed"
            exit 1
        fi
    else
        log_warning "Wait script not found, attempting direct connection"
        sleep 60  # Give sensor extra time
    fi

    # Auto-connect
    log_info ""
    log_info "Connecting to sensor..."
    log_info ""

    SSH_USERNAME="${SSH_USERNAME:-broala}"
    SSH_PASSWORD="${SSH_PASSWORD:-This#ahNg9Pi}"

    if command -v sshpass &> /dev/null; then
        exec sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$sensor_ip"
    else
        exec ssh "$SSH_USERNAME@$sensor_ip"
    fi
}

# Function to enable sensor features
enable_sensor_features() {
    log_info "Enabling Sensor Features"
    log_info "------------------------"

    # Source environment
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    if ! check_env; then
        log_error "Failed to load environment variables"
        exit 1
    fi

    # Get sensor IP from .env
    if [ -z "${SSH_HOST:-}" ]; then
        log_error "No sensor IP found. Run './sensor_lifecycle.sh status' first."
        exit 1
    fi

    log_info "Sensor IP: $SSH_HOST"
    log_info ""
    log_info "Step 1: Waiting for sensor to be fully ready..."

    # Wait for sensor to be ready
    if ! "${SCRIPT_DIR}/scripts/wait_for_sensor_ready.sh" "$SSH_HOST"; then
        log_error "Sensor readiness check failed"
        exit 1
    fi

    log_info ""
    log_info "Step 2: Enabling features..."

    # Enable features
    if ! "${SCRIPT_DIR}/scripts/enable_sensor_features.sh" "$SSH_HOST"; then
        log_error "Feature enablement failed"
        exit 1
    fi

    log_info ""
    log_info "Sensor features enabled successfully"
}

# Function to check sensor status
check_status() {
    log_info "Checking EC2 Sensor status"
    log_info "-------------------------"
    
    # Source environment and check credentials
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    if ! check_env; then
        log_error "Failed to load environment variables. Please run setup first."
        exit 1
    fi
    
    # Check if sensor name is set
    if [ -z "$SENSOR_NAME" ]; then
        log_error "SENSOR_NAME not set in .env file"
        log_error "Please run './sensor_lifecycle.sh create' first"
        exit 1
    fi
    
    log_info "Checking status for sensor: $SENSOR_NAME"
    log_info "----------------------------------------"
    
    # Make API request
    log_debug "Sending API request to check sensor status..."
    response=$(curl -s -X GET "${EC2_SENSOR_BASE_URL}/${SENSOR_NAME}" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${EC2_SENSOR_API_KEY}")
    status=$?
    
    # Log API interaction
    log_api "GET" "${EC2_SENSOR_BASE_URL}/${SENSOR_NAME}" "" "${response}" $status
    
    # Check if request was successful
    if [ $status -ne 0 ]; then
        log_error "Failed to make API request"
        exit 1
    fi
    
    # Pretty print the response and extract key information
    if command -v jq &> /dev/null; then
        echo "$response" | jq '.'
        
        echo -e "\n----------------------------------------"
        log_info "Key Information:"
        sensor_ip=$(echo "$response" | jq -r '.sensor_ip // "Not available yet"')
        sensor_status=$(echo "$response" | jq -r '.sensor_status // "Unknown"')
        brolin_version=$(echo "$response" | jq -r '.brolin_version // "Unknown"')
        
        log_info "Sensor IP: $sensor_ip"
        log_info "Status: $sensor_status"
        log_info "Brolin Version: $brolin_version"
        
        # Update .env with IP if available
        if [ "$sensor_ip" != "Not available yet" ] && [ "$sensor_ip" != "null" ]; then
            if grep -q "^SSH_HOST=" "${SCRIPT_DIR}/.env"; then
                sed -i.bak "s/^SSH_HOST=.*/SSH_HOST=${sensor_ip}/" "${SCRIPT_DIR}/.env"
            else
                echo "SSH_HOST=${sensor_ip}" >> "${SCRIPT_DIR}/.env"
            fi
            log_info "Updated SSH_HOST in .env file: $sensor_ip"
        else
            log_warning "Sensor IP not available yet"
        fi
        
        # Calculate and show expiration information if created timestamp exists
        if grep -q "^SENSOR_CREATED_AT=" "${SCRIPT_DIR}/.env"; then
            created_at=$(grep "^SENSOR_CREATED_AT=" "${SCRIPT_DIR}/.env" | cut -d= -f2)
            current_time=$(date +%s)
            age_seconds=$((current_time - created_at))
            age_days=$((age_seconds / 86400))
            age_hours=$(( (age_seconds % 86400) / 3600 ))
            expiry_days=$((4 - age_days))
            
            log_info ""
            log_info "Sensor Age: $age_days days, $age_hours hours"
            log_info "Auto-deletion in: $expiry_days days"
            
            # Warn if sensor is close to expiry
            if [ $expiry_days -le 1 ]; then
                log_warning "Sensor will be auto-deleted soon!"
            fi
        fi
    else
        echo "$response"
        log_warning "jq not found, cannot parse JSON response"
    fi
}

# Function to connect to sensor via SSH
connect_to_sensor() {
    log_info "Connecting to EC2 Sensor"
    log_info "-----------------------"

    # Source environment and load variables
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    load_env

    # Always get fresh IP from API
    if [ -n "${SENSOR_NAME:-}" ]; then
        response=$(curl -s "${EC2_SENSOR_BASE_URL}/${SENSOR_NAME}" -H "x-api-key: ${EC2_SENSOR_API_KEY}" 2>/dev/null || echo '{}')
        SSH_HOST=$(echo "$response" | jq -r '.sensor_ip // empty' 2>/dev/null)

        if [ -z "$SSH_HOST" ] || [ "$SSH_HOST" = "null" ]; then
            log_error "Sensor not ready yet. Run: ./sensor_lifecycle.sh"
            exit 1
        fi

        log_info "Connecting to: $SSH_HOST"
    else
        log_error "No sensor found. Run: ./sensor_lifecycle.sh create"
        exit 1
    fi
    
    # Check if SSH_USERNAME is set
    if [ -z "$SSH_USERNAME" ]; then
        log_error "SSH_USERNAME not set in .env file"
        log_error "Please run './sensor_lifecycle.sh setup' first"
        exit 1
    fi
    
    log_info "Connecting to: $SSH_USERNAME@$SSH_HOST"
    log_info "----------------------------------------"
    
    # Try different authentication methods
    
    # 1. Try SSH key if it exists
    SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
    if [ -f "$SSH_KEY_PATH" ]; then
        log_info "Attempting connection with SSH key: $SSH_KEY_PATH"
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$SSH_USERNAME@$SSH_HOST"
        EXIT_CODE=$?
        
        # Log SSH attempt
        log_ssh "$SSH_HOST" "$SSH_USERNAME" "" $EXIT_CODE
        
        if [ $EXIT_CODE -eq 0 ]; then
            return 0
        else
            log_warning "Key authentication failed, trying alternative methods..."
        fi
    fi
    
    # 2. Try sshpass if password is set and sshpass exists
    if [ -n "$SSH_PASSWORD" ] && command -v sshpass &> /dev/null; then
        log_info "Attempting connection with password authentication"
        export SSHPASS="$SSH_PASSWORD"
        sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$SSH_USERNAME@$SSH_HOST"
        EXIT_CODE=$?
        
        # Log SSH attempt
        log_ssh "$SSH_HOST" "$SSH_USERNAME" "" $EXIT_CODE
        
        if [ $EXIT_CODE -eq 0 ]; then
            return 0
        else
            log_warning "Password authentication failed"
        fi
    fi
    
    # 3. Last resort: regular SSH (manual password entry)
    log_info "Falling back to regular SSH (manual password entry)"
    log_info "Password can be found in 1Password under 'Test Sensors' > 'Dev Sensor Login'"
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$SSH_USERNAME@$SSH_HOST"
    EXIT_CODE=$?
    
    # Log SSH attempt
    log_ssh "$SSH_HOST" "$SSH_USERNAME" "" $EXIT_CODE
    
    return $EXIT_CODE
}

# Function to run network performance tests
run_tests() {
    log_info "Running Network Performance Tests"
    log_info "--------------------------------"
    
    # Check if we have SSH access
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    
    # Force SSH_HOST for testing (we know it's set from status command)
    SSH_HOST="10.50.88.100"
    log_info "Using sensor IP: $SSH_HOST"
    
    # Define test script path
    TEST_SCRIPT="${SCRIPT_DIR}/scripts/run_network_test.sh"
    
    # Check if test script exists
    if [ ! -f "$TEST_SCRIPT" ]; then
        log_error "Test script not found at $TEST_SCRIPT"
        exit 1
    fi
    
    # First, copy the test script to the sensor
    log_info "Copying test script to sensor..."
    
    # Determine authentication method to use
    SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
    
    if [ -f "$SSH_KEY_PATH" ]; then
        # Try key-based authentication for SCP
        log_debug "Using key-based authentication for SCP"
        scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new "$TEST_SCRIPT" "${SSH_USERNAME}@${SSH_HOST}:/home/${SSH_USERNAME}/run_network_test.sh"
        SCP_EXIT=$?
        
        # Log SCP attempt
        if [ $SCP_EXIT -eq 0 ]; then
            log_info "Successfully copied test script to sensor"
        else
            log_error "Failed to copy test script with key-based authentication"
        fi
    elif [ -n "$SSH_PASSWORD" ] && command -v sshpass &> /dev/null; then
        # Try password-based authentication for SCP
        log_debug "Using password-based authentication for SCP"
        export SSHPASS="$SSH_PASSWORD"
        sshpass -e scp -o StrictHostKeyChecking=accept-new "$TEST_SCRIPT" "${SSH_USERNAME}@${SSH_HOST}:/home/${SSH_USERNAME}/run_network_test.sh"
        SCP_EXIT=$?
        
        # Log SCP attempt
        if [ $SCP_EXIT -eq 0 ]; then
            log_info "Successfully copied test script to sensor"
        else
            log_error "Failed to copy test script with password-based authentication"
        fi
    else
        log_error "Cannot copy test script: No authentication method available"
        log_error "Please run './sensor_lifecycle.sh setup' to configure SSH"
        exit 1
    fi
    
    if [ $SCP_EXIT -ne 0 ]; then
        log_error "Failed to copy test script to sensor"
        exit 1
    fi
    
    # Now run the test script remotely
    log_info "Running network test on sensor..."
    
    if [ -f "$SSH_KEY_PATH" ]; then
        # Try key-based authentication
        log_debug "Running test script with key-based authentication"
        ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new "$SSH_USERNAME@$SSH_HOST" "chmod +x /home/${SSH_USERNAME}/run_network_test.sh && /home/${SSH_USERNAME}/run_network_test.sh"
        SSH_EXIT=$?
        
        # Log SSH command execution
        log_ssh "$SSH_HOST" "$SSH_USERNAME" "chmod +x /home/${SSH_USERNAME}/run_network_test.sh && /home/${SSH_USERNAME}/run_network_test.sh" $SSH_EXIT
    elif [ -n "$SSH_PASSWORD" ] && command -v sshpass &> /dev/null; then
        # Try password-based authentication
        log_debug "Running test script with password-based authentication"
        export SSHPASS="$SSH_PASSWORD"
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "$SSH_USERNAME@$SSH_HOST" "chmod +x /home/${SSH_USERNAME}/run_network_test.sh && /home/${SSH_USERNAME}/run_network_test.sh"
        SSH_EXIT=$?
        
        # Log SSH command execution
        log_ssh "$SSH_HOST" "$SSH_USERNAME" "chmod +x /home/${SSH_USERNAME}/run_network_test.sh && /home/${SSH_USERNAME}/run_network_test.sh" $SSH_EXIT
    else
        log_error "Cannot run test: No authentication method available"
        exit 1
    fi
    
    if [ $SSH_EXIT -eq 0 ]; then
        log_info "Test execution complete."
    else
        log_error "Test execution failed with exit code $SSH_EXIT"
    fi
}

# Function to delete the current sensor
delete_sensor() {
    log_info "Deleting EC2 Sensor"
    log_info "------------------"
    
    # Source environment and check credentials
    source "${SCRIPT_DIR}/scripts/load_env.sh"
    if ! check_env; then
        log_error "Failed to load environment variables. Please run setup first."
        exit 1
    fi
    
    # Check if sensor name is set
    if [ -z "$SENSOR_NAME" ]; then
        log_error "SENSOR_NAME not set in .env file"
        log_error "No sensor to delete"
        exit 1
    fi
    
    log_warning "WARNING: This will permanently delete sensor: $SENSOR_NAME"
    read -p "Are you sure you want to continue? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        log_info "Deletion cancelled"
        exit 0
    fi
    
    log_info "Deleting sensor: $SENSOR_NAME"
    log_info "----------------------------------------"
    
    # Make API request to delete the sensor
    log_debug "Sending API request to delete sensor..."
    response=$(curl -s -X DELETE "${EC2_SENSOR_BASE_URL}/${SENSOR_NAME}" \
        -H "accept: application/json" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${EC2_SENSOR_API_KEY}")
    status=$?
    
    # Log API interaction
    log_api "DELETE" "${EC2_SENSOR_BASE_URL}/${SENSOR_NAME}" "" "${response}" $status
    
    # Check if request was successful
    if [ $status -ne 0 ]; then
        log_error "Failed to make API request"
        exit 1
    fi
    
    # Parse response
    if command -v jq &> /dev/null; then
        echo "$response" | jq '.'
    else
        echo "$response"
        log_warning "jq not found, cannot parse JSON response"
    fi
    
    log_info "----------------------------------------"
    log_info "Sensor deletion requested"
    
    # Reset sensor-specific environment variables
    if grep -q "^SENSOR_NAME=" "${SCRIPT_DIR}/.env"; then
        sed -i.bak "/^SENSOR_NAME=/d" "${SCRIPT_DIR}/.env"
        log_debug "Removed SENSOR_NAME from .env"
    fi
    
    if grep -q "^SSH_HOST=" "${SCRIPT_DIR}/.env"; then
        sed -i.bak "/^SSH_HOST=/d" "${SCRIPT_DIR}/.env"
        log_debug "Removed SSH_HOST from .env"
    fi
    
    if grep -q "^SENSOR_CREATED_AT=" "${SCRIPT_DIR}/.env"; then
        sed -i.bak "/^SENSOR_CREATED_AT=/d" "${SCRIPT_DIR}/.env"
        log_debug "Removed SENSOR_CREATED_AT from .env"
    fi
    
    log_info "Environment reset for new sensor creation"
    log_info "Run './sensor_lifecycle.sh create' to create a new sensor"
}

# Function to reset environment
reset_environment() {
    log_info "Resetting EC2 Sensor Environment"
    log_info "-------------------------------"
    
    # Prompt for confirmation
    read -p "This will reset sensor-specific variables. Continue? (y/n): " confirm
    
    if [ "$confirm" != "y" ]; then
        log_info "Reset cancelled"
        exit 0
    fi
    
    # Reset sensor-specific environment variables but keep credentials
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        # Make a backup
        cp "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/.env.bak"
        log_debug "Created backup of .env file: .env.bak"
        
        # Remove sensor-specific variables
        sed -i.tmp "/^SENSOR_NAME=/d" "${SCRIPT_DIR}/.env"
        sed -i.tmp "/^SSH_HOST=/d" "${SCRIPT_DIR}/.env"
        sed -i.tmp "/^SENSOR_CREATED_AT=/d" "${SCRIPT_DIR}/.env"
        
        # Clean up temporary files
        rm -f "${SCRIPT_DIR}/.env.tmp"
        
        log_info "Environment reset complete"
        log_info "Backup saved as .env.bak"
    else
        log_warning "No .env file found. Nothing to reset."
        log_info "Run './sensor_lifecycle.sh setup' to create initial configuration."
    fi
}

# Function to verify security settings
verify_security() {
    log_info "Verifying EC2 Sensor Security Settings"
    log_info "-------------------------------------"

    # Check .env file permissions
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        perms=$(stat -c "%a" "${SCRIPT_DIR}/.env" 2>/dev/null || stat -f "%Lp" "${SCRIPT_DIR}/.env")
        if [ "$perms" = "600" ]; then
            log_info "✅ .env file permissions: Secure (600)"
        else
            log_warning "⚠️ .env file permissions: Insecure ($perms)"
            log_info "   Fixing permissions..."
            chmod 600 "${SCRIPT_DIR}/.env"
            log_info "✅ Permissions updated to 600"
        fi
    else
        log_warning "⚠️ .env file not found"
        log_info "   Run './sensor_lifecycle.sh setup' to create it"
    fi

    # Check for hardcoded credentials in scripts
    log_info ""
    log_info "Checking for hardcoded credentials..."

    # Look for potential API keys in scripts
    api_key_pattern="[a-zA-Z0-9]{30,}"
    potential_keys=$(grep -r --include="*.sh" "$api_key_pattern" "${SCRIPT_DIR}" | grep -v "api_key_pattern" | grep -v "load_env")

    if [ -n "$potential_keys" ]; then
        log_warning "⚠️ Potential hardcoded API keys found:"
        echo "$potential_keys"
        log_info ""
        log_info "Consider replacing these with environment variables"
    else
        log_info "✅ No hardcoded API keys detected in scripts"
    fi

    # Check for hardcoded IP addresses
    ip_pattern="[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"
    hardcoded_ips=$(grep -r --include="*.sh" "$ip_pattern" "${SCRIPT_DIR}" | grep -v "ip_pattern" | grep -v "load_env" | grep -v "SSH_HOST")

    if [ -n "$hardcoded_ips" ]; then
        log_warning "⚠️ Potential hardcoded IP addresses found:"
        echo "$hardcoded_ips"
        log_info ""
        log_info "Consider replacing these with environment variables"
    else
        log_info "✅ No hardcoded IP addresses detected in scripts"
    fi

    # Check for SSH key permissions if exists
    SSH_KEY_PATH="$HOME/.ssh/ec2_sensor_key"
    if [ -f "$SSH_KEY_PATH" ]; then
        key_perms=$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%Lp" "$SSH_KEY_PATH")
        if [ "$key_perms" = "600" ]; then
            log_info "✅ SSH key file permissions: Secure (600)"
        else
            log_warning "⚠️ SSH key file permissions: Insecure ($key_perms)"
            log_info "   Fix with: chmod 600 $SSH_KEY_PATH"
        fi
    fi

    log_info ""
    log_info "Security verification complete"
    log_debug "Log file location: $(get_log_file)"
}

# Function to troubleshoot SSH connectivity
troubleshoot_connection() {
    log_info "SSH Connection Troubleshooting"
    log_info "-----------------------------"

    # Source environment
    source "${SCRIPT_DIR}/scripts/load_env.sh"

    # Set defaults if environment variables not loaded
    SENSOR_IP="${SSH_HOST:-}"
    SENSOR_USERNAME="${SSH_USERNAME:-broala}"

    if [ -z "$SENSOR_IP" ]; then
        log_error "No sensor IP configured"
        log_info "Run './sensor_lifecycle.sh status' to get the current sensor IP"
        exit 1
    fi

    log_info "Sensor IP: $SENSOR_IP"
    log_info "Username: $SENSOR_USERNAME"
    log_info "Date/Time: $(date)"
    log_info ""

    log_info "0. Checking Tailscale VPN status..."
    if command -v tailscale &> /dev/null; then
        tailscale status | grep -E "(^100\.|corelight)" || log_warning "Tailscale not connected to Corelight network"
    else
        log_warning "Tailscale not found. Install and connect to corelight.com"
    fi

    log_info ""
    log_info "1. Testing network connectivity..."
    if ping -c 3 "$SENSOR_IP" > /dev/null 2>&1; then
        log_info "✅ Sensor is reachable via ping"
    else
        log_error "✗ Cannot reach sensor via ping"
    fi

    log_info ""
    log_info "2. Testing SSH port (22)..."
    if nc -zv "$SENSOR_IP" 22 2>&1 | grep -q succeeded; then
        log_info "✅ SSH port 22 is open"
    else
        log_error "✗ SSH port 22 is not accessible"
    fi

    log_info ""
    log_info "3. Checking if SSH key exists..."
    if [ -f "$HOME/.ssh/ec2_sensor_key" ]; then
        log_info "✅ EC2 sensor key found at $HOME/.ssh/ec2_sensor_key"
        log_info "Testing key authentication..."
        if timeout 5 ssh -i "$HOME/.ssh/ec2_sensor_key" -o StrictHostKeyChecking=accept-new -o BatchMode=yes "$SENSOR_USERNAME@$SENSOR_IP" "echo 'Key auth works'" 2>&1 | grep -q "Key auth works"; then
            log_info "✅ Key authentication successful"
        else
            log_warning "✗ Key authentication failed"
        fi
    else
        log_info "No EC2 sensor key found"
        log_info "Run './scripts/setup_ssh_keys.sh' to set up key-based authentication"
    fi

    log_info ""
    log_info "=== Troubleshooting Summary ==="
    log_info "If you can ping but not SSH, try these solutions:"
    log_info "1. Wait longer: Sensor may still be initializing (15-20 minutes after creation)"
    log_info "2. Verify Tailscale: Make sure you're connected to the Corelight VPN"
    log_info "3. Try connecting: ./sensor_lifecycle.sh connect"
    log_info "4. Check readiness: ./scripts/wait_for_sensor_ready.sh $SENSOR_IP"
    log_info "5. Review logs: grep 'SSH' logs/sensor_lifecycle_*.log"
    log_info ""
    log_info "For detailed help, see docs/SSH_GUIDE.md"
}

# Main script execution
case "$1" in
    setup)
        setup_credentials
        ;;
    create)
        shift  # Remove 'create' from arguments
        create_sensor "$@"  # Pass remaining arguments
        ;;
    enable-features)
        enable_sensor_features
        ;;
    status)
        check_status
        ;;
    connect)
        connect_to_sensor
        ;;
    test)
        run_tests
        ;;
    delete)
        delete_sensor
        ;;
    reset)
        reset_environment
        ;;
    secure)
        verify_security
        ;;
    troubleshoot)
        troubleshoot_connection
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        # No command given - show smart status
        source "${SCRIPT_DIR}/scripts/load_env.sh" 2>/dev/null || true
        load_env 2>/dev/null || true

        echo ""
        echo "======================================"
        echo "  WHAT TO DO"
        echo "======================================"
        echo ""

        if [ -z "${SENSOR_NAME:-}" ]; then
            echo "No sensor exists."
            echo ""
            echo "Run this command:"
            echo "  ./sensor_lifecycle.sh create"
        else
            response=$(curl -s "${EC2_SENSOR_BASE_URL}/${SENSOR_NAME}" -H "x-api-key: ${EC2_SENSOR_API_KEY}" 2>/dev/null || echo '{}')
            status=$(echo "$response" | jq -r '.sensor_status // "unknown"' 2>/dev/null || echo "unknown")
            ip=$(echo "$response" | jq -r '.sensor_ip // "not assigned"' 2>/dev/null || echo "not assigned")

            echo "Current sensor: ${SENSOR_NAME##*-}"
            echo "Status: $status"
            echo "IP: $ip"
            echo ""

            if [ "$status" = "running" ]; then
                echo "✓ Sensor is READY!"
                echo ""
                echo "Connecting now..."
                echo ""

                # Auto-connect
                SSH_HOST="$ip"
                SSH_USERNAME="${SSH_USERNAME:-broala}"
                SSH_PASSWORD="${SSH_PASSWORD:-This#ahNg9Pi}"

                if command -v sshpass &> /dev/null; then
                    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USERNAME@$SSH_HOST"
                else
                    ssh "$SSH_USERNAME@$SSH_HOST"
                fi
                exit 0
            else
                echo "⏳ Sensor is still starting up (takes ~20 min)"
                echo ""
                echo "Run this command again to check:"
                echo "  ./sensor_lifecycle.sh"
            fi
        fi
        echo ""
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Run '$0' to see what to do"
        exit 1
        ;;
esac

# Log script completion
log_debug "Script completed: $0 $1"
exit 0