#!/bin/bash

# Unified Sensor Diagnostics Tool
# Consolidates diagnostic functionality into a single tool with subcommands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load_env.sh"

# Default values
SENSOR_IP="${SSH_HOST:-}"
SENSOR_USER="${SSH_USERNAME:-broala}"
SENSOR_PASS="${SSH_PASSWORD:-}"

show_help() {
    echo "Sensor Diagnostics Tool"
    echo "======================="
    echo ""
    echo "Usage: $0 <command> [sensor_ip]"
    echo ""
    echo "Commands:"
    echo "  metrics [ip]      - Check sensor metrics and data collection"
    echo "  processes [ip]    - Show top processes by CPU and memory"
    echo "  performance [ip]  - Continuous performance monitoring (Ctrl+C to stop)"
    echo "  all [ip]          - Run all diagnostic checks"
    echo "  help              - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 metrics                    # Use sensor IP from .env"
    echo "  $0 processes 10.50.88.203     # Check specific sensor"
    echo "  $0 performance                # Monitor current sensor"
    echo "  $0 all                        # Run all diagnostics"
    echo ""
    echo "Note: If sensor_ip is not provided, uses SSH_HOST from .env"
}

check_sensor_ip() {
    local ip="$1"
    if [ -z "$ip" ]; then
        if [ -z "$SENSOR_IP" ]; then
            echo "Error: No sensor IP provided and SSH_HOST not set in .env"
            echo "Usage: $0 <command> <sensor_ip>"
            echo "   or: Set SSH_HOST in .env file"
            exit 1
        fi
        echo "$SENSOR_IP"
    else
        echo "$ip"
    fi
}

check_metrics() {
    local ip=$(check_sensor_ip "$1")

    echo "=== Checking Metrics on Sensor: $ip ==="
    echo ""

    if ! command -v sshpass &> /dev/null; then
        echo "Error: sshpass not installed"
        echo "Install with: brew install hudochenkov/sshpass/sshpass"
        exit 1
    fi

    SSHPASS="$SENSOR_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$SENSOR_USER@$ip" << 'EOF'

echo "=== Sensor Version ==="
sudo corelightctl sensor status 2>&1 | grep -E "OSVersion|Platform"

echo ""
echo "=== Sensor Status ==="
sudo corelightctl sensor status 2>&1 | grep -A 20 "Services:"

echo ""
echo "=== Metrics: corelight-client ==="
sudo corelight-client -b https://localhost --ssl-no-verify-certificate --ssl-no-verify-hostname -u admin -p admin metrics current 2>&1 | grep -E "link|bytes" | head -20

echo ""
echo "=== Metrics: Direct API ==="
curl -k -u admin:admin https://localhost/api/v1/metrics 2>&1 | head -20

echo ""
echo "=== Metrics: Prometheus Endpoint ==="
curl -s http://localhost:9090/metrics 2>&1 | grep -i "link\|bytes" | head -10

echo ""
echo "=== Zeek/Bro Data ==="
if [ -d /data/bro ]; then
    echo "Bro directory exists"
    ls -lh /data/bro/ | head -10
else
    echo "No /data/bro directory found"
fi

echo ""
echo "=== Metrics Files ==="
find /var/corelight /data -name "*metrics*" -type f 2>/dev/null | head -10

EOF

    echo ""
    echo "=== Diagnostic Complete for $ip ==="
}

check_processes() {
    local ip=$(check_sensor_ip "$1")

    echo "=== Process Monitor: $ip ==="
    echo "Time: $(date)"
    echo ""

    SSHPASS="$SENSOR_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$SENSOR_USER@$ip" << 'EOF'

echo "Top 10 Processes by CPU Usage:"
echo "----------------------------"
ps aux --sort=-%cpu | head -11

echo ""
echo "Top 10 Processes by Memory Usage:"
echo "----------------------------"
ps aux --sort=-%mem | head -11

echo ""
echo "System Load:"
echo "------------"
uptime

echo ""
echo "Memory Usage:"
echo "-------------"
free -h

echo ""
echo "Disk Usage:"
echo "-----------"
df -h /

echo ""
echo "Network Interface Status:"
echo "------------------------"
ip -s link show eth0 2>/dev/null || ifconfig eth0 | grep -E "RX packets|TX packets"

EOF
}

monitor_performance() {
    local ip=$(check_sensor_ip "$1")

    echo "=== Performance Monitor: $ip ==="
    echo "Press Ctrl+C to stop monitoring"
    echo ""

    while true; do
        clear
        echo "=== EC2 Sensor Performance Monitor ==="
        echo "Sensor: $ip"
        echo "Time: $(date)"
        echo ""

        SSHPASS="$SENSOR_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$SENSOR_USER@$ip" << 'EOF'
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}'
echo ""

echo "Memory Usage:"
free -m | awk 'NR==2{printf "Used: %sMB (%.2f%%)\n", $3,$3*100/$2 }'
echo ""

echo "Network Interface Stats (eth0):"
ip -s link show eth0 2>/dev/null | grep -A 1 "RX:" | grep -v "RX:" || ifconfig eth0 | grep "RX packets"
ip -s link show eth0 2>/dev/null | grep -A 1 "TX:" | grep -v "TX:" || ifconfig eth0 | grep "TX packets"
echo ""

echo "Top 5 Processes:"
ps aux --sort=-%cpu | head -6
EOF

        sleep 3
    done
}

run_all_diagnostics() {
    local ip=$(check_sensor_ip "$1")

    echo "========================================"
    echo "Running All Diagnostics for: $ip"
    echo "========================================"
    echo ""

    echo "1/2: Checking Metrics..."
    check_metrics "$ip"
    echo ""
    echo ""

    echo "2/2: Checking Processes..."
    check_processes "$ip"
    echo ""

    echo "========================================"
    echo "All Diagnostics Complete"
    echo "========================================"
}

# Main command dispatcher
case "$1" in
    metrics)
        check_metrics "$2"
        ;;
    processes)
        check_processes "$2"
        ;;
    performance)
        monitor_performance "$2"
        ;;
    all)
        run_all_diagnostics "$2"
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
