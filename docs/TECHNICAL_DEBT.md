# EC2 Sensor Project - Technical Debt Analysis

Generated: 2025-12-15

## CRITICAL Issues (Priority 1)

### 1. Duplicate/Conflicting Scripts
**Severity: HIGH**
- **3 versions of enable_sensor_features.sh:**
  - `scripts/enable_sensor_features.sh` (84 lines) - Currently active, recently fixed
  - `sensor_prep/enable_sensor_features.sh` (137 lines) - Array-based approach
  - `sensor_prep/enable_sensor_features_v2.sh` (207 lines) - YAML-based approach

- **2 versions of snapshot_manager.sh:**
  - `sensor_prep/snapshots/snapshot_manager.sh`
  - `sensor_prep/snapshots/snapshot_manager_v2.sh`

**Impact:** Confusion about which script to use, potential bugs from using wrong version, maintenance overhead

**Recommendation:** Consolidate to single canonical version per script, delete obsolete versions

### 2. Silent Error Suppression (-q flag)
**Severity: HIGH**
**Affected files:**
- scripts/enable_sensor_features.sh
- sensor_prep/prepare_sensor.sh
- testing/lib/test_framework.sh
- sensor_prep/enable_sensor_features_v2.sh
- sensor_prep/detect_sensor_version.sh
- sensor_prep/enable_sensor_features.sh

**Issue:** `broala-apply-config -q` suppresses Ansible errors, causing silent failures

**Evidence:** Recent debugging showed configuration wasn't applied because errors were hidden

**Recommendation:** Remove `-q` flag, add proper error detection with `| grep -E "(failed=)"` and exit on failed!=0

### 3. Hardcoded Credentials
**Severity: HIGH (Security)**
**Occurrences:** 11 files contain hardcoded credentials
- `CoreL1ght!` (admin password)
- `your_ssh_password_here` (SSH password)
- `192.168.22.239` (fleet manager IP)

**Files affected:**
- sensor.sh
- sensor_lifecycle.sh
- scripts/prepare_p1_automation.sh
- Documentation files (README, CLAUDE.md)

**Recommendation:**
- Credentials should ONLY be in .env (already there)
- Scripts should ALWAYS source from .env, never hardcode
- Documentation should use placeholders like `YOUR_PASSWORD` or `${ADMIN_PASSWORD}`

### 4. Inconsistent Error Handling
**Severity: MEDIUM-HIGH**
**Issue:** 9 critical scripts lack `set -e` (exit on error):
- compare_sensors.sh
- ec2sensor_logging.sh
- sensor_lifecycle.sh
- sensor.sh
- scripts/load_env.sh
- scripts/run_network_test.sh
- scripts/sensor_diagnostics.sh
- scripts/setup_ssh_keys.sh
- scripts/tcpreplay.sh

**Impact:** Scripts continue executing after failures, leading to cascading errors

**Recommendation:** Add `set -euo pipefail` to all scripts for strict error handling

## HIGH Priority Issues (Priority 2)

### 5. No Logging in sensor.sh
**Severity: MEDIUM**
- sensor.sh has 0 log calls while sensor_lifecycle.sh has 231
- No audit trail for user operations
- Difficult to debug issues

**Recommendation:** Add logging infrastructure to sensor.sh using ec2sensor_logging.sh

### 6. Manual .env File Manipulation
**Severity: MEDIUM**
**Issue:** sensor_lifecycle.sh has 10+ `sed -i.bak` operations for .env editing
- Creates .bak files (found: .env.bak, scripts/.env.bak)
- Error-prone string manipulation
- No validation of values

**Recommendation:** Create helper functions for .env management:
```bash
update_env_var() {
    key=$1
    value=$2
    # Validate, update, no .bak files
}
```

### 7. Minimal Test Coverage
**Severity: MEDIUM**
- 28 shell scripts in project
- Only 4 YAML test cases in testing/test_cases/
- No unit tests for critical functions
- No integration test suite

**Recommendation:**
- Add test cases for critical workflows (sensor creation, feature enablement, fleet setup)
- Create integration test suite

### 8. Incomplete TODOs in Workflows
**Severity: MEDIUM**
**Found in workflows:**
- reproduce_jira_issue.sh: `TODO: Get from sensor status`
- validate_fix.sh: `TODO: Deploy sensor with specific AMI`
- performance_baseline.sh: `TODO: Implement actual tcpreplay throughput test`
- performance_baseline.sh: `TODO: Implement packet loss test`
- performance_baseline.sh: `TODO: Implement detailed comparison logic`

**Recommendation:** Complete or document these TODOs, track as issues

## MEDIUM Priority Issues (Priority 3)

### 9. Orphaned/Empty Directories
**Severity: LOW-MEDIUM**
- `./core/` - Empty except for empty `lib/` subdirectory
- `./~/` - Unusual directory name, contains `Library/` subdirectory
- Neither in .gitignore

**Recommendation:** Remove unused directories, add to .gitignore if needed

### 10. Python venv in Project
**Severity: LOW**
- `./venv/` contains 3,118 files
- Already in .gitignore (good)
- Should document Python setup in README

**Recommendation:** Document Python virtual environment setup and dependencies

### 11. Backup Files Not Cleaned
**Severity: LOW**
- .env.bak
- scripts/.env.bak

**Recommendation:** Add cleanup to scripts that create .bak files, or gitignore them (already done)

## Documentation Debt

### 12. Inconsistent Documentation
**Issue:** Recent refactoring removed emoji/unicode but some files may still reference old behavior
**Recommendation:** Verify all docs match current implementation

### 13. Missing Error Recovery Documentation
**Issue:** No documentation on how to recover from common failures
**Recommendation:** Add TROUBLESHOOTING section with:
- What to do when broala-apply-config fails
- How to recover from partial configuration
- How to clean up failed sensor deployments

## Architecture Debt

### 14. Tight Coupling to broala-config
**Issue:** Many scripts depend on broala-config behavior which differs by version
**Current handling:** detect_sensor_version.sh and enable_sensor_features_v2.sh try to handle this
**Problem:** Version detection logic scattered across multiple scripts

**Recommendation:** Centralize version detection and command routing

### 15. No Idempotency Guarantees
**Issue:** Running scripts multiple times may cause issues
- Feature enablement runs multiple config sets
- No checking if already configured
- Could be more efficient

**Recommendation:** Add state checking before operations

## Metrics Summary

- **Total Shell Scripts:** 28
- **Scripts with Duplicate Logic:** 5 (3 feature enablement + 2 snapshot managers)
- **Scripts without `set -e`:** 9 (32%)
- **Scripts with hardcoded secrets:** 3 (sensor.sh, sensor_lifecycle.sh, prepare_p1_automation.sh)
- **Files with `-q` error suppression:** 6
- **Test Coverage:** 4 test cases for 28 scripts (~14%)
- **Incomplete TODOs:** 5
- **Log files accumulated:** 56

## Recommended Action Plan

### Phase 1 (Immediate - This Week)
1. Remove `-q` flags from all broala-apply-config calls
2. Consolidate duplicate scripts (choose one version, delete others)
3. Add `set -euo pipefail` to all critical scripts
4. Remove hardcoded credentials from scripts

### Phase 2 (Short Term - Next 2 Weeks)
1. Add logging to sensor.sh
2. Create .env helper functions
3. Clean up orphaned directories
4. Complete or document TODOs

### Phase 3 (Medium Term - Next Month)
1. Increase test coverage to 50%
2. Add error recovery documentation
3. Centralize version detection logic
4. Implement idempotency checks
