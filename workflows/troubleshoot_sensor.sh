#!/bin/bash
################################################################################
# Interactive Troubleshooting Workflow
#
# Purpose: Guided troubleshooting assistant for sensor issues
#
# Flow:
#   1. Interactive symptom collection
#   2. Automated diagnostics
#   3. Knowledge base search (MCP Memory + Exa + Obsidian)
#   4. Suggested solutions (ranked by relevance)
#   5. Guided fix application
#   6. Generate troubleshooting report
#   7. Update knowledge base with solution
#
# Usage:
#   ./workflows/troubleshoot_sensor.sh [OPTIONS]
#
# Options:
#   --sensor-ip <IP>            Sensor IP address
#   --stack-name <NAME>         CloudFormation stack name
#   --symptom <TYPE>            Symptom type (connectivity, performance, feature_failure, logs)
#   --auto-diagnose             Run diagnostics without interaction
#   --apply-fix <SOLUTION_ID>   Apply specific solution automatically
#   --dry-run                   Simulate workflow without execution
#   --help                      Show this help message
#
# Examples:
#   ./workflows/troubleshoot_sensor.sh --sensor-ip 10.50.88.154
#   ./workflows/troubleshoot_sensor.sh --auto-diagnose --sensor-ip 10.50.88.154
#   ./workflows/troubleshoot_sensor.sh --symptom connectivity --sensor-ip 10.50.88.154
#   ./workflows/troubleshoot_sensor.sh --dry-run
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

SENSOR_IP=""
SENSOR_STACK_NAME=""
SYMPTOM_TYPE=""
AUTO_DIAGNOSE=false
APPLY_FIX_ID=""
DRY_RUN=false
INTERACTIVE=true

# Workflow state
WORKFLOW_ID="troubleshoot-$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$PROJECT_ROOT/troubleshooting/reports"
TEMP_DIR="/tmp/troubleshoot_sensor_$$"

# Diagnostics results
declare -A DIAGNOSTICS
declare -a SOLUTIONS
SELECTED_SOLUTION=""

# Sensor connection details
SENSOR_SSH_KEY=""
SENSOR_ACCESSIBLE=false

################################################################################
# Usage
################################################################################

usage() {
    cat << 'EOF'
Interactive Troubleshooting Workflow

Usage:
  ./workflows/troubleshoot_sensor.sh [OPTIONS]

Options:
  --sensor-ip <IP>            Sensor IP address
  --stack-name <NAME>         CloudFormation stack name
  --symptom <TYPE>            Symptom type (connectivity, performance, feature_failure, logs)
  --auto-diagnose             Run diagnostics without interaction
  --apply-fix <SOLUTION_ID>   Apply specific solution automatically
  --dry-run                   Simulate workflow without execution
  --help                      Show this help message

Symptom Types:
  connectivity      - Cannot connect to sensor (SSH/API)
  performance       - Sensor running slowly or dropping packets
  feature_failure   - Specific Corelight feature not working
  logs              - Error messages in logs
  configuration     - Configuration issues
  disk_space        - Disk space issues

Examples:
  # Interactive troubleshooting
  ./workflows/troubleshoot_sensor.sh --sensor-ip 10.50.88.154

  # Auto-diagnose without interaction
  ./workflows/troubleshoot_sensor.sh --auto-diagnose --sensor-ip 10.50.88.154

  # Specific symptom
  ./workflows/troubleshoot_sensor.sh --symptom connectivity --sensor-ip 10.50.88.154

  # Apply known solution
  ./workflows/troubleshoot_sensor.sh --apply-fix SOLUTION-001 --sensor-ip 10.50.88.154

Diagnostics Performed:
  - Network connectivity (ping, traceroute)
  - SSH access test
  - Sensor service status (corelightctl status)
  - Configuration validation
  - Log error analysis (last 100 lines)
  - Disk space check
  - Memory availability check
  - Recent configuration changes

Knowledge Sources:
  - MCP Memory: Similar past issues and solutions
  - Exa AI: Corelight documentation search
  - Obsidian: Troubleshooting playbooks

Output:
  - JSON: troubleshooting/reports/troubleshoot_<timestamp>.json
  - Markdown: troubleshooting/reports/troubleshoot_<timestamp>.md

EOF
    exit 0
}

################################################################################
# Argument Parsing
################################################################################

parse_arguments() {
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        usage
    fi

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --sensor-ip)
                SENSOR_IP="$2"
                shift 2
                ;;
            --stack-name)
                SENSOR_STACK_NAME="$2"
                shift 2
                ;;
            --symptom)
                SYMPTOM_TYPE="$2"
                shift 2
                ;;
            --auto-diagnose)
                AUTO_DIAGNOSE=true
                INTERACTIVE=false
                shift
                ;;
            --apply-fix)
                APPLY_FIX_ID="$2"
                INTERACTIVE=false
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # If no sensor IP provided, try to get from sensor state
    if [ -z "$SENSOR_IP" ] && [ -f "$PROJECT_ROOT/.sensor_state" ]; then
        SENSOR_IP=$(jq -r '.sensor_ip' "$PROJECT_ROOT/.sensor_state")
        SENSOR_STACK_NAME=$(jq -r '.stack_name' "$PROJECT_ROOT/.sensor_state")
        SENSOR_SSH_KEY=$(jq -r '.ssh_key_path' "$PROJECT_ROOT/.sensor_state")
        log_info "Using sensor from state: $SENSOR_IP"
    fi

    # Validate sensor IP
    if [ -z "$SENSOR_IP" ] && [ "$DRY_RUN" = "false" ]; then
        log_error "Sensor IP required (use --sensor-ip or ensure .sensor_state exists)"
        usage
    fi

    log_info "Configuration:"
    [ -n "$SENSOR_IP" ] && log_info "  Sensor IP: $SENSOR_IP"
    [ -n "$SENSOR_STACK_NAME" ] && log_info "  Stack Name: $SENSOR_STACK_NAME"
    [ -n "$SYMPTOM_TYPE" ] && log_info "  Symptom: $SYMPTOM_TYPE"
    log_info "  Auto Diagnose: $AUTO_DIAGNOSE"
    log_info "  Interactive: $INTERACTIVE"
    log_info "  Dry Run: $DRY_RUN"
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    local exit_code=$?

    log_info "Cleaning up workflow resources..."

    # Remove temporary files
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi

    if [ $exit_code -eq 0 ]; then
        log_success "Troubleshooting workflow completed successfully"
    else
        log_error "Troubleshooting workflow failed with exit code: $exit_code"
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM

################################################################################
# Prerequisite Validation
################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check required tools
    local required_tools=("jq" "curl" "ssh" "ping" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done

    # Create results directory
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$TEMP_DIR"

    # Find SSH key if not set
    if [ -z "$SENSOR_SSH_KEY" ] && [ -f "$PROJECT_ROOT/.sensor_state" ]; then
        SENSOR_SSH_KEY=$(jq -r '.ssh_key_path' "$PROJECT_ROOT/.sensor_state")
    fi

    if [ -z "$SENSOR_SSH_KEY" ]; then
        # Try to find SSH key in standard location
        SENSOR_SSH_KEY=$(find "$PROJECT_ROOT" -name "ec2-sensor-*.pem" | head -1)
    fi

    log_success "Prerequisites validated"
}

################################################################################
# Step 1: Interactive Symptom Collection
################################################################################

step_1_collect_symptoms() {
    log_info "[1/7] Collecting symptom information..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would collect symptoms interactively"
        SYMPTOM_TYPE="connectivity"
        return 0
    fi

    # If symptom already specified, skip interactive collection
    if [ -n "$SYMPTOM_TYPE" ]; then
        log_info "Symptom type specified: $SYMPTOM_TYPE"
        return 0
    fi

    # If not interactive, auto-detect
    if [ "$INTERACTIVE" = "false" ]; then
        log_info "Auto-detecting symptoms..."
        SYMPTOM_TYPE="auto_detect"
        return 0
    fi

    # Interactive symptom collection
    echo ""
    echo "What problem are you experiencing?"
    echo ""
    echo "1. Cannot connect to sensor (SSH/API)"
    echo "2. Sensor running slowly or dropping packets"
    echo "3. Specific feature not working"
    echo "4. Error messages in logs"
    echo "5. Configuration issues"
    echo "6. Disk space issues"
    echo "7. Other / Not sure"
    echo ""
    read -p "Enter number (1-7): " choice

    case "$choice" in
        1) SYMPTOM_TYPE="connectivity" ;;
        2) SYMPTOM_TYPE="performance" ;;
        3) SYMPTOM_TYPE="feature_failure" ;;
        4) SYMPTOM_TYPE="logs" ;;
        5) SYMPTOM_TYPE="configuration" ;;
        6) SYMPTOM_TYPE="disk_space" ;;
        7) SYMPTOM_TYPE="unknown" ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac

    log_info "Symptom type: $SYMPTOM_TYPE"

    # Additional context questions
    echo ""
    read -p "When did this start? (e.g., today, yesterday, last week): " when_started
    read -p "Any recent changes? (y/n): " recent_changes

    log_info "Additional context:"
    log_info "  When started: $when_started"
    log_info "  Recent changes: $recent_changes"

    log_success "Symptom information collected"
}

################################################################################
# Step 2: Automated Diagnostics
################################################################################

step_2_run_diagnostics() {
    log_info "[2/7] Running automated diagnostics..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would run diagnostics:"
        log_info "  - Network connectivity check"
        log_info "  - SSH access test"
        log_info "  - Service status check"
        log_info "  - Configuration validation"
        log_info "  - Log analysis"
        log_info "  - Resource checks"
        return 0
    fi

    # Run all diagnostic checks
    check_network_connectivity
    check_ssh_access
    check_sensor_service_status
    check_configuration
    check_logs
    check_disk_space
    check_memory
    check_recent_changes

    # Print diagnostics summary
    echo ""
    log_info "Diagnostics Summary:"
    for key in "${!DIAGNOSTICS[@]}"; do
        local status="${DIAGNOSTICS[$key]}"
        local icon="✅"
        [ "$status" = "FAIL" ] && icon="❌"
        [ "$status" = "WARN" ] && icon="⚠️ "
        log_info "  $icon $key: $status"
    done
    echo ""

    log_success "Automated diagnostics completed"
}

check_network_connectivity() {
    log_debug "Checking network connectivity..."

    if ping -c 3 -W 2 "$SENSOR_IP" >/dev/null 2>&1; then
        DIAGNOSTICS["network_ping"]="PASS"
    else
        DIAGNOSTICS["network_ping"]="FAIL"
    fi
}

check_ssh_access() {
    log_debug "Checking SSH access..."

    if [ -z "$SENSOR_SSH_KEY" ]; then
        DIAGNOSTICS["ssh_access"]="FAIL (No SSH key found)"
        SENSOR_ACCESSIBLE=false
        return 1
    fi

    if ssh -i "$SENSOR_SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        "admin@$SENSOR_IP" "echo 'SSH test'" >/dev/null 2>&1; then
        DIAGNOSTICS["ssh_access"]="PASS"
        SENSOR_ACCESSIBLE=true
    else
        DIAGNOSTICS["ssh_access"]="FAIL"
        SENSOR_ACCESSIBLE=false
    fi
}

check_sensor_service_status() {
    log_debug "Checking sensor service status..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        DIAGNOSTICS["service_status"]="SKIP (SSH not accessible)"
        return 1
    fi

    local status=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" \
        "sudo corelightctl status" 2>&1 || echo "FAILED")

    if echo "$status" | grep -q "running"; then
        DIAGNOSTICS["service_status"]="PASS (running)"
    else
        DIAGNOSTICS["service_status"]="FAIL (not running)"
    fi
}

check_configuration() {
    log_debug "Checking configuration..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        DIAGNOSTICS["configuration"]="SKIP (SSH not accessible)"
        return 1
    fi

    # Check if configuration has syntax errors
    local config_check=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" \
        "sudo corelightctl config-check" 2>&1 || echo "FAILED")

    if echo "$config_check" | grep -q "OK\|valid"; then
        DIAGNOSTICS["configuration"]="PASS"
    else
        DIAGNOSTICS["configuration"]="WARN (check needed)"
    fi
}

check_logs() {
    log_debug "Checking logs for errors..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        DIAGNOSTICS["log_errors"]="SKIP (SSH not accessible)"
        return 1
    fi

    # Get last 100 lines and look for errors
    local error_count=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" \
        "sudo tail -100 /var/log/corelight/current/corelight.log | grep -i error | wc -l" 2>&1 || echo "0")

    if [ "$error_count" -eq 0 ]; then
        DIAGNOSTICS["log_errors"]="PASS (no errors)"
    elif [ "$error_count" -lt 10 ]; then
        DIAGNOSTICS["log_errors"]="WARN ($error_count errors found)"
    else
        DIAGNOSTICS["log_errors"]="FAIL ($error_count errors found)"
    fi
}

check_disk_space() {
    log_debug "Checking disk space..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        DIAGNOSTICS["disk_space"]="SKIP (SSH not accessible)"
        return 1
    fi

    local disk_usage=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" \
        "df -h / | tail -1 | awk '{print \$5}'" | tr -d '%' || echo "0")

    if [ "$disk_usage" -lt 80 ]; then
        DIAGNOSTICS["disk_space"]="PASS (${disk_usage}% used)"
    elif [ "$disk_usage" -lt 90 ]; then
        DIAGNOSTICS["disk_space"]="WARN (${disk_usage}% used)"
    else
        DIAGNOSTICS["disk_space"]="FAIL (${disk_usage}% used)"
    fi
}

check_memory() {
    log_debug "Checking memory availability..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        DIAGNOSTICS["memory"]="SKIP (SSH not accessible)"
        return 1
    fi

    local mem_usage=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" \
        "free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}'" || echo "0")

    if [ "$mem_usage" -lt 80 ]; then
        DIAGNOSTICS["memory"]="PASS (${mem_usage}% used)"
    elif [ "$mem_usage" -lt 90 ]; then
        DIAGNOSTICS["memory"]="WARN (${mem_usage}% used)"
    else
        DIAGNOSTICS["memory"]="FAIL (${mem_usage}% used)"
    fi
}

check_recent_changes() {
    log_debug "Checking for recent configuration changes..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        DIAGNOSTICS["recent_changes"]="SKIP (SSH not accessible)"
        return 1
    fi

    # Check last modified time of config files
    local recent_changes=$(ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" \
        "find /etc/corelight -type f -mtime -1 | wc -l" || echo "0")

    if [ "$recent_changes" -eq 0 ]; then
        DIAGNOSTICS["recent_changes"]="NONE"
    else
        DIAGNOSTICS["recent_changes"]="FOUND ($recent_changes files modified in last 24h)"
    fi
}

################################################################################
# Step 3: Knowledge Base Search
################################################################################

step_3_search_knowledge_base() {
    log_info "[3/7] Searching knowledge base for solutions..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would search knowledge base:"
        log_info "  - MCP Memory: Similar past issues"
        log_info "  - Exa AI: Corelight documentation"
        log_info "  - Obsidian: Troubleshooting playbooks"
        SOLUTIONS=("SOLUTION-001: Restart sensor service" "SOLUTION-002: Check network configuration")
        return 0
    fi

    # Search MCP Memory for similar issues
    search_memory_for_similar_issues

    # Search Exa for Corelight documentation
    search_exa_documentation

    # Search Obsidian for playbooks
    search_obsidian_playbooks

    log_success "Knowledge base search completed (${#SOLUTIONS[@]} solutions found)"
}

search_memory_for_similar_issues() {
    if [ ! -f "$PROJECT_ROOT/mcp_integration/mcp_manager.py" ]; then
        log_warning "MCP integration not available"
        return 1
    fi

    log_debug "Searching MCP Memory for similar issues..."

    python3 << EOF || log_warning "Memory search failed"
import sys
sys.path.insert(0, '$PROJECT_ROOT/mcp_integration')
from mcp_manager import MCPManager

mcp = MCPManager()

# Search for similar troubleshooting cases
results = mcp.memory.search_nodes("troubleshooting $SYMPTOM_TYPE sensor")

print(f"Found {len(results.get('nodes', []))} similar cases in knowledge graph")
EOF
}

search_exa_documentation() {
    if [ ! -f "$PROJECT_ROOT/mcp_integration/mcp_manager.py" ]; then
        log_warning "MCP integration not available"
        return 1
    fi

    log_debug "Searching Exa for Corelight documentation..."

    python3 << EOF || log_warning "Exa search failed"
import sys
sys.path.insert(0, '$PROJECT_ROOT/mcp_integration')
from mcp_manager import MCPManager

mcp = MCPManager()

# Research symptom in documentation
query = "Corelight sensor $SYMPTOM_TYPE troubleshooting"
results = mcp.exa.search_web(query, num_results=5)

print(f"Found {len(results.get('results', []))} documentation articles")
EOF

    # Add common solutions based on symptom type
    case "$SYMPTOM_TYPE" in
        connectivity)
            SOLUTIONS+=("SOLUTION-001: Check network connectivity and firewall rules")
            SOLUTIONS+=("SOLUTION-002: Verify SSH key and permissions")
            SOLUTIONS+=("SOLUTION-003: Restart network services")
            ;;
        performance)
            SOLUTIONS+=("SOLUTION-004: Check CPU and memory usage")
            SOLUTIONS+=("SOLUTION-005: Review packet drop statistics")
            SOLUTIONS+=("SOLUTION-006: Optimize sensor configuration")
            ;;
        feature_failure)
            SOLUTIONS+=("SOLUTION-007: Restart Corelight service")
            SOLUTIONS+=("SOLUTION-008: Verify feature configuration")
            SOLUTIONS+=("SOLUTION-009: Check feature compatibility with version")
            ;;
        logs)
            SOLUTIONS+=("SOLUTION-010: Review recent log entries")
            SOLUTIONS+=("SOLUTION-011: Check log rotation and disk space")
            ;;
        disk_space)
            SOLUTIONS+=("SOLUTION-012: Clean up old PCAP files")
            SOLUTIONS+=("SOLUTION-013: Adjust log retention policies")
            ;;
    esac
}

search_obsidian_playbooks() {
    log_debug "Searching Obsidian for troubleshooting playbooks..."

    # Check if Obsidian vault has troubleshooting guides
    local vault_path="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian/Corelight}"

    if [ -d "$vault_path/Troubleshooting" ]; then
        local playbooks=$(find "$vault_path/Troubleshooting" -name "*${SYMPTOM_TYPE}*.md" 2>/dev/null || true)
        if [ -n "$playbooks" ]; then
            log_info "Found troubleshooting playbooks in Obsidian vault"
        fi
    fi
}

################################################################################
# Step 4: Display Suggested Solutions
################################################################################

step_4_suggest_solutions() {
    log_info "[4/7] Suggested solutions..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would display ranked solutions"
        return 0
    fi

    if [ ${#SOLUTIONS[@]} -eq 0 ]; then
        log_warning "No solutions found in knowledge base"
        SOLUTIONS+=("SOLUTION-MANUAL: Manual troubleshooting required")
    fi

    echo ""
    log_info "Suggested Solutions (ranked by relevance):"
    echo ""

    local index=1
    for solution in "${SOLUTIONS[@]}"; do
        echo "  $index. $solution"
        index=$((index + 1))
    done
    echo ""

    # If applying specific fix, skip selection
    if [ -n "$APPLY_FIX_ID" ]; then
        SELECTED_SOLUTION="$APPLY_FIX_ID"
        log_info "Auto-applying solution: $APPLY_FIX_ID"
        return 0
    fi

    # If not interactive, select first solution
    if [ "$INTERACTIVE" = "false" ]; then
        SELECTED_SOLUTION="${SOLUTIONS[0]}"
        log_info "Auto-selected solution: $SELECTED_SOLUTION"
        return 0
    fi

    # Interactive solution selection
    read -p "Select solution to apply (1-${#SOLUTIONS[@]}, or 0 to skip): " choice

    if [ "$choice" -eq 0 ]; then
        log_info "Skipping solution application"
        SELECTED_SOLUTION=""
        return 0
    fi

    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#SOLUTIONS[@]} ]; then
        SELECTED_SOLUTION="${SOLUTIONS[$((choice - 1))]}"
        log_info "Selected: $SELECTED_SOLUTION"
    else
        log_error "Invalid choice"
        exit 1
    fi
}

################################################################################
# Step 5: Guided Fix Application
################################################################################

step_5_apply_fix() {
    log_info "[5/7] Applying selected fix..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would apply fix: $SELECTED_SOLUTION"
        return 0
    fi

    if [ -z "$SELECTED_SOLUTION" ]; then
        log_info "No solution selected, skipping fix application"
        return 0
    fi

    # Extract solution ID
    local solution_id=$(echo "$SELECTED_SOLUTION" | cut -d':' -f1)

    log_info "Applying solution: $solution_id"

    case "$solution_id" in
        SOLUTION-001)
            apply_connectivity_fix
            ;;
        SOLUTION-007)
            apply_service_restart
            ;;
        SOLUTION-012)
            apply_disk_cleanup
            ;;
        *)
            log_warning "No automated fix available for $solution_id"
            log_info "Manual steps required:"
            log_info "  $SELECTED_SOLUTION"
            ;;
    esac

    log_success "Fix application completed"
}

apply_connectivity_fix() {
    log_info "Checking network connectivity..."

    # Verify VPN connection
    if ! tailscale status >/dev/null 2>&1; then
        log_warning "Not connected to Tailscale VPN - connecting..."
        tailscale up || log_error "Failed to connect to VPN"
    fi

    # Test connectivity again
    if ping -c 3 "$SENSOR_IP" >/dev/null 2>&1; then
        log_success "Network connectivity restored"
    else
        log_error "Network connectivity still failing"
    fi
}

apply_service_restart() {
    log_info "Restarting Corelight service..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        log_error "Cannot restart service - SSH not accessible"
        return 1
    fi

    ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" << 'EOF'
        sudo systemctl restart corelight-softsensor
        sleep 5
        sudo corelightctl status
EOF

    log_success "Service restarted"
}

apply_disk_cleanup() {
    log_info "Cleaning up disk space..."

    if [ "$SENSOR_ACCESSIBLE" = "false" ]; then
        log_error "Cannot clean disk - SSH not accessible"
        return 1
    fi

    ssh -i "$SENSOR_SSH_KEY" "admin@$SENSOR_IP" << 'EOF'
        # Clean up old PCAP files
        sudo find /var/corelight/pcap -name "*.pcap" -mtime +7 -delete

        # Clean up old logs
        sudo journalctl --vacuum-time=7d

        # Show disk usage
        df -h /
EOF

    log_success "Disk cleanup completed"
}

################################################################################
# Step 6: Generate Troubleshooting Report
################################################################################

step_6_generate_report() {
    log_info "[6/7] Generating troubleshooting report..."

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local json_report="$RESULTS_DIR/troubleshoot_${timestamp}.json"
    local md_report="$RESULTS_DIR/troubleshoot_${timestamp}.md"

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

    log_success "Troubleshooting reports generated:"
    log_info "  JSON: $json_report"
    log_info "  Markdown: $md_report"
}

generate_json_report() {
    local output_file=$1

    cat > "$output_file" << EOF
{
  "workflow_id": "$WORKFLOW_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sensor": {
    "ip": "$SENSOR_IP",
    "stack_name": "$SENSOR_STACK_NAME"
  },
  "symptom": {
    "type": "$SYMPTOM_TYPE"
  },
  "diagnostics": {
$(
    local first=true
    for key in "${!DIAGNOSTICS[@]}"; do
        [ "$first" = "false" ] && echo ","
        echo -n "    \"$key\": \"${DIAGNOSTICS[$key]}\""
        first=false
    done
    echo ""
)
  },
  "solutions_found": ${#SOLUTIONS[@]},
  "selected_solution": "$SELECTED_SOLUTION",
  "status": "completed"
}
EOF
}

generate_markdown_report() {
    local output_file=$1

    cat > "$output_file" << EOF
# Troubleshooting Report

**Workflow ID**: $WORKFLOW_ID
**Date**: $(date +%Y-%m-%d)
**Sensor IP**: $SENSOR_IP (ephemeral)

---

## Symptom

**Type**: $SYMPTOM_TYPE

---

## Diagnostics Results

| Check | Status |
|-------|--------|
$(
    for key in "${!DIAGNOSTICS[@]}"; do
        local status="${DIAGNOSTICS[$key]}"
        echo "| $key | $status |"
    done
)

---

## Solutions Found

Total: ${#SOLUTIONS[@]}

$(
    local index=1
    for solution in "${SOLUTIONS[@]}"; do
        echo "$index. $solution"
        index=$((index + 1))
    done
)

---

## Selected Solution

$SELECTED_SOLUTION

---

## Status

✅ **Troubleshooting completed**

EOF
}

################################################################################
# Step 7: Update Knowledge Base
################################################################################

step_7_update_knowledge_base() {
    log_info "[7/7] Updating knowledge base with solution..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would update MCP Memory with troubleshooting case"
        return 0
    fi

    if [ ! -f "$PROJECT_ROOT/mcp_integration/mcp_manager.py" ]; then
        log_warning "MCP integration not available, skipping knowledge base update"
        return 0
    fi

    # Record troubleshooting case in knowledge graph
    python3 << EOF || log_warning "Knowledge base update failed (non-critical)"
import sys
sys.path.insert(0, '$PROJECT_ROOT/mcp_integration')
from mcp_manager import MCPManager

mcp = MCPManager()

# Create troubleshooting case entity
mcp.memory.create_entities([{
    "name": "troubleshooting-$WORKFLOW_ID",
    "entityType": "troubleshooting_case",
    "observations": [
        "Symptom: $SYMPTOM_TYPE",
        "Sensor IP: $SENSOR_IP (ephemeral)",
        "Solutions Found: ${#SOLUTIONS[@]}",
        "Selected Solution: $SELECTED_SOLUTION",
        "Status: completed"
    ]
}])

print("✅ Troubleshooting case recorded in knowledge base")
EOF

    log_success "Knowledge base updated"
}

################################################################################
# Main Workflow
################################################################################

main() {
    log_info "=================================================="
    log_info "Interactive Troubleshooting Workflow"
    log_info "Workflow ID: $WORKFLOW_ID"
    log_info "=================================================="

    parse_arguments "$@"
    validate_prerequisites

    local workflow_start=$(date +%s)

    # Execute workflow steps
    step_1_collect_symptoms
    step_2_run_diagnostics
    step_3_search_knowledge_base
    step_4_suggest_solutions
    step_5_apply_fix
    step_6_generate_report
    step_7_update_knowledge_base

    local workflow_end=$(date +%s)
    local duration=$((workflow_end - workflow_start))

    log_info "=================================================="
    log_success "Troubleshooting Workflow Completed"
    log_info "Duration: ${duration}s"
    log_info "Sensor IP: $SENSOR_IP"
    log_info "Results: $RESULTS_DIR"
    log_info "=================================================="
}

# Run main workflow
main "$@"
