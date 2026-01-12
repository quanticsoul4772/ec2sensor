# EC2 Sensor Testing Platform

Automation framework for testing Corelight sensors on AWS EC2 instances.

## Quick Start

```bash
# One command to create, configure, and connect to a sensor
./sensor.sh
```

The script will:
1. Show existing sensors or create a new one
2. Wait ~20 minutes for sensor deployment and initialization
3. Automatically enable HTTP, YARA, Suricata, and SmartPCAP features
4. Connect you via SSH when ready

## Prerequisites

Required:
- Tailscale VPN access (run `tailscale up`)
- AWS credentials configured
- Command-line tools: `jq`, `curl`, `ssh`, `sshpass`

Optional:
- Obsidian vault for MCP integration
- Claude Code with MCP servers

## Environment Setup

```bash
# Copy example environment file
cp env.example .env

# Edit with your values (if different from defaults)
nano .env
```

The `env.example` contains working defaults for the shared test environment. No changes needed unless you have custom requirements.

## Sensor Management

### Create and Connect

```bash
./sensor.sh
# Select option 2 to create new sensor
# Wait ~20 minutes for deployment
# Auto-connects when ready
```

### Connect to Existing Sensor

```bash
./sensor.sh
# Select sensor number from menu
# Connects immediately
```

### Manual Operations (Advanced)

```bash
# Check sensor status
./sensor_lifecycle.sh status

# Enable features manually (if needed)
./sensor_lifecycle.sh enable-features

# Connect to specific sensor
./sensor_lifecycle.sh connect

# Delete sensor
./sensor_lifecycle.sh delete
```

## What Gets Enabled Automatically

When you create a sensor, these features are enabled automatically:
- HTTP access (port 80/443)
- YARA file scanning
- Suricata IDS
- SmartPCAP packet capture

After features are enabled, you'll be prompted to optionally prepare the sensor for P1 automation testing:
- Configure admin password
- Disable PCAP replay mode
- Add to fleet manager (192.168.22.239)

No manual configuration needed for basic use.

## Sensor Lifecycle

- Creation: ~5 minutes (CloudFormation stack deployment)
- Initialization: ~15 minutes (sensor services startup)
- Seeding: ~30-60 minutes (complete system initialization)
- Auto-deletion: 4 days (AWS lifecycle policy)
- IP addresses: Change on each deployment and nightly restart

Sensors are ephemeral. Create new ones as needed.

## Project Structure

```
ec2sensor/
├── sensor.sh                  # Main entry point (ONE command)
├── sensor_lifecycle.sh        # Backend lifecycle management
├── scripts/                   # Utility scripts
│   ├── enable_sensor_features.sh
│   ├── wait_for_sensor_ready.sh
│   └── load_env.sh
├── sensor_prep/               # Sensor configuration
│   ├── configs/               # YAML configuration profiles
│   └── packages/              # Package installers
├── testing/                   # Test framework
│   ├── test_cases/            # YAML test definitions
│   └── test_results/          # Execution results
├── workflows/                 # Automated workflows
│   ├── reproduce_jira_issue.sh
│   ├── validate_fix.sh
│   └── troubleshoot_sensor.sh
├── mcp_integration/           # MCP connectors (Obsidian, Memory, Exa)
├── logs/                      # Execution logs
└── .sensors                   # Tracked sensors
```

## P1 Automation Testing

Prepare sensors for API P1/E2E automation pipelines:

```bash
# Automatic during sensor creation (prompted)
./sensor.sh
# Answer 'y' when asked about P1 preparation

# Manual preparation
./scripts/prepare_p1_automation.sh <sensor_ip>

# With upgrade to latest build
./scripts/prepare_p1_automation.sh <sensor_ip> --upgrade

# Custom fleet manager
./scripts/prepare_p1_automation.sh <sensor_ip> --fleet-ip 192.168.22.228
```

See `docs/P1_AUTOMATION_PREP.md` for complete guide.

## Advanced Workflows

For complex testing scenarios, use the workflow scripts:

```bash
# Reproduce JIRA issue
./workflows/reproduce_jira_issue.sh CORE-5432

# Validate fix
./workflows/validate_fix.sh CORE-5432 --fixed-version ami-0fix123

# Performance baseline
./workflows/performance_baseline.sh "28.5.0"

# Troubleshoot sensor
./workflows/troubleshoot_sensor.sh --sensor-ip 10.50.88.154
```

See `workflows/README.md` for details.

## Testing

Run test cases against a deployed sensor:

```bash
# Run specific test
./testing/run_test.sh TEST-001_yara_enable_disable --sensor 10.50.88.154

# View results
cat testing/test_results/TEST-001_*.md
```

See `testing/README.md` for test framework details.

## Troubleshooting

### Common Issues

**Sensor not connecting:**
```bash
# Check VPN
tailscale status

# Verify sensor IP
./sensor_lifecycle.sh status

# Check sensor is ready
ssh broala@<sensor-ip> "sudo corelightctl sensor status"
```

**Features not enabled:**
```bash
# Check if seeded
ssh broala@<sensor-ip> "sudo /opt/broala/bin/broala-config get system.seeded"
# Should return 1 (not 0)

# Enable manually
./sensor_lifecycle.sh enable-features
```

**SSH connection fails:**
```bash
# Check SSH key permissions
chmod 600 ~/.ssh/ec2_sensor_key

# Test password auth
sshpass -p 'your_ssh_password_here' ssh broala@<sensor-ip>
```

### Logs

All operations are logged:

```bash
# View recent logs
ls -lht logs/*.log | head -5

# Check for errors
grep ERROR logs/*.log | tail -20

# Watch live log
tail -f logs/sensor_lifecycle_*.log
```

## Security

- Credentials stored in `.env` with 600 permissions
- No hardcoded secrets in scripts
- SSH keys preferred over passwords
- All operations logged for audit trail

Run `./sensor_lifecycle.sh secure` to verify security settings.

## Documentation

- `CLAUDE.md` - AI agent instructions (comprehensive reference)
- `workflows/README.md` - Workflow documentation
- `testing/README.md` - Test framework
- `sensor_prep/README.md` - Sensor preparation system
- `docs/` - Additional guides and architecture

## Support

For issues or questions:
1. Check `logs/` directory for error details
2. Review `CLAUDE.md` for comprehensive reference
3. Run `./sensor_lifecycle.sh` without arguments for help

---

Version: 1.0.0
Last Updated: 2025-12-09
