package ssh

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/quanticsoul4772/ec2sensor-go/config"
	"github.com/quanticsoul4772/ec2sensor-go/models"
)

// Client handles SSH connections for metrics collection
type Client struct {
	username string
	password string
	useKeys  bool
	timeout  time.Duration
}

// NewClient creates a new SSH client
func NewClient(cfg *config.Config) *Client {
	return &Client{
		username: cfg.SSHUsername,
		password: cfg.SSHPassword,
		useKeys:  cfg.SSHUseKeys,
		timeout:  30 * time.Second, // Increased timeout for upgrade operations
	}
}

// CollectMetrics gathers resource metrics from a sensor via SSH
func (c *Client) CollectMetrics(ip string) (*models.SensorMetrics, error) {
	// Build the remote command for collecting metrics
	remoteCmd := `cpu=$(awk "/^cpu / {printf \"%.0f\", (\$2+\$4)*100/(\$2+\$4+\$5)}" /proc/stat 2>/dev/null || echo "0"); \
        mem=$(free 2>/dev/null | awk "/Mem:/ {printf \"%.0f\", \$3/\$2*100}" || echo "0"); \
        disk=$(df / 2>/dev/null | awk "NR==2 {gsub(/%/,\"\"); print \$5}" || echo "0"); \
        pods=$(sudo corelightctl sensor status 2>/dev/null | grep -c "Ok" || sudo kubectl get pods --all-namespaces 2>/dev/null | grep -c Running || echo "0"); \
        echo "${cpu}|${mem}|${disk}|${pods}"`

	output, err := c.runCommand(ip, remoteCmd)
	if err != nil {
		return nil, err
	}

	return parseMetrics(strings.TrimSpace(output))
}

// GetUptime retrieves the system uptime from a sensor
func (c *Client) GetUptime(ip string) (string, error) {
	output, err := c.runCommand(ip, "uptime -p 2>/dev/null || uptime | awk '{print $3,$4}'")
	if err != nil {
		return "unknown", err
	}
	return strings.TrimSpace(output), nil
}

// GetServiceStatus retrieves the status of services on a sensor
func (c *Client) GetServiceStatus(ip string) ([]ServiceStatus, error) {
	output, err := c.runCommand(ip, "sudo corelightctl sensor status 2>/dev/null | grep -E '^[a-z]' | head -15")
	if err != nil {
		return nil, err
	}

	var services []ServiceStatus
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			services = append(services, ServiceStatus{
				Name:   parts[0],
				Status: parts[1],
			})
		}
	}
	return services, nil
}

// ServiceStatus represents a service and its current state
type ServiceStatus struct {
	Name   string
	Status string
}

// TestConnection checks if SSH connection is possible
func (c *Client) TestConnection(ip string) bool {
	_, err := c.runCommand(ip, "echo ok")
	return err == nil
}

// GetAdminPassword retrieves the admin password from the sensor's corelightctl.yaml
func (c *Client) GetAdminPassword(ip string) (string, error) {
	// Try getting password from api section first
	output, err := c.runCommand(ip, "sudo grep -A5 'api:' /etc/corelight/corelightctl.yaml 2>/dev/null | grep password | awk '{print $2}'")
	if err == nil && strings.TrimSpace(output) != "" {
		return strings.TrimSpace(output), nil
	}

	// Fallback to old method
	output, err = c.runCommand(ip, "sudo grep 'password:' /etc/corelight/corelightctl.yaml 2>/dev/null | awk '{print $2}'")
	if err == nil && strings.TrimSpace(output) != "" {
		return strings.TrimSpace(output), nil
	}

	return "", fmt.Errorf("could not retrieve admin password")
}

// GetSensorVersion retrieves the current sensor version
func (c *Client) GetSensorVersion(ip, adminPassword string) (string, error) {
	// Try corelight-client first
	cmd := fmt.Sprintf("corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p %s information get 2>&1 | grep -i version | head -1 | awk '{print $NF}'", adminPassword)
	output, err := c.runCommand(ip, cmd)
	if err == nil && strings.TrimSpace(output) != "" && strings.TrimSpace(output) != "unknown" {
		return strings.TrimSpace(output), nil
	}

	// Fallback to corelightctl version
	output, err = c.runCommand(ip, "sudo corelightctl version 2>/dev/null | jq -r '.version // \"unknown\"'")
	if err == nil && strings.TrimSpace(output) != "" {
		return strings.TrimSpace(output), nil
	}

	return "unknown", fmt.Errorf("could not get sensor version")
}

// GetReleaseChannel retrieves the release channel from sensor config
func (c *Client) GetReleaseChannel(ip string) (string, error) {
	output, err := c.runCommand(ip, "sudo grep 'release_channel:' /etc/corelight/corelightctl.yaml 2>/dev/null | awk '{print $2}'")
	if err != nil {
		return "testing", err
	}
	channel := strings.TrimSpace(output)
	if channel == "" {
		return "testing", nil
	}
	return channel, nil
}

// GetAvailableUpdates retrieves available updates via corelight-client
func (c *Client) GetAvailableUpdates(ip, adminPassword string) ([]string, error) {
	// Fix corelight-client cache permissions first
	c.runCommand(ip, "mkdir -p ~/.corelight-client && sudo chown -R $(whoami) ~/.corelight-client 2>/dev/null")

	cmd := fmt.Sprintf("corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p %s updates list 2>&1", adminPassword)
	output, err := c.runCommand(ip, cmd)
	if err != nil {
		return nil, err
	}

	// Check for "No entries" response
	if strings.Contains(output, "No entries") {
		return []string{}, nil
	}

	// Parse version lines
	var versions []string
	for _, line := range strings.Split(output, "\n") {
		if strings.Contains(line, "version") {
			versions = append(versions, strings.TrimSpace(line))
		}
	}

	return versions, nil
}

// RunUpgradeLatest runs the upgrade to latest using corelight-client updates apply
func (c *Client) RunUpgradeLatest(ip, adminPassword string) error {
	cmd := fmt.Sprintf("corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p %s updates apply 2>&1", adminPassword)
	output, err := c.runCommand(ip, cmd)
	if err != nil {
		return fmt.Errorf("upgrade command failed: %v", err)
	}

	// Check for success in output
	if !strings.Contains(output, "success") && !strings.Contains(output, "True") {
		return fmt.Errorf("upgrade may have failed: %s", output)
	}

	return nil
}

// RunUpgradeSpecific runs the upgrade to a specific version using broala-update-repository
func (c *Client) RunUpgradeSpecific(ip, repo, version string) error {
	if version == "" {
		return fmt.Errorf("no target version specified")
	}

	cmd := fmt.Sprintf("sudo broala-update-repository -r %s -R -U %s 2>&1", repo, version)
	_, err := c.runCommand(ip, cmd)
	return err
}

// IsUpgradeProcessRunning checks if upgrade processes are still running
func (c *Client) IsUpgradeProcessRunning(ip string) bool {
	// Check for dpkg, apt, update scripts, broala-update processes
	output, err := c.runCommand(ip, "pgrep -f 'dpkg|apt|update-system|corelight.*update|broala-update' 2>/dev/null | head -1")
	if err == nil && strings.TrimSpace(output) != "" {
		return true
	}

	// Also check active update count
	output, err = c.runCommand(ip, "ps aux 2>/dev/null | grep -E 'dpkg|apt-get|update|upgrade|broala' | grep -v grep | wc -l")
	if err == nil {
		count := strings.TrimSpace(output)
		if count != "" && count != "0" {
			return true
		}
	}

	return false
}

// GetUpgradeLogLines retrieves the last N lines from upgrade-related log files
// Returns a map of log file names to their recent lines
func (c *Client) GetUpgradeLogLines(ip string, numLines int) (map[string][]string, error) {
	logs := make(map[string][]string)

	// List of log files to check for upgrade progress
	logFiles := []struct {
		name string
		path string
	}{
		{"dpkg", "/var/log/dpkg.log"},
		{"apt-term", "/var/log/apt/term.log"},
		{"apt-history", "/var/log/apt/history.log"},
		{"syslog", "/var/log/syslog"},
	}

	for _, lf := range logFiles {
		cmd := fmt.Sprintf("sudo tail -n %d %s 2>/dev/null || tail -n %d %s 2>/dev/null || echo ''", 
			numLines, lf.path, numLines, lf.path)
		output, err := c.runCommand(ip, cmd)
		if err == nil && strings.TrimSpace(output) != "" {
			lines := strings.Split(strings.TrimSpace(output), "\n")
			if len(lines) > 0 && lines[0] != "" {
				logs[lf.name] = lines
			}
		}
	}

	return logs, nil
}

// GetUpgradeStatus returns a detailed status of the upgrade process
type UpgradeStatus struct {
	SSHAvailable    bool
	ProcessRunning  bool
	CurrentPhase    string
	RecentLogs      []string
	CurrentVersion  string
	DpkgLocked      bool
	RebootDetected  bool
}

// CheckUpgradeStatus performs a comprehensive check of upgrade progress
func (c *Client) CheckUpgradeStatus(ip, adminPassword string) (*UpgradeStatus, error) {
	status := &UpgradeStatus{}

	// Test SSH connectivity first
	_, err := c.runCommand(ip, "echo ok")
	if err != nil {
		status.SSHAvailable = false
		status.CurrentPhase = "Sensor rebooting or SSH unavailable"
		status.RebootDetected = true
		return status, nil
	}
	status.SSHAvailable = true

	// Check for dpkg lock (indicates package operations in progress)
	lockOutput, _ := c.runCommand(ip, "sudo lsof /var/lib/dpkg/lock-frontend 2>/dev/null | wc -l")
	if strings.TrimSpace(lockOutput) != "" && strings.TrimSpace(lockOutput) != "0" {
		status.DpkgLocked = true
	}

	// Check if upgrade processes are running
	status.ProcessRunning = c.IsUpgradeProcessRunning(ip)

	// Determine current phase based on running processes
	phaseOutput, _ := c.runCommand(ip, `ps aux 2>/dev/null | grep -E 'dpkg|apt|broala-update|corelight' | grep -v grep | head -3 | awk '{print $11, $12, $13}' | tr '\n' '; '`)
	if strings.TrimSpace(phaseOutput) != "" {
		status.CurrentPhase = strings.TrimSpace(phaseOutput)
	} else if status.DpkgLocked {
		status.CurrentPhase = "Package operations in progress (dpkg locked)"
	} else if status.ProcessRunning {
		status.CurrentPhase = "Upgrade processes running"
	} else {
		status.CurrentPhase = "Verifying completion"
	}

	// Get recent log entries (combined from dpkg and apt)
	var recentLogs []string
	
	// Get last 5 dpkg log entries
	dpkgOutput, _ := c.runCommand(ip, "sudo tail -n 5 /var/log/dpkg.log 2>/dev/null | grep -E 'status|install|configure' | tail -3")
	if strings.TrimSpace(dpkgOutput) != "" {
		for _, line := range strings.Split(dpkgOutput, "\n") {
			if trimmed := strings.TrimSpace(line); trimmed != "" {
				// Extract just the relevant part (package name and status)
				parts := strings.Fields(trimmed)
				if len(parts) >= 4 {
					recentLogs = append(recentLogs, fmt.Sprintf("[dpkg] %s %s", parts[2], parts[3]))
				}
			}
		}
	}

	// Get last apt activity
	aptOutput, _ := c.runCommand(ip, "sudo tail -n 10 /var/log/apt/term.log 2>/dev/null | grep -E 'Setting up|Unpacking|Processing' | tail -3")
	if strings.TrimSpace(aptOutput) != "" {
		for _, line := range strings.Split(aptOutput, "\n") {
			if trimmed := strings.TrimSpace(line); trimmed != "" {
				if len(trimmed) > 60 {
					trimmed = trimmed[:60] + "..."
				}
				recentLogs = append(recentLogs, fmt.Sprintf("[apt] %s", trimmed))
			}
		}
	}

	status.RecentLogs = recentLogs

	// Try to get current version if upgrade seems complete
	if !status.ProcessRunning && !status.DpkgLocked {
		version, err := c.GetSensorVersion(ip, adminPassword)
		if err == nil {
			status.CurrentVersion = version
		}
	}

	return status, nil
}

// EnableFeatures runs the enable_sensor_features commands on the sensor
func (c *Client) EnableFeatures(ip string) (string, error) {
	// This is a simplified version - the full script does more
	// We run the key commands directly
	commands := `set +u
set -e
echo "Enabling sensor features and licenses..."
for cmd in \
    "sudo /opt/broala/bin/broala-config set http.access.enable=1" \
    "sudo /opt/broala/bin/broala-config set license.yara.enable=1" \
    "sudo /opt/broala/bin/broala-config set license.suricata.enable=1" \
    "sudo /opt/broala/bin/broala-config set license.smartpcap.enable=1" \
    "sudo /opt/broala/bin/broala-config set corelight.yara.enable=1" \
    "sudo /opt/broala/bin/broala-config set suricata.enable=1" \
    "sudo /opt/broala/bin/broala-config set smartpcap.enable=1"; do
    echo "Running: $cmd"
    if ! eval "$cmd"; then
        echo "Failed: $cmd" >&2
        exit 1
    fi
done
echo "Applying configuration..."

# Get admin password for corelight-client authentication
ADMIN_PASSWORD=$(sudo grep "password:" /etc/corelight/corelightctl.yaml | awk "{print \$2}")
if [ -z "$ADMIN_PASSWORD" ]; then
    echo "Warning: Could not read admin password, skipping apply-config" >&2
    echo "Features configured (restart sensor to apply)"
    exit 0
fi

# Apply config with wrapper for SSL bypass
WRAPPER_DIR="/tmp/corelight-wrapper-$$"
mkdir -p "$WRAPPER_DIR"
cat > "$WRAPPER_DIR/corelight-client" << 'WRAPPER'
#!/bin/bash
ARGS=()
for arg in "$@"; do
    if [[ "$arg" != --dynamic_backfill* ]]; then
        ARGS+=("$arg")
    fi
done
WRAPPER
echo "exec /usr/bin/corelight-client --ssl-no-verify-certificate -u admin -p $ADMIN_PASSWORD \"\${ARGS[@]}\"" >> "$WRAPPER_DIR/corelight-client"
chmod +x "$WRAPPER_DIR/corelight-client"
export PATH="$WRAPPER_DIR:$PATH"

if sudo -E LC_ALL=en_US.utf8 LANG=en_US.utf8 PATH="$PATH" /opt/broala/bin/broala-apply-config -q 2>&1; then
    rm -rf "$WRAPPER_DIR" 2>/dev/null
    echo "Features enabled successfully"
else
    rm -rf "$WRAPPER_DIR" 2>/dev/null
    echo "Warning: broala-apply-config had issues, features may still be enabled"
fi`

	return c.runCommand(ip, commands)
}

// AddToFleetManager runs the fleet manager registration script
func (c *Client) AddToFleetManager(ip string) (string, error) {
	// Run the prepare_p1_automation equivalent commands
	// This is simplified - the full script does more setup
	commands := `echo "Adding sensor to fleet manager..."
FLEET_IP="192.168.22.239"
FLEET_PORT="4443"

# Get admin password
ADMIN_PASSWORD=$(sudo grep "password:" /etc/corelight/corelightctl.yaml | awk "{print \$2}")
if [ -z "$ADMIN_PASSWORD" ]; then
    echo "Error: Could not read admin password" >&2
    exit 1
fi

# Configure fleet manager connection
echo "Configuring fleet manager connection to $FLEET_IP:$FLEET_PORT..."
sudo corelight-client -b 192.0.2.1:30443 --ssl-no-verify-certificate -u admin -p "$ADMIN_PASSWORD" \
    fleet-manager set --address "$FLEET_IP" --port "$FLEET_PORT" --enabled true 2>&1 || true

echo "Fleet manager configuration complete"
echo "Sensor should now appear in fleet manager at https://$FLEET_IP"`

	return c.runCommand(ip, commands)
}

// ConfigureTrafficGenerator sets up the sensor as a traffic generator
func (c *Client) ConfigureTrafficGenerator(ip string) error {
	commands := `echo "Configuring traffic generator..."
# Create simple traffic generator script
cat > /tmp/simple_traffic_generator.py << 'SCRIPT'
#!/usr/bin/env python3
import socket
import time
import argparse
import random
import string

def generate_payload(size=100):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=size)).encode()

def main():
    parser = argparse.ArgumentParser(description='Simple traffic generator')
    parser.add_argument('-t', '--target', required=True, help='Target IP')
    parser.add_argument('-p', '--port', type=int, default=5555, help='Target port')
    parser.add_argument('--protocol', default='udp', choices=['udp', 'tcp'], help='Protocol')
    parser.add_argument('-r', '--rate', type=int, default=1000, help='Packets per second')
    parser.add_argument('-D', '--duration', type=int, default=60, help='Duration in seconds')
    args = parser.parse_args()
    
    print(f"Starting {args.protocol.upper()} traffic to {args.target}:{args.port}")
    print(f"Rate: {args.rate} pps, Duration: {args.duration}s")
    
    if args.protocol == 'udp':
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    else:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((args.target, args.port))
    
    start = time.time()
    count = 0
    interval = 1.0 / args.rate
    
    while time.time() - start < args.duration:
        payload = generate_payload()
        try:
            if args.protocol == 'udp':
                sock.sendto(payload, (args.target, args.port))
            else:
                sock.send(payload)
            count += 1
        except Exception as e:
            print(f"Error: {e}")
            break
        time.sleep(interval)
    
    print(f"Sent {count} packets in {time.time() - start:.1f}s")
    sock.close()

if __name__ == '__main__':
    main()
SCRIPT
chmod +x /tmp/simple_traffic_generator.py
echo "Traffic generator installed at /tmp/simple_traffic_generator.py"`

	_, err := c.runCommand(ip, commands)
	return err
}

// StartTrafficGeneration starts the traffic generator in background
func (c *Client) StartTrafficGeneration(ip, targetIP, targetPort, protocol, pps, duration string) error {
	if duration == "0" {
		duration = "999999" // Continuous
	}
	cmd := fmt.Sprintf("cd /tmp && nohup python3 simple_traffic_generator.py -t %s -p %s --protocol %s -r %s -D %s > /tmp/traffic.log 2>&1 &",
		targetIP, targetPort, protocol, pps, duration)
	_, err := c.runCommand(ip, cmd)
	return err
}

// StopTrafficGeneration stops any running traffic generation
func (c *Client) StopTrafficGeneration(ip string) error {
	_, err := c.runCommand(ip, "sudo pkill -f simple_traffic_generator.py 2>/dev/null || true")
	return err
}

// GetTrafficStatus checks if traffic generation is running
func (c *Client) GetTrafficStatus(ip string) (string, error) {
	output, err := c.runCommand(ip, "ps aux | grep simple_traffic_generator | grep -v grep | head -1")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(output), nil
}

// runCommand executes a command on a remote host via SSH
func (c *Client) runCommand(ip, command string) (string, error) {
	var cmd *exec.Cmd

	sshArgs := []string{
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", fmt.Sprintf("ConnectTimeout=%d", int(c.timeout.Seconds())),
		"-o", "BatchMode=yes",
		fmt.Sprintf("%s@%s", c.username, ip),
		command,
	}

	if c.useKeys {
		cmd = exec.Command("ssh", sshArgs...)
	} else if c.password != "" {
		// Use sshpass for password authentication
		sshpassArgs := append([]string{"-e", "ssh"}, sshArgs...)
		cmd = exec.Command("sshpass", sshpassArgs...)
		// Inherit parent environment and add SSHPASS
		cmd.Env = append(os.Environ(), fmt.Sprintf("SSHPASS=%s", c.password))
	} else {
		// Try without password (will prompt or fail)
		cmd = exec.Command("ssh", sshArgs...)
	}

	output, err := cmd.Output()
	if err != nil {
		return "", err
	}

	return string(output), nil
}

// parseMetrics parses the pipe-separated metrics string
func parseMetrics(output string) (*models.SensorMetrics, error) {
	parts := strings.Split(output, "|")
	if len(parts) != 4 {
		return nil, fmt.Errorf("invalid metrics format: %s", output)
	}

	cpu, _ := strconv.Atoi(parts[0])
	mem, _ := strconv.Atoi(parts[1])
	disk, _ := strconv.Atoi(parts[2])
	pods, _ := strconv.Atoi(parts[3])

	return &models.SensorMetrics{
		CPU:    cpu,
		Memory: mem,
		Disk:   disk,
		Pods:   pods,
	}, nil
}
