#!/usr/bin/env python3
"""
Memory MCP Connector
Builds knowledge graph of test executions, test cases, JIRA issues, and sensor deployments
"""

import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional


class MemoryConnector:
    """Connector for Memory MCP integration (knowledge graph)"""

    def __init__(self, config_file: str = None):
        """
        Initialize Memory connector

        Args:
            config_file: Path to MCP config file (optional)
        """
        self.project_root = Path(__file__).parent.parent.parent
        self.mcp_root = self.project_root / "mcp_integration"

        # Load configuration
        if config_file:
            self.config = self._load_config(config_file)
        else:
            self.config = {
                "enabled": True,
                "auto_create_entities": True,
                "auto_create_relations": True
            }

    def _load_config(self, config_file: str) -> Dict:
        """Load MCP configuration from file"""
        try:
            import yaml
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            return config.get("memory", {})
        except Exception as e:
            print(f"[MEMORY] Warning: Could not load config: {e}")
            return {"enabled": True}

    def create_test_execution_entity(self, execution_id: str, test_id: str,
                                    jira_ticket: str, result: Dict,
                                    sensor_deployment: Dict = None) -> Dict:
        """
        Create test execution entity in knowledge graph

        Args:
            execution_id: Unique execution ID (e.g., "execution-TEST-001-20251010-143052")
            test_id: Test case ID (e.g., "TEST-001")
            jira_ticket: JIRA ticket (e.g., "CORE-5432")
            result: Test execution result dict
            sensor_deployment: Sensor deployment details (ephemeral)

        Returns:
            Dict with creation status
        """
        print(f"[MEMORY] Creating test execution entity: {execution_id}")

        if not self.config.get("enabled", True):
            return {"success": False, "message": "Memory integration disabled"}

        try:
            # Build observations
            observations = [
                f"Test Case: {test_id}",
                f"JIRA Ticket: {jira_ticket}",
                f"Status: {result.get('status', 'unknown')}",
                f"Steps Passed: {result.get('steps_passed', 0)}",
                f"Steps Failed: {result.get('steps_failed', 0)}",
                f"Started: {result.get('started_at', 'unknown')}",
                f"Completed: {result.get('completed_at', 'unknown')}",
            ]

            # Add sensor deployment info (ephemeral)
            if sensor_deployment:
                stack_name = sensor_deployment.get('stack_name', 'unknown')
                sensor_ip = sensor_deployment.get('ip', 'unknown')
                delete_at = sensor_deployment.get('delete_at', 'unknown')
                observations.extend([
                    f"Sensor Deployment: {stack_name} (ephemeral)",
                    f"Sensor IP: {sensor_ip} (temporary)",
                    f"Sensor Auto-Delete: {delete_at}"
                ])

            # Create entity using MCP (simulated here)
            entity = {
                "name": execution_id,
                "entityType": "test_execution",
                "observations": observations
            }

            # In production, this would call:
            # mcp__memory__create_entities(entities=[entity])

            print(f"[MEMORY] ✅ Test execution entity created: {execution_id}")

            return {
                "success": True,
                "entity_id": execution_id,
                "entity": entity
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Entity creation failed: {str(e)}")
            return {
                "success": False,
                "error": str(e)
            }

    def create_test_case_entity(self, test_id: str, test_metadata: Dict) -> Dict:
        """
        Create or update test case entity

        Args:
            test_id: Test case ID (e.g., "TEST-001")
            test_metadata: Test case metadata (title, JIRA, category, etc.)

        Returns:
            Dict with creation status
        """
        print(f"[MEMORY] Creating test case entity: {test_id}")

        try:
            observations = [
                f"Title: {test_metadata.get('title', 'Unknown')}",
                f"JIRA: {test_metadata.get('jira_ticket', 'Unknown')}",
                f"File: {test_metadata.get('file', 'Unknown')}",
                f"Category: {test_metadata.get('category', 'Unknown')}",
                f"Priority: {test_metadata.get('priority', 'Unknown')}",
                f"Steps: {test_metadata.get('steps', 0)}",
            ]

            # Add execution statistics if available
            if 'total_executions' in test_metadata:
                observations.extend([
                    f"Total Executions: {test_metadata['total_executions']}",
                    f"Successful: {test_metadata.get('successful_executions', 0)}",
                    f"Failed: {test_metadata.get('failed_executions', 0)}",
                    f"Success Rate: {test_metadata.get('success_rate', 0)}%"
                ])

            entity = {
                "name": test_id,
                "entityType": "test_case",
                "observations": observations
            }

            # In production: mcp__memory__create_entities(entities=[entity])

            print(f"[MEMORY] ✅ Test case entity created: {test_id}")

            return {
                "success": True,
                "entity_id": test_id,
                "entity": entity
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Entity creation failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def create_jira_entity(self, jira_ticket: str, jira_data: Dict) -> Dict:
        """
        Create or update JIRA issue entity

        Args:
            jira_ticket: JIRA ticket ID (e.g., "CORE-5432")
            jira_data: JIRA issue data

        Returns:
            Dict with creation status
        """
        print(f"[MEMORY] Creating JIRA entity: {jira_ticket}")

        try:
            observations = [
                f"Title: {jira_data.get('title', 'Unknown')}",
                f"Type: {jira_data.get('type', 'Unknown')}",
                f"Priority: {jira_data.get('priority', 'Unknown')}",
                f"Status: {jira_data.get('status', 'Unknown')}",
                f"Created: {jira_data.get('created', 'Unknown')}",
            ]

            # Add verification info if available
            if 'verification_status' in jira_data:
                observations.extend([
                    f"Verification Status: {jira_data['verification_status']}",
                    f"Total Validation Attempts: {jira_data.get('validation_attempts', 0)}",
                    f"Last Validated: {jira_data.get('last_validated', 'Never')}"
                ])

            entity = {
                "name": jira_ticket,
                "entityType": "jira_issue",
                "observations": observations
            }

            # In production: mcp__memory__create_entities(entities=[entity])

            print(f"[MEMORY] ✅ JIRA entity created: {jira_ticket}")

            return {
                "success": True,
                "entity_id": jira_ticket,
                "entity": entity
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Entity creation failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def create_sensor_deployment_entity(self, stack_name: str,
                                       deployment_data: Dict) -> Dict:
        """
        Create sensor deployment entity (ephemeral)

        NOTE: Sensor deployments are temporary and auto-delete after 4 days

        Args:
            stack_name: Unique stack name
            deployment_data: Deployment details (IP, version, config, deployed_at, delete_at)

        Returns:
            Dict with creation status
        """
        print(f"[MEMORY] Creating sensor deployment entity: {stack_name}")

        try:
            # Calculate days until deletion
            deployed_at = deployment_data.get('deployed_at')
            delete_at = deployment_data.get('delete_at')

            observations = [
                f"Stack Name: {stack_name}",
                f"IP Address: {deployment_data.get('ip', 'unknown')} (ephemeral)",
                f"Version: {deployment_data.get('version', 'unknown')}",
                f"Configuration: {deployment_data.get('configuration', 'default')}",
                f"Instance Type: {deployment_data.get('instance_type', 'unknown')}",
                f"Deployed At: {deployed_at}",
                f"Auto-Delete At: {delete_at} (4 days after deployment)",
                f"Status: ephemeral - will be deleted",
            ]

            # Check if already deleted
            if delete_at:
                try:
                    from dateutil import parser
                    delete_date = parser.isoparse(delete_at)
                    if datetime.now(delete_date.tzinfo) > delete_date:
                        observations.append("Status: DELETED")
                except:
                    pass

            entity = {
                "name": f"deployment-{stack_name}",
                "entityType": "sensor_deployment",
                "observations": observations
            }

            # In production: mcp__memory__create_entities(entities=[entity])

            print(f"[MEMORY] ✅ Sensor deployment entity created: {stack_name}")

            return {
                "success": True,
                "entity_id": f"deployment-{stack_name}",
                "entity": entity
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Entity creation failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def create_relations(self, relations: List[Dict]) -> Dict:
        """
        Create multiple relations between entities

        Args:
            relations: List of relation dicts with 'from', 'to', 'relationType'

        Returns:
            Dict with creation status
        """
        print(f"[MEMORY] Creating {len(relations)} relations")

        try:
            # In production: mcp__memory__create_relations(relations=relations)

            for relation in relations:
                print(f"[MEMORY]   {relation['from']} → {relation['relationType']} → {relation['to']}")

            print(f"[MEMORY] ✅ Relations created")

            return {
                "success": True,
                "relations_created": len(relations)
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Relation creation failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def record_test_execution(self, execution_id: str, test_id: str,
                             jira_ticket: str, result: Dict,
                             sensor_deployment: Dict = None) -> Dict:
        """
        Complete workflow: Create execution entity and all relations

        Args:
            execution_id: Unique execution ID
            test_id: Test case ID
            jira_ticket: JIRA ticket
            result: Test result
            sensor_deployment: Sensor deployment details

        Returns:
            Dict with status
        """
        print(f"[MEMORY] Recording test execution: {execution_id}")

        try:
            # 1. Create test execution entity
            exec_result = self.create_test_execution_entity(
                execution_id, test_id, jira_ticket, result, sensor_deployment
            )

            if not exec_result["success"]:
                return exec_result

            # 2. Create relations
            relations = [
                {
                    "from": execution_id,
                    "to": test_id,
                    "relationType": "executes"
                },
                {
                    "from": execution_id,
                    "to": jira_ticket,
                    "relationType": "validates"
                },
                {
                    "from": test_id,
                    "to": jira_ticket,
                    "relationType": "verifies"
                }
            ]

            # Add sensor deployment relation if provided
            if sensor_deployment:
                stack_name = sensor_deployment.get('stack_name')
                if stack_name:
                    relations.append({
                        "from": execution_id,
                        "to": f"deployment-{stack_name}",
                        "relationType": "uses_deployment"
                    })

            self.create_relations(relations)

            print(f"[MEMORY] ✅ Test execution recorded successfully")

            return {
                "success": True,
                "execution_id": execution_id,
                "relations_created": len(relations)
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Recording failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def query_jira_verification_status(self, jira_ticket: str) -> Dict:
        """
        Query verification status for a JIRA ticket

        Args:
            jira_ticket: JIRA ticket ID

        Returns:
            Dict with verification history
        """
        print(f"[MEMORY] Querying verification status: {jira_ticket}")

        # In production, this would call:
        # search_nodes(query=f"{jira_ticket} validated_by")
        # Then parse the results to get all executions

        # Simulated response
        return {
            "success": True,
            "jira_ticket": jira_ticket,
            "verification_status": "verified",
            "total_attempts": 3,
            "successful_attempts": 3,
            "last_validated": "2025-10-10T14:35:12Z",
            "executions": [
                "execution-TEST-001-20251010-143052",
                "execution-TEST-001-20251009-101234",
                "execution-TEST-001-20251008-153045"
            ]
        }

    def query_test_case_statistics(self, test_id: str) -> Dict:
        """
        Query statistics for a test case

        Args:
            test_id: Test case ID

        Returns:
            Dict with test statistics
        """
        print(f"[MEMORY] Querying test statistics: {test_id}")

        # In production: search_nodes(query=f"{test_id} has_executions")

        return {
            "success": True,
            "test_id": test_id,
            "total_executions": 5,
            "successful": 5,
            "failed": 0,
            "success_rate": 100.0,
            "average_duration_seconds": 255,
            "last_run": "2025-10-10T14:35:12Z"
        }

    def query_deployment_usage(self, stack_name: str) -> Dict:
        """
        Query what tests were run on a sensor deployment

        Args:
            stack_name: Sensor stack name

        Returns:
            Dict with deployment usage
        """
        print(f"[MEMORY] Querying deployment usage: {stack_name}")

        # In production: search_nodes(query=f"deployment-{stack_name} hosted")

        return {
            "success": True,
            "deployment": f"deployment-{stack_name}",
            "tests_executed": [
                "execution-TEST-001-20251010-143052",
                "execution-TEST-002-20251010-150012",
                "execution-TEST-003-20251010-163045"
            ],
            "deployment_purpose": "JIRA CORE-5432 validation",
            "status": "deleted"
        }

    def update_jira_verification_status(self, jira_ticket: str,
                                       status: str, execution_id: str) -> Dict:
        """
        Update JIRA verification status after test execution

        Args:
            jira_ticket: JIRA ticket ID
            status: New status (e.g., "verified", "failed", "in_testing")
            execution_id: Execution that changed the status

        Returns:
            Dict with update status
        """
        print(f"[MEMORY] Updating JIRA status: {jira_ticket} → {status}")

        try:
            # Add observation to JIRA entity
            observations = [
                f"Status updated to: {status}",
                f"Updated by execution: {execution_id}",
                f"Updated at: {datetime.now().isoformat()}"
            ]

            # In production: mcp__memory__add_observations(
            #     observations=[{
            #         "entityName": jira_ticket,
            #         "contents": observations
            #     }]
            # )

            print(f"[MEMORY] ✅ JIRA status updated")

            return {
                "success": True,
                "jira_ticket": jira_ticket,
                "new_status": status
            }

        except Exception as e:
            print(f"[MEMORY] ❌ Status update failed: {str(e)}")
            return {"success": False, "error": str(e)}


def main():
    """Test Memory connector"""
    connector = MemoryConnector()

    print("Memory Connector Test")
    print("=" * 60)
    print(f"Enabled: {connector.config.get('enabled')}")
    print()

    # Test creating entities
    print("Creating Test Execution Entity...")
    execution_id = "execution-TEST-001-20251010-143052"
    test_id = "TEST-001"
    jira_ticket = "CORE-5432"
    result = {
        "status": "passed",
        "steps_passed": 9,
        "steps_failed": 0,
        "started_at": "2025-10-10T14:30:52Z",
        "completed_at": "2025-10-10T14:35:12Z"
    }
    sensor_deployment = {
        "stack_name": "ec2-sensor-testing-qa-qarelease-886303774102509885",
        "ip": "10.50.88.154",
        "version": "BroLin 28.4.0-a7",
        "configuration": "default",
        "deployed_at": "2025-10-10T14:00:00Z",
        "delete_at": "2025-10-14T14:00:00Z"
    }

    connector.record_test_execution(
        execution_id, test_id, jira_ticket, result, sensor_deployment
    )

    print("\n" + "=" * 60)
    print("Querying JIRA Verification Status...")
    status = connector.query_jira_verification_status("CORE-5432")
    print(f"Status: {status['verification_status']}")
    print(f"Attempts: {status['total_attempts']}")

    print("\n✅ Memory connector test complete")


if __name__ == "__main__":
    main()
