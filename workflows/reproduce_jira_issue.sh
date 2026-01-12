#!/bin/bash
################################################################################
# JIRA Issue Reproduction Workflow
#
# Complete automated workflow for reproducing a JIRA issue on an EC2 sensor
#
# Usage:
#   ./workflows/reproduce_jira_issue.sh <JIRA_TICKET> [OPTIONS]
#
# Options:
#   --dry-run         Simulate workflow without executing
#   --no-cleanup      Don't delete sensor after completion
#   --config <name>   Override sensor configuration profile
#   --resume          Resume from previous interrupted run
#
# Example:
#   ./workflows/reproduce_jira_issue.sh CORE-5432
#   ./workflows/reproduce_jira_issue.sh CORE-5432 --dry-run
#   ./workflows/reproduce_jira_issue.sh CORE-5432 --config smartpcap_enabled
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source logging
source "$PROJECT_ROOT/ec2sensor_logging.sh"
log_init

# Workflow metadata
WORKFLOW_NAME="reproduce_jira_issue"
WORKFLOW_ID="workflow-$(date +%Y%m%d-%H%M%S)"
WORKFLOW_START_TIME=$(date +%s)

# State management
STATE_DIR="$PROJECT_ROOT/.workflow_state"
WORKFLOW_STATE_FILE="$STATE_DIR/${WORKFLOW_NAME}_\${JIRA_TICKET}.state"

# Results
RESULTS_DIR="$PROJECT_ROOT/testing/test_results"
WORKFLOW_LOG="$PROJECT_ROOT/logs/${WORKFLOW_NAME}_$(date +%Y%m%d_%H%M%S).log"

# Options
DRY_RUN=false
AUTO_CLEANUP=true
SENSOR_CONFIG="default"
RESUME=false

################################################################################
# Usage
################################################################################

usage() {
    cat << EOF
JIRA Issue Reproduction Workflow

Usage:
    $0 <JIRA_TICKET> [OPTIONS]

Arguments:
    JIRA_TICKET     JIRA ticket ID (e.g., CORE-5432)

Options:
    --dry-run       Simulate workflow without executing
    --no-cleanup    Don't delete sensor after completion
    --config NAME   Override sensor configuration profile (default: default)
    --resume        Resume from previous interrupted run
    --help          Show this help message

Examples:
    $0 CORE-5432
    $0 CORE-5432 --dry-run
    $0 CORE-5432 --config smartpcap_enabled --no-cleanup

Workflow Steps:
    1. Fetch JIRA issue details
    2. Determine sensor requirements
    3. Deploy sensor
    4. Prepare sensor (features + packages)
    5. Execute test case
    6. Collect results
    7. Sync to MCP (Obsidian + Memory + Exa)
    8. Generate report

Output:
    - Test results: $RESULTS_DIR/
    - Workflow log: $WORKFLOW_LOG
    - Obsidian note: ~/obsidian/corelight/Test-Executions/

EOF
}

################################################################################
# Parse Arguments
################################################################################

parse_args() {
    if [ $# -eq 0 ]; then
        log_error "No JIRA ticket provided"
        usage
        exit 1
    fi

    JIRA_TICKET="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log_info "DRY-RUN mode enabled"
                shift
                ;;
            --no-cleanup)
                AUTO_CLEANUP=false
                shift
                ;;
            --config)
                SENSOR_CONFIG="$2"
                shift 2
                ;;
            --resume)
                RESUME=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Update state file path
    WORKFLOW_STATE_FILE="$STATE_DIR/${WORKFLOW_NAME}_${JIRA_TICKET}.state"
}

################################################################################
# State Management
################################################################################

save_state() {
    local current_step=$1
    local total_steps=$2

    mkdir -p "$STATE_DIR"

    cat > "$WORKFLOW_STATE_FILE" <<EOF
{
  "workflow_id": "$WORKFLOW_ID",
  "workflow_name": "$WORKFLOW_NAME",
  "jira_ticket": "$JIRA_TICKET",
  "current_step": $current_step,
  "total_steps": $total_steps,
  "sensor_deployed": ${SENSOR_DEPLOYED:-false},
  "sensor_ip": "${SENSOR_IP:-unknown}",
  "sensor_stack": "${SENSOR_STACK:-unknown}",
  "test_id": "${TEST_ID:-unknown}",
  "can_resume": true,
  "last_updated": "$(date -Iseconds)"
}
EOF

    log_debug "State saved: step $current_step/$total_steps"
}

load_state() {
    if [ -f "$WORKFLOW_STATE_FILE" ]; then
        log_info "Found previous workflow state"

        local prev_step=$(jq -r '.current_step' "$WORKFLOW_STATE_FILE")
        local can_resume=$(jq -r '.can_resume' "$WORKFLOW_STATE_FILE")

        if [ "$can_resume" = "true" ]; then
            if [ "$RESUME" = "true" ]; then
                log_info "Resuming from step $prev_step"
                CURRENT_STEP=$prev_step

                # Load previous values
                SENSOR_DEPLOYED=$(jq -r '.sensor_deployed' "$WORKFLOW_STATE_FILE")
                SENSOR_IP=$(jq -r '.sensor_ip' "$WORKFLOW_STATE_FILE")
                SENSOR_STACK=$(jq -r '.sensor_stack' "$WORKFLOW_STATE_FILE")
                TEST_ID=$(jq -r '.test_id' "$WORKFLOW_STATE_FILE")

                return 0
            else
                log_warning "Previous workflow found. Use --resume to continue from step $prev_step"
            fi
        fi
    fi

    CURRENT_STEP=1
}

clean_state() {
    if [ -f "$WORKFLOW_STATE_FILE" ]; then
        rm -f "$WORKFLOW_STATE_FILE"
        log_debug "State file cleaned"
    fi
}

################################################################################
# Validation
################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check VPN connection
    if ! tailscale status >/dev/null 2>&1; then
        log_error "Not connected to Tailscale VPN"
        log_error "Run: tailscale up"
        exit 1
    fi
    log_success "VPN: Connected"

    # Check required tools
    local required_tools=("jq" "curl" "ssh" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    log_success "Tools: All required tools available"

    # Check .env file
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log_error ".env file not found"
        log_error "Copy .env.template and configure your credentials"
        exit 1
    fi
    log_success "Configuration: .env file found"

    # Check test framework
    if [ ! -f "$PROJECT_ROOT/testing/run_test.sh" ]; then
        log_error "Test framework not found: testing/run_test.sh"
        exit 1
    fi
    log_success "Test Framework: Available"

    # Check MCP integration
    if [ ! -f "$PROJECT_ROOT/mcp_integration/mcp_manager.py" ]; then
        log_warning "MCP integration not found (optional)"
    else
        log_success "MCP Integration: Available"
    fi

    log_success "All prerequisites validated"
}

################################################################################
# Workflow Steps
################################################################################

step_1_fetch_jira_details() {
    log_info "[1/8] Fetching JIRA issue details: $JIRA_TICKET"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would fetch JIRA issue: $JIRA_TICKET"
        JIRA_SUMMARY="Sample JIRA issue"
        return 0
    fi

    # Try to find test case matching JIRA ticket
    local test_case_file=$(find "$PROJECT_ROOT/testing/test_cases" -name "*${JIRA_TICKET}*.yaml" -o -name "*${JIRA_TICKET}*.yml" 2>/dev/null | head -1)

    if [ -z "$test_case_file" ]; then
        log_warning "No test case found for $JIRA_TICKET"
        log_info "Available test cases:"
        find "$PROJECT_ROOT/testing/test_cases" -name "*.yaml" -o -name "*.yml" | sed 's/.*\//  - /'
        log_error "Please create a test case YAML file for $JIRA_TICKET"
        exit 1
    fi

    TEST_CASE_FILE="$test_case_file"
    TEST_ID=$(basename "$test_case_file" | sed 's/\.ya\?ml$//')

    log_success "Found test case: $TEST_ID"
    log_info "Test case file: $TEST_CASE_FILE"

    # Parse test case metadata
    JIRA_SUMMARY=$(yq eval '.metadata.title // "Unknown"' "$TEST_CASE_FILE" 2>/dev/null || echo "Unknown")

    log_success "JIRA details fetched"

    save_state 1 8
}

step_2_determine_sensor_requirements() {
    log_info "[2/8] Determining sensor requirements"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would determine sensor config: $SENSOR_CONFIG"
        return 0
    fi

    # Check if test case specifies a sensor config
    local test_config=$(yq eval '.sensor.config // "default"' "$TEST_CASE_FILE" 2>/dev/null || echo "default")

    # Override with command-line option if provided
    if [ "$SENSOR_CONFIG" != "default" ]; then
        log_info "Using command-line config override: $SENSOR_CONFIG"
    else
        SENSOR_CONFIG="$test_config"
        log_info "Using test case config: $SENSOR_CONFIG"
    fi

    # Check if config file exists
    local config_file="$PROJECT_ROOT/sensor_prep/configs/${SENSOR_CONFIG}.yaml"
    if [ ! -f "$config_file" ]; then
        log_error "Sensor config not found: $config_file"
        log_info "Available configs:"
        ls "$PROJECT_ROOT/sensor_prep/configs/"*.yaml | sed 's/.*\//  - /' | sed 's/\.yaml$//'
        exit 1
    fi

    log_success "Sensor requirements determined: $SENSOR_CONFIG"

    save_state 2 8
}

step_3_deploy_sensor() {
    log_info "[3/8] Deploying sensor with config: $SENSOR_CONFIG"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would deploy sensor with config: $SENSOR_CONFIG"
        SENSOR_DEPLOYED=true
        SENSOR_IP="10.50.88.154"
        SENSOR_STACK="ec2-sensor-testing-qa-qarelease-TEST"
        return 0
    fi

    # Deploy sensor using sensor_lifecycle.sh
    log_info "Creating sensor deployment..."
    if ! "$PROJECT_ROOT/sensor_lifecycle.sh" create; then
        log_error "Sensor deployment failed"
        exit 1
    fi

    SENSOR_DEPLOYED=true

    # Wait for sensor to be ready
    log_info "Waiting for sensor to be ready (this may take 15-20 minutes)..."
    local max_wait=1200  # 20 minutes
    local waited=0
    local check_interval=30

    while [ $waited -lt $max_wait ]; do
        if "$PROJECT_ROOT/sensor_lifecycle.sh" status | grep -q "running"; then
            log_success "Sensor is ready!"
            break
        fi

        log_info "Sensor not ready yet, waiting ${check_interval}s... ($waited/$max_wait seconds elapsed)"
        sleep $check_interval
        waited=$((waited + check_interval))
    done

    if [ $waited -ge $max_wait ]; then
        log_error "Sensor did not become ready within $max_wait seconds"
        exit 1
    fi

    # Get sensor details from .env
    source "$PROJECT_ROOT/.env"
    SENSOR_IP="${SSH_HOST:-unknown}"
    SENSOR_STACK="${SENSOR_NAME:-unknown}"

    log_success "Sensor deployed successfully"
    log_info "Sensor IP: $SENSOR_IP"
    log_info "Sensor stack: $SENSOR_STACK"

    save_state 3 8
}

step_4_prepare_sensor() {
    log_info "[4/8] Preparing sensor (features + packages)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would prepare sensor with:"
        log_info "[DRY-RUN]   - Enable sensor features"
        log_info "[DRY-RUN]   - Install required packages"
        return 0
    fi

    # Run sensor preparation script
    log_info "Running sensor preparation script..."
    if ! "$PROJECT_ROOT/sensor_prep/prepare_sensor.sh" --config "$SENSOR_CONFIG"; then
        log_error "Sensor preparation failed"
        exit 1
    fi

    log_success "Sensor prepared successfully"

    save_state 4 8
}

step_5_execute_test() {
    log_info "[5/8] Executing test case: $TEST_ID"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would execute test: $TEST_ID"
        log_info "[DRY-RUN] Test case file: $TEST_CASE_FILE"
        TEST_RESULT="passed"
        TEST_RESULT_FILE="$RESULTS_DIR/${TEST_ID}_$(date +%Y%m%d_%H%M%S).json"
        return 0
    fi

    # Execute test using test runner
    log_info "Running test: $TEST_ID"
    if ! "$PROJECT_ROOT/testing/run_test.sh" --test-file "$TEST_CASE_FILE"; then
        log_warning "Test execution completed with failures"
        TEST_RESULT="failed"
    else
        TEST_RESULT="passed"
    fi

    # Find the most recent test result file
    TEST_RESULT_FILE=$(find "$RESULTS_DIR" -name "${TEST_ID}_*.json" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

    if [ -z "$TEST_RESULT_FILE" ]; then
        log_error "Test result file not found"
        exit 1
    fi

    log_success "Test execution complete: $TEST_RESULT"
    log_info "Results: $TEST_RESULT_FILE"

    save_state 5 8
}

step_6_collect_artifacts() {
    log_info "[6/8] Collecting test artifacts"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would collect artifacts"
        return 0
    fi

    # Artifacts are already collected by test framework
    # Just verify they exist

    if [ -f "$TEST_RESULT_FILE" ]; then
        log_success "Test result JSON: $(basename "$TEST_RESULT_FILE")"
    fi

    local md_file="${TEST_RESULT_FILE%.json}.md"
    if [ -f "$md_file" ]; then
        log_success "Test result Markdown: $(basename "$md_file")"
    fi

    log_success "Artifacts collected"

    save_state 6 8
}

step_7_sync_mcp() {
    log_info "[7/8] Syncing to MCP (Obsidian + Memory + Exa)"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would sync to MCP systems"
        return 0
    fi

    # Check if MCP integration is available
    if [ ! -f "$PROJECT_ROOT/mcp_integration/mcp_manager.py" ]; then
        log_warning "MCP integration not available, skipping sync"
        return 0
    fi

    # Prepare sensor deployment info for MCP
    local sensor_deployed_at=$(date -Iseconds)
    local sensor_delete_at=$(date -d "+4 days" -Iseconds 2>/dev/null || date -v+4d -Iseconds)

    # Call MCP manager
    log_info "Syncing to MCP systems..."
    cd "$PROJECT_ROOT/mcp_integration"

    python3 << EOF
from mcp_manager import MCPManager

mcp = MCPManager()

sensor_deployment = {
    'stack_name': '$SENSOR_STACK',
    'ip': '$SENSOR_IP',
    'version': 'BroLin 28.4.0-a7',  # TODO: Get from sensor status
    'deployed_at': '$sensor_deployed_at',
    'delete_at': '$sensor_delete_at',
    'configuration': '$SENSOR_CONFIG'
}

result = mcp.record_test_execution(
    test_id='$TEST_ID',
    jira_ticket='$JIRA_TICKET',
    result_file='$TEST_RESULT_FILE',
    sensor_deployment=sensor_deployment
)

print(f"MCP Sync: {'Success' if result['success'] else 'Failed'}")
EOF

    cd "$PROJECT_ROOT"

    log_success "MCP sync complete"

    save_state 7 8
}

step_8_generate_report() {
    log_info "[8/8] Generating workflow report"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would generate report"
        return 0
    fi

    local workflow_end_time=$(date +%s)
    local workflow_duration=$((workflow_end_time - WORKFLOW_START_TIME))

    # Generate JSON report
    local report_file="$RESULTS_DIR/workflow_${JIRA_TICKET}_$(date +%Y%m%d_%H%M%S).json"

    cat > "$report_file" <<EOF
{
  "workflow_name": "$WORKFLOW_NAME",
  "workflow_id": "$WORKFLOW_ID",
  "jira_ticket": "$JIRA_TICKET",
  "started_at": "$(date -d @$WORKFLOW_START_TIME -Iseconds 2>/dev/null || date -r $WORKFLOW_START_TIME -Iseconds)",
  "completed_at": "$(date -Iseconds)",
  "duration_seconds": $workflow_duration,
  "status": "success",
  "steps_completed": 8,
  "steps_total": 8,
  "sensor": {
    "stack_name": "$SENSOR_STACK",
    "ip": "$SENSOR_IP",
    "config": "$SENSOR_CONFIG"
  },
  "test": {
    "test_id": "$TEST_ID",
    "result": "$TEST_RESULT",
    "result_file": "$TEST_RESULT_FILE"
  },
  "artifacts": [
    "$TEST_RESULT_FILE",
    "${TEST_RESULT_FILE%.json}.md",
    "$WORKFLOW_LOG",
    "$report_file"
  ]
}
EOF

    log_success "Workflow report generated: $report_file"

    # Generate Markdown summary
    local md_report="${report_file%.json}.md"

    cat > "$md_report" <<EOF
# Workflow Report: $JIRA_TICKET

**Workflow**: $WORKFLOW_NAME
**JIRA**: $JIRA_TICKET
**Date**: $(date)
**Duration**: ${workflow_duration}s ($(date -d@$workflow_duration -u +%M:%S 2>/dev/null || echo "${workflow_duration}s"))

## Results

- **Test**: $TEST_ID
- **Status**: $TEST_RESULT
- **Sensor Config**: $SENSOR_CONFIG

## Sensor Details

- **Stack**: $SENSOR_STACK
- **IP**: $SENSOR_IP
- **Config**: $SENSOR_CONFIG

## Artifacts

- Test Results: $TEST_RESULT_FILE
- Test Report: ${TEST_RESULT_FILE%.json}.md
- Workflow Report: $report_file
- Workflow Log: $WORKFLOW_LOG

## Workflow Steps

1. ✅ Fetch JIRA details
2. ✅ Determine sensor requirements
3. ✅ Deploy sensor
4. ✅ Prepare sensor
5. ✅ Execute test
6. ✅ Collect artifacts
7. ✅ Sync to MCP
8. ✅ Generate report

---

*Generated by $WORKFLOW_NAME at $(date)*
EOF

    log_success "Markdown report generated: $md_report"

    save_state 8 8
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    local exit_code=$?

    log_info "Cleaning up workflow resources..."

    # Clean state file on successful completion
    if [ $exit_code -eq 0 ] && [ "${CURRENT_STEP:-0}" -eq 8 ]; then
        clean_state
        log_info "Workflow completed successfully"
    else
        log_warning "Workflow interrupted or failed at step ${CURRENT_STEP:-unknown}"
        log_info "Use --resume to continue from this point"
    fi

    # Optionally delete sensor
    if [ "$AUTO_CLEANUP" = "true" ] && [ "${SENSOR_DEPLOYED:-false}" = "true" ]; then
        log_info "Auto-cleanup enabled, deleting sensor..."
        "$PROJECT_ROOT/sensor_lifecycle.sh" delete || log_warning "Sensor deletion failed"
    else
        log_info "Sensor preserved (use --no-cleanup to keep sensor)"
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

################################################################################
# Main Workflow
################################################################################

main() {
    log_info "=========================================="
    log_info "JIRA Issue Reproduction Workflow"
    log_info "=========================================="
    log_info "Workflow ID: $WORKFLOW_ID"
    echo

    # Parse arguments
    parse_args "$@"

    log_info "JIRA Ticket: $JIRA_TICKET"
    log_info "Sensor Config: $SENSOR_CONFIG"
    log_info "Auto Cleanup: $AUTO_CLEANUP"
    echo

    # Validate prerequisites
    validate_prerequisites
    echo

    # Load previous state if resuming
    load_state

    # Execute workflow steps
    [ ${CURRENT_STEP:-1} -le 1 ] && step_1_fetch_jira_details
    [ ${CURRENT_STEP:-1} -le 2 ] && step_2_determine_sensor_requirements
    [ ${CURRENT_STEP:-1} -le 3 ] && step_3_deploy_sensor
    [ ${CURRENT_STEP:-1} -le 4 ] && step_4_prepare_sensor
    [ ${CURRENT_STEP:-1} -le 5 ] && step_5_execute_test
    [ ${CURRENT_STEP:-1} -le 6 ] && step_6_collect_artifacts
    [ ${CURRENT_STEP:-1} -le 7 ] && step_7_sync_mcp
    [ ${CURRENT_STEP:-1} -le 8 ] && step_8_generate_report

    echo
    log_success "=========================================="
    log_success "Workflow Complete!"
    log_success "=========================================="
    log_info "Results available at:"
    log_info "  - Test results: $TEST_RESULT_FILE"
    log_info "  - Workflow log: $WORKFLOW_LOG"
    if [ -d ~/obsidian/corelight ]; then
        log_info "  - Obsidian: ~/obsidian/corelight/Test-Executions/"
    fi
}

main "$@"
