#!/bin/bash

# Unified TCP Replay Tool
# Consolidates tcpreplay installation, setup, and replay functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load_env.sh"

# Default values
SENSOR_IP="${SSH_HOST:-}"
SENSOR_USER="${SSH_USERNAME:-broala}"
SENSOR_PASS="${SSH_PASSWORD:-}"
INTERFACE="${REPLAY_INTERFACE:-eth1}"

show_help() {
    echo "TCP Replay Tool"
    echo "==============="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  install [ip]              - Install tcpreplay on sensor"
    echo "  setup [ip]                - Discover pcaps, interfaces, and tools"
    echo "  start <speed> <pcap> [ip] - Start replay at specified Mbps"
    echo "  help                      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install                          # Install on sensor from .env"
    echo "  $0 setup 10.50.88.203               # Discover on specific sensor"
    echo "  $0 start 50 test.pcap               # Replay at 50 Mbps"
    echo "  $0 start 100 /path/to/file.pcap     # Replay at 100 Mbps"
    echo ""
    echo "Environment:"
    echo "  SSH_HOST          - Sensor IP (from .env)"
    echo "  SSH_USERNAME      - SSH username (default: broala)"
    echo "  SSH_PASSWORD      - SSH password (from .env)"
    echo "  REPLAY_INTERFACE  - Network interface (default: eth1)"
}

check_sensor_ip() {
    local ip="$1"
    if [ -z "$ip" ]; then
        if [ -z "$SENSOR_IP" ]; then
            echo "Error: No sensor IP provided and SSH_HOST not set in .env"
            echo "Usage: $0 <command> <sensor_ip>"
            exit 1
        fi
        echo "$SENSOR_IP"
    else
        echo "$ip"
    fi
}

install_tcpreplay() {
    local ip=$(check_sensor_ip "$1")

    echo "=== Installing tcpreplay on sensor: $ip ==="
    echo ""

    if ! command -v sshpass &> /dev/null; then
        echo "Error: sshpass not installed"
        echo "Install with: brew install hudochenkov/sshpass/sshpass"
        exit 1
    fi

    SSHPASS="$SENSOR_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new "$SENSOR_USER@$ip" << 'EOF'
echo "Installing tcpreplay..."

# First, enable EPEL repository if not already enabled
if ! yum repolist | grep -q "epel"; then
    echo "Enabling EPEL repository..."
    sudo yum install -y epel-release
fi

# Install tcpreplay using yum from EPEL repository
echo "Installing tcpreplay from EPEL repository..."
if ! sudo yum install -y tcpreplay; then
    echo "Error: Failed to install tcpreplay"
    echo "Trying alternative method..."

    # Alternative method: direct download from EPEL mirror
    echo "Downloading tcpreplay directly from EPEL mirror..."
    wget https://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/t/tcpreplay-4.3.4-1.el7.x86_64.rpm

    if [ $? -eq 0 ]; then
        sudo rpm -i tcpreplay-4.3.4-1.el7.x86_64.rpm
        rm -f tcpreplay-4.3.4-1.el7.x86_64.rpm
    else
        echo "Error: Failed to download tcpreplay package"
        exit 1
    fi
fi

# Verify installation
if command -v tcpreplay &> /dev/null; then
    echo ""
    echo "✓ tcpreplay installed successfully"
    tcpreplay --version
else
    echo "✗ Installation failed"
    exit 1
fi
EOF

    echo ""
    echo "=== Installation complete ==="
}

setup_discovery() {
    local ip=$(check_sensor_ip "$1")

    echo "=== TCP Replay Setup and Discovery: $ip ==="
    echo ""

    SSHPASS="$SENSOR_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new "$SENSOR_USER@$ip" << 'EOF'
echo "1. Looking for TCP replay tools..."
if command -v tcpreplay &> /dev/null; then
    echo "✓ tcpreplay found at: $(which tcpreplay)"
    tcpreplay --version
else
    echo "✗ tcpreplay not found. Run 'tcpreplay.sh install' first"
fi

echo ""
echo "2. Checking for pcap files..."
echo "Searching /home..."
find /home -name "*.pcap" -type f 2>/dev/null | head -10
echo "Searching /opt..."
find /opt -name "*.pcap" -type f 2>/dev/null | head -10
echo "Searching /data..."
find /data -name "*.pcap" -type f 2>/dev/null | head -5

echo ""
echo "3. Network interfaces available for replay..."
ip link show | grep -E "^[0-9]+: " | cut -d: -f2 | tr -d ' '

echo ""
echo "4. Network interface details..."
echo "eth0 (management):"
ip addr show eth0 2>/dev/null | grep "inet " || echo "  Not found"
echo "eth1 (monitoring):"
ip addr show eth1 2>/dev/null | grep "inet " || echo "  Not found"

echo ""
echo "5. Available traffic generation tools..."
which tcpreplay tcprewrite tcpprep tcpbridge tcpliveplay 2>/dev/null || echo "  None found"
which trex 2>/dev/null || echo "  TRex: not found"
which hping3 2>/dev/null || echo "  hping3: not found"

echo ""
echo "6. Package manager..."
if command -v yum &> /dev/null; then
    echo "✓ YUM package manager found"
elif command -v apt &> /dev/null; then
    echo "✓ APT package manager found"
else
    echo "✗ No standard package manager found"
fi

echo ""
echo "7. Corelight-specific tools..."
ls -la /opt/corelight* 2>/dev/null || echo "  No Corelight tools found in /opt"
find /usr/local/bin -name "*corelight*" 2>/dev/null | head -5
EOF

    echo ""
    echo "=== Discovery complete ==="
}

start_replay() {
    local speed="$1"
    local pcap_file="$2"
    local ip="$3"

    if [ -z "$speed" ] || [ -z "$pcap_file" ]; then
        echo "Error: Missing required arguments"
        echo "Usage: $0 start <speed_mbps> <pcap_file> [sensor_ip]"
        echo "Example: $0 start 50 test.pcap"
        exit 1
    fi

    ip=$(check_sensor_ip "$ip")

    echo "=== Starting TCP Replay ==="
    echo "Sensor: $ip"
    echo "Speed: ${speed} Mbps"
    echo "PCAP: ${pcap_file}"
    echo "Interface: ${INTERFACE}"
    echo ""

    # Check if pcap file exists locally
    if [ ! -f "$pcap_file" ]; then
        echo "Error: PCAP file '$pcap_file' not found locally"
        echo "If the file is already on the sensor, SSH in and run tcpreplay directly"
        exit 1
    fi

    echo "Copying PCAP file to sensor..."
    SSHPASS="$SENSOR_PASS" sshpass -e scp -o StrictHostKeyChecking=accept-new "$pcap_file" "$SENSOR_USER@$ip:/home/$SENSOR_USER/"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy PCAP file to sensor"
        exit 1
    fi

    local basename=$(basename "$pcap_file")
    echo "Starting replay..."
    echo "Press Ctrl+C to stop"
    echo "----------------------------------------"

    SSHPASS="$SENSOR_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new "$SENSOR_USER@$ip" << EOF
# Check if tcpreplay is installed
if ! command -v tcpreplay &> /dev/null; then
    echo "Error: tcpreplay is not installed on sensor"
    echo "Run './scripts/tcpreplay.sh install' first"
    exit 1
fi

# Start replay
echo "Running: sudo tcpreplay --mbps=${speed} --loop=0 --stats=3 -i ${INTERFACE} /home/$SENSOR_USER/${basename}"
sudo tcpreplay --mbps=${speed} --loop=0 --stats=3 -i ${INTERFACE} /home/$SENSOR_USER/${basename}
EOF

    echo ""
    echo "=== Replay complete ==="
}

# Main command dispatcher
case "$1" in
    install)
        install_tcpreplay "$2"
        ;;
    setup)
        setup_discovery "$2"
        ;;
    start)
        start_replay "$2" "$3" "$4"
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_help
        exit 1
        ;;
esac
