#!/bin/bash

# Function to securely load environment variables
load_env() {
    # Get script directory for absolute paths (use unique variable name to avoid clobbering)
    local ENV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ENV_FILE="${ENV_SCRIPT_DIR}/../.env"
    
    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        echo "Error: .env file not found at $ENV_FILE!"
        echo "Please copy .env.template to .env and configure your settings."
        return 1
    fi
    
    # Load environment variables from .env file
    set -a
    source "$ENV_FILE"
    set +a
    
    # Validate required variables
    if [ -z "$EC2_SENSOR_API_KEY" ]; then
        echo "Error: EC2_SENSOR_API_KEY not set in .env file"
        return 1
    fi
    
    if [ -z "$EC2_SENSOR_BASE_URL" ]; then
        echo "Error: EC2_SENSOR_BASE_URL not set in .env file"
        return 1
    fi
    
    return 0
}

# Function to check if env is loaded
check_env() {
    if [ -z "$EC2_SENSOR_API_KEY" ] || [ -z "$EC2_SENSOR_BASE_URL" ]; then
        echo "Environment variables not loaded. Loading now..."
        load_env
        return $?
    fi
    return 0
}
