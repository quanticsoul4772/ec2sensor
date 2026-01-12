#!/usr/bin/env python3
"""
Scapy Traffic Generator for EC2 Sensors
Generates various types of network traffic for sensor testing
"""

import sys
import time
import argparse
from datetime import datetime

try:
    from scapy.all import *
except ImportError:
    print("Error: scapy is not installed. Install with: sudo python3 -m pip install scapy")
    sys.exit(1)

class TrafficGenerator:
    def __init__(self, src_ip, dst_ip, interface="eth1", src_mac=None, dst_mac=None):
        self.src_ip = src_ip
        self.dst_ip = dst_ip
        self.interface = interface
        self.src_mac = src_mac
        self.dst_mac = dst_mac
        self.packets_sent = 0
        self.bytes_sent = 0
        self.start_time = None
        self.use_layer2 = (src_mac is not None and dst_mac is not None)

    def log(self, message):
        """Print timestamped log message"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {message}")

    def print_stats(self):
        """Print current statistics"""
        if self.start_time:
            duration = time.time() - self.start_time
            pps = self.packets_sent / duration if duration > 0 else 0
            mbps = (self.bytes_sent * 8) / (1024 * 1024 * duration) if duration > 0 else 0
            self.log(f"Stats: {self.packets_sent} packets, {self.bytes_sent} bytes, {pps:.2f} pps, {mbps:.2f} Mbps")

    def generate_http_traffic(self, duration=10, pps=100):
        """Generate HTTP GET request traffic"""
        self.log(f"Generating HTTP traffic: {pps} pps for {duration}s")
        self.start_time = time.time()

        # Create HTTP GET request packet
        http_get = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
        pkt = IP(src=self.src_ip, dst=self.dst_ip)/TCP(dport=80, flags="PA")/Raw(load=http_get)

        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            while time.time() < end_time:
                send(pkt, iface=self.interface, verbose=0)
                self.packets_sent += 1
                self.bytes_sent += len(pkt)
                time.sleep(interval)

                if self.packets_sent % 100 == 0:
                    self.print_stats()
        except KeyboardInterrupt:
            self.log("Interrupted by user")

        self.print_stats()

    def generate_dns_traffic(self, duration=10, pps=50):
        """Generate DNS query traffic"""
        self.log(f"Generating DNS traffic: {pps} pps for {duration}s")
        self.start_time = time.time()

        # Create DNS query packet
        pkt = IP(src=self.src_ip, dst=self.dst_ip)/UDP(dport=53)/DNS(rd=1, qd=DNSQR(qname="example.com"))

        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            while time.time() < end_time:
                send(pkt, iface=self.interface, verbose=0)
                self.packets_sent += 1
                self.bytes_sent += len(pkt)
                time.sleep(interval)

                if self.packets_sent % 50 == 0:
                    self.print_stats()
        except KeyboardInterrupt:
            self.log("Interrupted by user")

        self.print_stats()

    def generate_tcp_syn_flood(self, duration=10, pps=100):
        """Generate TCP SYN flood traffic"""
        self.log(f"Generating TCP SYN flood: {pps} pps for {duration}s")
        self.start_time = time.time()

        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            port = 80
            while time.time() < end_time:
                # Vary destination port
                pkt = IP(src=self.src_ip, dst=self.dst_ip)/TCP(dport=port, flags="S")
                send(pkt, iface=self.interface, verbose=0)
                self.packets_sent += 1
                self.bytes_sent += len(pkt)

                port = (port % 65535) + 1
                time.sleep(interval)

                if self.packets_sent % 100 == 0:
                    self.print_stats()
        except KeyboardInterrupt:
            self.log("Interrupted by user")

        self.print_stats()

    def generate_icmp_traffic(self, duration=10, pps=10):
        """Generate ICMP ping traffic"""
        self.log(f"Generating ICMP traffic: {pps} pps for {duration}s")
        self.start_time = time.time()

        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            seq = 0
            while time.time() < end_time:
                if self.use_layer2:
                    pkt = Ether(src=self.src_mac, dst=self.dst_mac)/IP(src=self.src_ip, dst=self.dst_ip)/ICMP(seq=seq)
                    sendp(pkt, iface=self.interface, verbose=0)
                else:
                    pkt = IP(src=self.src_ip, dst=self.dst_ip)/ICMP(seq=seq)
                    send(pkt, iface=self.interface, verbose=0)
                self.packets_sent += 1
                self.bytes_sent += len(pkt)
                seq += 1
                time.sleep(interval)

                if self.packets_sent % 10 == 0:
                    self.print_stats()
        except KeyboardInterrupt:
            self.log("Interrupted by user")

        self.print_stats()

    def generate_mixed_traffic(self, duration=60, pps=100):
        """Generate mixed traffic (HTTP, DNS, ICMP)"""
        self.log(f"Generating mixed traffic: {pps} pps for {duration}s")
        self.start_time = time.time()

        # Create packet templates
        http_get = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
        http_pkt = IP(src=self.src_ip, dst=self.dst_ip)/TCP(dport=80, flags="PA")/Raw(load=http_get)
        dns_pkt = IP(src=self.src_ip, dst=self.dst_ip)/UDP(dport=53)/DNS(rd=1, qd=DNSQR(qname="example.com"))
        icmp_pkt = IP(src=self.src_ip, dst=self.dst_ip)/ICMP()

        packets = [http_pkt, dns_pkt, icmp_pkt]
        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            i = 0
            while time.time() < end_time:
                pkt = packets[i % len(packets)]
                send(pkt, iface=self.interface, verbose=0)
                self.packets_sent += 1
                self.bytes_sent += len(pkt)
                i += 1
                time.sleep(interval)

                if self.packets_sent % 100 == 0:
                    self.print_stats()
        except KeyboardInterrupt:
            self.log("Interrupted by user")

        self.print_stats()

    def generate_udp_flood(self, duration=10, pps=100, size=1400):
        """Generate UDP flood with custom payload size"""
        self.log(f"Generating UDP flood: {pps} pps, {size} bytes payload for {duration}s")
        self.start_time = time.time()

        # Create UDP packet with custom payload
        payload = "X" * size
        pkt = IP(src=self.src_ip, dst=self.dst_ip)/UDP(dport=9999)/Raw(load=payload)

        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            while time.time() < end_time:
                send(pkt, iface=self.interface, verbose=0)
                self.packets_sent += 1
                self.bytes_sent += len(pkt)
                time.sleep(interval)

                if self.packets_sent % 100 == 0:
                    self.print_stats()
        except KeyboardInterrupt:
            self.log("Interrupted by user")

        self.print_stats()

def main():
    parser = argparse.ArgumentParser(
        description="Scapy Traffic Generator for EC2 Sensors",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate HTTP traffic at 100 pps for 60 seconds
  sudo python3 scapy_traffic_generator.py -s 10.50.88.80 -d 10.50.88.156 -t http -r 100 -D 60

  # Generate mixed traffic (HTTP, DNS, ICMP)
  sudo python3 scapy_traffic_generator.py -s 10.50.88.80 -d 10.50.88.156 -t mixed -r 50

  # Generate UDP flood with large packets
  sudo python3 scapy_traffic_generator.py -s 10.50.88.80 -d 10.50.88.156 -t udp -r 200 --size 1400

Traffic Types:
  http    - HTTP GET requests
  dns     - DNS queries
  tcp     - TCP SYN flood
  icmp    - ICMP ping
  udp     - UDP flood
  mixed   - Mixed HTTP, DNS, ICMP traffic
        """
    )

    parser.add_argument('-s', '--src-ip', required=True, help='Source IP address')
    parser.add_argument('-d', '--dst-ip', required=True, help='Destination IP address')
    parser.add_argument('-i', '--interface', default='eth1', help='Network interface (default: eth1)')
    parser.add_argument('--src-mac', help='Source MAC address (optional, for layer 2 sending)')
    parser.add_argument('--dst-mac', help='Destination MAC address (optional, for layer 2 sending)')
    parser.add_argument('-t', '--traffic-type', default='http',
                       choices=['http', 'dns', 'tcp', 'icmp', 'udp', 'mixed'],
                       help='Type of traffic to generate (default: http)')
    parser.add_argument('-r', '--rate', type=int, default=100, help='Packets per second (default: 100)')
    parser.add_argument('-D', '--duration', type=int, default=10, help='Duration in seconds (default: 10)')
    parser.add_argument('--size', type=int, default=1400, help='UDP payload size in bytes (default: 1400)')

    args = parser.parse_args()

    # Check if running as root
    if os.geteuid() != 0:
        print("Error: This script must be run as root (use sudo)")
        sys.exit(1)

    # Create traffic generator
    gen = TrafficGenerator(args.src_ip, args.dst_ip, args.interface, args.src_mac, args.dst_mac)

    # Generate traffic based on type
    if args.traffic_type == 'http':
        gen.generate_http_traffic(duration=args.duration, pps=args.rate)
    elif args.traffic_type == 'dns':
        gen.generate_dns_traffic(duration=args.duration, pps=args.rate)
    elif args.traffic_type == 'tcp':
        gen.generate_tcp_syn_flood(duration=args.duration, pps=args.rate)
    elif args.traffic_type == 'icmp':
        gen.generate_icmp_traffic(duration=args.duration, pps=args.rate)
    elif args.traffic_type == 'udp':
        gen.generate_udp_flood(duration=args.duration, pps=args.rate, size=args.size)
    elif args.traffic_type == 'mixed':
        gen.generate_mixed_traffic(duration=args.duration, pps=args.rate)

    gen.log("Traffic generation complete")

if __name__ == "__main__":
    main()
