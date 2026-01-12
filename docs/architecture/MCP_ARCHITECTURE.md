# MCP Integration Architecture

**Version**: 1.0.0
**Date**: 2025-10-10
**Status**: Design Phase

---

## Overview

Phase 4 integrates three Model Context Protocol (MCP) servers to enhance the EC2 Sensor Testing Platform with:

1. **Obsidian MCP** - Bidirectional sync with Obsidian vault for documentation and knowledge management
2. **Memory MCP** - Knowledge graph for tracking sensors, tests, and relationships
3. **Exa MCP** - AI-powered research for JIRA issues and Corelight documentation

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  EC2 Sensor Testing Platform                     │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Test         │  │ Sensor       │  │ Documentation│          │
│  │ Executor     │  │ Monitor      │  │ Agent        │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                   │
│         └──────────────────┴──────────────────┘                   │
│                            │                                      │
│                   ┌────────▼─────────┐                           │
│                   │  MCP Integration  │                           │
│                   │     Layer         │                           │
│                   └────────┬──────────┘                           │
└────────────────────────────┼──────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  Obsidian MCP   │ │   Memory MCP    │ │    Exa MCP      │
│                 │ │                 │ │                 │
│ - Vault sync   │ │ - Knowledge     │ │ - Web search   │
│ - Note CRUD    │ │   graph         │ │ - Research     │
│ - Bidirectional│ │ - Entities      │ │ - Documentation│
│   updates      │ │ - Relations     │ │   lookup       │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## MCP Server Integration Details

### 1. Obsidian MCP

**Purpose**: Sync test results, sensor configurations, and documentation to Obsidian vault

**Capabilities** (from mcp__obsidian-mcp__* functions):
- `obsidian_create_file` - Create notes in vault
- `obsidian_read_file` - Read existing notes
- `obsidian_update_file` - Update note content
- `obsidian_search_text` - Search vault content
- `obsidian_search_by_tags` - Find notes by tags
- `obsidian_get_backlinks` - Get note relationships

**Integration Points**:
1. **Test Results → Obsidian Notes**
   - After each test execution, create note in vault
   - Format: `Tests/TEST-001-YYYY-MM-DD.md`
   - Include: test steps, results, screenshots, links to JIRA

2. **Sensor Configurations → Obsidian**
   - Sync sensor preparation details
   - Track sensor versions and configurations
   - Link to related tests

3. **Documentation Updates → Obsidian**
   - Auto-sync README files
   - Create knowledge base articles
   - Maintain version history

**Directory Structure in Vault**:
```
obsidian/corelight/
├── Sensors/
│   ├── 10.50.88.154.md
│   └── Configuration-History.md
├── Tests/
│   ├── TEST-001-2025-10-10.md
│   ├── TEST-002-2025-10-10.md
│   └── Test-Results-Index.md
├── JIRA/
│   ├── CORE-5432.md
│   ├── CORE-5678.md
│   └── CORE-6001.md
└── Documentation/
    ├── Test-Framework.md
    ├── Agent-System.md
    └── API-Reference.md
```

### 2. Memory MCP

**Purpose**: Build knowledge graph of sensors, tests, configurations, and their relationships

**Capabilities** (from mcp__memory__* functions):
- `create_entities` - Create nodes (sensors, tests, JIRAs)
- `create_relations` - Create edges (sensor→test, test→JIRA)
- `add_observations` - Add metadata to entities
- `read_graph` - Query knowledge graph
- `search_nodes` - Find entities by criteria

**Entity Types**:

1. **Sensor Entities**
   ```json
   {
     "name": "sensor-10.50.88.154",
     "entityType": "sensor",
     "observations": [
       "IP: 10.50.88.154",
       "Version: BroLin 28.4.0-a7",
       "Configuration: default",
       "Status: active",
       "Last tested: 2025-10-10"
     ]
   }
   ```

2. **Test Entities**
   ```json
   {
     "name": "TEST-001",
     "entityType": "test_case",
     "observations": [
       "Title: YARA Enable/Disable Test",
       "JIRA: CORE-5432",
       "Last run: 2025-10-10",
       "Last result: passed",
       "Steps: 9"
     ]
   }
   ```

3. **JIRA Entities**
   ```json
   {
     "name": "CORE-5432",
     "entityType": "jira_issue",
     "observations": [
       "Type: bug",
       "Priority: high",
       "Status: in_testing",
       "Linked tests: TEST-001"
     ]
   }
   ```

**Relations**:
- sensor → runs → test
- test → validates → jira_issue
- sensor → has_configuration → config
- test → uses_snapshot → snapshot
- jira_issue → affects → sensor_version

**Knowledge Graph Queries**:
```python
# Find all tests that ran on a sensor
search_nodes(query="sensor-10.50.88.154 runs")

# Find tests for a JIRA issue
search_nodes(query="CORE-5432 validated_by")

# Find sensors with specific configuration
search_nodes(query="configuration:default")
```

### 3. Exa MCP

**Purpose**: AI-powered research for JIRA issues, Corelight documentation, and test case generation

**Capabilities** (from mcp__exa__* functions):
- `exa_search` - General web search
- `research_paper_search` - Search research papers
- `company_research` - Research companies/products
- `crawling` - Extract content from URLs

**Integration Points**:

1. **JIRA Issue Research**
   ```python
   # Research a JIRA issue
   exa_search(query="Corelight YARA enable disable bug CORE-5432")

   # Find related Corelight docs
   company_research(
     query="corelight.com",
     subpageTarget=["docs", "kb", "support"]
   )
   ```

2. **Test Case Generation Assistance**
   ```python
   # Find similar test cases
   exa_search(query="Suricata configuration testing best practices")

   # Research specific features
   exa_search(query="Corelight SmartPCAP testing procedures")
   ```

3. **Troubleshooting Assistance**
   ```python
   # Research sensor errors
   exa_search(query="Corelight sensor service failed to start")

   # Find documentation
   crawling(url="https://docs.corelight.com/specific-article")
   ```

---

## Implementation Plan

### Phase 4.1: Obsidian Integration

**Goal**: Sync test results and documentation to Obsidian vault

**Tasks**:
1. Create `obsidian_connector.py` - Wrapper around Obsidian MCP
2. Implement test result → note converter
3. Create vault templates for tests, sensors, JIRA
4. Add sync command to Documentation Agent
5. Test bidirectional sync

**Deliverables**:
- `mcp_integration/obsidian/obsidian_connector.py`
- Vault note templates
- Sync script
- Documentation

### Phase 4.2: Memory Integration

**Goal**: Build knowledge graph of testing ecosystem

**Tasks**:
1. Create `memory_connector.py` - Wrapper around Memory MCP
2. Define entity schemas (sensors, tests, JIRAs)
3. Implement entity creation on test execution
4. Create relation builders
5. Add knowledge graph queries

**Deliverables**:
- `mcp_integration/memory/memory_connector.py`
- Entity schemas
- Graph query library
- Documentation

### Phase 4.3: Exa Integration

**Goal**: Enable AI-powered research for testing

**Tasks**:
1. Create `exa_connector.py` - Wrapper around Exa MCP
2. Implement JIRA research automation
3. Create test case generation assistant
4. Add troubleshooting research
5. Integrate with Documentation Agent

**Deliverables**:
- `mcp_integration/exa/exa_connector.py`
- Research automation scripts
- Documentation

### Phase 4.4: Unified MCP Manager

**Goal**: Single interface to all MCP services

**Tasks**:
1. Create `mcp_manager.py` - Unified MCP interface
2. Implement workflow automation
3. Add error handling and retries
4. Create CLI commands
5. Integration tests

**Deliverables**:
- `mcp_integration/mcp_manager.py`
- CLI tool
- Integration tests
- Comprehensive documentation

---

## Usage Examples

### Example 1: Sync Test Result to Obsidian

```python
from mcp_integration.obsidian import obsidian_connector

# After test execution
connector = obsidian_connector.ObsidianConnector()

connector.sync_test_result(
    test_id="TEST-001",
    result_file="testing/test_results/TEST-001_1760120000.json",
    vault_path="Tests/TEST-001-2025-10-10.md"
)
```

### Example 2: Update Knowledge Graph

```python
from mcp_integration.memory import memory_connector

# After sensor preparation
connector = memory_connector.MemoryConnector()

# Create sensor entity
connector.create_sensor_entity(
    sensor_ip="10.50.88.154",
    version="BroLin 28.4.0-a7",
    configuration="default"
)

# Create relation to test
connector.create_relation(
    from_entity="sensor-10.50.88.154",
    to_entity="TEST-001",
    relation_type="executed_test"
)
```

### Example 3: Research JIRA Issue

```python
from mcp_integration.exa import exa_connector

# Research JIRA issue
connector = exa_connector.ExaConnector()

research = connector.research_jira_issue(
    jira_ticket="CORE-5432",
    query="Corelight YARA enable disable issue"
)

print(research['summary'])
print(research['related_docs'])
print(research['suggested_tests'])
```

### Example 4: Unified MCP Workflow

```python
from mcp_integration.mcp_manager import MCPManager

# Complete workflow after test execution
manager = MCPManager()

manager.post_test_workflow(
    test_id="TEST-001",
    sensor_ip="10.50.88.154",
    result_file="testing/test_results/TEST-001_1760120000.json",
    jira_ticket="CORE-5432"
)

# This will:
# 1. Sync test result to Obsidian
# 2. Update knowledge graph in Memory
# 3. Research related issues in Exa
# 4. Generate summary report
```

---

## Integration with Existing Agents

### Documentation Agent Extension

Add MCP sync after document generation:

```python
def record_test_results(self, test_case: str, workflow_id: str) -> Dict:
    # Existing code to generate JSON + Markdown
    result = self._generate_reports(test_case, workflow_id)

    # NEW: Sync to Obsidian
    if self.mcp_enabled:
        self.obsidian.sync_test_result(
            test_case=test_case,
            result_file=result['json_file']
        )

    # NEW: Update knowledge graph
    if self.mcp_enabled:
        self.memory.update_test_entity(
            test_case=test_case,
            result=result
        )

    return result
```

### Test Executor Agent Extension

Add knowledge graph updates:

```python
def execute_test_steps(self, test_case: str, sensor_ip: str) -> Dict:
    # Existing test execution code
    result = self._execute_steps(test_case, sensor_ip)

    # NEW: Update knowledge graph
    if self.mcp_enabled:
        self.memory.create_relation(
            from_entity=f"sensor-{sensor_ip}",
            to_entity=test_case,
            relation_type="executed_test"
        )

    return result
```

### Sensor Monitor Agent Extension

Add sensor entity tracking:

```python
def validate_sensor_ready(self, sensor_ip: str) -> Dict:
    # Existing validation code
    result = self._check_sensor(sensor_ip)

    # NEW: Update sensor entity
    if self.mcp_enabled:
        self.memory.add_observations(
            entity_name=f"sensor-{sensor_ip}",
            observations=[
                f"Last check: {datetime.now().isoformat()}",
                f"Status: {result['status']}",
                f"Health: {result['overall_status']}"
            ]
        )

    return result
```

---

## Configuration

### MCP Configuration File

`mcp_integration/config.yaml`:

```yaml
obsidian:
  enabled: true
  vault_path: "/Users/russellsmith/obsidian/corelight"
  sync_on_test_complete: true
  sync_on_documentation: true
  templates:
    test_result: "mcp_integration/obsidian/templates/test_result.md"
    sensor: "mcp_integration/obsidian/templates/sensor.md"
    jira: "mcp_integration/obsidian/templates/jira.md"

memory:
  enabled: true
  auto_create_entities: true
  auto_create_relations: true
  entity_types:
    - sensor
    - test_case
    - jira_issue
    - configuration
    - snapshot

exa:
  enabled: true
  auto_research_jira: false  # Manual trigger
  cache_results: true
  cache_duration: 86400  # 24 hours
  research_on_failure: true  # Research when tests fail
```

---

## Expected Benefits

### 1. Enhanced Documentation
- Automatic sync to Obsidian vault
- Bidirectional updates
- Rich linking between notes
- Version history

### 2. Knowledge Graph
- Track all sensors, tests, and relationships
- Query historical data
- Find patterns and trends
- Identify test coverage gaps

### 3. AI-Powered Research
- Automatic JIRA issue research
- Find related documentation
- Generate test case suggestions
- Troubleshooting assistance

### 4. Improved Workflows
- Reduced manual documentation
- Faster troubleshooting
- Better test coverage
- Automated knowledge capture

---

## Success Criteria

Phase 4 will be considered complete when:

- OK: Obsidian connector implemented and tested
- OK: Test results auto-sync to vault
- OK: Memory knowledge graph operational
- OK: Sensor/test entities created automatically
- OK: Exa research integration working
- OK: JIRA research automation functional
- OK: Unified MCP manager implemented
- OK: All agents integrated with MCP
- OK: Documentation complete
- OK: End-to-end workflow tested

---

## Timeline

**Estimated Duration**: 2-3 days

- Day 1: Obsidian integration + Memory integration
- Day 2: Exa integration + MCP manager
- Day 3: Agent integration + testing + documentation

---

## File Structure

```
mcp_integration/
├── MCP_ARCHITECTURE.md           (This file)
├── config.yaml                    (MCP configuration)
├── mcp_manager.py                 (Unified MCP interface)
│
├── obsidian/
│   ├── obsidian_connector.py      (Obsidian MCP wrapper)
│   ├── templates/
│   │   ├── test_result.md
│   │   ├── sensor.md
│   │   └── jira.md
│   └── README.md
│
├── memory/
│   ├── memory_connector.py        (Memory MCP wrapper)
│   ├── schemas/
│   │   ├── sensor_entity.json
│   │   ├── test_entity.json
│   │   └── jira_entity.json
│   └── README.md
│
└── exa/
    ├── exa_connector.py           (Exa MCP wrapper)
    ├── research_templates/
    │   ├── jira_research.yaml
    │   └── troubleshooting.yaml
    └── README.md
```

---

**Status**: Design Complete
**Next Step**: Begin implementation with Obsidian connector
**Version**: 1.0.0
**Last Updated**: 2025-10-10
