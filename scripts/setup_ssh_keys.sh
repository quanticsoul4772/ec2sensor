#!/bin/bash

# Script to set up SSH key-based authentication for the EC2 sensor
# This is the more secure long-term solution

# Load environment variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found!"
    exit 1
fi

# Define key file
KEY_FILE="$HOME/.ssh/ec2_sensor_key"

# Generate SSH key if it doesn't exist
if [ ! -f "$KEY_FILE" ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "ec2-sensor-automation"
else
    echo "SSH key already exists at $KEY_FILE"
fi

# Copy public key to sensor
echo "Copying public key to sensor..."
export SSHPASS=$SSH_PASSWORD
sshpass -e ssh-copy-id -i "${KEY_FILE}.pub" -o StrictHostKeyChecking=no $SSH_USERNAME@$SSH_HOST

# Test key-based authentication
echo "Testing key-based authentication..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no $SSH_USERNAME@$SSH_HOST "echo 'Key authentication successful!'"

# Create key-based SSH script
cat > "$SCRIPT_DIR/ssh_with_key.sh" << EOF
#!/bin/bash
# SSH with key-based authentication
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no $SSH_USERNAME@$SSH_HOST "\$@"
EOF

chmod +x "$SCRIPT_DIR/ssh_with_key.sh"

echo "SSH key setup complete!"
echo "You can now use ./ssh_with_key.sh for passwordless access"
