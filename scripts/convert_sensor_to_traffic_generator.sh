#!/bin/bash
# Convert EC2 Sensor to Traffic Generator
# Installs tools and configures sensor for traffic generation

set -euo pipefail

# Change to script directory
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# Source logging and environment
source "$PROJECT_ROOT/ec2sensor_logging.sh"
source "$PROJECT_ROOT/scripts/load_env.sh"

log_init "convert_traffic_generator"

# Parse arguments
SENSOR_IP="${1:-}"
MODE="${2:-simple}"  # simple, scapy, or trex

if [ -z "$SENSOR_IP" ]; then
    log_error "Usage: $0 <sensor_ip> [mode]"
    log_error "Modes: simple (default), scapy, trex"
    log_error "Example: $0 10.50.88.80 simple"
    exit 2
fi

log_info "Converting sensor $SENSOR_IP to traffic generator"
log_info "Mode: $MODE"

# SSH credentials
SSH_USERNAME="${SSH_USERNAME:-broala}"
SSH_PASSWORD="${SSH_PASSWORD:-${SSH_PASSWORD}}"

# Step 1: Check sensor connectivity
log_info "Checking sensor connectivity..."
if ! SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SENSOR_IP" "echo 'Connected'" >/dev/null 2>&1; then
    log_error "Cannot connect to sensor at $SENSOR_IP"
    exit 1
fi
log_info "Sensor is reachable"

# Step 2: Check sensor status
log_info "Checking sensor status..."
sensor_status=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SENSOR_IP" \
    "sudo corelightctl sensor status 2>/dev/null | grep -o 'Status:.*' | awk '{print \$2}' || echo 'unknown'")

log_info "Sensor status: $sensor_status"

if [ "$sensor_status" = "running" ]; then
    log_warning "Sensor services are running. For eth1 traffic generation, services must be stopped."
    log_info "You can stop services with: ssh $SSH_USERNAME@$SENSOR_IP sudo corelightctl sensor stop"
    log_info "Note: eth0 traffic generation works with services running."
fi

# Step 3: Install tools based on mode
log_info "Installing traffic generation tools..."

case "$MODE" in
    simple)
        log_info "Uploading simple socket-based traffic generator..."
        SSHPASS="$SSH_PASSWORD" sshpass -e scp -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "$PROJECT_ROOT/scripts/simple_traffic_generator.py" \
            "$SSH_USERNAME@$SENSOR_IP:/tmp/" || {
            log_error "Failed to upload simple traffic generator"
            exit 1
        }

        SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "$SSH_USERNAME@$SENSOR_IP" \
            "chmod +x /tmp/simple_traffic_generator.py"

        log_info "Simple traffic generator installed at /tmp/simple_traffic_generator.py"
        ;;

    scapy)
        log_info "Installing scapy..."
        SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "$SSH_USERNAME@$SENSOR_IP" \
            "sudo python3 -m pip install scapy 2>&1 | tail -5" || {
            log_error "Failed to install scapy"
            exit 1
        }

        log_info "Uploading scapy traffic generator..."
        SSHPASS="$SSH_PASSWORD" sshpass -e scp -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "$PROJECT_ROOT/scripts/scapy_traffic_generator.py" \
            "$SSH_USERNAME@$SENSOR_IP:/tmp/" || {
            log_error "Failed to upload scapy traffic generator"
            exit 1
        }

        SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "$SSH_USERNAME@$SENSOR_IP" \
            "chmod +x /tmp/scapy_traffic_generator.py"

        log_info "Scapy traffic generator installed at /tmp/scapy_traffic_generator.py"
        ;;

    trex)
        log_info "Installing TRex..."
        log_warning "TRex installation requires significant resources and time"

        SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "$SSH_USERNAME@$SENSOR_IP" \
            "cd /tmp && wget --no-check-certificate https://trex-tgn.cisco.com/trex/release/latest -O trex.tar.gz && tar -xzf trex.tar.gz" || {
            log_error "Failed to download/extract TRex"
            exit 1
        }

        log_info "TRex installed in /tmp/v*/"
        log_warning "TRex requires additional configuration. See docs/TRAFFIC_GENERATION_GUIDE.md"
        ;;

    *)
        log_error "Unknown mode: $MODE"
        log_error "Valid modes: simple, scapy, trex"
        exit 2
        ;;
esac

# Step 4: Get network interface information
log_info "Getting network interface information..."
interfaces=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SENSOR_IP" \
    "ip addr show | grep -E '^[0-9]+: (eth|ens)' | cut -d: -f2 | tr -d ' '")

log_info "Available interfaces:"
echo "$interfaces" | while read -r iface; do
    log_info "  - $iface"
done

# Step 5: Get MAC addresses
log_info "Getting interface MAC addresses..."
eth0_mac=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SENSOR_IP" \
    "ip link show eth0 | grep 'link/ether' | awk '{print \$2}'")

eth1_mac=$(SSHPASS="$SSH_PASSWORD" sshpass -e ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    "$SSH_USERNAME@$SENSOR_IP" \
    "ip link show eth1 | grep 'link/ether' | awk '{print \$2}'")

log_info "  eth0 MAC: $eth0_mac"
log_info "  eth1 MAC: $eth1_mac"

# Step 6: Create usage instructions
cat > "$PROJECT_ROOT/traffic_generator_${SENSOR_IP}_usage.txt" <<EOF
Traffic Generator Configuration for Sensor: $SENSOR_IP
================================================================

Installation Date: $(date)
Mode: $MODE
Sensor Status: $sensor_status

Network Configuration:
- eth0 (management): $SENSOR_IP - MAC: $eth0_mac
- eth1 (monitoring): MAC: $eth1_mac

USAGE INSTRUCTIONS:

1. Connect to sensor:
   ssh $SSH_USERNAME@$SENSOR_IP

2. Generate traffic based on mode:

EOF

case "$MODE" in
    simple)
        cat >> "$PROJECT_ROOT/traffic_generator_${SENSOR_IP}_usage.txt" <<EOF
   Simple Traffic Generator (socket-based):

   # UDP traffic (100 pps, 10 seconds)
   python3 /tmp/simple_traffic_generator.py -t <target_ip> -p 5555 --protocol udp -r 100 -D 10

   # TCP traffic (50 pps, 30 seconds)
   python3 /tmp/simple_traffic_generator.py -t <target_ip> -p 8080 --protocol tcp -r 50 -D 30

   # HTTP requests (10 rps, 60 seconds)
   python3 /tmp/simple_traffic_generator.py -t <target_ip> -p 80 --protocol http -r 10 -D 60

   # Mixed TCP/UDP traffic (100 pps)
   python3 /tmp/simple_traffic_generator.py -t <target_ip> -p 5555 --protocol mixed -r 100

   # High throughput UDP (1000 pps, large packets)
   python3 /tmp/simple_traffic_generator.py -t <target_ip> -p 9999 --protocol udp -r 1000 --size 8192 -D 30

EOF
        ;;

    scapy)
        cat >> "$PROJECT_ROOT/traffic_generator_${SENSOR_IP}_usage.txt" <<EOF
   Scapy Traffic Generator (advanced packet crafting):

   # ICMP traffic with layer 2 (eth0)
   sudo python3 /tmp/scapy_traffic_generator.py \\
       -s $SENSOR_IP -d <target_ip> -i eth0 \\
       --src-mac $eth0_mac --dst-mac <target_mac> \\
       -t icmp -r 20 -D 60

   # HTTP traffic
   sudo python3 /tmp/scapy_traffic_generator.py \\
       -s $SENSOR_IP -d <target_ip> -i eth0 \\
       -t http -r 50 -D 30

   # DNS traffic
   sudo python3 /tmp/scapy_traffic_generator.py \\
       -s $SENSOR_IP -d <target_ip> -i eth0 \\
       -t dns -r 100 -D 60

   # TCP SYN flood
   sudo python3 /tmp/scapy_traffic_generator.py \\
       -s $SENSOR_IP -d <target_ip> -i eth0 \\
       -t tcp -r 200 -D 30

   # Mixed traffic
   sudo python3 /tmp/scapy_traffic_generator.py \\
       -s $SENSOR_IP -d <target_ip> -i eth0 \\
       -t mixed -r 100 -D 120

EOF
        ;;

    trex)
        cat >> "$PROJECT_ROOT/traffic_generator_${SENSOR_IP}_usage.txt" <<EOF
   TRex Traffic Generator (high performance):

   # Start TRex console
   cd /tmp/v*/
   sudo ./trex-console

   # See docs/TRAFFIC_GENERATION_GUIDE.md for TRex configuration

EOF
        ;;
esac

cat >> "$PROJECT_ROOT/traffic_generator_${SENSOR_IP}_usage.txt" <<EOF

IMPORTANT NOTES:

1. eth0 vs eth1:
   - eth0 (management): Works with sensor services running, routable through AWS VPC
   - eth1 (monitoring): Requires sensor services stopped, AWS networking may block inter-sensor traffic

2. To stop sensor services (for eth1 usage):
   ssh $SSH_USERNAME@$SENSOR_IP
   sudo corelightctl sensor stop

3. To restart sensor services:
   sudo corelightctl sensor start

4. AWS Networking Limitations:
   - AWS source/destination checks may block non-standard traffic
   - Calico/Kubernetes networking filters traffic between sensors
   - For best results, use eth0 (management interface)

5. Testing Traffic Reception:
   On target sensor, start a listener:
   python3 /tmp/simple_traffic_generator.py  # (upload listener script first)

For more information, see: docs/TRAFFIC_GENERATION_GUIDE.md
================================================================
EOF

log_info "Usage instructions saved to: traffic_generator_${SENSOR_IP}_usage.txt"

# Step 7: Display summary
echo ""
log_info "====================================="
log_info "Traffic Generator Setup Complete!"
log_info "====================================="
log_info ""
log_info "Sensor: $SENSOR_IP"
log_info "Mode: $MODE"
log_info "Status: $sensor_status"
log_info ""
log_info "Next Steps:"
log_info "1. Review usage instructions: cat traffic_generator_${SENSOR_IP}_usage.txt"
log_info "2. Connect to sensor: ssh $SSH_USERNAME@$SENSOR_IP"
log_info "3. Start generating traffic!"
log_info ""
log_info "Example command (simple mode):"
log_info "  ssh $SSH_USERNAME@$SENSOR_IP python3 /tmp/simple_traffic_generator.py -t <target_ip> -p 5555 --protocol udp -r 100 -D 60"
log_info ""

exit 0
