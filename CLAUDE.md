# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The **EC2 Sensor Testing Platform** is a comprehensive automation framework for testing Corelight sensors deployed on AWS EC2 instances. The platform automates the full lifecycle from JIRA ticket reproduction to validated fixes, with integrated performance testing and AI-powered troubleshooting.

**Architecture**: Modular Bash-based system with three core subsystems (Workflows, Testing, Sensor Preparation), unified logging, environment-based configuration, and MCP integrations for documentation persistence.

## Entry Points

### Primary Interface: sensor.sh

Single command interface for sensor management:

```bash
# Create and manage sensors
./sensor.sh

# Shows menu:
# 1) Select existing sensor to connect
# 2) Create new sensor (auto-enables features, auto-connects)
```

**Features:**
- Multi-sensor tracking in `.sensors` file
- Automatic feature enablement (HTTP, YARA, Suricata, SmartPCAP)
- Waits for full sensor initialization (~20-60 minutes)
- Optional P1 automation preparation (prompted after feature enablement)
- Auto-connects via SSH when ready
- No manual configuration needed

### Advanced Workflows (workflows/)

For complex testing scenarios:

```bash
# JIRA issue reproduction
./workflows/reproduce_jira_issue.sh CORE-5432 [--dry-run] [--no-cleanup]

# Fix validation with baseline comparison
./workflows/validate_fix.sh CORE-5432 --fixed-version ami-0fix123

# Performance testing and comparison
./workflows/performance_baseline.sh "28.5.0" [--compare-with "28.4.0"]

# Troubleshooting with diagnostics
./workflows/troubleshoot_sensor.sh --sensor-ip 10.50.88.154 [--auto-diagnose]
```

### Backend: Sensor Lifecycle CLI (sensor_lifecycle.sh)

Low-level sensor management (called by sensor.sh):

```bash
# Setup once
./sensor_lifecycle.sh setup

# Create sensor (features auto-enabled by default)
./sensor_lifecycle.sh create                # Create sensor, wait, enable features, connect
./sensor_lifecycle.sh status                # Check status and update IP
./sensor_lifecycle.sh connect               # SSH with fallback auth
./sensor_lifecycle.sh enable-features       # Manually enable features if needed
./sensor_lifecycle.sh delete                # Delete sensor

# Diagnostics
./sensor_lifecycle.sh secure                # Verify permissions and credentials
```

**Diagnostic Tools:**
```bash
# Unified diagnostics (scripts/sensor_diagnostics.sh)
./scripts/sensor_diagnostics.sh metrics [ip]      # Check sensor metrics
./scripts/sensor_diagnostics.sh processes [ip]    # Show top processes
./scripts/sensor_diagnostics.sh performance [ip]  # Live performance monitor
./scripts/sensor_diagnostics.sh all [ip]          # Run all diagnostics

# Unified TCP replay (scripts/tcpreplay.sh)
./scripts/tcpreplay.sh install [ip]               # Install tcpreplay
./scripts/tcpreplay.sh setup [ip]                 # Discover pcaps/interfaces
./scripts/tcpreplay.sh start <mbps> <pcap> [ip]   # Start replay

# Readiness checking
./scripts/wait_for_sensor_ready.sh <ip>           # 3-phase readiness check
```

### P1 Automation Preparation

Prepare sensors for API P1/E2E automation testing:

```bash
# Automatic preparation (prompted during sensor creation)
./sensor.sh  # Answer 'y' when prompted for P1 preparation

# Manual preparation
./scripts/prepare_p1_automation.sh <ip>            # Prepare for P1 testing
./scripts/prepare_p1_automation.sh <ip> --upgrade  # Upgrade + prepare
./scripts/prepare_p1_automation.sh <ip> --fleet-ip 192.168.22.228  # Custom fleet

# Fleet manager commands (on sensor)
sudo /opt/broala/bin/broala-config set fleet.community_string=broala && sudo /opt/broala/bin/broala-config set fleet.server=192.168.22.239:1443 && sudo /opt/broala/bin/broala-config set fleet.enable=1 && sudo /opt/broala/bin/broala-apply-config -q  # Add to fleet
sudo /opt/broala/bin/broala-config set fleet.enable=0 && sudo /opt/broala/bin/broala-apply-config -q  # Remove from fleet
```

**P1 Preparation includes:**
- Admin password configuration
- PCAP replay mode disabled
- Suricata verified/enabled
- SmartPCAP verified/enabled
- Sensor added to fleet manager (default: 192.168.22.239:1443)
- Optional: Upgrade to latest build

**Documentation:** See `docs/P1_AUTOMATION_PREP.md` for complete guide including pipeline setup and infrastructure details.

## Architecture

### Three-Tier Subsystem Design

**1. Workflow Layer (workflows/)**
- High-level orchestration of multi-step operations
- Manages state, cleanup, and error recovery
- Integrates with all subsystems
- Output: Test results, reports, MCP sync

**2. Testing Subsystem (testing/)**
- `lib/test_framework.sh` - Core test execution library with `test_init()`, `test_step()`, `test_validate()`, `test_report()`
- `test_cases/` - YAML test case definitions with metadata, steps, and expected outcomes
- `run_test.sh` - Standalone test runner
- `test_results/` - JSON + Markdown execution results

**3. Sensor Preparation Subsystem (sensor_prep/)**
- `prepare_sensor.sh` - 7-step orchestrator: version detection → feature enablement → package installation → snapshot creation
- `configs/*.yaml` - Configuration profiles (default, smartpcap_enabled, suricata_test, high_throughput)
- `enable_sensor_features_v2.sh` - Dual-API feature enablement (legacy < 28.0, modern ≥ 28.4.0)
- `packages/*.sh` - Modular package installers (testing tools, suricata, smartpcap, performance monitoring)
- `snapshots/snapshot_manager_v2.sh` - AMI snapshot management

### Cross-Cutting Concerns

**Logging System (`ec2sensor_logging.sh`):**
- Functions: `log_init`, `log_info`, `log_debug`, `log_error`, `log_warning`, `log_fatal`
- Specialized: `log_api`, `log_ssh`, `log_cmd` for operation-specific logging
- Features: Automatic 10MB rotation, 30-day retention, color-coded console output, structured file logging
- Log files: `logs/sensor_lifecycle_YYYYMMDD_HHMMSS.log`

**Environment Management:**
- `.env` stores credentials (600 permissions) and dynamic sensor state
- `env.example` is the template (note: contains actual API key for shared test environment)
- `scripts/load_env.sh` loads and validates environment variables
- Sensor-specific variables (`SENSOR_NAME`, `SSH_HOST`, `SENSOR_CREATED_AT`) dynamically managed
- API credentials (`EC2_SENSOR_API_KEY`, `EC2_SENSOR_BASE_URL`) persist across sensor lifecycles

**MCP Integration (`mcp_integration/`):**
- `mcp_manager.py` - Unified Python-based MCP manager
- Obsidian connector: Permanent test execution records in `Test-Executions/` folder
- Memory Graph connector: Knowledge graph relationships between tests, issues, fixes
- Exa AI connector: Research and troubleshooting assistance
- Non-blocking: MCP failures don't stop workflows

### Ephemeral Sensor Model

**Critical Design Decision**: Sensors are ephemeral, test executions are permanent.

- Sensors auto-delete after 4 days (AWS lifecycle policy)
- Sensor IPs change with every deployment and nightly restart
- Platform tracks test executions (permanent) not sensors (ephemeral)
- `.env` dynamically updated with current sensor state
- Workflows automatically clean up sensors on completion
- Test results persisted to MCP before sensor deletion

See `docs/architecture/EPHEMERAL_SENSOR_MODEL.md` for full rationale.

## API Integration

**Base URL:** `https://w5f1gqx5g0.execute-api.us-east-1.amazonaws.com/prod/ec2_sensor`

**Endpoints:**
- `POST /create` - Create sensor (returns `ec2_sensor_name`)
- `GET /{sensor_name}` - Get status (returns `sensor_ip`, `sensor_status`, `brolin_version`)
- `DELETE /{sensor_name}` - Delete sensor

**Authentication:** All requests require `x-api-key` header

**Important Behaviors:**
- 15-20 minute initialization after creation (sensor goes from "starting" → "running")
- `sensor_ip` only available when `sensor_status="running"`
- Sensors restart nightly at ~2 AM UTC (IP may change)
- 4-day auto-deletion enforced by AWS

**API Version Detection:**
- Legacy API: `< 28.0` - Uses `GET /status` endpoint, different response format
- Modern API: `≥ 28.4.0` - Uses `GET /{sensor_name}` endpoint, standardized response
- Auto-detection in `sensor_prep/detect_sensor_version.sh`

## SSH Connection Strategy

**Standard Credentials** (all sensors):
- Username: `broala`
- Password: `your_ssh_password_here`

**Authentication Fallback Order:**
1. SSH key at `~/.ssh/ec2_sensor_key` (if exists, must be 600 permissions)
2. Password via `sshpass` (uses `SSH_PASSWORD` from `.env`)
3. Manual password entry (fallback)

**Network Requirements:**
- Tailscale VPN connection required (`tailscale status` to verify)
- Sensor IPs are internal AWS IPs (e.g., `10.50.88.x`)
- Each sensor gets a unique IP address
- IPs tracked in `.env` (manual) or `automation/state/sensor_*.env` (daily automation)
- SSH timeout: 10 seconds default (`ConnectTimeout=10`)

## Code Style & Patterns

### Variable Naming
- `UPPER_SNAKE_CASE` for constants and environment variables
- `lower_snake_case` for local function variables
- Global state in workflows: `WORKFLOW_STATE`, `SENSOR_NAME`, `TEST_RESULTS_FILE`

### Error Handling
```bash
# Capture exit codes explicitly
result=$(some_command) || status=$?

# Log operations before executing
log_api "POST /create" "Creating sensor: $name"
response=$(curl ...) || { log_error "API call failed"; return 1; }

# Exit with proper codes
exit 0  # Success
exit 1  # General error
exit 2  # Usage error
```

### Security Patterns
- Environment variables sourced via `load_env.sh`, never hardcoded
- File permissions enforced: 600 for `.env`, 600 for SSH keys, 644 for logs
- Sensitive data never logged (use placeholders: `log_api "Authenticating with key: ***"`)
- `verify_security()` function in `sensor_lifecycle.sh` checks for hardcoded credentials and permissions
- Use `./sensor_lifecycle.sh secure` to audit and fix permissions

### JSON Handling
```bash
# Parse with jq (with fallback)
if command -v jq &> /dev/null; then
    sensor_ip=$(echo "$response" | jq -r '.sensor_ip // "unavailable"')
else
    sensor_ip=$(echo "$response" | grep -oP '"sensor_ip":\s*"\K[^"]+' || echo "unavailable")
fi

# Pretty-print responses
echo "$response" | jq '.' 2>/dev/null || echo "$response"

# Extract nested fields with defaults
jq -r '.results.metrics.cpu_usage // 0'
```

### State Management in Workflows
```bash
# Save state for resumability
STATE_DIR="$PROJECT_ROOT/.workflow_state"
STATE_FILE="$STATE_DIR/${WORKFLOW_NAME}_${JIRA_TICKET}.state"

save_state() {
    cat > "$STATE_FILE" <<EOF
CURRENT_STEP="$1"
SENSOR_NAME="$SENSOR_NAME"
TEST_CASE_ID="$TEST_CASE_ID"
TIMESTAMP="$(date +%s)"
EOF
}

# Load state on --resume
if [ "$RESUME" = true ] && [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
    log_info "Resuming from step: $CURRENT_STEP"
fi
```

### Atomic Operations with Cleanup
```bash
# Setup trap for cleanup on exit
trap cleanup EXIT INT TERM

cleanup() {
    local exit_code=$?
    if [ "$AUTO_CLEANUP" = true ] && [ -n "$SENSOR_NAME" ]; then
        log_info "Cleaning up sensor: $SENSOR_NAME"
        ./sensor_lifecycle.sh delete
    fi
    exit $exit_code
}
```

## Test Framework Patterns

### YAML Test Case Structure
```yaml
metadata:
  id: TEST-001
  title: "YARA Enable/Disable Test"
  jira_ticket: CORE-5432
  sensor_version: "28.4.0"
  tags: [yara, configuration]

requirements:
  features: [yara]
  packages: [yara_testing_tools]
  config: default

steps:
  - number: 1
    description: "Enable YARA processing"
    command: "sudo corelight-softsensor ctl feature enable yara"
    expected_output: "YARA enabled successfully"

validation:
  success_criteria:
    - "YARA feature enabled"
    - "No errors in sensor logs"
```

### Test Execution Pattern
```bash
# Initialize test
source "$PROJECT_ROOT/testing/lib/test_framework.sh"
test_init "TEST-001_yara_enable_disable"

# Execute steps with validation
test_step 1 "Enable YARA" "$SENSOR_IP" \
    "sudo corelight-softsensor ctl feature enable yara" \
    "enabled successfully"

# Generate report
test_report "TEST-001" "$TEST_RESULTS_FILE"
```

## Sensor Configuration Profiles

Four pre-built profiles in `sensor_prep/configs/`:

1. **default.yaml** - Minimal setup for general testing
2. **smartpcap_enabled.yaml** - SmartPCAP + PCAP replay capabilities
3. **suricata_test.yaml** - Suricata IDS testing with custom rules
4. **high_throughput.yaml** - Performance testing with tuned buffers and CPU pinning

**Usage in workflows:**
```bash
./workflows/reproduce_jira_issue.sh CORE-5432 --config smartpcap_enabled
```

## Common Development Tasks

### Adding a New Workflow

1. Create script in `workflows/` following naming: `{action}_{noun}.sh`
2. Source logging: `source "$PROJECT_ROOT/ec2sensor_logging.sh"`
3. Implement state management with `STATE_DIR` and state save/load
4. Add cleanup trap: `trap cleanup EXIT INT TERM`
5. Add `--dry-run` mode for validation
6. Document in `workflows/README.md`
7. Add example to this file

### Adding a New Test Case

1. Create YAML in `testing/test_cases/` following template
2. Define metadata with JIRA ticket, version, tags
3. Specify requirements (features, packages, config profile)
4. Define steps with commands and expected outputs
5. Add validation criteria
6. Test with: `./testing/run_test.sh TEST-XXX_name`

### Adding Sensor Feature Enablement

1. Add detection logic to `sensor_prep/detect_sensor_version.sh`
2. Add enablement for both APIs in `sensor_prep/enable_sensor_features_v2.sh`:
   - Legacy path: `< 28.0`
   - Modern path: `≥ 28.4.0`
3. Update relevant config profiles in `sensor_prep/configs/`
4. Test with both old and new sensor versions

### Modifying Environment Variables

1. Update `env.example` with new variable and comment
2. Add validation in `scripts/load_env.sh` if required
3. Update `setup_credentials()` in `sensor_lifecycle.sh` if user input needed
4. Document in this file under Environment Management

### Adding MCP Integration

1. Add connector logic to `mcp_integration/`
2. Update `mcp_manager.py` with new connector
3. Handle failures gracefully (MCP is non-blocking)
4. Test with `--dry-run` first
5. Document expected MCP structure

## Troubleshooting

### Quick Diagnostics

```bash
# Comprehensive health check
./health_check.sh

# Check VPN connection (required)
tailscale status

# Check AWS credentials
aws sts get-caller-identity

# View recent errors
grep ERROR logs/*.log | tail -20

# Check environment
source scripts/load_env.sh && env | grep -E '(SENSOR|SSH|API)'

# Verify security
./sensor_lifecycle.sh secure
```

### Common Issues

**Workflow fails to start**
- Check script permissions: `chmod +x workflows/*.sh`
- Verify prerequisites: `which jq curl ssh python3 sshpass`

**SSH connection fails**
- Verify VPN: `tailscale status`
- Check sensor status: `./sensor_lifecycle.sh status`
- Verify SSH key permissions: `chmod 600 ~/.ssh/ec2_sensor_key`
- Check IP is current: Sensor IPs change on nightly restart

**Sensor deployment fails**
- Check CloudFormation console for stack errors
- Verify AWS credentials: `aws sts get-caller-identity`
- Check API key in `.env`
- Wait for initialization: ~15-20 minutes after creation

**Test execution hangs**
- Verify Tailscale VPN: `tailscale up`
- Check sensor is "running": `./sensor_lifecycle.sh status`
- Verify SSH works: `ssh broala@<sensor_ip>`
- Check test case YAML syntax

**MCP sync fails**
- Non-critical, workflow continues
- Verify `mcp_manager.py` dependencies: `python3 -m pip list | grep -E '(obsidian|anthropic)'`
- Check Obsidian vault path in config
- Review logs: `grep MCP logs/*.log`

### Debug Commands

```bash
# Watch logs in real-time
tail -f logs/sensor_lifecycle_*.log

# Test workflow without execution
./workflows/reproduce_jira_issue.sh CORE-5432 --dry-run

# Resume interrupted workflow
./workflows/reproduce_jira_issue.sh CORE-5432 --resume

# Compare two sensors
./compare_sensors.sh

# Check sensor metrics
./check_sensor_metrics.sh

# Run specific test
./testing/run_test.sh TEST-001_yara_enable_disable --sensor 10.50.88.154
```

## Important Notes

### Sensor Lifecycle Timing
- **Creation**: ~5 minutes for CloudFormation stack
- **Initialization**: ~15-20 minutes for sensor to reach "running" state
- **Nightly Restart**: ~2 AM UTC (IP address may change)
- **Auto-Deletion**: 4 days after creation

### Workflow State
- All workflows save state to `.workflow_state/` for `--resume` capability
- State includes: current step, sensor name, test case ID, timestamp
- Cleanup happens even on failure via `trap` handlers
- Use `--no-cleanup` to preserve sensor for debugging

### MCP Integration Behavior
- MCP operations are non-blocking (failures don't stop workflows)
- Results synced to Obsidian in `Test-Executions/` folder
- Memory Graph tracks relationships between tests, issues, fixes
- Exa AI used for research and troubleshooting assistance

### Performance Considerations
- Sensor preparation (features + packages): ~10 minutes
- Test execution: Varies by test (5-30 minutes typical)
- Performance baseline workflow: ~30-40 minutes
- Full JIRA reproduction workflow: ~25-35 minutes

## Documentation Structure

- `README.md` - Quick start and overview
- `workflows/QUICK_START.md` - 5-minute workflow introduction
- `docs/USER_GUIDE.md` - Comprehensive end-user guide
- `docs/DEVELOPER_GUIDE.md` - Architecture and development patterns
- `docs/TROUBLESHOOTING_GUIDE.md` - Common issues and solutions
- `docs/architecture/` - Architecture decision records
- `{subsystem}/README.md` - Subsystem-specific documentation
