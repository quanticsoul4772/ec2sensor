# Traffic Generation Guide for EC2 Sensors

## Overview

EC2 sensors run in Kubernetes pods with Calico networking, making standard traffic generation challenging. This guide documents the best approaches.

## Challenge

- Sensors run in K8s pods with isolated networking
- AWS EC2 has source/destination checks on ENIs
- Calico iptables rules filter non-standard traffic
- eth1 interfaces are in PROMISC mode for passive monitoring only

## Solution Options

### Option 1: tcpreplay with AWS Modifications (Recommended for PCAP Replay)

**Requirements:**
- Disable AWS source/destination checks on both sensors' eth1 ENIs
- Rewrite PCAP files with correct src/dst IPs matching the sensor IPs

**Steps:**
1. Get ENI IDs for both sensors:
   ```bash
   aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[].Instances[].NetworkInterfaces[?DeviceIndex==`1`].NetworkInterfaceId'
   ```

2. Disable source/dest checks:
   ```bash
   aws ec2 modify-network-interface-attribute \
       --network-interface-id eni-xxx \
       --no-source-dest-check
   ```

3. Rewrite PCAP files:
   ```bash
   sudo tcprewrite \
       --srcipmap=0.0.0.0/0:10.50.88.81 \
       --dstipmap=0.0.0.0/0:10.50.88.157 \
       --enet-smac=0a:ff:db:f6:41:6f \
       --enet-dmac=0e:59:38:8d:d4:b7 \
       --infile=traffic.pcap \
       --outfile=traffic_rewritten.pcap
   ```

4. Run tcpreplay:
   ```bash
   sudo tcpreplay --intf1=eth1 --mbps=100 --loop=0 traffic_rewritten.pcap
   ```

**Pros:**
- Can replay real PCAP files
- High throughput (99.99 Mbps achieved)
- Exact protocol reproduction

**Cons:**
- Requires AWS permissions
- Complex setup
- PCAP rewriting needed for each test

### Option 2: Python scapy (Recommended for Custom Traffic)

**Installation:**
```bash
sudo python3 -m pip install scapy
```

**Simple traffic generator:**
```python
#!/usr/bin/env python3
from scapy.all import *
import time

src_ip = "10.50.88.80"
dst_ip = "10.50.88.156"
interface = "eth1"

# Generate HTTP traffic
http_pkt = IP(src=src_ip, dst=dst_ip)/TCP(dport=80, flags="S")

# Send continuously
while True:
    send(http_pkt, iface=interface, verbose=0)
    time.sleep(0.01)
```

**Pros:**
- Very flexible - can craft any packet
- Python scripting for complex scenarios
- Works within AWS networking constraints

**Cons:**
- Slower than compiled tools
- Requires Python knowledge
- Still subject to AWS source/dest checks

### Option 3: TRex Traffic Generator (Recommended for High Performance)

**Installation:**
```bash
cd /opt
wget --no-check-certificate https://trex-tgn.cisco.com/trex/release/latest
tar -xzf latest
cd v3.x
sudo ./trex-console
```

**Basic configuration:**
```yaml
- port_limit: 2
  version: 2
  interfaces: ["eth1", "eth1"]
  port_info:
      - dest_mac: "0e:59:38:8d:d4:b7"
        src_mac: "0a:ff:db:f6:41:6f"
```

**Pros:**
- Very high performance (designed for 10G+)
- Professional-grade features
- Stateful traffic generation

**Cons:**
- Complex installation and configuration
- Requires significant resources
- Steep learning curve

### Option 4: Simple Bash Tools (For Testing Only)

**Using netcat for basic validation:**
```bash
# On target sensor (156)
nc -l -p 5555

# On source sensor (80)
while true; do echo "test" | nc 10.50.88.156 5555; done
```

**Using ping for connectivity:**
```bash
ping -f 10.50.88.156  # Flood ping
```

**Pros:**
- No installation needed
- Simple to use
- Good for connectivity testing

**Cons:**
- Very limited traffic types
- Low throughput
- Not suitable for real testing

## Recommended Approach

For your use case (converting sensors to traffic generators):

1. **Phase 1**: Use Option 4 to validate network connectivity
2. **Phase 2**: Install and test TRex (Option 3) for professional traffic generation
3. **Fallback**: Use scapy (Option 2) if TRex is too complex

## AWS Source/Destination Check Automation

To automate disabling source/dest checks:

```bash
#!/bin/bash
# Get instance ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Get eth1 ENI ID
ENI_ID=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[].Instances[].NetworkInterfaces[?DeviceIndex==`1`].NetworkInterfaceId' \
    --output text)

# Disable source/dest check
aws ec2 modify-network-interface-attribute \
    --network-interface-id $ENI_ID \
    --no-source-dest-check

echo "Source/dest check disabled on $ENI_ID"
```

## Troubleshooting

### Traffic not reaching target

1. Check routing:
   ```bash
   ip route get <target_ip>
   ```

2. Check iptables:
   ```bash
   sudo iptables -L -n -v
   ```

3. Verify interface is up:
   ```bash
   ip link show eth1
   ```

4. Test with tcpdump on both ends:
   ```bash
   # Target
   sudo tcpdump -i eth1 -n

   # Source
   sudo tcpdump -i eth1 -n dst <target_ip>
   ```

### AWS blocks traffic

- Verify source/dest checks are disabled
- Check security groups allow traffic
- Verify NACLs allow traffic
- Confirm both sensors in same VPC

### High packet loss

- Reduce transmission rate
- Check CPU usage on both sensors
- Verify network bandwidth limits
- Monitor for iptables drops

## Next Steps

Create an automated sensor-to-traffic-generator conversion script that:
1. Detects sensor configuration
2. Installs appropriate tools (TRex or scapy)
3. Configures networking
4. Disables AWS source/dest checks
5. Provides simple commands to start/stop traffic generation
