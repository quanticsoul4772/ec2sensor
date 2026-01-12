#!/bin/bash
#
# Test Framework Library
# Core functions for test case execution, validation, and reporting
#

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source logging module
export SENSOR_NAME="${SENSOR_NAME:-test-framework}"
source "${PROJECT_ROOT}/ec2sensor_logging.sh"

# Test framework directories
TESTING_DIR="${PROJECT_ROOT}/testing"
TEST_CASES_DIR="${TESTING_DIR}/test_cases"
TEST_RESULTS_DIR="${TESTING_DIR}/test_results"
TEST_LIB_DIR="${TESTING_DIR}/lib"

# Test execution state
declare -g TEST_CASE_NAME=""
declare -g TEST_START_TIME=""
declare -g TEST_RESULTS_FILE=""
declare -g TEST_STEPS_PASSED=0
declare -g TEST_STEPS_FAILED=0
declare -g TEST_STEPS_TOTAL=0

#######################################
# Initialize test execution
# Arguments:
#   $1 - Test case name
# Returns:
#   0 on success, 1 on failure
#######################################
test_init() {
    local test_name="${1:-}"

    if [ -z "$test_name" ]; then
        log_error "Test name required"
        return 1
    fi

    TEST_CASE_NAME="$test_name"
    TEST_START_TIME="$(date +%s)"
    TEST_RESULTS_FILE="${TEST_RESULTS_DIR}/${test_name}_$(date +%Y%m%d_%H%M%S).json"
    TEST_STEPS_PASSED=0
    TEST_STEPS_FAILED=0
    TEST_STEPS_TOTAL=0

    log_info "Initializing test: $test_name"
    log_info "Results will be saved to: $TEST_RESULTS_FILE"

    # Create results file
    cat > "$TEST_RESULTS_FILE" <<EOF
{
  "test_case": "$test_name",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "in_progress",
  "steps": []
}
EOF

    return 0
}

#######################################
# Execute a test step with SSH command
# Arguments:
#   $1 - Step number
#   $2 - Step description
#   $3 - Sensor IP
#   $4 - Command to execute
#   $5 - Expected outcome (optional)
# Returns:
#   0 if step passed, 1 if failed
#######################################
test_step() {
    local step_num="${1:-}"
    local description="${2:-}"
    local sensor_ip="${3:-}"
    local command="${4:-}"
    local expected="${5:-}"

    log_info "Step $step_num: $description"

    ((TEST_STEPS_TOTAL++))

    local step_start=$(date +%s)
    local result_code=0
    local output=""
    local error=""

    # Execute SSH command
    if [ -n "${SSH_PASSWORD:-}" ] && command -v sshpass &> /dev/null; then
        export SSHPASS="${SSH_PASSWORD}"
        output=$(sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
            "broala@${sensor_ip}" "$command" 2>&1) || result_code=$?
    else
        log_error "SSH password not available or sshpass not installed"
        result_code=1
        error="SSH authentication failed"
    fi

    local step_end=$(date +%s)
    local duration=$((step_end - step_start))

    # Determine if step passed
    local step_status="passed"
    if [ $result_code -ne 0 ]; then
        step_status="failed"
        ((TEST_STEPS_FAILED++))
        log_error "Step $step_num FAILED (exit code: $result_code)"
    else
        # Check expected outcome if provided
        if [ -n "$expected" ]; then
            if echo "$output" | grep -q "$expected"; then
                ((TEST_STEPS_PASSED++))
                log_info "Step $step_num PASSED (matched expected: $expected)"
            else
                step_status="failed"
                ((TEST_STEPS_FAILED++))
                log_error "Step $step_num FAILED (output did not match expected: $expected)"
            fi
        else
            ((TEST_STEPS_PASSED++))
            log_info "Step $step_num PASSED"
        fi
    fi

    # Add step result to JSON file
    local temp_file="${TEST_RESULTS_FILE}.tmp"
    jq --arg num "$step_num" \
       --arg desc "$description" \
       --arg cmd "$command" \
       --arg status "$step_status" \
       --arg output "$output" \
       --arg error "$error" \
       --arg duration "$duration" \
       --arg expected "$expected" \
       '.steps += [{
          "step": ($num | tonumber),
          "description": $desc,
          "command": $cmd,
          "status": $status,
          "output": $output,
          "error": $error,
          "duration_seconds": ($duration | tonumber),
          "expected": $expected,
          "timestamp": (now | todate)
       }]' "$TEST_RESULTS_FILE" > "$temp_file"
    mv "$temp_file" "$TEST_RESULTS_FILE"

    [ "$step_status" = "passed" ] && return 0 || return 1
}

#######################################
# Validate test result
# Arguments:
#   $1 - Actual value
#   $2 - Expected value
#   $3 - Validation type (equals|contains|regex)
# Returns:
#   0 if validation passed, 1 if failed
#######################################
test_validate() {
    local actual="${1:-}"
    local expected="${2:-}"
    local validation_type="${3:-equals}"

    case "$validation_type" in
        equals)
            [ "$actual" = "$expected" ] && return 0 || return 1
            ;;
        contains)
            echo "$actual" | grep -q "$expected" && return 0 || return 1
            ;;
        regex)
            echo "$actual" | grep -Eq "$expected" && return 0 || return 1
            ;;
        *)
            log_error "Unknown validation type: $validation_type"
            return 1
            ;;
    esac
}

#######################################
# Finalize test execution
# Arguments:
#   None
# Returns:
#   0 on success
#######################################
test_finalize() {
    local test_end_time=$(date +%s)
    local total_duration=$((test_end_time - TEST_START_TIME))

    # Determine overall test status
    local overall_status="passed"
    if [ $TEST_STEPS_FAILED -gt 0 ]; then
        overall_status="failed"
    fi

    log_info "Test completed: $overall_status"
    log_info "Steps: $TEST_STEPS_PASSED passed, $TEST_STEPS_FAILED failed, $TEST_STEPS_TOTAL total"
    log_info "Duration: ${total_duration}s"

    # Update results file with final status
    local temp_file="${TEST_RESULTS_FILE}.tmp"
    jq --arg status "$overall_status" \
       --arg passed "$TEST_STEPS_PASSED" \
       --arg failed "$TEST_STEPS_FAILED" \
       --arg total "$TEST_STEPS_TOTAL" \
       --arg duration "$total_duration" \
       --arg ended "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.status = $status |
        .steps_passed = ($passed | tonumber) |
        .steps_failed = ($failed | tonumber) |
        .steps_total = ($total | tonumber) |
        .duration_seconds = ($duration | tonumber) |
        .completed_at = $ended' "$TEST_RESULTS_FILE" > "$temp_file"
    mv "$temp_file" "$TEST_RESULTS_FILE"

    # Generate markdown report
    local md_file="${TEST_RESULTS_DIR}/${TEST_CASE_NAME}_$(date +%Y%m%d_%H%M%S).md"
    cat > "$md_file" <<EOF
# Test Report: ${TEST_CASE_NAME}

**Status**: ${overall_status^^} ✅
**Date**: $(date +%Y-%m-%d\ %H:%M:%S)
**Duration**: ${total_duration}s

## Summary

- **Steps Passed**: ${TEST_STEPS_PASSED}
- **Steps Failed**: ${TEST_STEPS_FAILED}
- **Total Steps**: ${TEST_STEPS_TOTAL}

## Test Steps

EOF

    # Add each step to markdown
    local step_count=$(jq '.steps | length' "$TEST_RESULTS_FILE")
    for ((i=0; i<step_count; i++)); do
        local step_num=$(jq -r ".steps[$i].step" "$TEST_RESULTS_FILE")
        local step_desc=$(jq -r ".steps[$i].description" "$TEST_RESULTS_FILE")
        local step_status=$(jq -r ".steps[$i].status" "$TEST_RESULTS_FILE")
        local step_cmd=$(jq -r ".steps[$i].command" "$TEST_RESULTS_FILE")
        local step_output=$(jq -r ".steps[$i].output" "$TEST_RESULTS_FILE")

        local status_emoji="✅"
        [ "$step_status" = "failed" ] && status_emoji="❌"

        cat >> "$md_file" <<EOF
### Step ${step_num}: ${step_desc} ${status_emoji}

\`\`\`bash
${step_cmd}
\`\`\`

<details>
<summary>Output</summary>

\`\`\`
${step_output}
\`\`\`

</details>

EOF
    done

    log_info "Markdown report: $md_file"

    return 0
}

#######################################
# Get sensor configuration value
# Arguments:
#   $1 - Sensor IP
#   $2 - Configuration key
# Returns:
#   Configuration value
#######################################
get_sensor_config() {
    local sensor_ip="${1:-}"
    local config_key="${2:-}"

    if [ -z "$sensor_ip" ] || [ -z "$config_key" ]; then
        log_error "Sensor IP and config key required"
        return 1
    fi

    # Detect API version
    local api_version="legacy"
    if sshpass -e ssh -o StrictHostKeyChecking=accept-new "broala@${sensor_ip}" "which corelightctl" >/dev/null 2>&1; then
        api_version="modern"
    fi

    export SSHPASS="${SSH_PASSWORD}"

    if [ "$api_version" = "modern" ]; then
        # Modern API: corelightctl sensor configuration get
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "broala@${sensor_ip}" \
            "sudo corelightctl sensor configuration get -o yaml | grep '^${config_key}:' | awk '{print \$2}'"
    else
        # Legacy API: broala-config
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "broala@${sensor_ip}" \
            "sudo broala-config get ${config_key}"
    fi
}

#######################################
# Set sensor configuration value
# Arguments:
#   $1 - Sensor IP
#   $2 - Configuration key
#   $3 - Configuration value
# Returns:
#   0 on success, 1 on failure
#######################################
set_sensor_config() {
    local sensor_ip="${1:-}"
    local config_key="${2:-}"
    local config_value="${3:-}"

    if [ -z "$sensor_ip" ] || [ -z "$config_key" ] || [ -z "$config_value" ]; then
        log_error "Sensor IP, config key, and value required"
        return 1
    fi

    # Detect API version
    local api_version="legacy"
    if sshpass -e ssh -o StrictHostKeyChecking=accept-new "broala@${sensor_ip}" "which corelightctl" >/dev/null 2>&1; then
        api_version="modern"
    fi

    export SSHPASS="${SSH_PASSWORD}"

    if [ "$api_version" = "modern" ]; then
        # Modern API: export, modify, import
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "broala@${sensor_ip}" bash <<EOF
sudo corelightctl sensor configuration get -o yaml > /tmp/config.yaml
sudo sed -i 's/^${config_key}:.*/${config_key}: "${config_value}"/' /tmp/config.yaml
sudo corelightctl sensor configuration put -f /tmp/config.yaml
EOF
    else
        # Legacy API: broala-config
        sshpass -e ssh -o StrictHostKeyChecking=accept-new "broala@${sensor_ip}" \
            "sudo broala-config set ${config_key}=${config_value} && sudo broala-apply-config -q"
    fi
}

# Export functions
export -f test_init
export -f test_step
export -f test_validate
export -f test_finalize
export -f get_sensor_config
export -f set_sensor_config
