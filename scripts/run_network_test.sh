#!/bin/bash

# Network Performance Test Script
# Runs on the EC2 sensor to test network performance
# This script is executed remotely via SSH by sensor_lifecycle.sh

echo "EC2 Sensor Network Performance Test"
echo "=================================="
echo "Running on $(hostname) at $(date)"
echo ""

# Ensure we have necessary permissions
if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges."
    echo "Attempting to run with sudo..."
    exec sudo "$0" "$@"
    exit $?
fi

# Check required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: $1 not found. Installing..."
        if command -v yum &> /dev/null; then
            yum install -y "$1"
        elif command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "$1"
        else
            echo "Error: Cannot install $1. Please install manually."
            return 1
        fi
    fi
    return 0
}

# Check for required tools
check_tool tcpreplay || exit 1
check_tool ethtool || exit 1

# Identify network interfaces
echo "Network Interfaces:"
echo "-----------------"
ip -br link show
echo ""

# Select the monitoring interface (eth1 is typically the Zeek monitoring interface)
MONITOR_INTERFACE="eth1"
echo "Using $MONITOR_INTERFACE as the monitoring interface"
echo ""

# Record initial NIC counters
echo "Initial NIC Counters:"
echo "------------------"
ethtool -S "$MONITOR_INTERFACE" | grep -iE "drop|error|timeout|miss"
echo ""

# Record initial system stats
echo "Initial System Stats:"
echo "-----------------"
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}'
echo ""
echo "Memory Usage:"
free -m | awk 'NR==2{printf "Used: %sMB (%.2f%%)\n", $3,$3*100/$2 }'
echo ""

# Check if PCAP file exists or create a test one
TEST_PCAP="/tmp/test.pcap"
if [ ! -f "$TEST_PCAP" ]; then
    echo "Test PCAP file not found, checking for existing PCAPs..."
    EXISTING_PCAP=$(find /home -name "*.pcap" -type f -size +100k 2>/dev/null | head -1)
    
    if [ -n "$EXISTING_PCAP" ]; then
        echo "Using existing PCAP file: $EXISTING_PCAP"
        TEST_PCAP="$EXISTING_PCAP"
    else
        echo "No existing PCAP files found."
        echo "Creating simple test PCAP using tcpreplay..."
        # This would normally create a PCAP but we'll skip actual creation
        # as it requires more complex tools
        echo "WARNING: No PCAP file available for testing."
        echo "Please transfer a PCAP file to the sensor before running this test."
        exit 1
    fi
fi

# Run the performance test
echo ""
echo "Starting Network Performance Test"
echo "==============================="
echo "Test will flood $MONITOR_INTERFACE with traffic from $TEST_PCAP"
echo ""

# Start monitoring in background
echo "Starting performance monitoring..."
(
    for i in {1..10}; do
        echo "--- Monitor Iteration $i ---"
        echo "Time: $(date)"
        echo "NIC Counters:"
        ethtool -S "$MONITOR_INTERFACE" | grep -iE "drop|error|timeout|miss"
        echo "System Load:"
        uptime
        echo ""
        sleep 3
    done
) > /tmp/monitor_output.log &
MONITOR_PID=$!

# Run tcpreplay
echo "Running tcpreplay (this will take a few seconds)..."
tcpreplay --mbps=100 --loop=1000 -i "$MONITOR_INTERFACE" "$TEST_PCAP" &
TCPREPLAY_PID=$!

# Let it run for 30 seconds
echo "Test running for 30 seconds..."
sleep 30

# Stop tcpreplay
echo "Stopping tcpreplay..."
kill -TERM $TCPREPLAY_PID 2>/dev/null
wait $TCPREPLAY_PID 2>/dev/null

# Stop monitoring
echo "Stopping monitoring..."
kill -TERM $MONITOR_PID 2>/dev/null
wait $MONITOR_PID 2>/dev/null

# Record final NIC counters
echo ""
echo "Final NIC Counters:"
echo "----------------"
ethtool -S "$MONITOR_INTERFACE" | grep -iE "drop|error|timeout|miss"
echo ""

# Check for kernel error messages
echo "Kernel Error Messages:"
echo "------------------"
dmesg | grep -iE 'drop|error|timeout|reset' | tail -10
echo ""

# Display monitoring results
echo "Monitoring Results:"
echo "----------------"
cat /tmp/monitor_output.log
echo ""

# Provide analysis of results
echo "Test Analysis:"
echo "-----------"
echo "Test completed successfully."
echo "Review the NIC counter values above to check for packet drops."
echo "Look for increases in rx_errors, rx_dropped, rx_crc_errors, etc."
echo ""
echo "Complete detailed monitoring data is available in /tmp/monitor_output.log"
echo ""

echo "Network Performance Test Completed"
echo "================================"
