# Project knowledge

EC2 Sensor Testing Platform - Bash automation framework for testing Corelight sensors on AWS EC2 instances.

## Quickstart

```bash
# Main entry point - creates, configures, and connects to sensor
./sensor.sh

# Backend lifecycle management
./sensor_lifecycle.sh status|create|connect|delete|enable-features

# Run a test case
./testing/run_test.sh TEST-001_yara_enable_disable --sensor <ip>

# Prepare sensor for P1 automation
./scripts/prepare_p1_automation.sh <ip>
```

## Prerequisites

- Tailscale VPN (`tailscale up`)
- AWS credentials configured
- Tools: `jq`, `curl`, `ssh`, `sshpass`

## Architecture

- **Key directories:**
  - `sensor.sh` / `sensor_lifecycle.sh` - Main entry points
  - `workflows/` - High-level orchestration (reproduce issues, validate fixes)
  - `testing/` - Test framework with YAML test cases
  - `sensor_prep/` - Sensor configuration and feature enablement
  - `scripts/` - Utility scripts
  - `mcp_integration/` - MCP connectors (Obsidian, Memory, Exa)

- **Data flow:**
  1. Create sensor via API → Wait ~20 min for initialization
  2. Enable features (HTTP, YARA, Suricata, SmartPCAP)
  3. Run tests → Results saved to `testing/test_results/`
  4. Sync to MCP (non-blocking)

## Conventions

- **Shell style:** `UPPER_SNAKE_CASE` for constants/env vars, `lower_snake_case` for locals
- **Logging:** Use `ec2sensor_logging.sh` functions (`log_info`, `log_error`, `log_api`, etc.)
- **Error handling:** Capture exit codes explicitly, log before executing
- **Security:** Never hardcode credentials, use `.env` (600 permissions)

## Important Gotchas

- **Sensors are ephemeral:** Auto-delete after 4 days, IPs change on nightly restart (~2 AM UTC)
- **Initialization takes ~20 minutes** after creation before sensor is ready
- **SSH credentials:** User `broala`, password in `.env` (`SSH_PASSWORD`)
- **API versions:** Legacy (<28.0) vs Modern (≥28.4.0) use different endpoints
- **MCP failures are non-blocking** - workflows continue if MCP sync fails
- **Always source `scripts/load_env.sh`** before using env vars
