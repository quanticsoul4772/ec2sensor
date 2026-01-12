#!/bin/bash
#
# Test Runner
# Execute a test case via the Test Executor Agent
#

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Usage
usage() {
    cat <<EOF
Usage: $0 [options] <test_case_file> <sensor_ip>

Execute a test case on a sensor.

Arguments:
  test_case_file    Test case YAML file (e.g., TEST-001_yara_enable_disable.yaml)
  sensor_ip         Sensor IP address

Options:
  -h, --help        Show this help message
  -v, --validate    Validate test results after execution
  -l, --list        List available test cases

Examples:
  # Run a test
  $0 TEST-001_yara_enable_disable.yaml 10.50.88.154

  # Run test and validate results
  $0 --validate TEST-001_yara_enable_disable.yaml 10.50.88.154

  # List available test cases
  $0 --list
EOF
    exit 0
}

# List test cases
list_tests() {
    echo "Available Test Cases:"
    echo "===================="

    cd "${PROJECT_ROOT}/testing/test_cases"
    for test in *.yaml; do
        if [ "$test" = "test_case_template.yaml" ]; then
            continue
        fi

        test_id=$(grep 'test_id:' "$test" | head -1 | awk '{print $2}' | tr -d '"')
        title=$(grep 'title:' "$test" | head -1 | sed 's/.*title: *"\(.*\)"/\1/')
        jira=$(grep 'jira_ticket:' "$test" | head -1 | awk '{print $2}' | tr -d '"')

        echo ""
        echo "File: $test"
        echo "  ID: $test_id"
        echo "  Title: $title"
        echo "  JIRA: $jira"
    done
    exit 0
}

# Parse arguments
VALIDATE=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -l|--list)
            list_tests
            ;;
        -v|--validate)
            VALIDATE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [ $# -lt 2 ]; then
    echo "Error: Missing required arguments"
    echo ""
    usage
fi

TEST_CASE="$1"
SENSOR_IP="$2"

# Verify test case exists
TEST_CASE_PATH="${PROJECT_ROOT}/testing/test_cases/${TEST_CASE}"
if [ ! -f "$TEST_CASE_PATH" ]; then
    echo "Error: Test case not found: $TEST_CASE"
    echo "Use --list to see available test cases"
    exit 1
fi

# Source .env for SSH credentials
if [ -f "${PROJECT_ROOT}/.env" ]; then
    set +u
    source "${PROJECT_ROOT}/.env"
    set -u
fi

# Run test via Python agent
echo "=================================================="
echo "Running Test Case: $TEST_CASE"
echo "Sensor IP: $SENSOR_IP"
echo "=================================================="
echo ""

cd "$PROJECT_ROOT"

python3 <<EOF
import sys
from pathlib import Path
sys.path.insert(0, str(Path('$PROJECT_ROOT')))

from agents.test_executor.test_executor import TestExecutorAgent

agent = TestExecutorAgent()
result = agent.execute_test_steps('$TEST_CASE', '$SENSOR_IP')

print("\n" + "="*50)
print("Test Execution Complete")
print("="*50)
print(f"Status: {result.get('test_id', 'unknown')}")
print(f"Success: {result['success']}")
print(f"Steps Executed: {result['steps_executed']}")
print(f"Steps Passed: {result['steps_passed']}")
print(f"Steps Failed: {result['steps_failed']}")
print(f"Result File: {result.get('result_file', 'N/A')}")

# Store result file for validation
result_file = result.get('result_file')
exit(0 if result['success'] else 1)
EOF

TEST_EXIT_CODE=$?

# Validate if requested
if [ "$VALIDATE" = true ]; then
    echo ""
    echo "=================================================="
    echo "Validating Test Results"
    echo "=================================================="
    echo ""

    python3 <<EOF
import sys
from pathlib import Path
sys.path.insert(0, str(Path('$PROJECT_ROOT')))

from agents.test_executor.test_executor import TestExecutorAgent

agent = TestExecutorAgent()
result = agent.validate_results('$TEST_CASE')

print("Validation Results:")
print(f"  Success: {result['success']}")
print(f"  All Validations Passed: {result['validation_results']['all_passed']}")

for validation in result['validation_results']['validations']:
    status = '✅' if validation['passed'] else '❌'
    print(f"  {status} {validation.get('type', 'unknown')}: {validation.get('description', '')}")

exit(0 if result['success'] else 1)
EOF

    VALIDATE_EXIT_CODE=$?

    if [ $VALIDATE_EXIT_CODE -ne 0 ]; then
        echo ""
        echo "❌ Validation FAILED"
        exit 1
    fi
fi

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Test PASSED"
else
    echo ""
    echo "❌ Test FAILED"
fi

exit $TEST_EXIT_CODE
