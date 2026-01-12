#!/usr/bin/env python3
"""
Example MCP Workflow
Demonstrates how to integrate MCP Manager with test execution
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from mcp_integration.mcp_manager import MCPManager


def example_test_execution_workflow():
    """
    Example: Complete test execution workflow with MCP integration

    This demonstrates how to integrate MCP Manager with your test execution:
    1. Run test case
    2. Generate test results
    3. Record to all MCP systems (Obsidian, Memory, Exa)
    4. Query verification status
    """
    print("=" * 60)
    print("Example: Test Execution with MCP Integration")
    print("=" * 60)

    # Initialize MCP Manager
    mcp = MCPManager()

    # Step 1: Simulate test execution
    print("\n[STEP 1] Executing test case...")
    test_id = "TEST-001"
    jira_ticket = "CORE-5432"

    # Get sensor deployment info from environment or config
    # In real usage, this would come from CloudFormation outputs
    sensor_deployment = {
        "stack_name": os.getenv("SENSOR_STACK_NAME", "ec2-sensor-testing-qa-qarelease-886303774102509885"),
        "ip": os.getenv("SSH_HOST", "10.50.88.154"),
        "version": os.getenv("SENSOR_VERSION", "BroLin 28.4.0-a7"),
        "configuration": "default",
        "deployed_at": datetime.now().isoformat(),
        "delete_at": (datetime.now() + timedelta(days=4)).isoformat()
    }

    print(f"   Test: {test_id}")
    print(f"   JIRA: {jira_ticket}")
    print(f"   Sensor: {sensor_deployment['stack_name']}")
    print(f"   IP: {sensor_deployment['ip']} (ephemeral)")

    # Step 2: Create mock test result
    print("\n[STEP 2] Generating test results...")
    result_file = Path(__file__).parent.parent / "testing" / "test_results" / f"{test_id}_workflow_example.json"
    result_file.parent.mkdir(parents=True, exist_ok=True)

    test_result = {
        "test_id": test_id,
        "test_title": "YARA Enable/Disable Test",
        "jira_ticket": jira_ticket,
        "status": "passed",
        "steps_passed": 9,
        "steps_failed": 0,
        "total_steps": 9,
        "started_at": datetime.now().isoformat(),
        "completed_at": (datetime.now() + timedelta(minutes=4, seconds=20)).isoformat(),
        "duration_seconds": 260,
        "steps": [
            {"step": 1, "name": "Get sensor configuration", "status": "passed"},
            {"step": 2, "name": "Enable YARA feature", "status": "passed"},
            {"step": 3, "name": "Wait for service restart", "status": "passed"},
            {"step": 4, "name": "Verify YARA enabled", "status": "passed"},
            {"step": 5, "name": "Check sensor health", "status": "passed"},
            {"step": 6, "name": "Disable YARA feature", "status": "passed"},
            {"step": 7, "name": "Wait for service restart", "status": "passed"},
            {"step": 8, "name": "Verify YARA disabled", "status": "passed"},
            {"step": 9, "name": "Restore baseline config", "status": "passed"}
        ]
    }

    with open(result_file, 'w') as f:
        json.dump(test_result, f, indent=2)

    print(f"   ✅ Results saved: {result_file}")

    # Step 3: Record to MCP systems
    print("\n[STEP 3] Recording to MCP systems...")
    mcp_result = mcp.record_test_execution(
        test_id=test_id,
        jira_ticket=jira_ticket,
        result_file=str(result_file),
        sensor_deployment=sensor_deployment
    )

    if mcp_result["success"]:
        print("   ✅ MCP recording successful")
        if mcp_result.get("obsidian"):
            print(f"      📝 Obsidian: {mcp_result['obsidian'].get('vault_path')}")
        if mcp_result.get("memory"):
            print(f"      🧠 Memory: {mcp_result['memory'].get('relations_created')} relations created")
        if mcp_result.get("exa"):
            findings = len(mcp_result['exa'].get('findings', []))
            print(f"      🔍 Exa: {findings} research findings available")
    else:
        print("   ❌ MCP recording had errors")

    # Step 4: Query JIRA verification status
    print("\n[STEP 4] Querying JIRA verification status...")
    jira_status = mcp.query_jira_status(jira_ticket)
    print(f"   Verification Status: {jira_status.get('verification_status')}")
    print(f"   Total Attempts: {jira_status.get('total_attempts')}")
    print(f"   Last Validated: {jira_status.get('last_validated')}")

    # Step 5: Query test statistics
    print("\n[STEP 5] Querying test case statistics...")
    test_stats = mcp.query_test_statistics(test_id)
    print(f"   Total Executions: {test_stats.get('total_executions')}")
    print(f"   Success Rate: {test_stats.get('success_rate')}%")
    print(f"   Average Duration: {test_stats.get('average_duration_seconds')}s")

    print("\n✅ Example workflow complete")
    print("\nNext steps:")
    print("  1. Open Obsidian vault to view execution note")
    print(f"     Path: {mcp.get_obsidian_vault_path()}/Test-Executions/")
    print("  2. Check knowledge graph for relationships")
    print("  3. Review Exa research findings for JIRA ticket")


def example_test_failure_workflow():
    """
    Example: Test failure troubleshooting workflow

    Demonstrates how to use Exa research for test failures
    """
    print("\n" + "=" * 60)
    print("Example: Test Failure Troubleshooting")
    print("=" * 60)

    mcp = MCPManager()

    # Simulate test failure
    test_id = "TEST-002"
    error_message = "Configuration key not found: license.yara.enable"
    sensor_version = "BroLin 28.4.0-a7"

    print(f"\n[FAILURE] {test_id} failed")
    print(f"   Error: {error_message}")
    print(f"   Sensor: {sensor_version}")

    # Research the failure
    print("\n[RESEARCH] Investigating failure with Exa AI...")
    research = mcp.research_test_failure(
        test_id=test_id,
        error_message=error_message,
        sensor_version=sensor_version
    )

    if research.get("success"):
        print("\n[TROUBLESHOOTING STEPS]")
        for i, step in enumerate(research.get("troubleshooting_steps", []), 1):
            print(f"   {i}. {step}")

        print("\n[SIMILAR ISSUES]")
        for issue in research.get("similar_issues", []):
            print(f"   - {issue.get('title')}")
            print(f"     Resolution: {issue.get('resolution')}")

        print("\n[DOCUMENTATION]")
        for doc in research.get("documentation", []):
            print(f"   - {doc}")

    print("\n✅ Troubleshooting research complete")


def example_test_case_generation():
    """
    Example: Test case generation workflow

    Demonstrates how to use Exa to suggest test cases for a JIRA ticket
    """
    print("\n" + "=" * 60)
    print("Example: Test Case Generation")
    print("=" * 60)

    mcp = MCPManager()

    jira_ticket = "CORE-6789"
    feature_description = "Suricata rule update and reload"

    print(f"\n[JIRA] {jira_ticket}")
    print(f"   Feature: {feature_description}")

    print("\n[RESEARCH] Generating test case suggestions...")
    suggestions = mcp.suggest_test_cases(
        jira_ticket=jira_ticket,
        feature_description=feature_description
    )

    if suggestions.get("success"):
        print("\n[SUGGESTED TEST CASES]")
        for test in suggestions.get("suggested_tests", []):
            print(f"\n   {test.get('test_id')}: {test.get('title')}")
            print(f"   Priority: {test.get('priority')}")
            print(f"   Description: {test.get('description')}")
            print(f"   Steps:")
            for step in test.get('steps', []):
                print(f"      - {step}")

        print("\n[BEST PRACTICES]")
        for practice in suggestions.get("best_practices", []):
            print(f"   - {practice}")

    print("\n✅ Test case generation complete")


def example_integration_with_existing_code():
    """
    Example: How to integrate with existing test executor

    Shows the minimal changes needed to add MCP integration
    """
    print("\n" + "=" * 60)
    print("Example: Integration with Existing Code")
    print("=" * 60)

    print("""
This is how you would integrate MCP Manager with your existing test executor:

1. In your test executor agent (agents/test_executor/test_executor_agent.py):

```python
from mcp_integration.mcp_manager import MCPManager

class TestExecutorAgent:
    def __init__(self):
        # ... existing initialization ...

        # NEW: Initialize MCP Manager
        self.mcp = MCPManager()

    def execute_test(self, test_case_file: str) -> Dict:
        # ... existing test execution code ...

        # After test execution completes:
        result_file = self._save_test_results(test_case_file, results)

        # NEW: Record to MCP systems
        sensor_deployment = {
            'stack_name': os.getenv('SENSOR_STACK_NAME'),
            'ip': os.getenv('SSH_HOST'),
            'version': self._get_sensor_version(),
            'deployed_at': os.getenv('SENSOR_DEPLOYED_AT'),
            'delete_at': self._calculate_delete_time(),  # +4 days
            'configuration': 'default'
        }

        self.mcp.record_test_execution(
            test_id=test_metadata['test_id'],
            jira_ticket=test_metadata['jira_ticket'],
            result_file=result_file,
            sensor_deployment=sensor_deployment
        )

        return results
```

2. Benefits of this integration:
   ✅ Test executions automatically sync to Obsidian vault
   ✅ Knowledge graph tracks all relationships
   ✅ JIRA verification status is queryable
   ✅ AI research available for troubleshooting
   ✅ Historical audit trail maintained

3. No changes needed to:
   - Test case YAML format
   - SSH execution logic
   - Result reporting
   - Cleanup procedures
""")


def main():
    """Run all example workflows"""

    # Example 1: Normal test execution
    example_test_execution_workflow()

    # Example 2: Test failure troubleshooting
    example_test_failure_workflow()

    # Example 3: Test case generation
    example_test_case_generation()

    # Example 4: Integration guide
    example_integration_with_existing_code()

    print("\n" + "=" * 60)
    print("All examples complete!")
    print("=" * 60)
    print("\nTo integrate MCP into your workflow:")
    print("  1. Update Documentation Agent to call mcp.record_test_execution()")
    print("  2. Optionally use mcp.research_test_failure() for failed tests")
    print("  3. Use mcp.suggest_test_cases() when creating new tests")
    print("  4. Query mcp.query_jira_status() to check verification status")


if __name__ == "__main__":
    main()
