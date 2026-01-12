# Sensor Preparation

This directory contains tools and configurations for preparing EC2 sensors for different testing scenarios.

## Directory Structure

```
sensor_prep/
├── README.md                    # This file
├── enable_sensor_features.sh    # Enable HTTP, YARA, Suricata, SmartPCAP
├── prepare_sensor.sh            # Main preparation orchestrator (coming soon)
├── configs/                     # Sensor configuration profiles
│   ├── default.yaml
│   ├── smartpcap_enabled.yaml
│   ├── suricata_test.yaml
│   └── high_throughput.yaml
├── packages/                    # Package installation scripts
│   ├── base_testing_tools.sh
│   ├── smartpcap_tools.sh
│   ├── suricata_testing.sh
│   └── performance_monitoring.sh
└── snapshots/                   # Snapshot management tools
    └── snapshot_manager.sh
```

## Quick Start

### Enable Features on Existing Sensor

```bash
# Enable all standard features (HTTP, YARA, Suricata, SmartPCAP)
./sensor_prep/enable_sensor_features.sh

# Or specify sensor IP
./sensor_prep/enable_sensor_features.sh 10.50.88.100

# With custom SSH user
./sensor_prep/enable_sensor_features.sh 10.50.88.100 broala
```

This script will:
1. Connect to the sensor via SSH
2. Enable HTTP access, YARA, Suricata, and SmartPCAP
3. Apply configuration changes
4. Verify features are enabled

## Configuration Profiles

### Available Profiles

1. **default.yaml** - Standard testing configuration
   - General purpose testing
   - All features enabled
   - Moderate resources (m6a.2xlarge)

2. **smartpcap_enabled.yaml** - SmartPCAP testing
   - Full SmartPCAP functionality
   - 1TB disk for PCAP storage
   - SmartPCAP-specific tools

3. **suricata_test.yaml** - Suricata IDS testing
   - Suricata + YARA integration
   - Custom rule deployment
   - Alert generation and testing

4. **high_throughput.yaml** - Performance testing
   - Network-optimized instance (c6in.2xlarge)
   - High-volume traffic handling
   - Performance monitoring tools

### Profile Format

```yaml
name: profile_name
description: Brief description

aws:
  ami_id: ami-xxxxx
  instance_type: m6a.2xlarge
  disk_space: 500gb

brolin_config:
  http.access.enable: 1
  license.yara.enable: 1
  license.suricata.enable: 1
  license.smartpcap.enable: 1

packages:
  - base_testing_tools
  - custom_tools

test_scenarios:
  - Scenario 1
  - Scenario 2
```

## Creating Custom Profiles

1. Copy an existing profile as a template
2. Modify AWS settings (instance type, disk, etc.)
3. Adjust `brolin_config` for specific features
4. List required packages
5. Document test scenarios and notes

Example:

```bash
cp sensor_prep/configs/default.yaml sensor_prep/configs/my_custom.yaml
# Edit my_custom.yaml
```

## Post-Deployment Configuration

After creating a sensor, these commands are automatically run by `enable_sensor_features.sh`:

```bash
sudo broala-config set http.access.enable=1
sudo broala-config set license.yara.enable=1
sudo broala-config set license.suricata.enable=1
sudo broala-config set license.smartpcap.enable=1
sudo broala-apply-config -q
```

**Wait 2-3 minutes** after applying config for services to restart.

## Package Installation

Package installation scripts in `packages/` directory:

- **base_testing_tools.sh**: jq, wget, curl, netcat, tcpdump
- **smartpcap_tools.sh**: SmartPCAP testing utilities
- **suricata_testing.sh**: Suricata rule management and testing
- **performance_monitoring.sh**: htop, iotop, nethogs, iperf

## Snapshots

Create snapshots for repeatable testing:

```bash
# Create baseline snapshot
sudo broala-snapshot -c baseline-$(date +%Y%m%d)

# List snapshots
sudo broala-snapshot -l

# Revert to snapshot (requires reboot)
sudo broala-snapshot -R baseline-20251010 && sudo reboot
```

## Troubleshooting

### Features Not Enabling

```bash
# Check configuration
sudo broala-config all | grep -E 'yara|suricata|smartpcap|http.access'

# Verify services
sudo corelightctl sensor status

# Check logs
sudo broala-log | tail -n 100
```

### SSH Connection Issues

```bash
# Verify sensor is running
./sensor_lifecycle.sh status

# Check VPN
tailscale status

# Try different auth method
./troubleshoot_ssh.sh
```

## Related Documentation

- [Sensor Lifecycle Guide](../docs/guides/SENSOR_LIFECYCLE.md)
- [Test Case Creation](../docs/guides/TEST_CASE_CREATION.md)
- [Sensor Commands Reference](../docs/reference/SENSOR_COMMANDS.md)
