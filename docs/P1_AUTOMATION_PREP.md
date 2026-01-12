# P1 Automation Testing Preparation

Guide for preparing EC2 sensors for API P1/E2E automation pipeline testing.

## Prerequisites

- Sensor must be in NGS mode
- HTTP access enabled
- Fleet manager accessible at 192.168.22.239:1443
- Admin password configured
- Suricata and SmartPCAP enabled

## Quick Preparation

```bash
# After sensor is created and features enabled
./scripts/prepare_p1_automation.sh <sensor_ip>
```

This script will:
1. Configure admin password
2. Disable PCAP replay mode
3. Enable Suricata
4. Enable SmartPCAP
5. Add sensor to fleet manager

## Manual Preparation Steps

### 1. Configure HTTP Access (Already done by sensor.sh)

```bash
sudo /opt/broala/bin/broala-config set http.access.enable=1
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config
```

### 2. Configure Admin Password

```bash
sudo /opt/broala/bin/broala-config set security.user.admin.password='YOUR_PASSWORD'
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

### 3. Disable PCAP Replay Mode

```bash
sudo /opt/broala/bin/broala-config set bro.pcap_replay_mode=0
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

### 4. Enable Suricata (Already done by sensor.sh)

```bash
sudo /opt/broala/bin/broala-config set corelight.yara.enable=1
sudo /opt/broala/bin/broala-config set suricata.enable=1
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

### 5. Enable SmartPCAP (Already done by sensor.sh)

```bash
sudo /opt/broala/bin/broala-config set smartpcap.enable=1
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

### 6. Add to Fleet Manager

```bash
sudo /opt/broala/bin/broala-config set fleet.community_string=broala
sudo /opt/broala/bin/broala-config set fleet.server=192.168.22.239:1443
sudo /opt/broala/bin/broala-config set fleet.enable=1
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

### 7. Verify Sensor is Ready

```bash
# Check sensor status
sudo corelightctl sensor status

# Verify fleet connection
sudo /opt/broala/bin/broala-config get fleet.enable

# Check PCAP replay mode
sudo /opt/broala/bin/broala-config get bro.pcap_replay_mode
```

## Fleet Manager Commands

### Add to Fleet

```bash
sudo /opt/broala/bin/broala-config set fleet.community_string=broala
sudo /opt/broala/bin/broala-config set fleet.server=192.168.22.239:1443
sudo /opt/broala/bin/broala-config set fleet.enable=1
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

### Remove from Fleet

```bash
sudo /opt/broala/bin/broala-config set fleet.enable=0
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config -q
```

## Upgrade to Latest Build

### Check for Updates

```bash
sudo corelightctl sensor updates list
```

### Apply Updates

```bash
# Apply all pending updates
sudo corelightctl sensor updates apply

# Monitor update progress
sudo corelightctl sensor updates status
```

### Wait for Update Completion

Updates typically take 15-30 minutes. Monitor with:

```bash
watch -n 30 "sudo corelightctl sensor updates status"
```

## Pipeline Infrastructure

### Daily Pipelines

- DAILY--P1--NGS: Runs daily at 00:00 UTC on EC2 NGS sensors
- DAILY--P1--SS: Runs daily at 00:00 UTC on VMware soft sensors
- P1--PHYSICAL: Runs Tuesday and Friday at 3:27 UTC

### Infrastructure Resources

- NGS EC2 sensors: Created via API (ephemeral)
- Soft sensors: 192.168.21.163 (dev), 192.168.21.200 (RC)
- Physical sensors: 192.168.22.90, 192.168.22.233
- Fleet managers: 192.168.22.239, 192.168.22.228
- Streaming exporters: 192.168.21.151, 192.168.21.185, 192.168.22.72
- Kafka exporters: 192.168.22.179, 192.168.22.184
- SFTP server: 192.168.22.128

## Sensor Requirements for P1

- Must be in NGS mode (default for EC2 sensors)
- Must be attached to fleet manager
- HTTP access enabled
- Admin password configured
- Suricata enabled
- SmartPCAP enabled
- PCAP replay mode disabled
- No pending updates

## Troubleshooting

### Sensor Not Connecting to Fleet

```bash
# Check fleet configuration
corelight-client configuration get fleet

# Verify network connectivity to fleet
ping 192.168.22.239

# Check sensor status
corelight-client sensor status
```

### Updates Failing

```bash
# Check for errors
corelight-client updates list

# Verify sensor has internet access
curl -I https://packages.corelight.com

# Check disk space
df -h
```

### SmartPCAP Not Enabling

```bash
# Verify license
sudo /opt/broala/bin/broala-config get license.smartpcap.enable

# Check SmartPCAP status
corelight-client configuration get smartpcap.enable

# Reapply configuration
sudo LC_ALL=en_US.utf8 LANG=en_US.utf8 /opt/broala/bin/broala-apply-config
```

## Reference

- Confluence: https://corelight.atlassian.net/wiki/x/YQDiCw
- JIRA: https://corelight.atlassian.net/browse/SRE-3476
- Slack channels: eng-platform-team, baremetal-regression-nightly, testing

---

Last Updated: 2025-12-14
