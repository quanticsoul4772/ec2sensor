#!/bin/bash
################################################################################
# Fix Validation Workflow
#
# Validates that a fix resolves a previously reported JIRA issue
#
# Usage:
#   ./workflows/validate_fix.sh <JIRA_TICKET> --fixed-version <AMI_ID> [OPTIONS]
#
# Options:
#   --fixed-version <ami>  AMI ID or version of the fixed sensor
#   --baseline <file>      Path to baseline failure result (auto-detected if not provided)
#   --dry-run             Simulate workflow without executing
#   --no-cleanup          Don't delete sensor after completion
#
# Example:
#   ./workflows/validate_fix.sh CORE-5432 --fixed-version ami-0ff8677e76736570b
#   ./workflows/validate_fix.sh CORE-5432 --fixed-version ami-xyz --baseline testing/test_results/TEST-001_20251010.json
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
WORKFLOW_NAME="validate_fix"
WORKFLOW_ID="workflow-$(date +%Y%m%d-%H%M%S)"
WORKFLOW_START_TIME=$(date +%s)

# Results
RESULTS_DIR="$PROJECT_ROOT/testing/test_results"
WORKFLOW_LOG="$PROJECT_ROOT/logs/${WORKFLOW_NAME}_$(date +%Y%m%d_%H%M%S).log"

# Options
DRY_RUN=false
AUTO_CLEANUP=true
FIXED_VERSION=""
BASELINE_FILE=""

################################################################################
# Usage
################################################################################

usage() {
    cat << EOF
Fix Validation Workflow

Validates that a fix resolves a previously reported JIRA issue by comparing
test results before and after the fix.

Usage:
    $0 <JIRA_TICKET> --fixed-version <AMI_ID> [OPTIONS]

Arguments:
    JIRA_TICKET       JIRA ticket ID (e.g., CORE-5432)
    --fixed-version   AMI ID or version with the fix applied

Options:
    --baseline FILE   Path to baseline failure result (auto-detected if omitted)
    --dry-run         Simulate workflow without executing
    --no-cleanup      Don't delete sensor after completion
    --help            Show this help message

Validation Status:
    FIXED            - Previously failed, now passes ✅
    STILL_FAILING    - Still fails with same error ❌
    REGRESSED        - Fails with different error ⚠️
    NEW_ISSUE        - Passes but with warnings ⚠️

Examples:
    $0 CORE-5432 --fixed-version ami-0ff8677e76736570b
    $0 CORE-5432 --fixed-version ami-xyz --baseline results/TEST-001_original.json
    $0 CORE-5432 --fixed-version ami-xyz --dry-run

Output:
    - Validation report: $RESULTS_DIR/validation_<JIRA>_<timestamp>.json
    - Comparison report: $RESULTS_DIR/validation_<JIRA>_<timestamp>.md
    - Workflow log: $WORKFLOW_LOG

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
            --fixed-version)
                FIXED_VERSION="$2"
                shift 2
                ;;
            --baseline)
                BASELINE_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-cleanup)
                AUTO_CLEANUP=false
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

    # Validate required arguments
    if [ -z "$FIXED_VERSION" ]; then
        log_error "Missing required argument: --fixed-version"
        usage
        exit 1
    fi
}

################################################################################
# Validation
################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check VPN
    if ! tailscale status >/dev/null 2>&1; then
        log_error "Not connected to Tailscale VPN"
        exit 1
    fi
    log_success "VPN: Connected"

    # Check tools
    local required_tools=("jq" "curl" "ssh" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    log_success "Tools: Available"

    log_success "Prerequisites validated"
}

################################################################################
# Workflow Steps
################################################################################

step_1_find_baseline() {
    log_info "[1/6] Finding baseline failure result for $JIRA_TICKET"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would search for baseline result"
        BASELINE_FILE="$RESULTS_DIR/TEST-001_baseline.json"
        TEST_ID="TEST-001"
        return 0
    fi

    # If baseline provided, use it
    if [ -n "$BASELINE_FILE" ]; then
        if [ ! -f "$BASELINE_FILE" ]; then
            log_error "Baseline file not found: $BASELINE_FILE"
            exit 1
        fi
        log_info "Using provided baseline: $BASELINE_FILE"
    else
        # Auto-detect baseline: find most recent test result for this JIRA
        log_info "Auto-detecting baseline result..."

        # Find test case for this JIRA
        local test_case=$(find "$PROJECT_ROOT/testing/test_cases" -name "*${JIRA_TICKET}*.yaml" -o -name "*${JIRA_TICKET}*.yml" 2>/dev/null | head -1)

        if [ -z "$test_case" ]; then
            log_error "No test case found for $JIRA_TICKET"
            exit 1
        fi

        TEST_ID=$(basename "$test_case" | sed 's/\.ya\?ml$//')
        log_info "Test case: $TEST_ID"

        # Find most recent result file
        BASELINE_FILE=$(find "$RESULTS_DIR" -name "${TEST_ID}_*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

        if [ -z "$BASELINE_FILE" ]; then
            log_warning "No previous test results found for $TEST_ID"
            log_info "This will be the first execution - no comparison available"
            BASELINE_FILE=""
        else
            log_success "Found baseline: $(basename "$BASELINE_FILE")"
        fi
    fi

    # Parse baseline if exists
    if [ -n "$BASELINE_FILE" ] && [ -f "$BASELINE_FILE" ]; then
        BASELINE_STATUS=$(jq -r '.status // "unknown"' "$BASELINE_FILE")
        BASELINE_ERROR=$(jq -r '.error_message // ""' "$BASELINE_FILE")
        BASELINE_STEPS_PASSED=$(jq -r '.steps_passed // 0' "$BASELINE_FILE")
        BASELINE_STEPS_FAILED=$(jq -r '.steps_failed // 0' "$BASELINE_FILE")

        log_info "Baseline status: $BASELINE_STATUS"
        log_info "Baseline steps: $BASELINE_STEPS_PASSED passed, $BASELINE_STEPS_FAILED failed"
    fi
}

step_2_deploy_fixed_sensor() {
    log_info "[2/6] Deploying sensor with fixed version: $FIXED_VERSION"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would deploy sensor with AMI: $FIXED_VERSION"
        SENSOR_IP="10.50.88.200"
        SENSOR_STACK="ec2-sensor-testing-validation-TEST"
        return 0
    fi

    # TODO: Deploy sensor with specific AMI
    # Currently sensor_lifecycle.sh doesn't support AMI override
    # Would need to update deployment to accept AMI parameter

    log_warning "Sensor deployment with specific AMI not yet supported"
    log_info "Using standard deployment process"
    log_info "Manual step: You may need to specify AMI in API call"

    # Deploy sensor
    if ! "$PROJECT_ROOT/sensor_lifecycle.sh" create; then
        log_error "Sensor deployment failed"
        exit 1
    fi

    # Wait for ready
    log_info "Waiting for sensor to be ready..."
    local max_wait=1200
    local waited=0
    local check_interval=30

    while [ $waited -lt $max_wait ]; do
        if "$PROJECT_ROOT/sensor_lifecycle.sh" status | grep -q "running"; then
            break
        fi
        sleep $check_interval
        waited=$((waited + check_interval))
    done

    if [ $waited -ge $max_wait ]; then
        log_error "Sensor did not become ready"
        exit 1
    fi

    # Get sensor details
    source "$PROJECT_ROOT/.env"
    SENSOR_IP="${SSH_HOST:-unknown}"
    SENSOR_STACK="${SENSOR_NAME:-unknown}"

    log_success "Sensor deployed: $SENSOR_IP"
}

step_3_prepare_sensor() {
    log_info "[3/6] Preparing sensor"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would prepare sensor"
        return 0
    fi

    # Determine config from test case
    local test_case_file=$(find "$PROJECT_ROOT/testing/test_cases" -name "*${JIRA_TICKET}*.yaml" -o -name "*${JIRA_TICKET}*.yml" 2>/dev/null | head -1)
    local sensor_config=$(yq eval '.sensor.config // "default"' "$test_case_file" 2>/dev/null || echo "default")

    if ! "$PROJECT_ROOT/sensor_prep/prepare_sensor.sh" --config "$sensor_config"; then
        log_error "Sensor preparation failed"
        exit 1
    fi

    log_success "Sensor prepared"
}

step_4_run_test() {
    log_info "[4/6] Running test case: $TEST_ID"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would execute test: $TEST_ID"
        CURRENT_RESULT="passed"
        CURRENT_RESULT_FILE="$RESULTS_DIR/${TEST_ID}_validation_$(date +%Y%m%d_%H%M%S).json"
        return 0
    fi

    # Find test case file
    local test_case_file=$(find "$PROJECT_ROOT/testing/test_cases" -name "${TEST_ID}.yaml" -o -name "${TEST_ID}.yml" 2>/dev/null | head -1)

    if [ -z "$test_case_file" ]; then
        log_error "Test case file not found: $TEST_ID"
        exit 1
    fi

    # Execute test
    if ! "$PROJECT_ROOT/testing/run_test.sh" --test-file "$test_case_file"; then
        log_info "Test execution completed with failures"
        CURRENT_RESULT="failed"
    else
        CURRENT_RESULT="passed"
    fi

    # Find result file
    CURRENT_RESULT_FILE=$(find "$RESULTS_DIR" -name "${TEST_ID}_*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

    if [ -z "$CURRENT_RESULT_FILE" ]; then
        log_error "Test result file not found"
        exit 1
    fi

    # Parse current result
    CURRENT_STATUS=$(jq -r '.status // "unknown"' "$CURRENT_RESULT_FILE")
    CURRENT_ERROR=$(jq -r '.error_message // ""' "$CURRENT_RESULT_FILE")
    CURRENT_STEPS_PASSED=$(jq -r '.steps_passed // 0' "$CURRENT_RESULT_FILE")
    CURRENT_STEPS_FAILED=$(jq -r '.steps_failed // 0' "$CURRENT_RESULT_FILE")

    log_success "Test execution complete: $CURRENT_STATUS"
}

step_5_compare_results() {
    log_info "[5/6] Comparing results: Baseline vs Current"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would compare results"
        VALIDATION_STATUS="FIXED"
        return 0
    fi

    # If no baseline, can't compare
    if [ -z "$BASELINE_FILE" ] || [ ! -f "$BASELINE_FILE" ]; then
        log_warning "No baseline available for comparison"
        VALIDATION_STATUS="NO_BASELINE"
        VALIDATION_SUMMARY="First execution - no previous result to compare"
        return 0
    fi

    # Compare results
    log_info "Baseline: $BASELINE_STATUS (steps: $BASELINE_STEPS_PASSED/$((BASELINE_STEPS_PASSED + BASELINE_STEPS_FAILED)))"
    log_info "Current:  $CURRENT_STATUS (steps: $CURRENT_STEPS_PASSED/$((CURRENT_STEPS_PASSED + CURRENT_STEPS_FAILED)))"

    # Determine validation status
    if [ "$BASELINE_STATUS" = "failed" ] && [ "$CURRENT_STATUS" = "passed" ]; then
        VALIDATION_STATUS="FIXED"
        VALIDATION_SUMMARY="✅ Issue is FIXED - Previously failed, now passes"
        log_success "$VALIDATION_SUMMARY"

    elif [ "$BASELINE_STATUS" = "failed" ] && [ "$CURRENT_STATUS" = "failed" ]; then
        # Check if same error
        if [ "$BASELINE_ERROR" = "$CURRENT_ERROR" ]; then
            VALIDATION_STATUS="STILL_FAILING"
            VALIDATION_SUMMARY="❌ Issue STILL FAILING - Same error as before"
            log_error "$VALIDATION_SUMMARY"
        else
            VALIDATION_STATUS="REGRESSED"
            VALIDATION_SUMMARY="⚠️  Issue REGRESSED - Different error than before"
            log_warning "$VALIDATION_SUMMARY"
        fi

    elif [ "$BASELINE_STATUS" = "passed" ] && [ "$CURRENT_STATUS" = "failed" ]; then
        VALIDATION_STATUS="REGRESSED"
        VALIDATION_SUMMARY="⚠️  REGRESSION - Previously passed, now fails"
        log_error "$VALIDATION_SUMMARY"

    elif [ "$BASELINE_STATUS" = "passed" ] && [ "$CURRENT_STATUS" = "passed" ]; then
        # Check if improvement in steps
        if [ "$CURRENT_STEPS_PASSED" -gt "$BASELINE_STEPS_PASSED" ]; then
            VALIDATION_STATUS="IMPROVED"
            VALIDATION_SUMMARY="✅ Test IMPROVED - More steps passing"
            log_success "$VALIDATION_SUMMARY"
        else
            VALIDATION_STATUS="UNCHANGED"
            VALIDATION_SUMMARY="ℹ️  Test status UNCHANGED - Still passing"
            log_info "$VALIDATION_SUMMARY"
        fi

    else
        VALIDATION_STATUS="UNKNOWN"
        VALIDATION_SUMMARY="⚠️  Unable to determine validation status"
        log_warning "$VALIDATION_SUMMARY"
    fi
}

step_6_generate_validation_report() {
    log_info "[6/6] Generating validation report"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would generate validation report"
        return 0
    fi

    local workflow_end_time=$(date +%s)
    local workflow_duration=$((workflow_end_time - WORKFLOW_START_TIME))

    # Generate JSON report
    local report_file="$RESULTS_DIR/validation_${JIRA_TICKET}_$(date +%Y%m%d_%H%M%S).json"

    cat > "$report_file" <<EOF
{
  "workflow_name": "$WORKFLOW_NAME",
  "workflow_id": "$WORKFLOW_ID",
  "jira_ticket": "$JIRA_TICKET",
  "validation_status": "$VALIDATION_STATUS",
  "validation_summary": "$VALIDATION_SUMMARY",
  "fixed_version": "$FIXED_VERSION",
  "started_at": "$(date -d @$WORKFLOW_START_TIME -Iseconds 2>/dev/null || date -r $WORKFLOW_START_TIME -Iseconds)",
  "completed_at": "$(date -Iseconds)",
  "duration_seconds": $workflow_duration,
  "baseline": {
    "file": "${BASELINE_FILE:-null}",
    "status": "${BASELINE_STATUS:-unknown}",
    "steps_passed": ${BASELINE_STEPS_PASSED:-0},
    "steps_failed": ${BASELINE_STEPS_FAILED:-0},
    "error": "${BASELINE_ERROR:-}"
  },
  "current": {
    "file": "${CURRENT_RESULT_FILE:-null}",
    "status": "${CURRENT_STATUS:-unknown}",
    "steps_passed": ${CURRENT_STEPS_PASSED:-0},
    "steps_failed": ${CURRENT_STEPS_FAILED:-0},
    "error": "${CURRENT_ERROR:-}"
  },
  "sensor": {
    "stack_name": "${SENSOR_STACK:-unknown}",
    "ip": "${SENSOR_IP:-unknown}",
    "fixed_version": "$FIXED_VERSION"
  }
}
EOF

    log_success "JSON report: $report_file"

    # Generate Markdown report
    local md_report="${report_file%.json}.md"

    cat > "$md_report" <<EOF
# Fix Validation Report: $JIRA_TICKET

**Status**: $VALIDATION_STATUS
**JIRA**: $JIRA_TICKET
**Fixed Version**: $FIXED_VERSION
**Date**: $(date)
**Duration**: ${workflow_duration}s

---

## Validation Result

$VALIDATION_SUMMARY

---

## Comparison

| Metric | Baseline | Current | Change |
|--------|----------|---------|--------|
| **Status** | ${BASELINE_STATUS:-N/A} | ${CURRENT_STATUS:-N/A} | $([ "${BASELINE_STATUS:-}" != "${CURRENT_STATUS:-}" ] && echo "Changed" || echo "Same") |
| **Steps Passed** | ${BASELINE_STEPS_PASSED:-0} | ${CURRENT_STEPS_PASSED:-0} | $((CURRENT_STEPS_PASSED - ${BASELINE_STEPS_PASSED:-0})) |
| **Steps Failed** | ${BASELINE_STEPS_FAILED:-0} | ${CURRENT_STEPS_FAILED:-0} | $((CURRENT_STEPS_FAILED - ${BASELINE_STEPS_FAILED:-0})) |

### Baseline Error
\`\`\`
${BASELINE_ERROR:-No error}
\`\`\`

### Current Error
\`\`\`
${CURRENT_ERROR:-No error}
\`\`\`

---

## Sensor Details

- **Stack**: ${SENSOR_STACK:-unknown}
- **IP**: ${SENSOR_IP:-unknown}
- **Version**: $FIXED_VERSION

---

## Files

- **Baseline**: ${BASELINE_FILE:-N/A}
- **Current**: ${CURRENT_RESULT_FILE:-N/A}
- **Validation Report**: $report_file
- **Workflow Log**: $WORKFLOW_LOG

---

*Generated by $WORKFLOW_NAME at $(date)*
EOF

    log_success "Markdown report: $md_report"

    # Print summary to console
    echo
    log_info "=========================================="
    log_info "VALIDATION SUMMARY"
    log_info "=========================================="
    echo "$VALIDATION_SUMMARY"
    echo
    log_info "See full report: $md_report"
    log_info "=========================================="
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    local exit_code=$?

    log_info "Cleaning up workflow resources..."

    # Optionally delete sensor
    if [ "$AUTO_CLEANUP" = "true" ]; then
        log_info "Auto-cleanup enabled, deleting sensor..."
        "$PROJECT_ROOT/sensor_lifecycle.sh" delete || log_warning "Sensor deletion failed"
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

################################################################################
# Main
################################################################################

main() {
    log_info "=========================================="
    log_info "Fix Validation Workflow"
    log_info "=========================================="
    log_info "Workflow ID: $WORKFLOW_ID"
    echo

    # Parse arguments
    parse_args "$@"

    log_info "JIRA Ticket: $JIRA_TICKET"
    log_info "Fixed Version: $FIXED_VERSION"
    echo

    # Validate
    validate_prerequisites
    echo

    # Execute workflow
    step_1_find_baseline
    step_2_deploy_fixed_sensor
    step_3_prepare_sensor
    step_4_run_test
    step_5_compare_results
    step_6_generate_validation_report

    echo
    log_success "=========================================="
    log_success "Validation Complete!"
    log_success "=========================================="
}

main "$@"
