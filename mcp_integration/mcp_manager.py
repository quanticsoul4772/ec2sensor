#!/usr/bin/env python3
"""
Unified MCP Manager
Single interface to coordinate all MCP integrations (Obsidian, Memory, Exa)
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import sys
sys.path.insert(0, str(Path(__file__).parent))

from obsidian.obsidian_connector import ObsidianConnector
from memory.memory_connector import MemoryConnector
from exa.exa_connector import ExaConnector


class MCPManager:
    """Unified manager for all MCP integrations"""

    def __init__(self, config_file: str = None):
        """
        Initialize MCP Manager

        Args:
            config_file: Path to MCP config file (optional)
        """
        self.project_root = Path(__file__).parent.parent
        self.mcp_root = self.project_root / "mcp_integration"

        # Load configuration
        if config_file:
            self.config = self._load_config(config_file)
        else:
            self.config = {
                "enabled": True,
                "obsidian": {"enabled": True},
                "memory": {"enabled": True},
                "exa": {"enabled": True}
            }

        # Initialize connectors
        self.obsidian = ObsidianConnector(config_file) if self.config.get("obsidian", {}).get("enabled") else None
        self.memory = MemoryConnector(config_file) if self.config.get("memory", {}).get("enabled") else None
        self.exa = ExaConnector(config_file) if self.config.get("exa", {}).get("enabled") else None

        print("[MCP] Manager initialized")
        print(f"[MCP]   Obsidian: {'✅' if self.obsidian else '❌'}")
        print(f"[MCP]   Memory: {'✅' if self.memory else '❌'}")
        print(f"[MCP]   Exa: {'✅' if self.exa else '❌'}")

    def _load_config(self, config_file: str) -> Dict:
        """Load MCP configuration from file"""
        try:
            import yaml
            with open(config_file, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            print(f"[MCP] Warning: Could not load config: {e}")
            return {"enabled": True}

    def record_test_execution(self, test_id: str, jira_ticket: str,
                             result_file: str, sensor_deployment: Dict) -> Dict:
        """
        Complete workflow: Record test execution across all MCP systems

        This is the PRIMARY METHOD for recording test executions.
        It coordinates all three MCP integrations:
        1. Obsidian: Create execution note in vault
        2. Memory: Create entities and relations in knowledge graph
        3. Exa: Cache research for the JIRA ticket (if not already cached)

        Args:
            test_id: Test case ID (e.g., "TEST-001")
            jira_ticket: JIRA ticket ID (e.g., "CORE-5432")
            result_file: Path to JSON result file
            sensor_deployment: Dict with:
                - stack_name: Unique stack identifier
                - ip: Sensor IP address (ephemeral)
                - version: Sensor version
                - deployed_at: Deployment timestamp (ISO format)
                - delete_at: Auto-delete timestamp (ISO format, +4 days)
                - configuration: Configuration profile used

        Returns:
            Dict with status for each integration
        """
        print(f"[MCP] Recording test execution: {test_id}")
        print(f"[MCP]   JIRA: {jira_ticket}")
        print(f"[MCP]   Sensor: {sensor_deployment.get('stack_name', 'unknown')}")

        results = {
            "success": True,
            "test_id": test_id,
            "jira_ticket": jira_ticket,
            "obsidian": None,
            "memory": None,
            "exa": None
        }

        # Load test result data
        try:
            with open(result_file, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            print(f"[MCP] ❌ Failed to load result file: {e}")
            results["success"] = False
            results["error"] = str(e)
            return results

        # Generate execution ID
        now = datetime.now()
        execution_timestamp = now.strftime("%Y%m%d-%H%M%S")
        execution_id = f"execution-{test_id}-{execution_timestamp}"

        # 1. Obsidian: Create execution note
        if self.obsidian:
            try:
                print("[MCP] 📝 Syncing to Obsidian vault...")
                obsidian_result = self.obsidian.sync_test_execution(
                    test_id=test_id,
                    result_file=result_file,
                    sensor_deployment=sensor_deployment
                )
                results["obsidian"] = obsidian_result
                if obsidian_result.get("success"):
                    print(f"[MCP]   ✅ Obsidian: {obsidian_result.get('vault_path')}")
                else:
                    print(f"[MCP]   ❌ Obsidian failed: {obsidian_result.get('error')}")
                    results["success"] = False
            except Exception as e:
                print(f"[MCP]   ❌ Obsidian error: {e}")
                results["obsidian"] = {"success": False, "error": str(e)}
                results["success"] = False

        # 2. Memory: Create knowledge graph entities
        if self.memory:
            try:
                print("[MCP] 🧠 Creating knowledge graph entities...")
                memory_result = self.memory.record_test_execution(
                    execution_id=execution_id,
                    test_id=test_id,
                    jira_ticket=jira_ticket,
                    result=result_data,
                    sensor_deployment=sensor_deployment
                )
                results["memory"] = memory_result
                if memory_result.get("success"):
                    print(f"[MCP]   ✅ Memory: {memory_result.get('relations_created')} relations")
                else:
                    print(f"[MCP]   ❌ Memory failed: {memory_result.get('error')}")
                    results["success"] = False
            except Exception as e:
                print(f"[MCP]   ❌ Memory error: {e}")
                results["memory"] = {"success": False, "error": str(e)}
                results["success"] = False

        # 3. Exa: Research JIRA (if needed)
        if self.exa:
            try:
                print("[MCP] 🔍 Checking Exa research cache...")
                # Only research if not already cached
                exa_result = self.exa.research_jira_issue(
                    jira_ticket=jira_ticket,
                    issue_description=result_data.get("test_title", "")
                )
                results["exa"] = exa_result
                if exa_result.get("success"):
                    findings = len(exa_result.get("findings", []))
                    print(f"[MCP]   ✅ Exa: {findings} research findings available")
                else:
                    print(f"[MCP]   ⚠️  Exa warning: {exa_result.get('error')}")
                    # Don't mark overall as failed for Exa issues
            except Exception as e:
                print(f"[MCP]   ⚠️  Exa error: {e}")
                results["exa"] = {"success": False, "error": str(e)}
                # Don't mark overall as failed for Exa issues

        if results["success"]:
            print(f"[MCP] ✅ Test execution recorded successfully")
        else:
            print(f"[MCP] ⚠️  Test execution recording completed with errors")

        return results

    def research_test_failure(self, test_id: str, error_message: str,
                              sensor_version: str = None) -> Dict:
        """
        Research why a test failed using Exa AI

        Args:
            test_id: Test case ID
            error_message: Error message from failure
            sensor_version: Sensor version (optional)

        Returns:
            Dict with troubleshooting information
        """
        print(f"[MCP] Researching test failure: {test_id}")

        if not self.exa:
            return {"success": False, "message": "Exa integration disabled"}

        return self.exa.research_test_failure(
            test_id=test_id,
            error_message=error_message,
            sensor_version=sensor_version
        )

    def suggest_test_cases(self, jira_ticket: str,
                          feature_description: str) -> Dict:
        """
        Generate test case suggestions using Exa AI

        Args:
            jira_ticket: JIRA ticket ID
            feature_description: Description of feature to test

        Returns:
            Dict with test case suggestions
        """
        print(f"[MCP] Generating test suggestions for: {jira_ticket}")

        if not self.exa:
            return {"success": False, "message": "Exa integration disabled"}

        return self.exa.suggest_test_cases(
            jira_ticket=jira_ticket,
            feature_description=feature_description
        )

    def query_jira_status(self, jira_ticket: str) -> Dict:
        """
        Query JIRA verification status from knowledge graph

        Args:
            jira_ticket: JIRA ticket ID

        Returns:
            Dict with verification status and history
        """
        print(f"[MCP] Querying JIRA status: {jira_ticket}")

        if not self.memory:
            return {"success": False, "message": "Memory integration disabled"}

        return self.memory.query_jira_verification_status(jira_ticket)

    def query_test_statistics(self, test_id: str) -> Dict:
        """
        Query test case statistics from knowledge graph

        Args:
            test_id: Test case ID

        Returns:
            Dict with test statistics
        """
        print(f"[MCP] Querying test statistics: {test_id}")

        if not self.memory:
            return {"success": False, "message": "Memory integration disabled"}

        return self.memory.query_test_case_statistics(test_id)

    def get_obsidian_vault_path(self) -> Optional[Path]:
        """Get path to Obsidian vault"""
        if self.obsidian:
            return self.obsidian.vault_path
        return None

    def clear_research_cache(self, cache_key: str = None):
        """
        Clear Exa research cache

        Args:
            cache_key: Specific cache key to clear, or None for all
        """
        if self.exa:
            self.exa.clear_cache(cache_key)
        else:
            print("[MCP] Exa integration disabled")

    def health_check(self) -> Dict:
        """
        Check health of all MCP integrations

        Returns:
            Dict with health status for each service
        """
        print("[MCP] Running health check...")

        health = {
            "overall": True,
            "obsidian": {"enabled": False, "healthy": False},
            "memory": {"enabled": False, "healthy": False},
            "exa": {"enabled": False, "healthy": False}
        }

        # Check Obsidian
        if self.obsidian:
            health["obsidian"]["enabled"] = True
            try:
                vault_exists = self.obsidian.vault_path.exists()
                health["obsidian"]["healthy"] = vault_exists
                health["obsidian"]["vault_path"] = str(self.obsidian.vault_path)
                if not vault_exists:
                    health["overall"] = False
                    health["obsidian"]["error"] = "Vault path does not exist"
            except Exception as e:
                health["obsidian"]["healthy"] = False
                health["obsidian"]["error"] = str(e)
                health["overall"] = False

        # Check Memory
        if self.memory:
            health["memory"]["enabled"] = True
            health["memory"]["healthy"] = True  # Memory is always healthy if enabled
            health["memory"]["config"] = self.memory.config

        # Check Exa
        if self.exa:
            health["exa"]["enabled"] = True
            health["exa"]["healthy"] = True  # Exa is always healthy if enabled
            health["exa"]["cache_dir"] = str(self.exa.cache_dir)
            try:
                cache_files = len(list(self.exa.cache_dir.glob("*.json")))
                health["exa"]["cached_items"] = cache_files
            except:
                pass

        # Overall health
        if health["overall"]:
            print("[MCP] ✅ All systems healthy")
        else:
            print("[MCP] ⚠️  Some systems have issues")

        return health


def main():
    """Test MCP Manager"""
    manager = MCPManager()

    print("\n" + "=" * 60)
    print("Health Check")
    print("=" * 60)
    health = manager.health_check()
    print(json.dumps(health, indent=2))

    print("\n" + "=" * 60)
    print("Recording Test Execution")
    print("=" * 60)

    # Simulate test execution
    test_id = "TEST-001"
    jira_ticket = "CORE-5432"
    sensor_deployment = {
        "stack_name": "ec2-sensor-testing-qa-qarelease-886303774102509885",
        "ip": "10.50.88.154",
        "version": "BroLin 28.4.0-a7",
        "configuration": "default",
        "deployed_at": "2025-10-10T14:00:00Z",
        "delete_at": "2025-10-14T14:00:00Z"
    }

    # Create mock result file
    result_file = manager.project_root / "testing" / "test_results" / "mock_result.json"
    result_file.parent.mkdir(parents=True, exist_ok=True)

    mock_result = {
        "test_id": test_id,
        "test_title": "YARA Enable/Disable Test",
        "jira_ticket": jira_ticket,
        "status": "passed",
        "steps_passed": 9,
        "steps_failed": 0,
        "total_steps": 9,
        "started_at": "2025-10-10T14:30:52Z",
        "completed_at": "2025-10-10T14:35:12Z",
        "duration_seconds": 260
    }

    with open(result_file, 'w') as f:
        json.dump(mock_result, f, indent=2)

    # Record execution
    result = manager.record_test_execution(
        test_id=test_id,
        jira_ticket=jira_ticket,
        result_file=str(result_file),
        sensor_deployment=sensor_deployment
    )

    print("\n" + "=" * 60)
    print("Execution Recording Result")
    print("=" * 60)
    print(json.dumps(result, indent=2, default=str))

    print("\n" + "=" * 60)
    print("Querying JIRA Status")
    print("=" * 60)
    jira_status = manager.query_jira_status(jira_ticket)
    print(f"Status: {jira_status.get('verification_status')}")
    print(f"Attempts: {jira_status.get('total_attempts')}")

    print("\n✅ MCP Manager test complete")


if __name__ == "__main__":
    main()
