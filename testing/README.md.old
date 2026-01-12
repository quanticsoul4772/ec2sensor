# Testing Framework

This directory contains the test case framework, test data, and test results.

## Directory Structure

```
testing/
├── README.md              # This file
├── test_runner.sh         # Main test orchestrator (coming soon)
├── lib/                   # Test framework libraries
│   └── test_framework.sh
├── test_cases/            # Individual test case scripts
│   ├── template.sh
│   └── JIRA-XXXX_example.sh
├── test_data/             # PCAP files, configs, test files
│   └── .gitkeep
└── test_results/          # Test execution results
    └── .gitkeep
```

## Quick Start

### Running a Test Case

```bash
# Run a specific test case
./testing/test_runner.sh --test JIRA-1234 --sensor my-sensor

# With specific configuration
./testing/test_runner.sh --test JIRA-1234 --sensor my-sensor --config smartpcap_enabled

# Dry run (validate without executing)
./testing/test_runner.sh --test JIRA-1234 --dry-run
```

## Test Case Structure

Each test case is a standalone Bash script that follows this structure:

```bash
#!/bin/bash
# Test Case: JIRA-1234
# Description: Brief description of what this tests

source "$(dirname "$0")/../lib/test_framework.sh"

# Metadata
TEST_NAME="JIRA-1234: Description"
TEST_JIRA="JIRA-1234"
REQUIRED_CONFIG="default"
REQUIRED_PACKAGES=("base_testing_tools")

# Setup
test_setup() {
    log_info "Setting up test"
    # Prepare test environment
}

# Execute
test_execute() {
    log_info "Executing test steps"
    # Run test actions
}

# Verify
test_verify() {
    log_info "Verifying results"
    # Check expected outcomes
    return 0  # 0 = pass, 1 = fail
}

# Cleanup
test_cleanup() {
    log_info "Cleaning up"
    # Remove test artifacts
}

# Run
main() {
    test_init "$TEST_NAME" "$TEST_JIRA"
    test_setup
    test_execute
    test_verify
    test_cleanup
    test_report
}

main "$@"
```

## Creating a New Test Case

1. Copy the template:
```bash
cp testing/test_cases/template.sh testing/test_cases/JIRA-1234_my_test.sh
chmod +x testing/test_cases/JIRA-1234_my_test.sh
```

2. Edit the test case:
   - Update metadata (TEST_NAME, TEST_JIRA, etc.)
   - Implement test_setup()
   - Implement test_execute()
   - Implement test_verify()
   - Add test_cleanup() if needed

3. Test locally:
```bash
./testing/test_cases/JIRA-1234_my_test.sh
```

4. Run through test runner:
```bash
./testing/test_runner.sh --test JIRA-1234
```

## Test Framework Functions

The `lib/test_framework.sh` provides these functions:

### Initialization
- `test_init <name> <jira_issue>` - Initialize test execution

### Logging
- `log_test_info <message>` - Log informational message
- `log_test_error <message>` - Log error message
- `log_test_debug <message>` - Log debug message

### Assertions
- `assert_equals <expected> <actual> <message>`
- `assert_contains <haystack> <needle> <message>`
- `assert_file_exists <file> <message>`
- `assert_command_succeeds <command> <message>`

### Reporting
- `test_report` - Generate test result report (JSON + Markdown)

## Test Results

Test results are stored in `test_results/` with this structure:

```
test_results/
├── JIRA-1234_20251010_143052.log      # Execution log
├── JIRA-1234_20251010_143052.json     # Structured result
└── JIRA-1234_20251010_143052.md       # Human-readable report
```

### JSON Result Format

```json
{
  "test_name": "JIRA-1234: Test Description",
  "jira_issue": "JIRA-1234",
  "start_time": "1696953052",
  "end_time": "1696953152",
  "duration_seconds": 100,
  "result": "PASS",
  "sensor": "ec2-sensor-testing-platform-user-123",
  "config": "default",
  "assertions": {
    "total": 5,
    "passed": 5,
    "failed": 0
  }
}
```

## Test Data

Place test data files in `test_data/`:

```
test_data/
├── pcaps/                  # PCAP files for replay
│   ├── malware_sample.pcap
│   └── high_volume.pcap
├── configs/                # Test configurations
│   └── custom_rules.yaml
└── samples/                # Test files (malware, etc.)
    └── eicar.txt
```

## Best Practices

### Test Case Design
1. **Atomic Tests**: Each test should test one specific thing
2. **Idempotent**: Tests should be repeatable
3. **Independent**: Tests shouldn't depend on other tests
4. **Self-contained**: Include all necessary setup and cleanup

### Naming Conventions
- Test files: `JIRA-XXXX_brief_description.sh`
- Test data: Descriptive names with context
- Results: Auto-generated with timestamp

### Documentation
- Add clear description at top of test file
- Document prerequisites and dependencies
- Explain expected outcomes
- Add troubleshooting notes

## Example Test Cases

### Basic Connectivity Test

```bash
test_execute() {
    # SSH to sensor
    ssh broala@${SENSOR_IP} "corelightctl sensor status"
    assert_command_succeeds $? "Sensor status check"

    # Check HTTP API
    curl -s http://${SENSOR_IP}:8000/health
    assert_command_succeeds $? "HTTP API accessible"
}
```

### SmartPCAP Test

```bash
test_execute() {
    # Verify SmartPCAP enabled
    ssh broala@${SENSOR_IP} "sudo broala-config get smartpcap.enable"
    assert_equals "1" "$?" "SmartPCAP enabled"

    # Check SmartPCAP processes
    ssh broala@${SENSOR_IP} "ps aux | grep spcap"
    assert_contains "spcap-esm" "$?" "SmartPCAP process running"
}
```

## Related Documentation

- [Test Case Creation Guide](../docs/guides/TEST_CASE_CREATION.md)
- [JIRA Workflow](../docs/guides/JIRA_WORKFLOW.md)
- [Test Framework API](../docs/reference/TEST_FRAMEWORK_API.md)
