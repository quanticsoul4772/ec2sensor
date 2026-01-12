# Traffic Generation Options for Testing

**Research Date**: December 17, 2025
**Context**: Network traffic generation for sensor testing and security analysis

## Executive Summary

This document outlines comprehensive options for generating network traffic for testing purposes, including PCAP replay, synthetic traffic generation, cloud-specific solutions, and security testing tools. Options range from open-source command-line tools to commercial GUI-based solutions.

---

## 1. PCAP Replay Methods

### 1.1 Tcpreplay
**Description**: The industry-standard tool for replaying captured network traffic from PCAP files.

**Key Features**:
- Replay PCAP files at original, faster, or slower speeds
- Supports multiple output interfaces
- Can modify packets on-the-fly (tcprewrite)
- Loop replay for continuous testing
- Bandwidth control (Mbps limiting)

**Use Cases**:
- IDS/IPS testing
- Network security appliance testing
- Performance testing with real traffic patterns
- Protocol analysis validation

**Installation**:
```bash
# Ubuntu/Debian
sudo apt-get install tcpreplay

# RedHat/CentOS
sudo yum install tcpreplay

# macOS
brew install tcpreplay
```

**Example Usage**:
```bash
# Basic replay
sudo tcpreplay -i eth0 capture.pcap

# Replay at 10 Mbps
sudo tcpreplay -i eth0 -M 10 capture.pcap

# Continuous loop
sudo tcpreplay -i eth0 --loop=0 capture.pcap

# Modify MAC addresses
sudo tcprewrite --enet-dmac=00:11:22:33:44:55 \
  --enet-smac=00:55:44:33:22:11 \
  --infile=original.pcap \
  --outfile=modified.pcap
```

**Limitations**:
- Requires root/sudo privileges
- Transmits packets only (unidirectional)
- May not work across subnets without proper routing

**Source**: https://tcpreplay.appneta.com/

---

### 1.2 Sensor PCAP Replay Mode
**Description**: Built-in PCAP replay capability in network sensors (like Corelight, Zeek) that feeds PCAP files directly into the analysis engine.

**Key Features**:
- Traffic processed internally by Zeek/Suricata/analysis engines
- No network transmission required
- Supports continuous loop mode
- All sensor features (YARA, IDS, protocol analysis) work normally

**Use Cases**:
- Testing sensor features without live traffic
- Regression testing after sensor upgrades
- Feature validation (YARA rules, Suricata signatures)
- Protocol-specific testing

**Configuration** (Corelight/Zeek sensors):
```bash
# Enable PCAP replay mode
sudo broala-config set bro.pcap_replay_mode=1
sudo broala-config set bro.pcap_file=/path/to/capture.pcap
sudo broala-config set bro.pcap_replay_loop=1
sudo broala-apply-config
```

**Limitations**:
- Sensor-specific implementation
- No actual network packets visible on interfaces
- Limited to sensor's processing capabilities

---

## 2. Bandwidth and Performance Testing

### 2.1 iPerf3
**Description**: The standard tool for measuring maximum TCP/UDP bandwidth and network performance.

**Key Features**:
- TCP and UDP bandwidth testing
- Multiple simultaneous connections
- Bi-directional testing
- JSON output for automation
- Client-server architecture

**Use Cases**:
- Bandwidth capacity testing
- Network throughput validation
- QoS verification
- Link performance measurement

**Example Usage**:
```bash
# Server side
iperf3 -s

# Client side - TCP test
iperf3 -c server_ip -t 60

# UDP test at 100 Mbps
iperf3 -c server_ip -u -b 100M

# Parallel connections
iperf3 -c server_ip -P 10

# Bi-directional test
iperf3 -c server_ip --bidir
```

**Source**: https://iperf.fr/

---

### 2.2 hping3
**Description**: Advanced packet crafting tool for network testing, security auditing, and firewall testing.

**Key Features**:
- Custom packet crafting (TCP, UDP, ICMP, RAW-IP)
- Traceroute functionality
- Firewall testing
- Port scanning
- TCP/IP stack fingerprinting
- DoS testing capabilities

**Use Cases**:
- Firewall rule testing
- IDS/IPS signature testing
- Network troubleshooting
- Path MTU discovery
- Security auditing

**Example Usage**:
```bash
# TCP SYN flood test
sudo hping3 -S -p 80 --flood target_ip

# UDP flood
sudo hping3 --udp -p 53 --flood target_ip

# ICMP ping with custom interval
sudo hping3 -1 -i u1000 target_ip

# TCP with custom flags
sudo hping3 -c 100 -S -p 443 target_ip
```

**Source**: http://www.hping.org/

---

## 3. Packet Crafting and Custom Traffic

### 3.1 Scapy
**Description**: Python-based interactive packet manipulation program and library.

**Key Features**:
- Create custom packets from scratch
- Parse and dissect network packets
- Send/receive packets
- Forge protocols
- Network scanning and probing
- PCAP file manipulation

**Use Cases**:
- Protocol testing and development
- Network discovery
- Custom attack simulation
- Protocol fuzzing
- Educational purposes

**Example Usage**:
```python
from scapy.all import *

# Simple ICMP ping
send(IP(dst="192.168.1.1")/ICMP())

# TCP SYN scan
ans = sr1(IP(dst="192.168.1.1")/TCP(dport=80, flags="S"))

# Custom HTTP request
packet = IP(dst="example.com")/TCP(dport=80)/"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
send(packet)

# UDP flood
send(IP(dst="192.168.1.1")/UDP(dport=53)/Raw(load="X"*1024), count=1000)

# Read and replay PCAP
packets = rdpcap("capture.pcap")
sendp(packets, iface="eth0")
```

**Installation**:
```bash
pip install scapy
```

**Source**: https://scapy.net/

---

### 3.2 Ostinato
**Description**: GUI-based packet crafting and traffic generation tool with powerful stream configuration.

**Key Features**:
- Cross-platform GUI (Windows, Linux, macOS)
- Multiple protocol support (L2-L7)
- Stream-based traffic generation
- Real-time statistics
- Packet capture and analysis
- Multi-port support

**Use Cases**:
- Protocol testing
- Network device testing
- QA automation
- Performance testing
- Multi-stream traffic simulation

**Key Capabilities**:
- Visual packet builder
- Multiple traffic patterns (burst, continuous, random)
- Protocol-aware editing
- Statistics and graphing
- Remote drone control for distributed testing

**Source**: https://ostinato.org/

---

## 4. Cloud-Specific Options

### 4.1 AWS VPC Traffic Mirroring
**Description**: AWS native service for copying network traffic from ENIs for monitoring and security analysis.

**Key Features**:
- Mirror traffic from EC2 instances
- Send to analysis tools or appliances
- Filter by protocol, port, or direction
- No agent required
- VXLAN encapsulation

**Use Cases**:
- Security monitoring in AWS
- IDS/IPS deployment
- Network troubleshooting
- Compliance and auditing
- Threat detection

**Configuration**:
```bash
# Create mirror target
aws ec2 create-traffic-mirror-target \
  --network-interface-id eni-xxxxx \
  --description "Mirror target"

# Create filter
aws ec2 create-traffic-mirror-filter \
  --description "Capture all traffic"

# Add filter rule
aws ec2 create-traffic-mirror-filter-rule \
  --traffic-mirror-filter-id tmf-xxxxx \
  --traffic-direction ingress \
  --rule-action accept \
  --protocol 6  # TCP

# Create mirror session
aws ec2 create-traffic-mirror-session \
  --network-interface-id eni-source \
  --traffic-mirror-target-id tmt-xxxxx \
  --traffic-mirror-filter-id tmf-xxxxx \
  --session-number 1
```

**Limitations**:
- Same-subnet traffic may not be mirrored
- Additional costs per GB mirrored
- VXLAN overhead (50 bytes per packet)
- Regional service
- Requires ENI-compatible instances

**Source**: https://docs.aws.amazon.com/vpc/latest/mirroring/

---

### 4.2 AWS CloudWatch Synthetics
**Description**: AWS service for creating canaries that monitor endpoints and APIs.

**Key Features**:
- Scheduled synthetic monitoring
- HTTP/HTTPS endpoint testing
- Selenium-based UI testing
- Custom scripts (Node.js/Python)
- CloudWatch metrics integration

**Use Cases**:
- API endpoint monitoring
- Website availability testing
- Performance baselines
- Alerting on failures

**Source**: https://aws.amazon.com/cloudwatch/

---

## 5. Synthetic Traffic Generation

### 5.1 Python Socket Programming
**Description**: Custom traffic generation using Python's socket library.

**Key Features**:
- Full control over traffic patterns
- Protocol flexibility (TCP, UDP, HTTP)
- Rate limiting
- Custom payloads
- Scriptable and automatable

**Example** (UDP traffic generator):
```python
import socket
import time

def generate_udp_traffic(target_ip, target_port, pps, duration):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    payload = b"X" * 1024
    interval = 1.0 / pps
    end_time = time.time() + duration

    packets = 0
    while time.time() < end_time:
        sock.sendto(payload, (target_ip, target_port))
        packets += 1
        time.sleep(interval)

    sock.close()
    return packets

# Generate 1000 pps for 60 seconds
generate_udp_traffic("10.0.0.1", 5555, 1000, 60)
```

**Use Cases**:
- Custom protocol testing
- Specific traffic patterns
- Integration with test frameworks
- CI/CD pipeline testing

---

### 5.2 Network Traffic Simulators
**Description**: Tools that generate realistic network traffic patterns for testing.

**Options**:
- **D-ITG** (Distributed Internet Traffic Generator): Multi-protocol traffic generation with realistic patterns
- **MGEN** (Multi-Generator): UDP-based traffic with GPS sync
- **TRex**: High-performance traffic generator (up to 200 Gbps)
- **Moongen**: High-speed packet generator based on DPDK

**Use Cases**:
- Realistic traffic simulation
- High-throughput testing
- Protocol behavior analysis
- Network capacity planning

---

## 6. Security Testing Tools

### 6.1 Metasploit Framework
**Description**: Penetration testing framework with traffic generation capabilities.

**Key Features**:
- Exploit testing
- Auxiliary modules for scanning
- Post-exploitation modules
- Custom payload generation
- IDS/IPS evasion testing

**Use Cases**:
- Security validation
- IDS signature testing
- Exploit detection testing
- Red team exercises

---

### 6.2 nmap
**Description**: Network discovery and security auditing tool.

**Key Features**:
- Port scanning
- OS detection
- Service version detection
- Script engine (NSE)
- Multiple scan techniques

**Example Usage**:
```bash
# TCP SYN scan
nmap -sS target_ip

# UDP scan
nmap -sU target_ip

# Service version detection
nmap -sV target_ip

# OS detection
nmap -O target_ip

# Generate traffic continuously
while true; do nmap -sT target_ip; sleep 60; done
```

---

## 7. Load Testing and Application Traffic

### 7.1 Apache JMeter
**Description**: Java-based load testing tool for web applications and services.

**Key Features**:
- HTTP/HTTPS load testing
- Multiple protocol support (FTP, JDBC, SOAP, REST)
- Distributed testing
- GUI and CLI modes
- Extensive reporting

**Use Cases**:
- Web application load testing
- API performance testing
- Database load testing
- Realistic user behavior simulation

---

### 7.2 wrk / wrk2
**Description**: Modern HTTP benchmarking tools with scripting capabilities.

**Key Features**:
- Multi-threaded HTTP load generation
- Lua scripting for custom scenarios
- Low overhead
- Latency statistics

**Example Usage**:
```bash
# Simple HTTP load test
wrk -t12 -c400 -d30s http://example.com

# POST request test
wrk -t4 -c100 -d60s -s post.lua http://api.example.com
```

---

## 8. Comparison Matrix

| Tool | Type | Complexity | Cost | Best For |
|------|------|-----------|------|----------|
| tcpreplay | PCAP Replay | Low | Free | Realistic traffic replay |
| iPerf3 | Bandwidth | Low | Free | Throughput testing |
| hping3 | Packet Craft | Medium | Free | Security testing |
| Scapy | Packet Craft | High | Free | Custom protocols |
| Ostinato | GUI Generator | Medium | Free/Paid | Visual traffic design |
| AWS Traffic Mirror | Cloud Native | Medium | Paid | AWS monitoring |
| Python Sockets | Custom Code | High | Free | Specific use cases |
| JMeter | Application | Medium | Free | Web app testing |
| TRex | High-Speed | High | Free | Performance testing |

---

## 9. Recommendations by Use Case

### For IDS/IPS Testing
1. **tcpreplay** - Replay attack PCAPs
2. **hping3** - Test specific signatures
3. **Metasploit** - Exploit testing

### For Sensor Feature Testing
1. **Sensor PCAP Replay Mode** - Internal processing
2. **tcpreplay** - Network-level replay
3. **Scapy** - Custom protocol testing

### For Performance Testing
1. **iPerf3** - Bandwidth measurement
2. **TRex** - High-throughput testing
3. **wrk** - HTTP load testing

### For Cloud Environments
1. **AWS VPC Traffic Mirroring** - Native AWS solution
2. **Python scripts** - Custom EC2-based generation
3. **CloudWatch Synthetics** - Endpoint monitoring

### For Protocol Development
1. **Scapy** - Python-based crafting
2. **Ostinato** - GUI-based design
3. **hping3** - CLI-based testing

---

## 10. Best Practices

### General Guidelines
1. **Start Small**: Begin with low traffic rates and gradually increase
2. **Use PCAP Replay**: Most realistic traffic patterns come from captured traffic
3. **Monitor Resources**: Watch CPU, memory, and network utilization
4. **Document Baselines**: Record normal behavior before testing
5. **Clean Up**: Remove test configurations after completion

### Security Considerations
1. **Permission Required**: Only test on authorized systems
2. **Isolate Testing**: Use separate networks/VLANs when possible
3. **Rate Limiting**: Avoid overwhelming production systems
4. **Logging**: Keep records of all testing activities
5. **Coordinate**: Notify relevant teams before testing

### Performance Tips
1. **Hardware Offloading**: Disable NIC offloading for packet crafting
2. **Kernel Tuning**: Adjust network stack parameters for high rates
3. **CPU Affinity**: Pin processes to specific cores
4. **Buffering**: Increase socket buffers for high-throughput testing
5. **Timing**: Use high-resolution timers for accurate rate control

---

## 11. Troubleshooting Common Issues

### Traffic Not Visible
- **Check interface**: Verify correct network interface
- **Permissions**: Ensure root/sudo access
- **Firewall**: Check firewall rules blocking traffic
- **Routing**: Verify routing table entries
- **Promiscuous Mode**: Enable if monitoring on different interface

### Low Throughput
- **CPU Bottleneck**: Check CPU utilization
- **NIC Limits**: Verify interface speed
- **Buffer Sizes**: Increase socket buffers
- **Kernel Limits**: Adjust conntrack/netfilter settings
- **Rate Limiting**: Remove artificial rate limits

### AWS VPC Mirroring Not Working
- **Same Subnet**: Traffic may not mirror within same subnet
- **Instance Type**: Verify instance supports traffic mirroring
- **Filters**: Check mirror filter configuration
- **VXLAN**: Ensure target can handle VXLAN encapsulation
- **Limits**: Check service quotas

---

## Conclusion

Traffic generation for testing has numerous approaches depending on requirements:

- **Quick testing**: Use tcpreplay with existing PCAPs
- **Custom scenarios**: Use Scapy or Python
- **Performance validation**: Use iPerf3 or TRex
- **Security testing**: Use hping3 or Metasploit
- **Cloud deployments**: Use AWS Traffic Mirroring
- **Sensor testing**: Use built-in PCAP replay mode

The best approach depends on:
1. Testing objectives
2. Available resources
3. Network environment (physical, virtual, cloud)
4. Required traffic realism
5. Budget constraints

For most sensor testing scenarios, **PCAP replay** (either via tcpreplay or sensor-native replay) provides the best balance of realism, control, and ease of use.

---

## References

1. Tcpreplay Documentation: https://tcpreplay.appneta.com/
2. iPerf3 Documentation: https://iperf.fr/
3. Scapy Documentation: https://scapy.net/
4. AWS VPC Traffic Mirroring: https://docs.aws.amazon.com/vpc/latest/mirroring/
5. Ostinato: https://ostinato.org/
6. hping3: http://www.hping.org/
7. Network Testing Best Practices: https://codilime.com/blog/testing-network-configurations-with-free-traffic-generators/
