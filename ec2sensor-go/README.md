# EC2 Sensor Manager (Go Edition)

A professional Terminal User Interface (TUI) for managing EC2 sensors, built with Go and [Bubble Tea](https://github.com/charmbracelet/bubbletea).

![EC2 Sensor Manager](https://img.shields.io/badge/Go-1.21+-00ADD8?style=flat-square&logo=go)
![Bubble Tea](https://img.shields.io/badge/TUI-Bubble%20Tea-FF69B4?style=flat-square)

## Features

- 🖥️ **Beautiful TUI** - Professional terminal interface with colors, tables, and live updates
- ⚡ **Fast** - Single binary, instant startup, async operations
- 🎨 **Themes** - Dark, Light, and Minimal color themes (press `t` to cycle)
- ⌨️ **Keyboard Navigation** - Vim-style navigation (j/k), number selection, shortcuts
- 📊 **Live Metrics** - CPU, Memory, Disk, and Pod metrics via SSH
- 🔄 **Auto Refresh** - Automatic sensor data refresh every 60 seconds
- 🔒 **SSH Support** - Key-based and password authentication

## Installation

### Prerequisites

- Go 1.21 or later
- SSH access to your sensors
- API credentials (EC2_SENSOR_BASE_URL and EC2_SENSOR_API_KEY)

### Build from Source

```bash
cd ec2sensor-go
go mod download
go build -o ec2sensor .
```

### Build for Distribution

```bash
# Linux (amd64)
GOOS=linux GOARCH=amd64 go build -o ec2sensor-linux-amd64 .

# macOS (arm64 - Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -o ec2sensor-darwin-arm64 .

# macOS (amd64 - Intel)
GOOS=darwin GOARCH=amd64 go build -o ec2sensor-darwin-amd64 .

# Windows
GOOS=windows GOARCH=amd64 go build -o ec2sensor.exe .
```

## Configuration

Create a `.env` file in the project root or parent directory:

```env
# API Configuration (Required)
EC2_SENSOR_BASE_URL=https://your-api-endpoint.com/sensors
EC2_SENSOR_API_KEY=your-api-key-here

# SSH Configuration
SSH_USERNAME=broala
SSH_PASSWORD=your-password  # Or use SSH keys

# UI Configuration
EC2SENSOR_THEME=dark  # dark, light, or minimal
```

### SSH Authentication

The application supports two authentication methods:

1. **SSH Keys** (Recommended): If you have `~/.ssh/id_rsa` or `~/.ssh/id_ed25519`, they will be used automatically.

2. **Password**: Set `SSH_PASSWORD` in your environment or `.env` file. Requires `sshpass` to be installed:
   ```bash
   # macOS
   brew install hudochenkov/sshpass/sshpass
   
   # Linux
   apt-get install sshpass
   ```

## Usage

```bash
# Run from the ec2sensor-go directory
./ec2sensor

# Or run directly with go
go run .
```

### Keyboard Shortcuts

#### Main View
| Key | Action |
|-----|--------|
| `↑/↓` or `j/k` | Navigate sensor list |
| `1-9` | Select sensor by number |
| `Enter` | Open sensor operations |
| `r` | Refresh sensor list |
| `n` | Deploy new sensor |
| `m` | Toggle multi-select mode |
| `t` | Cycle color theme |
| `q` | Quit application |
| `?` | Show help |

#### Operations View
| Key | Action |
|-----|--------|
| `c` or `1` | Connect via SSH |
| `f` or `2` | Enable features |
| `u` or `5` | Upgrade sensor |
| `d` or `6` | Delete sensor |
| `h` or `7` | Health dashboard |
| `b` | Back to sensor list |
| `q` | Quit application |

### Themes

Press `t` to cycle through available themes:

- **Dark** (default) - Bright colors on dark background
- **Light** - Dark colors for light terminal backgrounds  
- **Minimal** - No colors, just bold/dim text

You can also set the default theme via environment variable:
```bash
export EC2SENSOR_THEME=light
```

## Architecture

```
ec2sensor-go/
├── main.go           # Application entry point and Bubble Tea model
├── config/
│   └── config.go     # Environment configuration
├── models/
│   └── sensor.go     # Sensor data structures
├── api/
│   └── client.go     # EC2 Sensor API client
├── ssh/
│   └── client.go     # SSH client for metrics collection
└── ui/
    ├── styles.go     # Lip Gloss styles and themes
    └── components.go # Reusable UI components
```

### Key Technologies

- **[Bubble Tea](https://github.com/charmbracelet/bubbletea)** - The Elm Architecture for Go TUIs
- **[Lip Gloss](https://github.com/charmbracelet/lipgloss)** - Declarative styling for terminal UIs
- **[Bubbles](https://github.com/charmbracelet/bubbles)** - Common TUI components (spinner, etc.)

## Comparison with Bash Version

| Feature | Bash | Go |
|---------|------|----|
| Startup time | ~1-2s | <100ms |
| Distribution | Requires bash | Single binary |
| Async operations | Background jobs | Goroutines |
| Live updates | Manual refresh | Auto-refresh |
| Memory usage | Spawns processes | ~10MB |
| Cross-platform | macOS/Linux | All platforms |
| Code maintenance | Complex | Clean/typed |

## Troubleshooting

### "Configuration error" on startup
Make sure you have a `.env` file with the required variables:
- `EC2_SENSOR_BASE_URL`
- `EC2_SENSOR_API_KEY`

### SSH connection failures
1. Check that the sensor IP is correct and reachable
2. Verify SSH credentials (keys or password)
3. Ensure `sshpass` is installed if using password authentication

### Metrics showing "-"
- The sensor may not be in "running" state
- SSH connection may have failed
- Try pressing `r` to refresh

## License

MIT
