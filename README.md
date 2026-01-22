# EC2 Sensor Manager

Professional CLI tool for managing Corelight sensors on AWS EC2 with live metrics and keyboard shortcuts.

## Quick Start

```bash
./sensor.sh
```

## Features

- **Professional TUI** - Clean, kubectl/docker-style interface
- **Live Metrics** - Real-time CPU%, MEM%, DISK%, and service counts
- **Keyboard Shortcuts** - `r` refresh, `n` new sensor, `m` multi-select, `t` theme, `q` quit, `?` help
- **Fast** - Parallel API calls, SSH connection reuse, and lazy metrics loading
- **Resilient** - Automatic retry with exponential backoff, offline mode with cached data
- **Bulk Operations** - Select multiple sensors for batch delete or feature enablement
- **Health Dashboard** - Detailed sensor view with resource bars and service status
- **Color Themes** - Dark (default), light, and minimal themes

## Prerequisites

- Tailscale VPN access (`tailscale up`)
- Command-line tools: `jq`, `curl`, `ssh`, `sshpass`

## Setup

```bash
# Copy example environment file
cp env.example .env

# Edit with your credentials
nano .env
```

## Usage

### Main Interface

```bash
./sensor.sh
```

From the TUI you can:
- View all sensors with live metrics
- Select a sensor to connect via SSH
- Deploy new sensors (~20 min)
- Refresh status with `r` key

### Manual Operations

```bash
# Check sensor status
./sensor_lifecycle.sh status

# Connect to sensor
./sensor_lifecycle.sh connect

# Delete sensor
./sensor_lifecycle.sh delete
```

## Sensor Lifecycle

- **Creation**: ~5 minutes (CloudFormation deployment)
- **Initialization**: ~15 minutes (services startup)
- **Auto-deletion**: 4 days (AWS lifecycle policy)

Sensors are ephemeral - create new ones as needed.

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `EC2_SENSOR_BASE_URL` | Yes | API endpoint URL |
| `EC2_SENSOR_API_KEY` | Yes | API authentication key |
| `SSH_USERNAME` | No | SSH user (default: broala) |
| `SSH_PASSWORD` | No | SSH password (or use SSH keys) |
| `ADMIN_PASSWORD` | No | Admin password for sensor config |
| `EC2SENSOR_THEME` | No | Color theme: dark, light, minimal |

### Color Themes

- **dark** (default) - Bright colors for dark terminal backgrounds
- **light** - Darker colors for light terminal backgrounds  
- **minimal** - No colors, just bold/dim for accessibility

Set theme via environment variable or press `t` to cycle through themes.

```bash
# In .env
EC2SENSOR_THEME=light

# Or export
export EC2SENSOR_THEME=minimal
```

## Troubleshooting

**Sensor not connecting:**
```bash
tailscale status              # Check VPN
./sensor_lifecycle.sh status  # Verify sensor IP
```

**SSH connection fails:**
```bash
SSHPASS="$SSH_PASSWORD" sshpass -e ssh broala@<sensor-ip>
```

## Security

- Credentials stored in `.env` (not tracked by git)
- No hardcoded secrets in scripts

---

Version: 1.1.0
