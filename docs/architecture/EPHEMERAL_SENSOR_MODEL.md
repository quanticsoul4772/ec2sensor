# Ephemeral Sensor Model - Redesign

**Date**: 2025-10-10
**Critical Insight**: Sensors auto-delete after 4 days and have different IPs per deployment

---

## The Problem

**Original Assumption** FAIL:: Sensors are persistent with stable IP addresses
**Reality** OK::
- Sensors are **ephemeral** - auto-delete after 4 days
- Each test case/JIRA verification spins up a **new sensor** with a **different IP**
- IP address (10.50.88.154) is meaningless after sensor deletion
- Can't track "sensor history" by IP - the IP changes every time

---

## New Mental Model

### Old Model FAIL:
```
Sensor (10.50.88.154)
  ├─ Configuration: default
  ├─ Tests Run: TEST-001, TEST-002, TEST-003
  └─ History: Multiple test runs over time
```
**Problem**: IP changes on each deployment, history is lost

### New Model OK:
```
Test Execution Session
  ├─ Purpose: TEST-001 (JIRA: CORE-5432)
  ├─ Sensor Deployment:
  │   ├─ IP: 10.50.88.154 (temporary)
  │   ├─ Deployed: 2025-10-10
  │   ├─ Will Delete: 2025-10-14
  │   └─ Stack Name: ec2-sensor-testing-qa-qarelease-886303774102509885
  ├─ Test Result: PASSED OK:
  └─ Artifacts:
      ├─ Test report (JSON + Markdown)
      ├─ Sensor config snapshot
      └─ Logs/screenshots
```

**Key Insight**: Track by **test execution** not by **sensor instance**

---

## Redesigned Entity Model

### Primary Entities

**1. Test Execution** (Primary Entity)
```json
{
  "name": "execution-TEST-001-20251010-143052",
  "entityType": "test_execution",
  "observations": [
    "Test ID: TEST-001",
    "JIRA: CORE-5432",
    "Purpose: YARA Enable/Disable validation",
    "Started: 2025-10-10T14:30:52Z",
    "Completed: 2025-10-10T14:35:12Z",
    "Duration: 4m 20s",
    "Result: PASSED",
    "Steps Passed: 9",
    "Steps Failed: 0"
  ]
}
```

**2. Sensor Deployment** (Supporting Entity)
```json
{
  "name": "sensor-deployment-886303774102509885",
  "entityType": "sensor_deployment",
  "observations": [
    "Stack Name: ec2-sensor-testing-qa-qarelease-886303774102509885",
    "IP Address: 10.50.88.154 (ephemeral)",
    "Deployed: 2025-10-10T14:00:00Z",
    "Auto-Delete: 2025-10-14T14:00:00Z (4 days)",
    "Version: BroLin 28.4.0-a7",
    "Configuration: default",
    "Status: DELETED on 2025-10-14"
  ]
}
```

**3. Test Case** (Template Entity)
```json
{
  "name": "TEST-001",
  "entityType": "test_case",
  "observations": [
    "Title: YARA Enable/Disable Test",
    "JIRA: CORE-5432",
    "File: TEST-001_yara_enable_disable.yaml",
    "Steps: 9",
    "Category: functional",
    "Priority: high",
    "Total Executions: 5",
    "Success Rate: 100%"
  ]
}
```

**4. JIRA Issue** (Requirement Entity)
```json
{
  "name": "CORE-5432",
  "entityType": "jira_issue",
  "observations": [
    "Title: YARA fails to enable on sensor",
    "Type: bug",
    "Priority: high",
    "Status: verified",
    "Created: 2025-09-15",
    "Verified: 2025-10-10",
    "Linked Test Case: TEST-001",
    "Total Verification Runs: 3"
  ]
}
```

### Relations

```
Test Execution → uses → Sensor Deployment (ephemeral)
Test Execution → validates → JIRA Issue
Test Execution → executes → Test Case
JIRA Issue → requires → Test Case
Test Case → has_executions → [Test Execution, ...]
Sensor Deployment → hosted → [Test Execution, ...]
```

---

## Obsidian Vault Structure (Redesigned)

### Old Structure FAIL:
```
Sensors/
  └── 10.50.88.154.md  FAIL: IP changes, this breaks
```

### New Structure OK:
```
obsidian/corelight/
├── Test-Executions/
│   ├── 2025-10/
│   │   ├── TEST-001-20251010-143052.md
│   │   ├── TEST-002-20251010-150012.md
│   │   └── TEST-003-20251010-163045.md
│   └── 2025-11/
│       └── TEST-001-20251105-091234.md
│
├── Test-Cases/
│   ├── TEST-001-YARA-Enable-Disable.md
│   ├── TEST-002-Suricata-Configuration.md
│   └── TEST-003-Sensor-Health-Check.md
│
├── JIRA/
│   ├── CORE-5432.md (links to all TEST-001 executions)
│   ├── CORE-5678.md
│   └── CORE-6001.md
│
├── Sensor-Deployments/
│   ├── 2025-10/
│   │   ├── deployment-886303774102509885.md
│   │   └── deployment-123456789012345678.md
│   └── README.md (explains ephemeral nature)
│
└── Dashboards/
    ├── Test-Results-Dashboard.md
    ├── JIRA-Verification-Status.md
    └── Recent-Executions.md
```

---

## Key Tracking Points

### What to Track OK:

1. **Test Execution ID** (unique, permanent)
   - Format: `execution-{TEST_ID}-{TIMESTAMP}`
   - Example: `execution-TEST-001-20251010-143052`

2. **JIRA Ticket** (permanent)
   - Track validation status
   - Link all execution attempts
   - Track verification history

3. **Test Case Template** (permanent)
   - YAML file path
   - Success/failure statistics
   - All executions over time

4. **Sensor Deployment** (temporary, track for context)
   - Stack name (unique identifier)
   - IP address (ephemeral, for current session only)
   - Auto-delete date
   - Configuration used

5. **Test Results** (permanent)
   - JSON result file
   - Markdown report
   - Execution logs
   - Artifacts (screenshots, configs)

### What NOT to Track FAIL:

1. FAIL: "Sensor History by IP" - IP changes
2. FAIL: "All tests on this sensor" - sensor deletes
3. FAIL: "Sensor performance over time" - different sensors
4. FAIL: Long-term sensor metrics - no long-term sensors

---

## Updated Obsidian Note Templates

### Test Execution Note

**File**: `Test-Executions/2025-10/TEST-001-20251010-143052.md`

```markdown
# TEST-001 Execution - 2025-10-10

## Execution Details
- **Execution ID**: `execution-TEST-001-20251010-143052`
- **Test Case**: [[TEST-001-YARA-Enable-Disable]]
- **JIRA Issue**: [[CORE-5432]]
- **Status**: OK: PASSED
- **Started**: 2025-10-10 14:30:52
- **Duration**: 4m 20s

## Sensor Deployment (Ephemeral)
- **Stack Name**: `ec2-sensor-testing-qa-qarelease-886303774102509885`
- **IP Address**: `10.50.88.154` WARN: *Will auto-delete 2025-10-14*
- **Version**: BroLin 28.4.0-a7
- **Configuration**: default
- **Deployment**: [[deployment-886303774102509885]]

## Test Results
- Steps Passed: 9
- Steps Failed: 0
- Total Steps: 9

## Test Steps
[... step details ...]

## Artifacts
- Result File: `testing/test_results/TEST-001_1760120000.json`
- Report: `testing/test_results/TEST-001_20251010.md`
- Sensor Config Snapshot: `sensor_prep/snapshots/backups/baseline.yaml`

## Tags
#test-execution #test-001 #jira-core-5432 #passed #2025-10

## Related
- [[TEST-001-YARA-Enable-Disable|Test Case]]
- [[CORE-5432|JIRA Issue]]
- [[deployment-886303774102509885|Sensor Deployment]]
- [[Test-Results-Dashboard]]
```

### Test Case Note (Template)

**File**: `Test-Cases/TEST-001-YARA-Enable-Disable.md`

```markdown
# TEST-001: YARA Enable/Disable Test

## Metadata
- **Test ID**: TEST-001
- **JIRA**: [[CORE-5432]]
- **File**: `testing/test_cases/TEST-001_yara_enable_disable.yaml`
- **Category**: functional
- **Priority**: high

## Description
This test validates that the YARA feature can be successfully enabled and disabled on the sensor without causing service failures.

## Statistics
- **Total Executions**: 5
- **Successful**: 5 (100%)
- **Failed**: 0 (0%)
- **Average Duration**: 4m 15s
- **Last Run**: 2025-10-10

## Recent Executions
- [[TEST-001-20251010-143052]] - OK: PASSED
- [[TEST-001-20251009-101234]] - OK: PASSED
- [[TEST-001-20251008-153045]] - OK: PASSED

## YAML Source
\`\`\`yaml
# View source: testing/test_cases/TEST-001_yara_enable_disable.yaml
\`\`\`

## Tags
#test-case #test-001 #yara #functional
```

### JIRA Issue Note

**File**: `JIRA/CORE-5432.md`

```markdown
# CORE-5432: YARA fails to enable on sensor

## Issue Details
- **Ticket**: CORE-5432
- **Type**: bug
- **Priority**: high
- **Status**: OK: Verified
- **Created**: 2025-09-15
- **Verified**: 2025-10-10

## Description
YARA feature fails to enable via configuration API on sensors running version 28.4.0+

## Test Case
- Primary: [[TEST-001-YARA-Enable-Disable]]

## Verification History
| Date | Execution | Result | Sensor |
|------|-----------|--------|--------|
| 2025-10-10 | [[TEST-001-20251010-143052]] | OK: PASSED | deployment-886303774102509885 |
| 2025-10-09 | [[TEST-001-20251009-101234]] | OK: PASSED | deployment-112233445566778899 |
| 2025-10-08 | [[TEST-001-20251008-153045]] | OK: PASSED | deployment-998877665544332211 |

## Status
OK: **VERIFIED** - Test passing consistently across 3 sensor deployments

## Tags
#jira #core-5432 #verified #yara
```

### Sensor Deployment Note

**File**: `Sensor-Deployments/2025-10/deployment-886303774102509885.md`

```markdown
# Sensor Deployment: 886303774102509885

## WARN: Ephemeral Sensor
**This sensor auto-deletes 4 days after deployment**

## Deployment Details
- **Stack Name**: `ec2-sensor-testing-qa-qarelease-886303774102509885`
- **IP Address**: `10.50.88.154`
- **Deployed**: 2025-10-10 14:00:00
- **Auto-Delete**: 2025-10-14 14:00:00
- **Status**: WARN: DELETED

## Configuration
- **Version**: BroLin 28.4.0-a7
- **Profile**: default
- **Instance Type**: m6a.2xlarge
- **Storage**: 500GB

## Tests Executed
- [[TEST-001-20251010-143052]] - YARA Enable/Disable
- [[TEST-002-20251010-150012]] - Suricata Configuration
- [[TEST-003-20251010-163045]] - Health Check

## Purpose
This sensor was deployed to validate JIRA ticket [[CORE-5432]]

## Lifecycle
- OK: Deployed: 2025-10-10 14:00:00
- OK: Configured: 2025-10-10 14:05:23
- OK: Tests Run: 2025-10-10 14:30-16:45
- WARN: Deleted: 2025-10-14 14:00:00

## Tags
#sensor-deployment #ephemeral #deleted #2025-10
```

---

## Memory Knowledge Graph (Redesigned)

### Example Queries

**Q: What's the verification status of CORE-5432?**
```python
# Search for JIRA issue
search_nodes(query="CORE-5432")

# Get relations
# CORE-5432 → validated_by → [execution-TEST-001-20251010, ...]

# Result: 3 passing executions, VERIFIED OK:
```

**Q: How many times has TEST-001 been run?**
```python
# Search for test case
search_nodes(query="TEST-001 executes")

# Get all executions
# TEST-001 → has_executions → [execution-1, execution-2, ...]

# Result: 5 executions, 100% success rate
```

**Q: What tests were run on deployment 886303774102509885?**
```python
# Search for deployment
search_nodes(query="deployment-886303774102509885")

# Get hosted executions
# deployment-886303774102509885 → hosted → [execution-1, execution-2, ...]

# Result: 3 test executions
```

---

## Implementation Changes

### Obsidian Connector Updates

```python
def sync_test_result(self, test_id: str, execution_timestamp: str,
                     result_file: str, sensor_deployment: Dict) -> Dict:
    """
    Sync test execution result

    Args:
        test_id: TEST-001
        execution_timestamp: 20251010-143052
        result_file: Path to result JSON
        sensor_deployment: Dict with stack_name, ip, deployed_at, delete_at
    """
    execution_id = f"{test_id}-{execution_timestamp}"

    # Create execution note
    vault_path = f"Test-Executions/{year}-{month}/{execution_id}.md"

    # Note includes:
    # - Execution details
    # - Sensor deployment (ephemeral, with delete date)
    # - Test results
    # - Links to test case, JIRA, deployment
```

### Memory Connector Updates

```python
def create_test_execution_entity(self, execution_id: str, test_id: str,
                                jira_ticket: str, sensor_deployment: str,
                                result: Dict) -> Dict:
    """Create test execution entity"""

    create_entities([{
        "name": execution_id,
        "entityType": "test_execution",
        "observations": [
            f"Test: {test_id}",
            f"JIRA: {jira_ticket}",
            f"Result: {result['status']}",
            f"Sensor: {sensor_deployment} (ephemeral)",
            f"Timestamp: {datetime.now().isoformat()}"
        ]
    }])

    # Create relations
    create_relations([
        {"from": execution_id, "to": test_id, "relationType": "executes"},
        {"from": execution_id, "to": jira_ticket, "relationType": "validates"},
        {"from": execution_id, "to": sensor_deployment, "relationType": "uses_deployment"}
    ])
```

---

## Benefits of New Model

### OK: Advantages

1. **Tracks What Matters**: Test executions and JIRA verification, not transient IPs
2. **JIRA-Centric**: Easy to see all validation attempts for a ticket
3. **Test Case Stats**: Track success rates and execution history
4. **Deployment Context**: Sensor info captured but acknowledged as ephemeral
5. **Time-Based Organization**: Group by month/year for easy navigation
6. **Searchable**: Find all attempts to validate a JIRA issue
7. **Audit Trail**: Complete history of verification attempts

###  Use Cases

**"Has CORE-5432 been verified?"**
→ Check JIRA note, see 3 passing executions OK:

**"What's the success rate of TEST-001?"**
→ Check Test Case note, see 5/5 passing (100%)

**"What tests were run on October 10?"**
→ Browse Test-Executions/2025-10/ folder

**"Why did TEST-002 fail last time?"**
→ Open execution note, see step-by-step details

---

## Migration from Old Model

**If old notes exist**:
1. Rename `Sensors/10.50.88.154.md` → `Sensor-Deployments/2025-10/deployment-{stack}.md`
2. Add "WARN: EPHEMERAL" warning
3. Add auto-delete date
4. Link to test executions instead of vice versa

---

## Summary

**Old Mental Model** FAIL::
- Track sensors by IP
- Build sensor history
- Multi-use sensors

**New Mental Model** OK::
- Track test **executions** (permanent)
- Track JIRA **verification** (permanent)
- Track sensor **deployments** (ephemeral, context only)
- IP addresses are temporary session identifiers
- One sensor = One test session = Auto-deletes in 4 days

**Key Insight**: We're not testing persistent infrastructure, we're validating JIRA issues using disposable sensor instances.

---

**Status**: Design Complete
**Next**: Update Obsidian connector with new model
**Impact**: Critical - fundamentally changes tracking strategy
