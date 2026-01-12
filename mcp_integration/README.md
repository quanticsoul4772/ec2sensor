# MCP Integration for EC2 Sensor Testing

**Model Context Protocol (MCP) Integration** - AI-powered documentation, knowledge management, and research

---

## Overview

This integration connects the EC2 Sensor Testing Platform with three MCP servers to provide:

1. **Obsidian MCP** - Automated documentation sync to Obsidian vault
2. **Memory MCP** - Knowledge graph for tracking relationships and verification status
3. **Exa MCP** - AI-powered research for JIRA issues and troubleshooting

### Key Features

- OK: **Automatic Documentation**: Test executions sync to Obsidian vault with detailed notes
- OK: **Knowledge Graph**: Track relationships between tests, JIRA tickets, and sensor deployments
- OK: **AI Research**: Automatic JIRA research, test case suggestions, and failure troubleshooting
- OK: **Ephemeral Sensor Tracking**: Properly handles temporary sensors that auto-delete after 4 days
- OK: **JIRA Verification**: Query verification status across multiple test runs
- OK: **Historical Audit Trail**: Complete record of all test executions

---

## Architecture

### Ephemeral Sensor Model

**Critical Design Decision**: Sensors are ephemeral (auto-delete after 4 days) and IP addresses change on each deployment.

**Primary Tracking Entity**: Test Execution (permanent)
**Supporting Entity**: Sensor Deployment (ephemeral, context only)

```
Test Execution (permanent)
  ├─ execution-TEST-001-20251010-143052
  ├─ Test Case: TEST-001 (permanent)
  ├─ JIRA Ticket: CORE-5432 (permanent)
  └─ Sensor Deployment (ephemeral)
      ├─ Stack: ec2-sensor-testing-qa-qarelease-886303774102509885
      ├─ IP: 10.50.88.154 (temporary, changes every deployment)
      ├─ Deployed: 2025-10-10
      └─ Auto-Delete: 2025-10-14 (4 days)
```

### Entity Relationships

```
execution-TEST-001-20251010-143052
  ├─ executes → TEST-001
  ├─ validates → CORE-5432
  └─ uses_deployment → deployment-886303774102509885

TEST-001
  └─ verifies → CORE-5432
```

---

## Quick Start

### Basic Usage

```python
from mcp_integration.mcp_manager import MCPManager

# Initialize MCP Manager
mcp = MCPManager()

# Record test execution
sensor_deployment = {
    'stack_name': 'ec2-sensor-testing-qa-qarelease-886303774102509885',
    'ip': '10.50.88.154',
    'version': 'BroLin 28.4.0-a7',
    'deployed_at': '2025-10-10T14:00:00Z',
    'delete_at': '2025-10-14T14:00:00Z',  # +4 days
    'configuration': 'default'
}

result = mcp.record_test_execution(
    test_id='TEST-001',
    jira_ticket='CORE-5432',
    result_file='/path/to/result.json',
    sensor_deployment=sensor_deployment
)

# Result includes status for all three MCP systems:
# - result['obsidian']: Obsidian sync status
# - result['memory']: Knowledge graph status
# - result['exa']: Research status
```

### Query Verification Status

```python
# Check if JIRA ticket has been verified
jira_status = mcp.query_jira_status('CORE-5432')

print(f"Status: {jira_status['verification_status']}")
print(f"Attempts: {jira_status['total_attempts']}")
print(f"Last Validated: {jira_status['last_validated']}")
```

### Troubleshoot Test Failures

```python
# Research test failure using Exa AI
research = mcp.research_test_failure(
    test_id='TEST-002',
    error_message='Configuration key not found: license.yara.enable',
    sensor_version='BroLin 28.4.0-a7'
)

# Returns:
# - troubleshooting_steps: List of steps to try
# - similar_issues: Known issues with resolutions
# - documentation: Relevant documentation links
```

---

## Integration with Existing Code

### Minimal Changes Required

**In your test executor** (`agents/test_executor/test_executor_agent.py`):

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

        # NEW: Record to MCP systems (3 lines of code)
        sensor_deployment = self._get_sensor_deployment_info()

        self.mcp.record_test_execution(
            test_id=test_metadata['test_id'],
            jira_ticket=test_metadata['jira_ticket'],
            result_file=result_file,
            sensor_deployment=sensor_deployment
        )

        return results
```

### Getting Sensor Deployment Info

```python
def _get_sensor_deployment_info(self) -> Dict:
    """Extract sensor deployment info for MCP tracking"""
    from datetime import datetime, timedelta

    return {
        'stack_name': os.getenv('SENSOR_STACK_NAME'),
        'ip': os.getenv('SSH_HOST'),
        'version': self._get_sensor_version(),  # From sensor status
        'deployed_at': os.getenv('SENSOR_DEPLOYED_AT'),  # From CloudFormation
        'delete_at': (datetime.now() + timedelta(days=4)).isoformat(),
        'configuration': 'default'
    }
```

---

## MCP Components

### 1. Obsidian MCP Connector

**Purpose**: Sync test executions to Obsidian vault for documentation

**File**: `mcp_integration/obsidian/obsidian_connector.py`

**Generated Notes**:
```
obsidian/corelight/
├── Test-Executions/
│   ├── 2025-10/
│   │   ├── TEST-001-20251010-143052.md  # Execution notes
│   │   └── TEST-002-20251010-150012.md
│   └── 2025-11/
│       └── TEST-001-20251105-091234.md
├── Test-Cases/
│   └── TEST-001-YARA-Enable-Disable.md  # Test case summaries
├── JIRA/
│   └── CORE-5432.md  # JIRA verification status
└── Sensor-Deployments/
    └── 2025-10/
        └── deployment-886303774102509885.md  # Deployment info
```

**Example Execution Note**:
```markdown
# TEST-001 Execution - 2025-10-10

## Execution Details
- **Execution ID**: `TEST-001-20251010-143052`
- **Test Case**: [[TEST-001|Test Case Details]]
- **Status**: OK: **PASSED**

## Sensor Deployment (WARN: Ephemeral)

> **Note**: This sensor is temporary and will auto-delete 4 days after deployment.
> IP addresses are session identifiers only and will change on next test run.

- **Stack Name**: `ec2-sensor-testing-qa-qarelease-886303774102509885`
- **IP Address**: `10.50.88.154` WARN: *Temporary*
- **Auto-Delete**: 2025-10-14
```

### 2. Memory MCP Connector

**Purpose**: Build knowledge graph of relationships

**File**: `mcp_integration/memory/memory_connector.py`

**Entity Types**:
- `test_execution` - Test execution records (permanent)
- `test_case` - Test case templates (permanent)
- `jira_issue` - JIRA tickets (permanent)
- `sensor_deployment` - Sensor deployments (ephemeral, marked with delete date)

**Relations**:
- `execution → executes → test_case`
- `execution → validates → jira_issue`
- `execution → uses_deployment → sensor_deployment`
- `test_case → verifies → jira_issue`

**Query Examples**:
```python
# Get JIRA verification status
status = memory.query_jira_verification_status('CORE-5432')
# Returns: verification_status, total_attempts, executions[]

# Get test statistics
stats = memory.query_test_case_statistics('TEST-001')
# Returns: total_executions, success_rate, average_duration

# Get deployment usage
usage = memory.query_deployment_usage('stack-name')
# Returns: tests_executed[], purpose, status
```

### 3. Exa MCP Connector

**Purpose**: AI-powered research and troubleshooting

**File**: `mcp_integration/exa/exa_connector.py`

**Features**:
- **JIRA Research**: Find relevant documentation and known issues
- **Test Failure Troubleshooting**: Get troubleshooting steps and solutions
- **Test Case Suggestions**: Generate test cases for new features
- **Documentation Search**: Find Corelight documentation

**Cache**: 24-hour cache for research results (configurable)

**Methods**:
```python
# Research JIRA issue
research = exa.research_jira_issue(
    jira_ticket='CORE-5432',
    issue_description='YARA fails to enable'
)
# Returns: findings, suggested_tests, related_docs

# Troubleshoot failure
troubleshooting = exa.research_test_failure(
    test_id='TEST-001',
    error_message='Configuration key not found',
    sensor_version='BroLin 28.4.0-a7'
)
# Returns: troubleshooting_steps, similar_issues, documentation

# Generate test suggestions
suggestions = exa.suggest_test_cases(
    jira_ticket='CORE-6789',
    feature_description='Suricata rule update'
)
# Returns: suggested_tests[], best_practices[]
```

---

## Unified MCP Manager

**File**: `mcp_integration/mcp_manager.py`

**Purpose**: Single interface to coordinate all three MCP integrations

### Primary Method

```python
mcp.record_test_execution(
    test_id='TEST-001',
    jira_ticket='CORE-5432',
    result_file='/path/to/result.json',
    sensor_deployment={...}
)
```

**This single call**:
1. OK: Creates execution note in Obsidian vault
2. OK: Creates entities and relations in knowledge graph
3. OK: Caches Exa research for the JIRA ticket

### Additional Methods

```python
# Query methods
mcp.query_jira_status(jira_ticket)
mcp.query_test_statistics(test_id)

# Research methods
mcp.research_test_failure(test_id, error_message, sensor_version)
mcp.suggest_test_cases(jira_ticket, feature_description)

# Utility methods
mcp.health_check()  # Check all MCP services
mcp.clear_research_cache(cache_key)  # Clear Exa cache
mcp.get_obsidian_vault_path()  # Get vault location
```

---

## Use Cases

### 1. "Has CORE-5432 been verified?"

**Query Knowledge Graph**:
```python
status = mcp.query_jira_status('CORE-5432')
print(f"Status: {status['verification_status']}")
print(f"Attempts: {status['total_attempts']}")
```

**Check Obsidian**:
- Open `JIRA/CORE-5432.md`
- See all validation attempts with links to execution notes

### 2. "What's the success rate of TEST-001?"

**Query Knowledge Graph**:
```python
stats = mcp.query_test_statistics('TEST-001')
print(f"Success Rate: {stats['success_rate']}%")
print(f"Total Runs: {stats['total_executions']}")
```

**Check Obsidian**:
- Open `Test-Cases/TEST-001.md`
- See execution history and statistics

### 3. "Why did TEST-002 fail?"

**Research with Exa**:
```python
research = mcp.research_test_failure(
    test_id='TEST-002',
    error_message='Configuration key not found: license.yara.enable',
    sensor_version='BroLin 28.4.0-a7'
)

for step in research['troubleshooting_steps']:
    print(f"- {step}")
```

**Check Obsidian**:
- Browse `Test-Executions/YYYY-MM/`
- Find failed execution note with step-by-step details

### 4. "What tests ran on October 10?"

**Browse Obsidian**:
```bash
ls obsidian/corelight/Test-Executions/2025-10/
# TEST-001-20251010-143052.md
# TEST-002-20251010-150012.md
# TEST-003-20251010-163045.md
```

---

## Configuration

### Default Configuration

```python
config = {
    "enabled": True,
    "obsidian": {
        "enabled": True,
        "vault_path": "~/obsidian/corelight"
    },
    "memory": {
        "enabled": True,
        "auto_create_entities": True,
        "auto_create_relations": True
    },
    "exa": {
        "enabled": True,
        "cache_results": True,
        "cache_duration": 86400,  # 24 hours
        "research_on_failure": True
    }
}
```

### Config File (Optional)

Create `mcp_integration/config.yaml`:

```yaml
enabled: true

obsidian:
  enabled: true
  vault_path: ~/obsidian/corelight

memory:
  enabled: true
  auto_create_entities: true
  auto_create_relations: true

exa:
  enabled: true
  cache_results: true
  cache_duration: 86400  # 24 hours
  auto_research_jira: false  # Research on demand only
  research_on_failure: true  # Auto-research test failures
```

Load config:
```python
mcp = MCPManager(config_file='mcp_integration/config.yaml')
```

---

## Testing

### Test Individual Connectors

```bash
# Test Obsidian connector
python3 mcp_integration/obsidian/obsidian_connector.py

# Test Memory connector
python3 mcp_integration/memory/memory_connector.py

# Test Exa connector
python3 mcp_integration/exa/exa_connector.py
```

### Test Unified Manager

```bash
# Test MCP Manager
cd mcp_integration && python3 mcp_manager.py
```

### Run Example Workflows

```bash
# Complete workflow examples
cd mcp_integration && python3 example_workflow.py
```

---

## File Structure

```
mcp_integration/
├── README.md                           # This file
├── MCP_ARCHITECTURE.md                 # Detailed architecture
├── EPHEMERAL_SENSOR_MODEL.md          # Ephemeral sensor design
├── PHASE4_PROGRESS.md                 # Implementation progress
├── config.yaml                         # Optional configuration
│
├── mcp_manager.py                      # Unified MCP Manager ⭐
├── example_workflow.py                 # Example usage
│
├── obsidian/
│   ├── obsidian_connector.py           # Obsidian sync (550+ lines)
│   └── README.md                       # Obsidian docs
│
├── memory/
│   ├── memory_connector.py             # Knowledge graph (450+ lines)
│   └── README.md                       # Memory docs
│
└── exa/
    ├── exa_connector.py                # AI research (400+ lines)
    ├── .cache/                         # Research cache (24h TTL)
    └── README.md                       # Exa docs
```

---

## Benefits

### For Test Engineers

OK: **Automatic Documentation**: No manual note-taking, everything auto-syncs to Obsidian
OK: **Search History**: Find all test attempts by JIRA ticket, test ID, or date
OK: **Verification Status**: Instantly know if a JIRA ticket has been validated
OK: **Failure Troubleshooting**: Get AI-powered suggestions when tests fail

### For Project Management

OK: **Audit Trail**: Complete history of all validation attempts
OK: **JIRA Tracking**: See which tickets have been verified and when
OK: **Test Coverage**: Know which tests are running and their success rates
OK: **Resource Usage**: Track sensor deployments and test execution costs

### For Documentation

OK: **Self-Documenting**: Test executions automatically generate comprehensive notes
OK: **Linked Notes**: All entities linked (tests, JIRAs, sensors, executions)
OK: **Temporal Organization**: Easy to find executions by date
OK: **Ephemeral Warnings**: Clear indicators when sensor info is temporary

---

## Ephemeral Sensor Handling

### Design Principles

**What We Track** OK::
- Test executions (permanent, unique ID)
- JIRA verification status (permanent)
- Test case templates and statistics (permanent)
- Sensor deployment context (ephemeral, with auto-delete date)

**What We Don't Track** FAIL::
- "Sensor history by IP" - IP changes every deployment
- "All tests on this sensor" - sensor deletes after 4 days
- Long-term sensor metrics - no long-term sensors exist

### Ephemeral Warnings

All Obsidian notes include prominent warnings:

```markdown
## Sensor Deployment (WARN: Ephemeral)

> **Note**: This sensor is temporary and will auto-delete 4 days after deployment.
> IP addresses are session identifiers only and will change on next test run.

- **Stack Name**: `ec2-sensor-testing-qa-qarelease-886303774102509885`
- **IP Address**: `10.50.88.154` WARN: *Temporary*
- **Auto-Delete**: 2025-10-14
```

### Lifecycle Tracking

Sensor deployments tracked with full lifecycle:

```python
sensor_deployment = {
    'stack_name': 'ec2-sensor-testing-qa-qarelease-886303774102509885',  # Permanent ID
    'ip': '10.50.88.154',  # Temporary session identifier
    'deployed_at': '2025-10-10T14:00:00Z',
    'delete_at': '2025-10-14T14:00:00Z',  # Auto-delete after 4 days
    'version': 'BroLin 28.4.0-a7',
    'configuration': 'default'
}
```

---

## Troubleshooting

### Obsidian Vault Not Found

```python
# Check vault path
mcp = MCPManager()
health = mcp.health_check()
print(health['obsidian']['vault_path'])

# Create vault directory if needed
mkdir -p ~/obsidian/corelight/Test-Executions
```

### Exa Research Cache Issues

```python
# Clear specific cache
mcp.clear_research_cache('jira-CORE-5432')

# Clear all cache
mcp.clear_research_cache()

# Check cache directory
ls mcp_integration/exa/.cache/
```

### Memory Graph Issues

Memory connector is simulation only in current implementation. To enable real Memory MCP:

1. Install Memory MCP server
2. Update `memory_connector.py` to call actual MCP functions
3. Uncomment MCP function calls (currently commented as "In production: ...")

---

## Future Enhancements

### Planned

- [ ] Real-time MCP server integration (currently simulated)
- [ ] Obsidian graph visualization
- [ ] Automated JIRA status updates from test results
- [ ] Test case auto-generation from Exa research
- [ ] Slack notifications for test completions
- [ ] Dashboard for test statistics

### Ideas

- AI-powered test case optimization based on success rates
- Automatic detection of flaky tests
- Cost optimization by tracking sensor usage patterns
- Integration with CI/CD pipelines

---

## Support

### Documentation

- **Architecture**: See `MCP_ARCHITECTURE.md`
- **Ephemeral Model**: See `EPHEMERAL_SENSOR_MODEL.md`
- **Progress**: See `PHASE4_PROGRESS.md`

### Examples

- **Complete Workflow**: Run `python3 mcp_integration/example_workflow.py`
- **Individual Tests**: Run connector test scripts directly

### Issues

File issues in the project repository with:
- MCP component affected (Obsidian, Memory, Exa)
- Error message
- Test case or JIRA ticket involved
- Sensor deployment details

---

## Summary

**MCP Integration** provides:

1. OK: **Automatic Documentation** - Obsidian vault sync with execution notes
2. OK: **Knowledge Graph** - Track relationships between tests, JIRAs, sensors
3. OK: **AI Research** - Troubleshooting, JIRA research, test suggestions
4. OK: **Ephemeral Handling** - Proper tracking of temporary sensors
5. OK: **Verification Status** - Query JIRA validation across all attempts
6. OK: **Historical Audit** - Complete record of all test executions

**Integration is simple**: 3 lines of code in your test executor.

**Benefits are significant**: Automated documentation, searchable history, AI-powered troubleshooting.

---

**Status**: Phase 4 Complete
**Last Updated**: 2025-10-10
