#!/usr/bin/env python3
"""
Obsidian MCP Connector
Syncs test results, sensor configurations, and documentation to Obsidian vault
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class ObsidianConnector:
    """Connector for Obsidian MCP integration"""

    def __init__(self, vault_path: str = None, config_file: str = None):
        """
        Initialize Obsidian connector

        Args:
            vault_path: Path to Obsidian vault (optional, reads from config)
            config_file: Path to MCP config file (optional)
        """
        self.project_root = Path(__file__).parent.parent.parent
        self.mcp_root = self.project_root / "mcp_integration"

        # Load configuration
        if config_file:
            self.config = self._load_config(config_file)
        else:
            # Default configuration
            self.config = {
                "vault_path": vault_path or "/Users/russellsmith/obsidian/corelight",
                "enabled": True,
                "sync_on_test_complete": True,
                "sync_on_documentation": True
            }

        self.vault_path = Path(self.config["vault_path"])

        # Ensure vault directories exist
        self._ensure_vault_structure()

    def _load_config(self, config_file: str) -> Dict:
        """Load MCP configuration from file"""
        try:
            import yaml
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            return config.get("obsidian", {})
        except Exception as e:
            print(f"[OBSIDIAN] Warning: Could not load config: {e}")
            return {"enabled": True}

    def _ensure_vault_structure(self):
        """Create necessary directories in Obsidian vault"""
        directories = [
            self.vault_path / "Sensors",
            self.vault_path / "Tests",
            self.vault_path / "JIRA",
            self.vault_path / "Documentation"
        ]

        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)

    def sync_test_execution(self, test_id: str, result_file: str,
                           sensor_deployment: Dict = None) -> Dict:
        """
        Sync test execution result to Obsidian vault

        NOTE: Sensors are ephemeral (auto-delete after 4 days).
        We track test EXECUTIONS, not persistent sensors.

        Args:
            test_id: Test case ID (e.g., "TEST-001")
            result_file: Path to JSON result file
            sensor_deployment: Dict with stack_name, ip, version, deployed_at, delete_at

        Returns:
            Dict with sync status
        """
        print(f"[OBSIDIAN] Syncing test execution: {test_id}")

        if not self.config.get("enabled", True):
            return {"success": False, "message": "Obsidian sync disabled"}

        try:
            # Load test result
            with open(result_file, 'r') as f:
                result_data = json.load(f)

            # Generate execution ID and path
            now = datetime.now()
            execution_timestamp = now.strftime("%Y%m%d-%H%M%S")
            execution_id = f"{test_id}-{execution_timestamp}"
            year_month = now.strftime("%Y-%m")

            # Create year-month directory
            executions_dir = self.vault_path / "Test-Executions" / year_month
            executions_dir.mkdir(parents=True, exist_ok=True)

            vault_path = f"Test-Executions/{year_month}/{execution_id}.md"

            # Generate note content
            note_content = self._generate_execution_note(
                test_id, execution_id, result_data, sensor_deployment
            )

            # Create note in vault
            note_path = str(self.vault_path / vault_path)

            # Write note directly (MCP call would go here in production)
            with open(note_path, 'w') as f:
                f.write(note_content)

            print(f"[OBSIDIAN] ✅ Test execution synced to: {note_path}")

            return {
                "success": True,
                "execution_id": execution_id,
                "vault_path": vault_path,
                "note_path": note_path
            }

        except Exception as e:
            print(f"[OBSIDIAN] ❌ Sync failed: {str(e)}")
            return {
                "success": False,
                "error": str(e)
            }

    def _generate_execution_note(self, test_id: str, execution_id: str,
                                 result_data: Dict, sensor_deployment: Dict = None) -> str:
        """
        Generate Obsidian note content for test execution

        NOTE: Emphasizes that sensors are ephemeral and will auto-delete
        """
        test_case = result_data.get("test_case", "Unknown")
        sensor_ip = result_data.get("sensor_ip", "Unknown")
        status = result_data.get("status", "unknown")
        steps_passed = result_data.get("steps_passed", 0)
        steps_failed = result_data.get("steps_failed", 0)
        started_at = result_data.get("started_at", "")
        completed_at = result_data.get("completed_at", "")

        # Calculate duration if possible
        duration = "Unknown"
        if started_at and completed_at:
            try:
                from dateutil import parser
                start = parser.isoparse(started_at)
                end = parser.isoparse(completed_at)
                delta = end - start
                minutes = delta.total_seconds() / 60
                duration = f"{int(minutes)}m {int(delta.total_seconds() % 60)}s"
            except:
                pass

        # Status emoji
        status_emoji = "✅" if status == "passed" else "❌"

        # Build note content
        content = f"""# {test_id} Execution - {datetime.now().strftime("%Y-%m-%d")}

## Execution Details
- **Execution ID**: `{execution_id}`
- **Test Case**: [[{test_id}|Test Case Details]]
- **Status**: {status_emoji} **{status.upper()}**
- **Started**: {started_at}
- **Completed**: {completed_at}
- **Duration**: {duration}

## Sensor Deployment (⚠️ Ephemeral)

> **Note**: This sensor is temporary and will auto-delete 4 days after deployment.
> IP addresses are session identifiers only and will change on next test run.

"""

        # Add sensor deployment details if provided
        if sensor_deployment:
            stack_name = sensor_deployment.get('stack_name', 'Unknown')
            deployed_at = sensor_deployment.get('deployed_at', 'Unknown')
            delete_at = sensor_deployment.get('delete_at', 'Unknown')
            version = sensor_deployment.get('version', 'Unknown')

            content += f"""- **Stack Name**: `{stack_name}`
- **IP Address**: `{sensor_ip}` ⚠️ *Temporary*
- **Version**: {version}
- **Deployed**: {deployed_at}
- **Auto-Delete**: {delete_at}
- **Configuration**: {sensor_deployment.get('configuration', 'default')}

"""
        else:
            content += f"- **IP Address**: `{sensor_ip}` ⚠️ *Ephemeral - will auto-delete in 4 days*\n\n"

        # Test Results Summary
        content += f"""## Test Results

{status_emoji} **Test {status.upper()}**
- **Steps Passed**: {steps_passed}
- **Steps Failed**: {steps_failed}
- **Total Steps**: {steps_passed + steps_failed}
- **Success Rate**: {(steps_passed / (steps_passed + steps_failed) * 100) if (steps_passed + steps_failed) > 0 else 0:.1f}%

## Test Steps

"""

        # Add test steps
        for idx, step in enumerate(result_data.get("test_steps", []), 1):
            step_status = step.get("status", "unknown")
            step_emoji = "✅" if step_status == "passed" else "❌"
            description = step.get("description", "No description")

            content += f"### Step {idx}: {description} {step_emoji}\n\n"

            if step.get("output"):
                output = step['output'][:300]  # Limit output
                content += f"**Output**:\n```\n{output}\n```\n\n"

            if step.get("error"):
                content += f"**Error**:\n```\n{step['error']}\n```\n\n"

        # Add artifacts section
        content += f"""## Artifacts
- **Result File**: `testing/test_results/{test_id}_{execution_id}.json`
- **Report**: `testing/test_results/{test_id}_{execution_id}.md`
- **Test Case**: `testing/test_cases/{test_case}`

"""

        # Add tags
        year_month = datetime.now().strftime("%Y-%m")
        content += f"""## Tags

#test-execution #{test_id.lower()} #{status}-status #{year_month.replace('-', '_')}

"""

        # Add related links
        content += f"""## Related
- [[{test_id}|Test Case]]
- [[Test-Results-Dashboard]]
- [[Test-Executions Index]]
"""

        return content

    def sync_sensor_info(self, sensor_ip: str, sensor_data: Dict) -> Dict:
        """
        Sync sensor information to Obsidian vault

        Args:
            sensor_ip: Sensor IP address
            sensor_data: Sensor configuration and status data

        Returns:
            Dict with sync status
        """
        print(f"[OBSIDIAN] Syncing sensor info: {sensor_ip}")

        try:
            # Generate note content
            note_content = self._generate_sensor_note(sensor_ip, sensor_data)

            # Create note in vault
            vault_path = f"Sensors/{sensor_ip}.md"
            note_path = str(self.vault_path / vault_path)

            with open(note_path, 'w') as f:
                f.write(note_content)

            print(f"[OBSIDIAN] ✅ Sensor info synced to: {note_path}")

            return {
                "success": True,
                "vault_path": vault_path,
                "note_path": note_path
            }

        except Exception as e:
            print(f"[OBSIDIAN] ❌ Sync failed: {str(e)}")
            return {
                "success": False,
                "error": str(e)
            }

    def _generate_sensor_note(self, sensor_ip: str, sensor_data: Dict) -> str:
        """Generate Obsidian note content for sensor"""
        content = f"""# Sensor: {sensor_ip}

## Configuration

- **IP Address**: `{sensor_ip}`
- **Version**: {sensor_data.get('version', 'Unknown')}
- **Configuration Profile**: {sensor_data.get('configuration', 'default')}
- **Status**: {sensor_data.get('status', 'unknown')}

## Features

- **YARA**: {sensor_data.get('yara_enabled', 'Unknown')}
- **Suricata**: {sensor_data.get('suricata_enabled', 'Unknown')}
- **SmartPCAP**: {sensor_data.get('smartpcap_enabled', 'Unknown')}

## Recent Tests

"""

        # Add recent tests if available
        recent_tests = sensor_data.get('recent_tests', [])
        if recent_tests:
            for test in recent_tests:
                content += f"- [[{test}]]\n"
        else:
            content += "No recent tests\n"

        # Add tags
        content += f"\n## Tags\n\n#sensor #ip-{sensor_ip.replace('.', '-')}\n"

        return content

    def sync_jira_info(self, jira_ticket: str, jira_data: Dict) -> Dict:
        """
        Sync JIRA ticket information to Obsidian vault

        Args:
            jira_ticket: JIRA ticket ID (e.g., "CORE-5432")
            jira_data: JIRA ticket data

        Returns:
            Dict with sync status
        """
        print(f"[OBSIDIAN] Syncing JIRA info: {jira_ticket}")

        try:
            # Generate note content
            note_content = self._generate_jira_note(jira_ticket, jira_data)

            # Create note in vault
            vault_path = f"JIRA/{jira_ticket}.md"
            note_path = str(self.vault_path / vault_path)

            with open(note_path, 'w') as f:
                f.write(note_content)

            print(f"[OBSIDIAN] ✅ JIRA info synced to: {note_path}")

            return {
                "success": True,
                "vault_path": vault_path,
                "note_path": note_path
            }

        except Exception as e:
            print(f"[OBSIDIAN] ❌ Sync failed: {str(e)}")
            return {
                "success": False,
                "error": str(e)
            }

    def _generate_jira_note(self, jira_ticket: str, jira_data: Dict) -> str:
        """Generate Obsidian note content for JIRA ticket"""
        title = jira_data.get('title', 'Unknown')
        description = jira_data.get('description', 'No description available')
        priority = jira_data.get('priority', 'Unknown')
        status = jira_data.get('status', 'Unknown')

        content = f"""# {jira_ticket}: {title}

## Details

- **Ticket**: {jira_ticket}
- **Priority**: {priority}
- **Status**: {status}
- **Created**: {jira_data.get('created', 'Unknown')}
- **Updated**: {jira_data.get('updated', 'Unknown')}

## Description

{description}

## Linked Tests

"""

        # Add linked tests
        linked_tests = jira_data.get('linked_tests', [])
        if linked_tests:
            for test in linked_tests:
                content += f"- [[{test}]]\n"
        else:
            content += "No linked tests yet\n"

        # Add tags
        content += f"\n## Tags\n\n#jira #{jira_ticket.lower().replace('-', '_')}\n"

        return content

    def search_tests(self, query: str, limit: int = 10) -> List[str]:
        """
        Search for tests in Obsidian vault

        Args:
            query: Search query
            limit: Maximum results to return

        Returns:
            List of matching note paths
        """
        print(f"[OBSIDIAN] Searching tests: {query}")

        # In production, this would use obsidian_search_text MCP function
        # For now, simple file search
        results = []
        tests_dir = self.vault_path / "Tests"

        if tests_dir.exists():
            for note_file in tests_dir.glob("*.md"):
                with open(note_file, 'r') as f:
                    content = f.read()
                    if query.lower() in content.lower():
                        results.append(str(note_file))

                if len(results) >= limit:
                    break

        return results

    def get_sensor_tests(self, sensor_ip: str) -> List[str]:
        """
        Get all tests run on a specific sensor

        Args:
            sensor_ip: Sensor IP address

        Returns:
            List of test note paths
        """
        print(f"[OBSIDIAN] Getting tests for sensor: {sensor_ip}")

        # Search for tests mentioning this sensor
        return self.search_tests(sensor_ip)

    def create_index_note(self, note_type: str = "tests") -> Dict:
        """
        Create index note for tests, sensors, or JIRA tickets

        Args:
            note_type: Type of index ("tests", "sensors", "jira")

        Returns:
            Dict with creation status
        """
        print(f"[OBSIDIAN] Creating {note_type} index note")

        try:
            if note_type == "tests":
                directory = self.vault_path / "Tests"
                index_path = directory / "Test-Results-Index.md"
                content = self._generate_test_index(directory)
            elif note_type == "sensors":
                directory = self.vault_path / "Sensors"
                index_path = directory / "Sensors-Index.md"
                content = self._generate_sensor_index(directory)
            elif note_type == "jira":
                directory = self.vault_path / "JIRA"
                index_path = directory / "JIRA-Index.md"
                content = self._generate_jira_index(directory)
            else:
                return {"success": False, "error": f"Unknown index type: {note_type}"}

            with open(index_path, 'w') as f:
                f.write(content)

            print(f"[OBSIDIAN] ✅ Index note created: {index_path}")

            return {
                "success": True,
                "index_path": str(index_path)
            }

        except Exception as e:
            print(f"[OBSIDIAN] ❌ Index creation failed: {str(e)}")
            return {
                "success": False,
                "error": str(e)
            }

    def _generate_test_index(self, directory: Path) -> str:
        """Generate test results index"""
        content = f"# Test Results Index\n\n"
        content += f"**Last Updated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        content += f"## All Test Results\n\n"

        # List all test notes
        if directory.exists():
            test_files = sorted(directory.glob("TEST-*.md"), reverse=True)
            for test_file in test_files:
                content += f"- [[{test_file.stem}]]\n"

        content += f"\n## Tags\n\n#index #test-results\n"

        return content

    def _generate_sensor_index(self, directory: Path) -> str:
        """Generate sensors index"""
        content = f"# Sensors Index\n\n"
        content += f"**Last Updated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        content += f"## All Sensors\n\n"

        # List all sensor notes
        if directory.exists():
            sensor_files = sorted(directory.glob("*.md"))
            for sensor_file in sensor_files:
                if sensor_file.name != "Sensors-Index.md":
                    content += f"- [[{sensor_file.stem}]]\n"

        content += f"\n## Tags\n\n#index #sensors\n"

        return content

    def _generate_jira_index(self, directory: Path) -> str:
        """Generate JIRA tickets index"""
        content = f"# JIRA Tickets Index\n\n"
        content += f"**Last Updated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        content += f"## All JIRA Tickets\n\n"

        # List all JIRA notes
        if directory.exists():
            jira_files = sorted(directory.glob("CORE-*.md"))
            for jira_file in jira_files:
                content += f"- [[{jira_file.stem}]]\n"

        content += f"\n## Tags\n\n#index #jira\n"

        return content


def main():
    """Test Obsidian connector"""
    connector = ObsidianConnector()

    print("Obsidian Connector Test")
    print("=" * 60)
    print(f"Vault Path: {connector.vault_path}")
    print(f"Enabled: {connector.config.get('enabled')}")
    print()

    # Test creating index notes
    connector.create_index_note("tests")
    connector.create_index_note("sensors")
    connector.create_index_note("jira")

    print("\n✅ Obsidian connector test complete")


if __name__ == "__main__":
    main()
