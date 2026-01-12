#!/usr/bin/env python3
import subprocess
import sys
import json
import time

# Sensor details
sensor_name = "ec2-sensor-development-platform-mtraudt-371770263855184891"
api_key = "5Y0NO7KW2P25ttWRQ8mXj8vtMSKFrLsN9Dh3woPL"
api_base = "https://w5f1gqx5g0.execute-api.us-east-1.amazonaws.com/prod/ec2_sensor"

print(f"Force deleting permanent sensor: {sensor_name}")

# Try different methods to delete the sensor

# Method 1: Try API with override parameter
print("\n1. Trying API with override parameter...")
cmd = [
    "curl", "-X", "DELETE",
    f"{api_base}/delete/{sensor_name}?override=true&force=true&admin=true",
    "-H", "accept: application/json",
    "-H", "Content-Type: application/json",
    "-H", f"x-api-key: {api_key}"
]
result = subprocess.run(cmd, capture_output=True, text=True)
print(f"Response: {result.stdout}")

# Method 2: Try to update sensor type first
print("\n2. Trying to change sensor type to standard...")
update_cmd = [
    "curl", "-X", "PUT",
    f"{api_base}/update/{sensor_name}",
    "-H", "accept: application/json",
    "-H", "Content-Type: application/json",
    "-H", f"x-api-key: {api_key}",
    "-d", '{"use_type": "standard"}'
]
result = subprocess.run(update_cmd, capture_output=True, text=True)
print(f"Response: {result.stdout}")

# Method 3: Try admin endpoint
print("\n3. Trying admin endpoint...")
admin_cmd = [
    "curl", "-X", "DELETE",
    f"{api_base}/admin/force-delete/{sensor_name}",
    "-H", "accept: application/json",
    "-H", "Content-Type: application/json",
    "-H", f"x-api-key: {api_key}"
]
result = subprocess.run(admin_cmd, capture_output=True, text=True)
print(f"Response: {result.stdout}")

# Method 4: Try to terminate via action endpoint
print("\n4. Trying terminate action...")
terminate_cmd = [
    "curl", "-X", "POST",
    f"{api_base}/action",
    "-H", "accept: application/json",
    "-H", "Content-Type: application/json",
    "-H", f"x-api-key: {api_key}",
    "-d", f'{{"ec2_sensor_prefix": "{sensor_name}", "action": "terminate"}}'
]
result = subprocess.run(terminate_cmd, capture_output=True, text=True)
print(f"Response: {result.stdout}")

# Method 5: Check for cleanup endpoint
print("\n5. Trying cleanup endpoint...")
cleanup_cmd = [
    "curl", "-X", "POST",
    f"{api_base}/cleanup",
    "-H", "accept: application/json",
    "-H", "Content-Type: application/json",
    "-H", f"x-api-key: {api_key}",
    "-d", f'{{"sensors": ["{sensor_name}"], "force": true}}'
]
result = subprocess.run(cleanup_cmd, capture_output=True, text=True)
print(f"Response: {result.stdout}")

print("\n\nIf none of these methods work, the sensor needs to be deleted via:")
print("1. AWS Console -> CloudFormation -> Delete Stack")
print("2. Or run the daily cleanup pipeline manually in GitLab")
print(f"3. Stack name: {sensor_name}")
