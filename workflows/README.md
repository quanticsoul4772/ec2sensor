# Workflows

Pre-built workflow scripts for common testing and troubleshooting operations.

## Available Workflows

### JIRA Issue Reproduction

**File**: `reproduce_jira_issue.sh`

Automates the complete workflow for reproducing a JIRA issue on an EC2 sensor.

```bash
./workflows/reproduce_jira_issue.sh APPS-1234
```

**What it does**:
1. Fetches JIRA issue details (from Obsidian or web)
2. Determines required sensor configuration
3. Creates sensor with appropriate config
4. Waits for sensor ready
5. Prepares sensor (enable features, install packages)
6. Executes test case
7. Captures results and evidence
8. Generates report
9. Updates knowledge base

### Fix Validation

**File**: `validate_fix.sh`

Validates that a fix resolves a previously reported issue.

```bash
./workflows/validate_fix.sh APPS-1234 --fixed-version ami-xxxxx
```

**What it does**:
1. Creates sensor with fixed version
2. Runs original failing test case
3. Compares results with original failure
4. Generates validation report
5. Updates JIRA with validation status

### Performance Baseline

**File**: `performance_baseline.sh`

Establishes performance baseline for a sensor version.

```bash
./workflows/performance_baseline.sh --version 28.0.6
```

**What it does**:
1. Creates high-throughput sensor
2. Runs performance test suite
3. Collects metrics (throughput, packet loss, CPU, memory)
4. Generates baseline report
5. Stores in knowledge base for comparison

### Interactive Troubleshooting

**File**: `troubleshoot_sensor.sh`

Interactive troubleshooting assistant for sensor issues.

```bash
./workflows/troubleshoot_sensor.sh
```

**Features**:
- Guided troubleshooting steps
- Automatic diagnostics
- Suggested solutions from knowledge base
- Creates troubleshooting report

## Workflow Patterns

### Standard Test Workflow

```bash
# 1. Create sensor
./sensor_lifecycle.sh create

# 2. Wait for ready
./sensor_lifecycle.sh status  # Repeat until running

# 3. Enable features
./sensor_prep/enable_sensor_features.sh

# 4. Run test
./testing/test_runner.sh --test JIRA-1234

# 5. Review results
cat testing/test_results/JIRA-1234_*.md

# 6. Cleanup
./sensor_lifecycle.sh delete
```

### Quick JIRA Reproduction

```bash
# All-in-one command
./workflows/reproduce_jira_issue.sh APPS-1234

# Results automatically saved to:
# - testing/test_results/APPS-1234_*.{json,md,log}
# - Obsidian vault (if sync enabled)
# - Knowledge graph
```

### Regression Testing

```bash
# Test multiple issues in sequence
for issue in APPS-1234 APPS-1235 APPS-1236; do
    ./workflows/reproduce_jira_issue.sh $issue
done

# Generate summary report
./workflows/generate_regression_report.sh
```

## Custom Workflows

### Creating a Custom Workflow

1. Create new script in `workflows/` directory
2. Follow this template:

```bash
#!/bin/bash
# Custom Workflow Name
# Description of what this workflow does

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../ec2sensor_logging.sh"
log_init

# Workflow logic
main() {
    log_info "Starting custom workflow"

    # Step 1
    # Step 2
    # Step 3

    log_info "Workflow complete"
}

main "$@"
```

3. Make it executable:
```bash
chmod +x workflows/my_custom_workflow.sh
```

### Example: Nightly Cleanup Workflow

```bash
#!/bin/bash
# Nightly cleanup of old sensors and test results

# Delete old sensors (>3 days)
./scripts/cleanup/cleanup_old_sensors.sh --days 3

# Archive old test results
tar -czf test_results_$(date +%Y%m%d).tar.gz testing/test_results/*.log
mv test_results_*.tar.gz archive/

# Clean up test data
find testing/test_data -type f -mtime +7 -delete
```

## Workflow Outputs

All workflows generate consistent outputs:

### Console Output
- Color-coded logging (INFO, WARNING, ERROR)
- Progress indicators
- Real-time status updates

### Log Files
- Stored in `logs/workflow_*.log`
- Timestamped entries
- Full command history

### Reports
- JSON: Structured data for automation
- Markdown: Human-readable reports
- Logs: Detailed execution trace

### Knowledge Updates
- Obsidian notes created/updated
- Knowledge graph entities added
- Test history tracked

## Integration with Other Tools

### Obsidian Integration

Workflows automatically sync with Obsidian vault:
- Test results → `ec2sensor/test-results/`
- Troubleshooting findings → `ec2sensor/troubleshooting/`
- Performance baselines → `ec2sensor/performance/`

### Knowledge Graph

Workflows track relationships:
- JIRA issues → Test cases → Sensors → Results
- Issues → Solutions → Validation status
- Sensor configs → Test outcomes

### JIRA Integration (Future)

Planned JIRA integration:
- Automatic ticket updates
- Evidence attachment
- Status transitions
- Comment posting

## Best Practices

### Workflow Design
1. **Single Responsibility**: One workflow, one purpose
2. **Error Handling**: Graceful failure with cleanup
3. **Logging**: Comprehensive logging at each step
4. **Documentation**: Clear usage examples
5. **Validation**: Verify prerequisites before execution

### Naming Conventions
- Verbs for actions: `reproduce_`, `validate_`, `troubleshoot_`
- Descriptive names: What does it do?
- Consistent format: `action_target.sh`

### Error Recovery
- Always include cleanup steps
- Save partial results
- Provide troubleshooting hints
- Log full error context

## Troubleshooting Workflows

### Workflow Fails to Start

```bash
# Check prerequisites
ls -la workflows/
./sensor_lifecycle.sh status

# Verify permissions
chmod +x workflows/*.sh

# Check logs
tail -f logs/workflow_*.log
```

### Workflow Hangs

```bash
# Check sensor status
./sensor_lifecycle.sh status

# Verify VPN connection
tailscale status

# Check background processes
ps aux | grep sensor
```

### Incomplete Results

```bash
# Check test results directory
ls -la testing/test_results/

# Review logs for errors
grep ERROR logs/workflow_*.log

# Re-run with verbose logging
LOG_LEVEL=DEBUG ./workflows/reproduce_jira_issue.sh APPS-1234
```

## Related Documentation

- [JIRA Workflow Guide](../docs/guides/JIRA_WORKFLOW.md)
- [Test Case Creation](../docs/guides/TEST_CASE_CREATION.md)
- [Sensor Preparation](../sensor_prep/README.md)
- [Testing Framework](../testing/README.md)
