# Phase 5: Workflow Automation - Architecture

**Date**: 2025-10-10
**Status**: Implementation Started

---

## Overview

Phase 5 creates end-to-end automated workflows that orchestrate the entire test lifecycle from JIRA issue to validated fix. These workflows integrate all previous phases (sensor prep, test framework, agents, MCP) into cohesive, single-command operations.

---

## Workflow Components

### 1. JIRA Issue Reproduction Workflow

**File**: `reproduce_jira_issue.sh`
**Purpose**: Complete automation from JIRA ticket to test execution

**Flow**:
```
JIRA Ticket
    ↓
1. Fetch issue details (from Obsidian or manual input)
    ↓
2. Determine sensor requirements (from test case YAML)
    ↓
3. Deploy sensor (via sensor_lifecycle.sh)
    ↓
4. Prepare sensor (features + packages)
    ↓
5. Execute test case (via test_runner.sh)
    ↓
6. Collect results + artifacts
    ↓
7. Sync to MCP (Obsidian + Memory + Exa)
    ↓
8. Generate report (JSON + Markdown)
```

**Integrations**:
- `sensor_lifecycle.sh` - Sensor deployment
- `sensor_prep/prepare_sensor.sh` - Sensor preparation
- `testing/run_test.sh` - Test execution
- `mcp_integration/mcp_manager.py` - MCP sync
- `agents/integration_coordinator/coordinator.py` - Agent orchestration (optional)

**Input**: JIRA ticket ID
**Output**: Test results + report + MCP sync

---

### 2. Fix Validation Workflow

**File**: `validate_fix.sh`
**Purpose**: Verify that a fix resolves the reported issue

**Flow**:
```
JIRA Ticket + Fix Version
    ↓
1. Load original test case + failure data
    ↓
2. Deploy sensor with FIXED version
    ↓
3. Run original failing test
    ↓
4. Compare: Original failure vs Current result
    ↓
5. Validation status: FIXED / STILL_FAILING / REGRESSED
    ↓
6. Generate validation report
    ↓
7. Update MCP with validation status
    ↓
8. (Optional) Update JIRA ticket
```

**Comparison Logic**:
- **FIXED**: Previously failed, now passes
- **STILL_FAILING**: Still fails with same error
- **REGRESSED**: Fails with different error
- **NEW_ISSUE**: Passes but with warnings

**Integrations**:
- Previous test results (from `testing/test_results/`)
- MCP Memory (for test execution history)
- Test framework (for re-execution)

**Input**: JIRA ticket + fixed AMI/version
**Output**: Validation report + comparison matrix

---

### 3. Performance Baseline Workflow

**File**: `performance_baseline.sh`
**Purpose**: Establish performance metrics for sensor versions

**Flow**:
```
Sensor Version
    ↓
1. Deploy high-throughput sensor
    ↓
2. Run performance test suite:
    - Packet processing throughput
    - Packet loss rate
    - CPU utilization
    - Memory usage
    - Disk I/O
    ↓
3. Collect system metrics (top, iostat, netstat)
    ↓
4. Run tcpreplay tests with various loads
    ↓
5. Generate performance baseline report
    ↓
6. Store in knowledge base
    ↓
7. Compare with previous baselines (if exist)
```

**Performance Tests**:
- **Throughput Test**: 1Gbps, 5Gbps, 10Gbps traffic
- **Packet Loss Test**: High packet rate stress test
- **CPU Load Test**: Multi-core utilization
- **Memory Stress**: Large PCAP processing
- **Disk I/O Test**: Log writing performance

**Metrics Collected**:
- Packets processed/sec
- Bytes processed/sec
- Packet loss percentage
- CPU usage (avg, peak)
- Memory usage (avg, peak)
- Disk write throughput
- Sensor response time

**Output**: Performance baseline report + metrics DB entry

---

### 4. Interactive Troubleshooting Workflow

**File**: `troubleshoot_sensor.sh`
**Purpose**: Guided troubleshooting assistant

**Flow**:
```
Sensor Issue Reported
    ↓
1. Interactive symptom collection:
    - What's the problem? (dropdown: connectivity, performance, feature failure, etc.)
    - When did it start?
    - Any recent changes?
    ↓
2. Automated diagnostics:
    - Sensor connectivity check
    - Service status check
    - Configuration validation
    - Log analysis
    ↓
3. Knowledge base search:
    - Similar issues (via MCP Memory)
    - Known solutions (via Exa research)
    - Obsidian troubleshooting notes
    ↓
4. Suggested solutions (ranked by relevance)
    ↓
5. Guided fix application:
    - Step-by-step instructions
    - Verification after each step
    - Rollback if needed
    ↓
6. Generate troubleshooting report
    ↓
7. Update knowledge base with solution
```

**Diagnostics Checks**:
- Network connectivity (ping, traceroute)
- SSH access
- Sensor service status (`corelightctl status`)
- Configuration errors
- Log errors (last 100 lines)
- Disk space
- Memory availability
- Recent configuration changes

**Knowledge Sources**:
- MCP Memory: Similar past issues
- Exa AI: Corelight documentation search
- Obsidian: Troubleshooting playbooks

**Output**: Troubleshooting report + solution applied

---

## Workflow Design Patterns

### Pattern 1: Validation Before Execution

All workflows validate prerequisites before starting:

```bash
validate_prerequisites() {
    # Check VPN connection
    if ! tailscale status >/dev/null 2>&1; then
        log_error "Not connected to Tailscale VPN"
        exit 1
    fi

    # Check sensor API access
    if ! curl -s "$SENSOR_API_URL/health" >/dev/null; then
        log_error "Cannot reach sensor API"
        exit 1
    fi

    # Check required tools
    for tool in jq curl ssh; do
        if ! command -v $tool >/dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
}
```

### Pattern 2: Atomic Operations with Cleanup

All workflows include cleanup on success or failure:

```bash
cleanup() {
    local exit_code=$?

    log_info "Cleaning up workflow resources..."

    # Save partial results
    if [ -f "$TEMP_RESULTS" ]; then
        cp "$TEMP_RESULTS" "$FINAL_RESULTS_DIR/"
    fi

    # Remove temporary files
    rm -rf "$TEMP_DIR"

    # Optionally delete sensor
    if [ "$AUTO_CLEANUP" = "true" ]; then
        ./sensor_lifecycle.sh delete
    fi

    exit $exit_code
}

trap cleanup EXIT INT TERM
```

### Pattern 3: Progress Reporting

All workflows report progress in real-time:

```bash
workflow_step() {
    local step_num=$1
    local total_steps=$2
    local step_desc=$3

    log_info "[$step_num/$total_steps] $step_desc"

    # Execute step
    if ! "$@"; then
        log_error "Step failed: $step_desc"
        return 1
    fi

    log_success "Step complete: $step_desc"
}
```

### Pattern 4: Result Standardization

All workflows generate consistent output:

```json
{
  "workflow_name": "reproduce_jira_issue",
  "workflow_id": "workflow-20251010-143052",
  "jira_ticket": "CORE-5432",
  "started_at": "2025-10-10T14:30:52Z",
  "completed_at": "2025-10-10T14:45:12Z",
  "duration_seconds": 860,
  "status": "success",
  "steps_completed": 8,
  "steps_total": 8,
  "sensor": {
    "stack_name": "ec2-sensor-testing-qa-qarelease-886303774102509885",
    "ip": "10.50.88.154",
    "version": "BroLin 28.4.0-a7"
  },
  "test_result": {
    "test_id": "TEST-001",
    "status": "passed",
    "file": "testing/test_results/TEST-001_20251010.json"
  },
  "artifacts": [
    "testing/test_results/TEST-001_20251010.json",
    "testing/test_results/TEST-001_20251010.md",
    "logs/workflow_reproduce_jira_issue_20251010_143052.log"
  ],
  "mcp_sync": {
    "obsidian": "success",
    "memory": "success",
    "exa": "success"
  }
}
```

---

## Integration Points

### With Previous Phases

**Phase 1 (Foundation)**:
- Use logging infrastructure (`ec2sensor_logging.sh`)
- Use environment configuration (`.env`)

**Phase 2 (Sensor Prep)**:
- Call `prepare_sensor.sh` for sensor setup
- Use configuration profiles
- Install required packages

**Phase 3 (Test Framework)**:
- Execute tests via `run_test.sh`
- Parse YAML test case metadata
- Collect test results

**Phase 4 (MCP Integration)**:
- Sync results to Obsidian
- Update knowledge graph
- Research with Exa AI

### With Agent System (Optional)

Workflows can optionally delegate to agents:

```bash
# Direct execution (simple)
./testing/run_test.sh --test-case TEST-001

# OR

# Agent orchestration (advanced)
python3 agents/integration_coordinator/coordinator.py test_case_execution '{
  "test_case": "TEST-001",
  "sensor_ip": "10.50.88.154"
}'
```

---

## Workflow State Management

### State Files

Workflows maintain state for resumability:

```bash
# .workflow_state/reproduce_jira_issue_CORE-5432.state
{
  "workflow_id": "workflow-20251010-143052",
  "jira_ticket": "CORE-5432",
  "current_step": 5,
  "total_steps": 8,
  "sensor_deployed": true,
  "sensor_ip": "10.50.88.154",
  "sensor_ready": true,
  "test_executed": false,
  "can_resume": true
}
```

### Resume Capability

```bash
# Workflow interrupted at step 5
./workflows/reproduce_jira_issue.sh CORE-5432

# On re-run, check for state file
if [ -f ".workflow_state/reproduce_jira_issue_${JIRA_TICKET}.state" ]; then
    log_info "Found previous workflow state"
    read -p "Resume from step $(jq -r '.current_step' $STATE_FILE)? (y/n) " RESUME

    if [ "$RESUME" = "y" ]; then
        # Skip completed steps
        CURRENT_STEP=$(jq -r '.current_step' $STATE_FILE)
    fi
fi
```

---

## Error Handling Strategy

### Levels of Failure

1. **Soft Failure**: Retry automatically
   - Network timeout → retry 3 times
   - SSH connection failure → retry with backoff
   - API rate limit → wait and retry

2. **Hard Failure**: User intervention required
   - Sensor deployment failed → cleanup and exit
   - Test case not found → exit with error
   - Invalid configuration → exit with error

3. **Partial Success**: Continue with warnings
   - Optional MCP sync failed → log warning, continue
   - Documentation update failed → log warning, continue

### Error Recovery

```bash
with_retry() {
    local max_attempts=3
    local delay=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi

        log_warning "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2))  # Exponential backoff
    done

    log_error "All retry attempts failed"
    return 1
}
```

---

## Performance Considerations

### Parallel Execution

Where possible, execute steps in parallel:

```bash
# Sequential (slow)
prepare_sensor
run_test
sync_mcp

# Parallel (fast)
(
    prepare_sensor &
    fetch_test_case &
    fetch_jira_details &
    wait
)
run_test
(
    sync_obsidian &
    sync_memory &
    sync_exa &
    wait
)
```

### Caching

Cache frequently accessed data:

```bash
# Cache JIRA issue details
CACHE_DIR=".workflow_cache"
JIRA_CACHE="$CACHE_DIR/jira_${JIRA_TICKET}.json"

if [ -f "$JIRA_CACHE" ]; then
    JIRA_DATA=$(cat "$JIRA_CACHE")
else
    JIRA_DATA=$(fetch_jira_issue "$JIRA_TICKET")
    echo "$JIRA_DATA" > "$JIRA_CACHE"
fi
```

---

## Testing Strategy

### Workflow Testing

Each workflow includes:

1. **Unit Tests**: Test individual workflow steps
2. **Integration Tests**: Test full workflow end-to-end
3. **Dry-Run Mode**: Simulate workflow without executing

```bash
# Dry-run mode
./workflows/reproduce_jira_issue.sh CORE-5432 --dry-run

# Output:
# [DRY-RUN] Would deploy sensor with config: default
# [DRY-RUN] Would prepare sensor with packages: base_testing_tools
# [DRY-RUN] Would execute test: TEST-001
# [DRY-RUN] Would sync to MCP
# [DRY-RUN] Would generate report
```

---

## Success Criteria

Phase 5 will be complete when:

- OK: All 4 workflows implemented and tested
- OK: Integration with all previous phases working
- OK: Error handling and recovery robust
- OK: Documentation complete
- OK: Dry-run mode available for all workflows
- OK: Resume capability for long-running workflows
- OK: Standardized output format (JSON + Markdown)

---

## Timeline

**Estimated Duration**: 2-3 days

**Day 1**:
- OK: Architecture design (this document)
- Implement JIRA reproduction workflow
- Implement fix validation workflow

**Day 2**:
- Implement performance baseline workflow
- Implement troubleshooting workflow
- Integration testing

**Day 3**:
- Error handling and edge cases
- Documentation
- End-to-end testing

---

**Status**: Architecture Complete - Ready for Implementation
**Next Step**: Implement `reproduce_jira_issue.sh`
