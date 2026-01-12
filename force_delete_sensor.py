#!/usr/bin/env python3
import boto3
import sys

sensor_name = "ec2-sensor-development-platform-mtraudt-205367309130833041"
region = "us-east-1"

print(f"Force deleting sensor: {sensor_name}")

# Create EC2 client
ec2 = boto3.client('ec2', region_name=region)

try:
    # Find instances with the sensor name tag
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': [sensor_name]},
            {'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'stopping', 'pending']}
        ]
    )
    
    instance_ids = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])
            print(f"Found instance: {instance['InstanceId']} (State: {instance['State']['Name']})")
    
    if not instance_ids:
        print("No instances found with that name")
        # Try CloudFormation stack
        cf = boto3.client('cloudformation', region_name=region)
        try:
            stack_response = cf.describe_stacks(StackName=sensor_name)
            print(f"Found CloudFormation stack: {sensor_name}")
            print("Deleting stack...")
            cf.delete_stack(StackName=sensor_name)
            print("Stack deletion initiated")
        except Exception as e:
            print(f"No CloudFormation stack found: {e}")
    else:
        # Force terminate instances
        print(f"Terminating {len(instance_ids)} instance(s)...")
        terminate_response = ec2.terminate_instances(InstanceIds=instance_ids)
        print("Termination initiated")
        
        # Get associated resources
        for instance_id in instance_ids:
            # Get volumes
            volumes = ec2.describe_volumes(
                Filters=[{'Name': 'attachment.instance-id', 'Values': [instance_id]}]
            )
            for volume in volumes['Volumes']:
                print(f"Found volume: {volume['VolumeId']}")
                
except Exception as e:
    print(f"Error: {e}")
    print("\nTrying alternative approach...")
    
    # Try to delete via CloudFormation
    cf = boto3.client('cloudformation', region_name=region)
    try:
        print(f"Attempting to delete CloudFormation stack: {sensor_name}")
        cf.delete_stack(StackName=sensor_name)
        print("Stack deletion initiated successfully")
    except Exception as cf_error:
        print(f"CloudFormation error: {cf_error}")
