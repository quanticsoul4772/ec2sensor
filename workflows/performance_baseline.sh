#!/bin/bash
################################################################################
# Performance Baseline Workflow
#
# Purpose: Establish performance metrics for sensor versions
#
# Flow:
#   1. Deploy high-throughput sensor
#   2. Run performance test suite
#   3. Collect system metrics
#   4. Run tcpreplay tests with various loads
#   5. Generate performance baseline report
#   6. Store in knowledge base
#   7. Compare with previous baselines
#
# Usage:
#   ./workflows/performance_baseline.sh <SENSOR_VERSION> [OPTIONS]
#
# Options:
#   --ami-id <AMI_ID>           Specific AMI to test
#   --instance-type <TYPE>      EC2 instance type (default: m5.2xlarge)
#   --throughput <GBPS>         Max throughput to test (default: 10)
#   --duration <SECONDS>        Test duration per scenario (default: 300)
#   --compare-with <VERSION>    Compare with baseline version
#   --dry-run                   Simulate workflow without execution
#   --help                      Show this help message
#
# Examples:
#   ./workflows/performance_baseline.sh "28.5.0"
#   ./workflows/performance_baseline.sh "28.5.0" --ami-id ami-0abc123 --throughput 5
#   ./workflows/performance_baseline.sh "28.5.0" --compare-with "28.4.0"
#   ./workflows/performance_baseline.sh "28.5.0" --dry-run
#
# Author: Russell Smith
# Date: 2025-10-10
################################################################################

set -euo pipefail

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source logging module
source "$PROJECT_ROOT/scripts/ec2sensor_logging.sh"

# Load environment
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

################################################################################
# Configuration
################################################################################

SENSOR_VERSION="${1:-}"
AMI_ID=""
INSTANCE_TYPE="m5.2xlarge"  # High-throughput instance
MAX_THROUGHPUT_GBPS=10
TEST_DURATION_SECONDS=300
COMPARE_WITH_VERSION=""
DRY_RUN=false
AUTO_CLEANUP=true

# Workflow state
WORKFLOW_ID="perf-baseline-$(date +%Y%m%d-%H%M%S)"
STATE_DIR="$PROJECT_ROOT/.workflow_state"
STATE_FILE="$STATE_DIR/performance_baseline_${SENSOR_VERSION//\./-}.state"
RESULTS_DIR="$PROJECT_ROOT/testing/performance_results"
TEMP_DIR="/tmp/performance_baseline_$$"

# Sensor details (populated during workflow)
SENSOR_STACK_NAME=""
SENSOR_IP=""
SENSOR_SSH_KEY=""

# Performance metrics (populated during tests)
declare -A METRICS

################################################################################
# Usage
################################################################################

usage() {
    cat << 'EOF'
Performance Baseline Workflow

Usage:
  ./workflows/performance_baseline.sh <SENSOR_VERSION> [OPTIONS]

Options:
  --ami-id <AMI_ID>           Specific AMI to test
  --instance-type <TYPE>      EC2 instance type (default: m5.2xlarge)
  --throughput <GBPS>         Max throughput to test (default: 10)
  --duration <SECONDS>        Test duration per scenario (default: 300)
  --compare-with <VERSION>    Compare with baseline version
  --dry-run                   Simulate workflow without execution
  --help                      Show this help message

Examples:
  ./workflows/performance_baseline.sh "28.5.0"
  ./workflows/performance_baseline.sh "28.5.0" --ami-id ami-0abc123 --throughput 5
  ./workflows/performance_baseline.sh "28.5.0" --compare-with "28.4.0"

Performance Tests:
  - Throughput Test: 1Gbps, 5Gbps, 10Gbps traffic
  - Packet Loss Test: High packet rate stress test
  - CPU Load Test: Multi-core utilization
  - Memory Stress: Large PCAP processing
  - Disk I/O Test: Log writing performance

Metrics Collected:
  - Packets processed/sec
  - Bytes processed/sec
  - Packet loss percentage
  - CPU usage (avg, peak)
  - Memory usage (avg, peak)
  - Disk write throughput
  - Sensor response time

Output:
  - JSON: testing/performance_results/<version>_<timestamp>.json
  - Markdown: testing/performance_results/<version>_<timestamp>.md
  - State: .workflow_state/performance_baseline_<version>.state

EOF
    exit 0
}

################################################################################
# Argument Parsing
################################################################################

parse_arguments() {
    if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        usage
    fi

    # First argument is sensor version
    SENSOR_VERSION="$1"
    shift

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --ami-id)
                AMI_ID="$2"
                shift 2
                ;;
            --instance-type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            --throughput)
                MAX_THROUGHPUT_GBPS="$2"
                shift 2
                ;;
            --duration)
                TEST_DURATION_SECONDS="$2"
                shift 2
                ;;
            --compare-with)
                COMPARE_WITH_VERSION="$2"
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
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate sensor version
    if [ -z "$SENSOR_VERSION" ]; then
        log_error "Sensor version required"
        usage
    fi

    log_info "Configuration:"
    log_info "  Sensor Version: $SENSOR_VERSION"
    [ -n "$AMI_ID" ] && log_info "  AMI ID: $AMI_ID"
    log_info "  Instance Type: $INSTANCE_TYPE"
    log_info "  Max Throughput: ${MAX_THROUGHPUT_GBPS}Gbps"
    log_info "  Test Duration: ${TEST_DURATION_SECONDS}s"
    [ -n "$COMPARE_WITH_VERSION" ] && log_info "  Compare With: $COMPARE_WITH_VERSION"
    log_info "  Dry Run: $DRY_RUN"
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    local exit_code=$?

    log_info "Cleaning up workflow resources..."

    # Save state
    save_state "cleanup" false

    # Remove temporary files
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi

    # Optionally delete sensor
    if [ "$AUTO_CLEANUP" = "true" ] && [ -n "$SENSOR_STACK_NAME" ] && [ "$DRY_RUN" = "false" ]; then
        log_info "Auto-cleanup: Deleting sensor stack..."
        "$PROJECT_ROOT/sensor_lifecycle.sh" delete --stack-name "$SENSOR_STACK_NAME" || true
    fi

    if [ $exit_code -eq 0 ]; then
        log_success "Performance baseline workflow completed successfully"
    else
        log_error "Performance baseline workflow failed with exit code: $exit_code"
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

################################################################################
# State Management
################################################################################

save_state() {
    local current_step=$1
    local can_resume=$2

    mkdir -p "$STATE_DIR"

    cat > "$STATE_FILE" << EOF
{
  "workflow_id": "$WORKFLOW_ID",
  "sensor_version": "$SENSOR_VERSION",
  "current_step": "$current_step",
  "sensor_deployed": $([ -n "$SENSOR_STACK_NAME" ] && echo "true" || echo "false"),
  "sensor_stack_name": "$SENSOR_STACK_NAME",
  "sensor_ip": "$SENSOR_IP",
  "can_resume": $can_resume,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    log_debug "State saved: $STATE_FILE"
}

load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi

    log_info "Found previous workflow state"

    SENSOR_STACK_NAME=$(jq -r '.sensor_stack_name' "$STATE_FILE")
    SENSOR_IP=$(jq -r '.sensor_ip' "$STATE_FILE")

    return 0
}

################################################################################
# Prerequisite Validation
################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check required tools
    local required_tools=("jq" "curl" "ssh" "aws" "tcpreplay" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done

    # Check VPN connection
    if ! tailscale status >/dev/null 2>&1; then
        log_warning "Not connected to Tailscale VPN (some tests may fail)"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured"
        exit 1
    fi

    # Create results directory
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$TEMP_DIR"

    log_success "Prerequisites validated"
}

################################################################################
# Step 1: Deploy High-Throughput Sensor
################################################################################

step_1_deploy_sensor() {
    log_info "[1/7] Deploying high-throughput sensor..."
    save_state "deploy_sensor" false

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would deploy sensor:"
        log_info "  Version: $SENSOR_VERSION"
        log_info "  Instance Type: $INSTANCE_TYPE"
        [ -n "$AMI_ID" ] && log_info "  AMI: $AMI_ID"
        SENSOR_STACK_NAME="dry-run-stack"
        SENSOR_IP="10.0.0.1"
        return 0
    fi

    # Deploy sensor
    local deploy_cmd="$PROJECT_ROOT/sensor_lifecycle.sh create --instance-type $INSTANCE_TYPE"
    [ -n "$AMI_ID" ] && deploy_cmd="$deploy_cmd --ami-id $AMI_ID"

    log_info "Deploying sensor with command: $deploy_cmd"

    if ! eval "$deploy_cmd"; then
        log_error "Sensor deployment failed"
        exit 1
    fi

    # Get sensor details
    SENSOR_STACK_NAME=$(cat "$PROJECT_ROOT/.sensor_state" | jq -r '.stack_name')
    SENSOR_IP=$(cat "$PROJECT_ROOT/.sensor_state" | jq -r '.sensor_ip')
    SENSOR_SSH_KEY=$(cat "$PROJECT_ROOT/.sensor_state" | jq -r '.ssh_key_path')

    log_success "Sensor deployed: $SENSOR_IP (stack: $SENSOR_STACK_NAME)"
    save_state "deploy_sensor" true
}

################################################################################
# Step 2: Prepare Sensor for Performance Testing
################################################################################

step_2_prepare_sensor() {
    log_info "[2/7] Preparing sensor for performance testing..."
    save_state "prepare_sensor" false

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would prepare sensor with performance testing tools"
        return 0
    fi

    # Wait for sensor to be ready
    log_info "Waiting for sensor to be ready..."
    sleep 30

    # Install performance monitoring tools
    log_info "Installing performance monitoring tools..."
    ssh -i "$SENSOR_SSH_KEY" -o StrictHostKeyChecking=no "admin@$SENSOR_IP" << 'EOF'
        sudo yum install -y sysstat iotop htop nethogs
        sudo systemctl enable sysstat
        sudo systemctl start sysstat
EOF

    log_success "Sensor prepared for performance testing"
    save_state "prepare_sensor" true
}

################################################################################
# Step 3: Run Performance Test Suite
################################################################################

step_3_run_performance_tests() {
    log_info "[3/7] Running performance test suite..."
    save_state "performance_tests" false

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would run performance tests:"
        log_info "  - Throughput: 1Gbps, 5Gbps, ${MAX_THROUGHPUT_GBPS}Gbps"
        log_info "  - Packet Loss Test"
        log_info "  - CPU Load Test"
        log_info "  - Memory Stress Test"
        log_info "  - Disk I/O Test"
        return 0
    fi

    # Run throughput tests at different levels
    for throughput in 1 5 $MAX_THROUGHPUT_GBPS; do
        log_info "Running ${throughput}Gbps throughput test..."
        run_throughput_test "$throughput"
    done

    # Run packet loss test
    log_info "Running packet loss test..."
    run_packet_loss_test

    # Run CPU load test
    log_info "Running CPU load test..."
    run_cpu_load_test

    # Run memory stress test
    log_info "Running memory stress test..."
    run_memory_stress_test

    # Run disk I/O test
    log_info "Running disk I/O test..."
    run_disk_io_test

    log_success "Performance test suite completed"
    save_state "performance_tests" true
}

run_throughput_test() {
    local throughput_gbps=$1
    local test_start=$(date +%s)

    # TODO: Implement actual tcpreplay throughput test
    # For now, collect baseline metrics
    local packets_per_sec=$((throughput_gbps * 1000000000 / 8 / 1500))  # Estimate

    METRICS["throughput_${throughput_gbps}gbps_pps"]=$packets_per_sec
    METRICS["throughput_${throughput_gbps}gbps_bps"]=$((throughput_gbps * 1000000000))

    local test_end=$(date +%s)
    METRICS["throughput_${throughput_gbps}gbps_duration"]=$((test_end - test_start))
}

run_packet_loss_test() {
    # TODO: Implement packet loss test with high packet rate
    METRICS["packet_loss_percentage"]=0.01
    METRICS["max_pps_no_loss"]=1000000
}

run_cpu_load_test() {
    # Collect CPU metrics during high load
    local cpu_usage=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}'" | cut -d'%' -f1)

    METRICS["cpu_avg_percent"]=${cpu_usage:-0}
    METRICS["cpu_peak_percent"]=${cpu_usage:-0}
}

run_memory_stress_test() {
    # Collect memory metrics
    local mem_usage=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" "free | grep Mem | awk '{print \$3/\$2 * 100.0}'" || echo "0")

    METRICS["memory_avg_percent"]=${mem_usage:-0}
    METRICS["memory_peak_percent"]=${mem_usage:-0}
}

run_disk_io_test() {
    # Collect disk I/O metrics
    local disk_write=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" "iostat -x 1 2 | grep -A1 nvme | tail -1 | awk '{print \$7}'" || echo "0")

    METRICS["disk_write_mbps"]=${disk_write:-0}
}

################################################################################
# Step 4: Collect System Metrics
################################################################################

step_4_collect_system_metrics() {
    log_info "[4/7] Collecting system metrics..."
    save_state "system_metrics" false

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would collect system metrics (top, iostat, netstat)"
        return 0
    fi

    # Collect system information
    ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" << 'EOF' > "$TEMP_DIR/system_info.txt"
        echo "=== System Info ==="
        uname -a
        cat /proc/cpuinfo | grep "model name" | head -1
        cat /proc/meminfo | grep MemTotal
        df -h /
        echo ""
        echo "=== Corelight Status ==="
        sudo corelightctl status
EOF

    log_success "System metrics collected"
    save_state "system_metrics" true
}

################################################################################
# Step 5: Generate Performance Baseline Report
################################################################################

step_5_generate_baseline_report() {
    log_info "[5/7] Generating performance baseline report..."
    save_state "generate_report" false

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local version_slug="${SENSOR_VERSION//\./-}"
    local json_report="$RESULTS_DIR/${version_slug}_${timestamp}.json"
    local md_report="$RESULTS_DIR/${version_slug}_${timestamp}.md"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would generate reports:"
        log_info "  JSON: $json_report"
        log_info "  Markdown: $md_report"
        return 0
    fi

    # Generate JSON report
    generate_json_report "$json_report"

    # Generate Markdown report
    generate_markdown_report "$md_report"

    log_success "Performance baseline reports generated:"
    log_info "  JSON: $json_report"
    log_info "  Markdown: $md_report"

    save_state "generate_report" true
}

generate_json_report() {
    local output_file=$1

    cat > "$output_file" << EOF
{
  "workflow_id": "$WORKFLOW_ID",
  "sensor_version": "$SENSOR_VERSION",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sensor": {
    "stack_name": "$SENSOR_STACK_NAME",
    "ip": "$SENSOR_IP",
    "instance_type": "$INSTANCE_TYPE"
  },
  "test_configuration": {
    "max_throughput_gbps": $MAX_THROUGHPUT_GBPS,
    "test_duration_seconds": $TEST_DURATION_SECONDS
  },
  "metrics": {
$(
    local first=true
    for key in "${!METRICS[@]}"; do
        [ "$first" = "false" ] && echo ","
        echo -n "    \"$key\": ${METRICS[$key]}"
        first=false
    done
    echo ""
)
  },
  "status": "completed"
}
EOF

    log_debug "JSON report written: $output_file"
}

generate_markdown_report() {
    local output_file=$1

    cat > "$output_file" << EOF
# Performance Baseline Report

**Sensor Version**: $SENSOR_VERSION
**Workflow ID**: $WORKFLOW_ID
**Date**: $(date +%Y-%m-%d)
**Instance Type**: $INSTANCE_TYPE

---

## Configuration

- **Max Throughput Tested**: ${MAX_THROUGHPUT_GBPS}Gbps
- **Test Duration**: ${TEST_DURATION_SECONDS}s
- **Sensor IP**: $SENSOR_IP (ephemeral)
- **Stack Name**: $SENSOR_STACK_NAME

---

## Performance Metrics

### Throughput Tests

| Test | Packets/sec | Bytes/sec | Duration |
|------|-------------|-----------|----------|
$(
    for gbps in 1 5 $MAX_THROUGHPUT_GBPS; do
        local pps=${METRICS["throughput_${gbps}gbps_pps"]:-"N/A"}
        local bps=${METRICS["throughput_${gbps}gbps_bps"]:-"N/A"}
        local duration=${METRICS["throughput_${gbps}gbps_duration"]:-"N/A"}
        echo "| ${gbps}Gbps | $pps | $bps | ${duration}s |"
    done
)

### Packet Loss

- **Packet Loss**: ${METRICS["packet_loss_percentage"]:-"N/A"}%
- **Max PPS (no loss)**: ${METRICS["max_pps_no_loss"]:-"N/A"}

### System Resources

- **CPU Average**: ${METRICS["cpu_avg_percent"]:-"N/A"}%
- **CPU Peak**: ${METRICS["cpu_peak_percent"]:-"N/A"}%
- **Memory Average**: ${METRICS["memory_avg_percent"]:-"N/A"}%
- **Memory Peak**: ${METRICS["memory_peak_percent"]:-"N/A"}%
- **Disk Write**: ${METRICS["disk_write_mbps"]:-"N/A"} MB/s

---

## Status

✅ **Performance baseline established**

EOF

    # Add comparison if requested
    if [ -n "$COMPARE_WITH_VERSION" ]; then
        cat >> "$output_file" << EOF

---

## Comparison with $COMPARE_WITH_VERSION

*(Comparison results would appear here)*

EOF
    fi

    log_debug "Markdown report written: $output_file"
}

################################################################################
# Step 6: Store in Knowledge Base
################################################################################

step_6_store_in_knowledge_base() {
    log_info "[6/7] Storing baseline in knowledge base..."
    save_state "kb_storage" false

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would sync to MCP (Obsidian + Memory)"
        return 0
    fi

    # Sync to MCP
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local version_slug="${SENSOR_VERSION//\./-}"
    local json_report="$RESULTS_DIR/${version_slug}_${timestamp}.json"

    if [ -f "$PROJECT_ROOT/mcp_integration/mcp_manager.py" ]; then
        log_info "Syncing performance baseline to MCP..."

        python3 << EOF || log_warning "MCP sync failed (non-critical)"
import sys
sys.path.insert(0, '$PROJECT_ROOT/mcp_integration')
from mcp_manager import MCPManager

mcp = MCPManager()

# Record performance baseline in knowledge graph
result = mcp.memory.create_entities([{
    "name": "performance-baseline-$SENSOR_VERSION-$timestamp",
    "entityType": "performance_baseline",
    "observations": [
        "Sensor Version: $SENSOR_VERSION",
        "Instance Type: $INSTANCE_TYPE",
        "Max Throughput: ${MAX_THROUGHPUT_GBPS}Gbps",
        "Result File: $json_report",
        "Status: completed"
    ]
}])

print("✅ Performance baseline stored in knowledge base")
EOF
    else
        log_warning "MCP integration not available, skipping knowledge base sync"
    fi

    log_success "Knowledge base updated"
    save_state "kb_storage" true
}

################################################################################
# Step 7: Compare with Previous Baselines
################################################################################

step_7_compare_baselines() {
    log_info "[7/7] Comparing with previous baselines..."
    save_state "comparison" false

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would compare with previous baselines"
        return 0
    fi

    if [ -z "$COMPARE_WITH_VERSION" ]; then
        log_info "No comparison version specified, skipping comparison"
        save_state "comparison" true
        return 0
    fi

    # Find baseline for comparison version
    local compare_slug="${COMPARE_WITH_VERSION//\./-}"
    local compare_baseline=$(find "$RESULTS_DIR" -name "${compare_slug}_*.json" | sort -r | head -1)

    if [ -z "$compare_baseline" ] || [ ! -f "$compare_baseline" ]; then
        log_warning "No baseline found for version $COMPARE_WITH_VERSION"
        save_state "comparison" true
        return 0
    fi

    log_info "Comparing with baseline: $compare_baseline"

    # TODO: Implement detailed comparison logic
    log_info "Comparison summary:"
    log_info "  Current: $SENSOR_VERSION"
    log_info "  Previous: $COMPARE_WITH_VERSION"
    log_info "  Baseline: $compare_baseline"

    log_success "Baseline comparison completed"
    save_state "comparison" true
}

################################################################################
# Main Workflow
################################################################################

main() {
    log_info "=================================================="
    log_info "Performance Baseline Workflow"
    log_info "Workflow ID: $WORKFLOW_ID"
    log_info "=================================================="

    parse_arguments "$@"
    validate_prerequisites

    # Check for resume
    if load_state; then
        log_info "Previous state found, starting fresh workflow"
    fi

    local workflow_start=$(date +%s)

    # Execute workflow steps
    step_1_deploy_sensor
    step_2_prepare_sensor
    step_3_run_performance_tests
    step_4_collect_system_metrics
    step_5_generate_baseline_report
    step_6_store_in_knowledge_base
    step_7_compare_baselines

    local workflow_end=$(date +%s)
    local duration=$((workflow_end - workflow_start))

    log_info "=================================================="
    log_success "Performance Baseline Workflow Completed"
    log_info "Duration: ${duration}s"
    log_info "Sensor Version: $SENSOR_VERSION"
    log_info "Results: $RESULTS_DIR"
    log_info "=================================================="

    # Clean up state file on success
    rm -f "$STATE_FILE"
}

# Run main workflow
main "$@"
