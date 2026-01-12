#!/bin/bash

# Compare previous sensor with current one
# Usage: ./compare_sensors.sh

PREVIOUS_SENSOR_IP="10.50.88.24"
CURRENT_SENSOR_IP="10.50.88.100"

echo "=== Testing network connectivity differences ==="
echo

echo "Testing previous sensor (that worked):"
echo "Ping: $PREVIOUS_SENSOR_IP"
ping -c 1 $PREVIOUS_SENSOR_IP
echo

echo "Testing current sensor:"
echo "Ping: $CURRENT_SENSOR_IP"
ping -c 1 $CURRENT_SENSOR_IP
echo

echo "=== Testing for SSH accessibility ==="
echo

echo "Testing SSH port on previous sensor:"
nc -zv $PREVIOUS_SENSOR_IP 22 -G 5
echo

echo "Testing SSH port on current sensor:"
nc -zv $CURRENT_SENSOR_IP 22 -G 5
echo

echo "=== Testing for HTTPS accessibility ==="
echo

echo "Testing HTTPS port on previous sensor:"
nc -zv $PREVIOUS_SENSOR_IP 443 -G 5
echo

echo "Testing HTTPS port on current sensor:"
nc -zv $CURRENT_SENSOR_IP 443 -G 5
echo

echo "=== Recommendations based on results ==="
echo
echo "If the previous sensor responds to SSH but the current one doesn't:"
echo "1. The new sensor may have a different security group configuration"
echo "2. The SSH service may not be running on the new sensor"
echo "3. Try waiting longer for the new sensor to complete initialization"
echo
echo "If both sensors behave the same way:"
echo "1. There may be a network/routing/VPN issue affecting both sensors"
echo "2. Tailscale may need to be reconfigured or restarted"
