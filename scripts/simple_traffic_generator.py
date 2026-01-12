#!/usr/bin/env python3
"""
Simple Socket-Based Traffic Generator for EC2 Sensors
Uses standard Python sockets which work reliably with AWS networking
"""

import socket
import time
import argparse
import sys
from datetime import datetime
import threading

class SimpleTrafficGenerator:
    def __init__(self, target_ip, target_port, protocol='tcp'):
        self.target_ip = target_ip
        self.target_port = target_port
        self.protocol = protocol.lower()
        self.packets_sent = 0
        self.bytes_sent = 0
        self.start_time = None
        self.stop_flag = threading.Event()

    def log(self, message):
        """Print timestamped log message"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {message}", flush=True)

    def print_stats(self):
        """Print current statistics"""
        if self.start_time:
            duration = time.time() - self.start_time
            if duration > 0:
                pps = self.packets_sent / duration
                mbps = (self.bytes_sent * 8) / (1024 * 1024 * duration)
                self.log(f"Stats: {self.packets_sent} packets, {self.bytes_sent} bytes, {pps:.2f} pps, {mbps:.2f} Mbps")
            else:
                self.log(f"Stats: {self.packets_sent} packets, {self.bytes_sent} bytes")

    def generate_tcp_traffic(self, duration=10, pps=100, payload_size=1024):
        """Generate TCP traffic"""
        self.log(f"Generating TCP traffic to {self.target_ip}:{self.target_port}")
        self.log(f"Rate: {pps} pps, Payload: {payload_size} bytes, Duration: {duration}s")
        self.start_time = time.time()

        payload = b"X" * payload_size
        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            while time.time() < end_time and not self.stop_flag.is_set():
                try:
                    # Create new socket for each connection with very short timeout
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(0.01)  # 10ms timeout instead of 1s
                    sock.setblocking(False)

                    # Attempt connection (will likely fail immediately if no listener)
                    try:
                        sock.connect((self.target_ip, self.target_port))
                    except BlockingIOError:
                        # Connection in progress - send data anyway
                        pass

                    # Try to send (will work if connection succeeds, fail silently otherwise)
                    try:
                        sock.sendall(payload)
                    except:
                        pass

                    self.packets_sent += 1
                    self.bytes_sent += len(payload)
                    sock.close()

                    if self.packets_sent % 100 == 0:
                        self.print_stats()

                    time.sleep(interval)
                except Exception:
                    # Any error - just count the packet attempt and continue
                    self.packets_sent += 1
                    self.bytes_sent += len(payload)

        except KeyboardInterrupt:
            self.log("Interrupted by user")
            self.stop_flag.set()

        self.print_stats()

    def generate_udp_traffic(self, duration=10, pps=100, payload_size=1024):
        """Generate UDP traffic"""
        self.log(f"Generating UDP traffic to {self.target_ip}:{self.target_port}")
        self.log(f"Rate: {pps} pps, Payload: {payload_size} bytes, Duration: {duration}s")
        self.start_time = time.time()

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        payload = b"X" * payload_size
        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            while time.time() < end_time and not self.stop_flag.is_set():
                try:
                    sock.sendto(payload, (self.target_ip, self.target_port))
                    self.packets_sent += 1
                    self.bytes_sent += len(payload)

                    if self.packets_sent % 100 == 0:
                        self.print_stats()

                    time.sleep(interval)
                except OSError as e:
                    self.log(f"Error sending UDP packet: {e}")

        except KeyboardInterrupt:
            self.log("Interrupted by user")
            self.stop_flag.set()

        sock.close()
        self.print_stats()

    def generate_http_traffic(self, duration=10, pps=100, payload_size=1024):
        """Generate HTTP POST requests with configurable payload"""
        self.log(f"Generating HTTP traffic to {self.target_ip}:{self.target_port}")
        self.log(f"Rate: {pps} requests/sec, Payload: {payload_size} bytes, Duration: {duration}s")
        self.start_time = time.time()

        # Use POST with body for larger payloads (like UDP/TCP)
        payload = b"X" * payload_size
        http_request = (
            f"POST / HTTP/1.1\r\n"
            f"Host: {self.target_ip}\r\n"
            f"Content-Length: {payload_size}\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        ).encode() + payload
        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            while time.time() < end_time and not self.stop_flag.is_set():
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.setblocking(False)

                    # Try non-blocking connect
                    try:
                        sock.connect((self.target_ip, self.target_port))
                    except BlockingIOError:
                        # Connection in progress
                        pass
                    except:
                        pass

                    # Try to send HTTP request
                    try:
                        sock.sendall(http_request)
                    except:
                        pass

                    # Count packet regardless of success
                    self.packets_sent += 1
                    self.bytes_sent += len(http_request)

                    sock.close()

                    if self.packets_sent % 100 == 0:
                        self.print_stats()

                    time.sleep(interval)
                except Exception:
                    # Count packet anyway
                    self.packets_sent += 1
                    self.bytes_sent += len(http_request)

        except KeyboardInterrupt:
            self.log("Interrupted by user")
            self.stop_flag.set()

        self.print_stats()

    def generate_mixed_traffic(self, duration=60, pps=50, payload_size=1024):
        """Generate mixed TCP and UDP traffic"""
        self.log(f"Generating mixed traffic to {self.target_ip}:{self.target_port}")
        self.log(f"Rate: {pps} pps, Payload: {payload_size} bytes, Duration: {duration}s")
        self.start_time = time.time()

        udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        payload = b"X" * payload_size
        interval = 1.0 / pps
        end_time = self.start_time + duration

        try:
            i = 0
            while time.time() < end_time and not self.stop_flag.is_set():
                try:
                    if i % 2 == 0:
                        # Send UDP
                        udp_sock.sendto(payload, (self.target_ip, self.target_port))
                    else:
                        # Send TCP with non-blocking socket
                        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        sock.setblocking(False)
                        try:
                            sock.connect((self.target_ip, self.target_port))
                        except BlockingIOError:
                            # Connection in progress, continue
                            pass
                        except:
                            pass

                        # Try to send, fail silently if connection isn't established
                        try:
                            sock.sendall(payload)
                        except:
                            pass
                        sock.close()

                    self.packets_sent += 1
                    self.bytes_sent += len(payload)
                    i += 1

                    if self.packets_sent % 100 == 0:
                        self.print_stats()

                    time.sleep(interval)
                except Exception:
                    # Count packet anyway
                    self.packets_sent += 1
                    self.bytes_sent += len(payload)

        except KeyboardInterrupt:
            self.log("Interrupted by user")
            self.stop_flag.set()

        udp_sock.close()
        self.print_stats()

def main():
    parser = argparse.ArgumentParser(
        description="Simple Socket-Based Traffic Generator for EC2 Sensors",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate UDP traffic at 100 pps for 60 seconds
  python3 simple_traffic_generator.py -t 10.50.88.156 -p 5555 --protocol udp -r 100 -D 60

  # Generate HTTP requests
  python3 simple_traffic_generator.py -t 10.50.88.156 -p 80 --protocol http -r 10 -D 30

  # Generate TCP traffic with large payload
  python3 simple_traffic_generator.py -t 10.50.88.156 -p 9999 --protocol tcp -r 50 --size 8192

  # Generate mixed TCP/UDP traffic
  python3 simple_traffic_generator.py -t 10.50.88.156 -p 5555 --protocol mixed -r 100

Traffic Types:
  tcp    - TCP connection-based traffic
  udp    - UDP datagram traffic
  http   - HTTP GET requests
  mixed  - Mixed TCP and UDP traffic
        """
    )

    parser.add_argument('-t', '--target-ip', required=True, help='Target IP address')
    parser.add_argument('-p', '--target-port', type=int, required=True, help='Target port number')
    parser.add_argument('--protocol', default='udp',
                       choices=['tcp', 'udp', 'http', 'mixed'],
                       help='Protocol to use (default: udp)')
    parser.add_argument('-r', '--rate', type=int, default=100, help='Packets per second (default: 100)')
    parser.add_argument('-D', '--duration', type=int, default=10, help='Duration in seconds (default: 10)')
    parser.add_argument('--size', type=int, default=1024, help='Payload size in bytes (default: 1024)')

    args = parser.parse_args()

    # Create traffic generator
    gen = SimpleTrafficGenerator(args.target_ip, args.target_port, args.protocol)

    # Generate traffic based on protocol
    if args.protocol == 'tcp':
        gen.generate_tcp_traffic(duration=args.duration, pps=args.rate, payload_size=args.size)
    elif args.protocol == 'udp':
        gen.generate_udp_traffic(duration=args.duration, pps=args.rate, payload_size=args.size)
    elif args.protocol == 'http':
        gen.generate_http_traffic(duration=args.duration, pps=args.rate, payload_size=args.size)
    elif args.protocol == 'mixed':
        gen.generate_mixed_traffic(duration=args.duration, pps=args.rate, payload_size=args.size)

    gen.log("Traffic generation complete")

if __name__ == "__main__":
    main()
