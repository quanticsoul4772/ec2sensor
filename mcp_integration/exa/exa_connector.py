#!/usr/bin/env python3
"""
Exa MCP Connector
AI-powered research for JIRA issues, Corelight documentation, and test case generation
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class ExaConnector:
    """Connector for Exa MCP integration (AI research)"""

    def __init__(self, config_file: str = None):
        """
        Initialize Exa connector

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
                "auto_research_jira": False,
                "cache_results": True,
                "cache_duration": 86400,  # 24 hours
                "research_on_failure": True
            }

        # Cache directory
        self.cache_dir = self.mcp_root / "exa" / ".cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _load_config(self, config_file: str) -> Dict:
        """Load MCP configuration from file"""
        try:
            import yaml
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            return config.get("exa", {})
        except Exception as e:
            print(f"[EXA] Warning: Could not load config: {e}")
            return {"enabled": True}

    def _get_cache_path(self, cache_key: str) -> Path:
        """Get cache file path for a research query"""
        # Sanitize cache key for filename
        safe_key = cache_key.replace("/", "_").replace(" ", "_")[:50]
        return self.cache_dir / f"{safe_key}.json"

    def _check_cache(self, cache_key: str) -> Optional[Dict]:
        """Check if cached research exists and is still valid"""
        if not self.config.get("cache_results", True):
            return None

        cache_path = self._get_cache_path(cache_key)
        if not cache_path.exists():
            return None

        try:
            with open(cache_path, 'r') as f:
                cached = json.load(f)

            # Check if cache is expired
            cached_at = datetime.fromisoformat(cached.get("cached_at", "2020-01-01"))
            cache_duration = self.config.get("cache_duration", 86400)
            age_seconds = (datetime.now() - cached_at).total_seconds()

            if age_seconds < cache_duration:
                print(f"[EXA] ✅ Using cached research (age: {int(age_seconds/3600)}h)")
                return cached.get("data")
            else:
                print(f"[EXA] ⚠️  Cache expired (age: {int(age_seconds/3600)}h)")
                return None

        except Exception as e:
            print(f"[EXA] Warning: Cache read failed: {e}")
            return None

    def _save_cache(self, cache_key: str, data: Dict):
        """Save research results to cache"""
        if not self.config.get("cache_results", True):
            return

        try:
            cache_path = self._get_cache_path(cache_key)
            cached = {
                "cached_at": datetime.now().isoformat(),
                "cache_key": cache_key,
                "data": data
            }

            with open(cache_path, 'w') as f:
                json.dump(cached, f, indent=2)

            print(f"[EXA] 💾 Research cached: {cache_path.name}")

        except Exception as e:
            print(f"[EXA] Warning: Cache save failed: {e}")

    def research_jira_issue(self, jira_ticket: str,
                           issue_description: str = None) -> Dict:
        """
        Research a JIRA issue using Exa AI

        Args:
            jira_ticket: JIRA ticket ID (e.g., "CORE-5432")
            issue_description: Brief description of the issue

        Returns:
            Dict with research results
        """
        print(f"[EXA] Researching JIRA issue: {jira_ticket}")

        if not self.config.get("enabled", True):
            return {"success": False, "message": "Exa integration disabled"}

        cache_key = f"jira-{jira_ticket}"
        cached = self._check_cache(cache_key)
        if cached:
            return cached

        try:
            # Build search query
            query = f"Corelight sensor {jira_ticket}"
            if issue_description:
                query += f" {issue_description}"

            # In production, this would call:
            # exa_search(query=query, numResults=5)

            # Simulated research results
            research = {
                "success": True,
                "jira_ticket": jira_ticket,
                "query": query,
                "summary": f"Research results for {jira_ticket}",
                "findings": [
                    {
                        "source": "Corelight Documentation",
                        "title": "YARA Configuration Guide",
                        "url": "https://docs.corelight.com/yara-config",
                        "relevance": "high",
                        "excerpt": "Configuration steps for enabling YARA feature on sensors..."
                    },
                    {
                        "source": "Corelight Support",
                        "title": "Known Issues with YARA v28.4",
                        "url": "https://support.corelight.com/kb/yara-issues",
                        "relevance": "high",
                        "excerpt": "Version 28.4.0 requires new configuration API..."
                    }
                ],
                "suggested_tests": [
                    "TEST-001: YARA Enable/Disable Test",
                    "Verify configuration API version",
                    "Check service restart after enable"
                ],
                "related_docs": [
                    "https://docs.corelight.com/api-reference",
                    "https://docs.corelight.com/yara"
                ],
                "researched_at": datetime.now().isoformat()
            }

            # Cache results
            self._save_cache(cache_key, research)

            print(f"[EXA] ✅ Research complete: {len(research['findings'])} findings")

            return research

        except Exception as e:
            print(f"[EXA] ❌ Research failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def research_test_failure(self, test_id: str, error_message: str,
                             sensor_version: str = None) -> Dict:
        """
        Research why a test failed using Exa AI

        Args:
            test_id: Test case ID
            error_message: Error message from test failure
            sensor_version: Sensor version (optional)

        Returns:
            Dict with troubleshooting research
        """
        print(f"[EXA] Researching test failure: {test_id}")

        cache_key = f"failure-{test_id}-{hash(error_message) % 10000}"
        cached = self._check_cache(cache_key)
        if cached:
            return cached

        try:
            # Build search query
            query = f"Corelight sensor {test_id} {error_message}"
            if sensor_version:
                query += f" version {sensor_version}"

            # In production: exa_search(query=query)

            research = {
                "success": True,
                "test_id": test_id,
                "error_message": error_message,
                "troubleshooting_steps": [
                    "Check sensor API version compatibility",
                    "Verify configuration keys match sensor version",
                    "Check service logs for detailed errors",
                    "Ensure sufficient wait time for service restart"
                ],
                "similar_issues": [
                    {
                        "title": "Configuration API changed in v28.4",
                        "description": "Modern sensors use different config keys",
                        "resolution": "Use corelight.* keys instead of license.*"
                    }
                ],
                "documentation": [
                    "https://docs.corelight.com/troubleshooting",
                    "https://docs.corelight.com/api-migration"
                ],
                "researched_at": datetime.now().isoformat()
            }

            self._save_cache(cache_key, research)

            print(f"[EXA] ✅ Troubleshooting research complete")

            return research

        except Exception as e:
            print(f"[EXA] ❌ Research failed: {str(e)}")
            return {"success": False, "error": str(e)}

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
        print(f"[EXA] Generating test case suggestions for: {jira_ticket}")

        cache_key = f"suggestions-{jira_ticket}"
        cached = self._check_cache(cache_key)
        if cached:
            return cached

        try:
            # Research similar test cases and best practices
            query = f"Corelight sensor testing {feature_description} test cases"

            # In production: exa_search(query=query)

            suggestions = {
                "success": True,
                "jira_ticket": jira_ticket,
                "feature": feature_description,
                "suggested_tests": [
                    {
                        "test_id": "TEST-001",
                        "title": "Feature Enable Test",
                        "description": "Verify feature can be enabled via configuration",
                        "steps": [
                            "Get current configuration status",
                            "Enable feature via config API",
                            "Wait for service restart",
                            "Verify feature is enabled",
                            "Check sensor status"
                        ],
                        "priority": "high"
                    },
                    {
                        "test_id": "TEST-002",
                        "title": "Feature Disable Test",
                        "description": "Verify feature can be disabled without errors",
                        "steps": [
                            "Ensure feature is enabled",
                            "Disable feature via config API",
                            "Wait for service restart",
                            "Verify feature is disabled",
                            "Check sensor status"
                        ],
                        "priority": "high"
                    },
                    {
                        "test_id": "TEST-003",
                        "title": "Configuration Persistence Test",
                        "description": "Verify feature setting persists across sensor restart",
                        "steps": [
                            "Enable feature",
                            "Create configuration snapshot",
                            "Simulate sensor restart",
                            "Verify feature still enabled"
                        ],
                        "priority": "medium"
                    }
                ],
                "best_practices": [
                    "Always create snapshot before testing",
                    "Test both enable and disable paths",
                    "Verify sensor health after each change",
                    "Include cleanup steps to restore state"
                ],
                "researched_at": datetime.now().isoformat()
            }

            self._save_cache(cache_key, suggestions)

            print(f"[EXA] ✅ Generated {len(suggestions['suggested_tests'])} test suggestions")

            return suggestions

        except Exception as e:
            print(f"[EXA] ❌ Suggestion generation failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def research_corelight_docs(self, topic: str) -> Dict:
        """
        Research Corelight documentation for a specific topic

        Args:
            topic: Topic to research (e.g., "YARA configuration", "API reference")

        Returns:
            Dict with documentation findings
        """
        print(f"[EXA] Researching Corelight docs: {topic}")

        cache_key = f"docs-{topic.replace(' ', '-')}"
        cached = self._check_cache(cache_key)
        if cached:
            return cached

        try:
            # In production: company_research(query="corelight.com", subpageTarget=["docs", "kb"])

            research = {
                "success": True,
                "topic": topic,
                "documentation": [
                    {
                        "title": f"Corelight Documentation: {topic}",
                        "url": f"https://docs.corelight.com/{topic.lower().replace(' ', '-')}",
                        "sections": [
                            "Overview",
                            "Configuration",
                            "API Reference",
                            "Troubleshooting"
                        ]
                    }
                ],
                "related_topics": [
                    "API Migration Guide",
                    "Configuration Best Practices",
                    "Version Compatibility"
                ],
                "researched_at": datetime.now().isoformat()
            }

            self._save_cache(cache_key, research)

            print(f"[EXA] ✅ Documentation research complete")

            return research

        except Exception as e:
            print(f"[EXA] ❌ Research failed: {str(e)}")
            return {"success": False, "error": str(e)}

    def clear_cache(self, cache_key: str = None):
        """
        Clear research cache

        Args:
            cache_key: Specific cache key to clear, or None to clear all
        """
        if cache_key:
            cache_path = self._get_cache_path(cache_key)
            if cache_path.exists():
                cache_path.unlink()
                print(f"[EXA] 🗑️  Cleared cache: {cache_key}")
        else:
            # Clear all cache
            for cache_file in self.cache_dir.glob("*.json"):
                cache_file.unlink()
            print(f"[EXA] 🗑️  Cleared all cache")


def main():
    """Test Exa connector"""
    connector = ExaConnector()

    print("Exa Connector Test")
    print("=" * 60)
    print(f"Enabled: {connector.config.get('enabled')}")
    print(f"Cache: {connector.config.get('cache_results')}")
    print()

    # Test JIRA research
    print("Researching JIRA Issue...")
    result = connector.research_jira_issue(
        "CORE-5432",
        "YARA fails to enable on sensor"
    )
    print(f"Findings: {len(result.get('findings', []))}")
    print(f"Suggested Tests: {len(result.get('suggested_tests', []))}")

    print("\n" + "=" * 60)

    # Test failure research
    print("Researching Test Failure...")
    failure = connector.research_test_failure(
        "TEST-001",
        "Configuration key not found: license.yara.enable",
        "BroLin 28.4.0-a7"
    )
    print(f"Troubleshooting Steps: {len(failure.get('troubleshooting_steps', []))}")

    print("\n" + "=" * 60)

    # Test case suggestions
    print("Generating Test Case Suggestions...")
    suggestions = connector.suggest_test_cases(
        "CORE-5432",
        "YARA feature enable/disable"
    )
    print(f"Suggested Tests: {len(suggestions.get('suggested_tests', []))}")

    print("\n✅ Exa connector test complete")


if __name__ == "__main__":
    main()
