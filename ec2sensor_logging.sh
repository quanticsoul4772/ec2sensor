#!/bin/bash
#
# EC2 Sensor Logging Module
# Provides logging functionality for the EC2 Sensor project
#

# Default configuration
LOG_DIR="${LOG_DIR:-/Users/russellsmith/Projects/ec2sensor/logs}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10485760}"  # 10MB
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
LOG_STDOUT="${LOG_STDOUT:-true}"

# Log levels (in order of severity)
# Using variables instead of associative array for compatibility
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_FATAL=4

# ANSI color codes
RESET='\033[0m'
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'

# Color mapping for log levels
# Using variables instead of associative array for compatibility
LOG_COLOR_DEBUG="${CYAN}"
LOG_COLOR_INFO="${GREEN}"
LOG_COLOR_WARNING="${YELLOW}"
LOG_COLOR_ERROR="${RED}"
LOG_COLOR_FATAL="${MAGENTA}${BOLD}"

# Global log file path
LOG_FILE=""

# Initialize logging
log_init() {
    local script_name sensor_name
    
    # Create log directory if it doesn't exist
    mkdir -p "${LOG_DIR}"
    
    # Get script name (without path and extension)
    script_name=$(basename "${0%.sh}")
    
    # Get current sensor name from environment if available
    if [ -n "${SENSOR_NAME:-}" ]; then
        sensor_name="_${SENSOR_NAME}"
    else
        sensor_name=""
    fi
    
    # Generate log file name with date and time
    LOG_FILE="${LOG_DIR}/${script_name}${sensor_name}_$(date +%Y%m%d_%H%M%S).log"
    
    # Initialize log file with header
    {
        echo "==== EC2 Sensor Log ====" 
        echo "Script: ${script_name}"
        echo "Date: $(date)"
        echo "Sensor: ${SENSOR_NAME:-N/A}"
        echo "========================="
        echo ""
    } > "${LOG_FILE}"
    
    # Set permissions on log file
    chmod 644 "${LOG_FILE}"
    
    # Clean up old log files
    log_cleanup
    
    # Log initialization
    log_info "Logging initialized: ${LOG_FILE}"
}

# Clean up old log files
log_cleanup() {
    if [ -d "${LOG_DIR}" ]; then
        # Find and delete log files older than LOG_RETENTION_DAYS
        find "${LOG_DIR}" -name "*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null
        
        # Check if any logs were deleted
        if [ $? -eq 0 ]; then
            log_debug "Cleaned up logs older than ${LOG_RETENTION_DAYS} days"
        fi
    fi
}

# Generic logging function
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    local log_entry
    
    # Check if log level is enabled
    local level_num
    local current_level_num
    
    case "$level" in
        DEBUG)   level_num=$LOG_LEVEL_DEBUG ;;
        INFO)    level_num=$LOG_LEVEL_INFO ;;
        WARNING) level_num=$LOG_LEVEL_WARNING ;;
        ERROR)   level_num=$LOG_LEVEL_ERROR ;;
        FATAL)   level_num=$LOG_LEVEL_FATAL ;;
        *)       level_num=$LOG_LEVEL_INFO ;;
    esac
    
    case "$LOG_LEVEL" in
        DEBUG)   current_level_num=$LOG_LEVEL_DEBUG ;;
        INFO)    current_level_num=$LOG_LEVEL_INFO ;;
        WARNING) current_level_num=$LOG_LEVEL_WARNING ;;
        ERROR)   current_level_num=$LOG_LEVEL_ERROR ;;
        FATAL)   current_level_num=$LOG_LEVEL_FATAL ;;
        *)       current_level_num=$LOG_LEVEL_INFO ;;
    esac
    
    if [ "$level_num" -lt "$current_level_num" ]; then
        return 0
    fi
    
    # Get current timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Format log entry
    log_entry="[${timestamp}] [${level}] ${message}"
    
    # Write to log file
    echo "${log_entry}" >> "${LOG_FILE}"
    
    # Write to stdout if enabled
    if [ "${LOG_STDOUT}" = "true" ]; then
        # Use colors in terminal
        local color
        
        case "$level" in
            DEBUG)   color=$LOG_COLOR_DEBUG ;;
            INFO)    color=$LOG_COLOR_INFO ;;
            WARNING) color=$LOG_COLOR_WARNING ;;
            ERROR)   color=$LOG_COLOR_ERROR ;;
            FATAL)   color=$LOG_COLOR_FATAL ;;
            *)       color=$LOG_COLOR_INFO ;;
        esac
        
        echo -e "${color}${log_entry}${RESET}"
    fi
    
    # Handle log rotation if needed
    if [ -f "${LOG_FILE}" ]; then
        local file_size
        file_size=$(stat -f%z "${LOG_FILE}" 2>/dev/null || stat -c%s "${LOG_FILE}" 2>/dev/null)
        
        if [ "${file_size}" -gt "${LOG_MAX_SIZE}" ]; then
            log_rotate
        fi
    fi
}

# Log rotation function
log_rotate() {
    local rotated_file="${LOG_FILE}.$(date +%Y%m%d_%H%M%S).old"
    
    # Rotate the file
    mv "${LOG_FILE}" "${rotated_file}"
    
    # Create a new log file
    log_init
    
    # Log the rotation
    log_info "Log file rotated: ${rotated_file}"
}

# Specific logging functions for each level
log_debug() {
    _log "DEBUG" "$1"
}

log_info() {
    _log "INFO" "$1"
}

log_warning() {
    _log "WARNING" "$1"
}

log_error() {
    _log "ERROR" "$1"
}

log_fatal() {
    _log "FATAL" "$1"
}

# Function to log command execution
log_cmd() {
    local cmd="$1"
    local start_time end_time duration
    
    # Log the command
    log_debug "Executing: ${cmd}"
    
    # Record start time
    start_time=$(date +%s)
    
    # Execute the command and capture output
    local output
    output=$( { $cmd; } 2>&1 )
    local status=$?
    
    # Record end time and calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Log the result
    if [ $status -eq 0 ]; then
        log_debug "Command succeeded (${duration}s): ${cmd}"
        log_debug "Output: ${output}"
    else
        log_error "Command failed (${duration}s, exit code ${status}): ${cmd}"
        log_error "Output: ${output}"
    fi
    
    # Return the original command's exit status
    return $status
}

# Function to log API interactions
log_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local response="$4"
    local status="$5"
    
    # Log the API interaction
    log_info "API ${method} ${endpoint}"
    log_debug "Request: ${data}"
    
    if [ $status -eq 0 ]; then
        log_debug "Response: ${response}"
    else
        log_error "API Error (${status}): ${response}"
    fi
}

# Function to log SSH attempts
log_ssh() {
    local host="$1"
    local user="$2"
    local cmd="$3"
    local status="$4"
    
    # Log the SSH attempt
    if [ -z "$cmd" ]; then
        log_info "SSH connection to ${user}@${host}"
    else
        log_info "SSH command on ${user}@${host}: ${cmd}"
    fi
    
    if [ $status -eq 0 ]; then
        log_debug "SSH successful"
    else
        log_error "SSH failed (exit code ${status})"
    fi
}

# Function to get current log file path
get_log_file() {
    echo "${LOG_FILE}"
}

# Initialize logging if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_init
    log_info "Logging module loaded directly"
fi