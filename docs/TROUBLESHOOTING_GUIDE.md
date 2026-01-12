# EC2 Sensor Testing Platform - Troubleshooting Guide

**Version**: 1.0.0
**Last Updated**: 2025-10-10

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Workflow Issues](#workflow-issues)
3. [Sensor Deployment Issues](#sensor-deployment-issues)
4. [Connectivity Issues](#connectivity-issues)
5. [Test Execution Issues](#test-execution-issues)
6. [MCP Integration Issues](#mcp-integration-issues)
7. [Performance Issues](#performance-issues)
8. [Common Error Messages](#common-error-messages)
9. [Getting Help](#getting-help)

---

## Quick Diagnostics

### Health Check Script

Run this script first to diagnose common issues:

```bash
#!/bin/bash
# health_check.sh

echo "=== EC2 Sensor Platform Health Check ==="
echo ""

# 1. VPN Connection
echo "1. VPN Connection:"
if tailscale status >/dev/null 2>&1; then
    echo "   OK: Tailscale VPN connected"
else
    echo "   FAIL: Tailscale VPN not connected"
    echo "   Fix: Run 'tailscale up'"
fi
echo ""

# 2. AWS Credentials
echo "2. AWS Credentials:"
if aws sts get-caller-identity >/dev/null 2>&1; then
    echo "   OK: AWS credentials configured"
    aws sts get-caller-identity | jq -r '"   Account: \(.Account), User: \(.Arn)"'
else
    echo "   FAIL: AWS credentials not configured"
    echo "   Fix: Run 'aws configure'"
fi
echo ""

# 3. Required Tools
echo "3. Required Tools:"
for tool in jq curl ssh python3 aws; do
    if command -v $tool >/dev/null 2>&1; then
        version=$(command $tool --version 2>&1 | head -1)
        echo "   OK: $tool: $version"
    else
        echo "   FAIL: $tool: Not installed"
        echo "   Fix: Install $tool"
    fi
done
echo ""

# 4. Environment Configuration
echo "4. Environment Configuration:"
if [ -f ".env" ]; then
    echo "   OK: .env file exists"
    if grep -q "AWS_REGION" .env; then
        echo "   OK: AWS_REGION configured"
    else
        echo "   WARN: AWS_REGION not set"
    fi
else
    echo "   FAIL: .env file missing"
    echo "   Fix: Copy .env.example to .env"
fi
echo ""

# 5. Sensor State
echo "5. Sensor State:"
if [ -f ".sensor_state" ]; then
    echo "   OK: Sensor state file exists"
    sensor_ip=$(jq -r '.sensor_ip' .sensor_state 2>/dev/null || echo "N/A")
    stack_name=$(jq -r '.stack_name' .sensor_state 2>/dev/null || echo "N/A")
    echo "   Sensor IP: $sensor_ip"
    echo "   Stack: $stack_name"
else
    echo "   INFO: No active sensor"
fi
echo ""

# 6. Recent Logs
echo "6. Recent Errors in Logs:"
if [ -d "logs" ]; then
    recent_errors=$(grep -r "ERROR" logs/*.log 2>/dev/null | tail -5)
    if [ -n "$recent_errors" ]; then
        echo "   WARN: Recent errors found:"
        echo "$recent_errors" | sed 's/^/   /'
    else
        echo "   OK: No recent errors"
    fi
else
    echo "   INFO: No logs directory"
fi
echo ""

echo "=== Health Check Complete ==="
```

Save as `health_check.sh` and run:
```bash
chmod +x health_check.sh
./health_check.sh
```

---

## Workflow Issues

### Issue: Workflow Won't Start

**Symptoms**:
- Workflow exits immediately
- "Command not found" errors
- Permission denied errors

**Diagnosis**:
```bash
# Check if workflow is executable
ls -l workflows/reproduce_jira_issue.sh

# Check file permissions
stat workflows/reproduce_jira_issue.sh
```

**Solutions**:

1. **Make workflow executable**:
   ```bash
   chmod +x workflows/*.sh
   ```

2. **Check shebang line**:
   ```bash
   head -1 workflows/reproduce_jira_issue.sh
   # Should be: #!/bin/bash
   ```

3. **Verify bash is available**:
   ```bash
   which bash
   # Should output: /bin/bash or /usr/bin/bash
   ```

---

### Issue: Workflow Hangs or Freezes

**Symptoms**:
- Workflow stops responding
- No progress for >10 minutes
- Cannot interrupt with Ctrl+C

**Diagnosis**:
```bash
# Check workflow state
cat .workflow_state/reproduce_jira_issue_*.state

# Check running processes
ps aux | grep workflow

# Check sensor connectivity
ping <sensor-ip>
```

**Solutions**:

1. **Check VPN connection**:
   ```bash
   tailscale status
   # If disconnected: tailscale up
   ```

2. **Check sensor status**:
   ```bash
   ./sensor_lifecycle.sh status
   ```

3. **Kill hung workflow**:
   ```bash
   # Find process ID
   ps aux | grep reproduce_jira_issue

   # Kill process
   kill -9 <PID>

   # Clean up state
   rm .workflow_state/reproduce_jira_issue_*.state
   ```

4. **Resume from last successful step**:
   ```bash
   ./workflows/reproduce_jira_issue.sh CORE-5432 --resume
   ```

---

### Issue: Dry-Run Mode Fails

**Symptoms**:
- Dry-run exits with error
- "Invalid option" errors

**Solutions**:

1. **Verify syntax**:
   ```bash
   ./workflows/reproduce_jira_issue.sh --help
   ```

2. **Check option placement**:
   ```bash
   # Correct:
   ./workflows/reproduce_jira_issue.sh CORE-5432 --dry-run

   # Incorrect:
   ./workflows/reproduce_jira_issue.sh --dry-run CORE-5432
   ```

---

## Sensor Deployment Issues

### Issue: Sensor Deployment Fails

**Symptoms**:
- "Sensor deployment failed" error
- CloudFormation stack creation fails
- Timeout waiting for sensor

**Diagnosis**:
```bash
# Check CloudFormation stacks
aws cloudformation describe-stacks \
  --query 'Stacks[?StackName!=`null`].[StackName,StackStatus]' \
  --output table

# Check specific stack
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --max-items 10

# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ec2sensor" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]'
```

**Solutions**:

1. **Check AWS quotas**:
   ```bash
   # Check EC2 instance quota
   aws service-quotas get-service-quota \
     --service-code ec2 \
     --quota-code L-1216C47A

   # Check if at limit
   aws ec2 describe-instances --query 'Reservations[].Instances | length'
   ```

2. **Check IAM permissions**:
   ```bash
   # Verify you can create CloudFormation stacks
   aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

   # If fails: Check IAM permissions
   ```

3. **Review CloudFormation template**:
   ```bash
   # Validate template
   aws cloudformation validate-template \
     --template-body file://cloudformation/sensor-template.yaml
   ```

4. **Delete failed stack and retry**:
   ```bash
   # Delete failed stack
   aws cloudformation delete-stack --stack-name <stack-name>

   # Wait for deletion
   aws cloudformation wait stack-delete-complete --stack-name <stack-name>

   # Retry deployment
   ./sensor_lifecycle.sh create
   ```

---

### Issue: Sensor Not Responding After Deployment

**Symptoms**:
- Sensor deployed but cannot connect
- SSH times out
- Sensor status shows "initializing" for >10 minutes

**Diagnosis**:
```bash
# Check sensor state
./sensor_lifecycle.sh status

# Try direct ping
ping <sensor-ip>

# Check security groups
aws ec2 describe-security-groups \
  --group-ids <security-group-id>
```

**Solutions**:

1. **Wait for full initialization** (can take 5-10 minutes):
   ```bash
   # Monitor sensor status
   watch -n 10 './sensor_lifecycle.sh status'
   ```

2. **Check security group rules**:
   ```bash
   # Ensure SSH (22) is open from your IP
   aws ec2 authorize-security-group-ingress \
     --group-id <sg-id> \
     --protocol tcp \
     --port 22 \
     --cidr <your-ip>/32
   ```

3. **Check VPN routing**:
   ```bash
   tailscale status
   tailscale netcheck
   ```

4. **Verify SSH key**:
   ```bash
   # Check key permissions
   ls -l <ssh-key-path>
   # Should be 600

   # Fix permissions
   chmod 600 <ssh-key-path>
   ```

---

## Connectivity Issues

### Issue: SSH Connection Refused

**Symptoms**:
- "Connection refused" error
- "Permission denied (publickey)" error
- SSH hangs and times out

**Diagnosis**:
```bash
# Test SSH with verbose output
ssh -vvv -i <key> admin@<sensor-ip>

# Check SSH service on sensor
./sensor_lifecycle.sh status | grep -i ssh

# Verify SSH key
ssh-keygen -l -f <key>
```

**Solutions**:

1. **Verify SSH key**:
   ```bash
   # Check key format
   file <ssh-key-path>
   # Should be: PEM RSA private key

   # Regenerate key if corrupted
   ./sensor_lifecycle.sh create --new-key
   ```

2. **Check sensor security group**:
   ```bash
   # Get security group ID
   aws ec2 describe-instances \
     --instance-ids <instance-id> \
     --query 'Reservations[].Instances[].SecurityGroups[].GroupId'

   # Check rules
   aws ec2 describe-security-groups --group-ids <sg-id>
   ```

3. **Try different SSH user**:
   ```bash
   # Try 'admin' user
   ssh -i <key> admin@<sensor-ip>

   # Try 'ec2-user' user
   ssh -i <key> ec2-user@<sensor-ip>
   ```

---

### Issue: VPN Disconnected

**Symptoms**:
- Cannot reach sensor IPs
- "Network unreachable" errors
- Tailscale shows offline

**Solutions**:

1. **Reconnect VPN**:
   ```bash
   tailscale up
   ```

2. **Check Tailscale status**:
   ```bash
   tailscale status
   tailscale netcheck
   ```

3. **Restart Tailscale**:
   ```bash
   sudo systemctl restart tailscaled  # Linux
   # OR
   brew services restart tailscale    # macOS
   ```

---

## Test Execution Issues

### Issue: Test Case Not Found

**Symptoms**:
- "Test case not found" error
- "Cannot read YAML file" error

**Diagnosis**:
```bash
# List available test cases
ls -l testing/test_cases/*.yaml

# Verify test case exists
cat testing/test_cases/TEST-001.yaml
```

**Solutions**:

1. **Check test case path**:
   ```bash
   # Use full path
   ./testing/run_test.sh --test-case testing/test_cases/TEST-001.yaml

   # OR use test ID
   ./testing/run_test.sh --test-case TEST-001
   ```

2. **Validate YAML syntax**:
   ```bash
   python3 << 'EOF'
   import yaml
   with open('testing/test_cases/TEST-001.yaml') as f:
       yaml.safe_load(f)
   print("Valid YAML")
   EOF
   ```

---

### Issue: Test Execution Fails

**Symptoms**:
- Test steps fail unexpectedly
- "Command not found" in test
- Test hangs on specific step

**Diagnosis**:
```bash
# Check test logs
cat logs/test_runner_*.log

# Run test with debug logging
LOG_LEVEL=DEBUG ./testing/run_test.sh --test-case TEST-001

# Check sensor status during test
ssh admin@<sensor-ip> "sudo corelightctl sensor status"
```

**Solutions**:

1. **Verify packages installed**:
   ```bash
   ssh admin@<sensor-ip> "which tcpreplay jq curl"
   ```

2. **Check sensor services**:
   ```bash
   ssh admin@<sensor-ip> "sudo systemctl status corelight-softsensor"
   ```

3. **Re-run specific step**:
   ```bash
   # Edit test case to start from failing step
   ./testing/run_test.sh --test-case TEST-001 --step 3
   ```

4. **Increase timeout**:
   ```yaml
   # In test case YAML
   test_steps:
     - step: 3
       timeout: 600  # Increase from default
   ```

---

## MCP Integration Issues

### Issue: Obsidian Sync Fails

**Symptoms**:
- "MCP sync failed" warning
- "Cannot find Obsidian vault" error
- Notes not created in vault

**Diagnosis**:
```bash
# Check Obsidian vault path
echo $OBSIDIAN_VAULT_PATH
ls -la "$OBSIDIAN_VAULT_PATH"

# Check .env configuration
grep OBSIDIAN .env

# Test manual sync
python3 mcp_integration/obsidian/obsidian_connector.py
```

**Solutions**:

1. **Set vault path**:
   ```bash
   # In .env
   OBSIDIAN_VAULT_PATH=/path/to/obsidian/vault
   ```

2. **Create vault directories**:
   ```bash
   mkdir -p "$OBSIDIAN_VAULT_PATH/Test-Executions"
   mkdir -p "$OBSIDIAN_VAULT_PATH/JIRA"
   ```

3. **Check vault permissions**:
   ```bash
   ls -ld "$OBSIDIAN_VAULT_PATH"
   # Ensure you have write permissions
   ```

4. **Disable MCP sync** (if not needed):
   ```bash
   # In .env
   ENABLE_MCP_SYNC=false
   ```

---

### Issue: Memory Graph Connection Fails

**Symptoms**:
- "Memory MCP not available" error
- Graph queries fail

**Solutions**:

1. **Check MCP servers in Claude Code**:
   - Open Claude Code settings
   - Verify Memory MCP server is enabled

2. **Test connection**:
   ```bash
   python3 << 'EOF'
   from mcp_integration.memory.memory_connector import MemoryConnector
   memory = MemoryConnector()
   print("Connected to Memory MCP")
   EOF
   ```

---

### Issue: Exa Research Fails

**Symptoms**:
- "Exa search failed" error
- No research results

**Solutions**:

1. **Check Exa MCP**:
   - Verify Exa MCP server in Claude Code settings

2. **Bypass Exa** (non-critical):
   - Exa failures are logged as warnings
   - Workflow continues without research

---

## Performance Issues

### Issue: Workflows Running Slowly

**Symptoms**:
- Workflows take >30 minutes
- Steps timeout frequently

**Solutions**:

1. **Check network latency**:
   ```bash
   ping -c 10 <sensor-ip>
   # Look for high latency or packet loss
   ```

2. **Use larger instance types**:
   ```bash
   # For performance testing
   ./workflows/performance_baseline.sh "28.5.0" --instance-type c6in.4xlarge
   ```

3. **Reduce test duration**:
   ```bash
   ./workflows/performance_baseline.sh "28.5.0" --duration 60
   ```

---

### Issue: Sensor Running Slow

**Symptoms**:
- High CPU usage
- Commands slow to respond
- Tests timeout

**Diagnosis**:
```bash
# Check CPU and memory
ssh admin@<sensor-ip> "top -bn1 | head -20"

# Check disk I/O
ssh admin@<sensor-ip> "iostat -x 1 5"

# Check disk space
ssh admin@<sensor-ip> "df -h"
```

**Solutions**:

1. **Restart sensor services**:
   ```bash
   ssh admin@<sensor-ip> "sudo systemctl restart corelight-softsensor"
   ```

2. **Clean up disk space**:
   ```bash
   ssh admin@<sensor-ip> << 'EOF'
   # Clean old PCAPs
   sudo find /var/corelight/pcap -name "*.pcap" -mtime +7 -delete

   # Clean logs
   sudo journalctl --vacuum-time=7d
   EOF
   ```

3. **Use larger instance**:
   ```bash
   # Delete current sensor
   ./sensor_lifecycle.sh delete

   # Deploy with larger instance
   ./sensor_lifecycle.sh create --instance-type m6a.4xlarge
   ```

---

## Common Error Messages

### "Command not found"

**Cause**: Required tool not installed

**Solution**:
```bash
# Install missing tool
brew install <tool>        # macOS
# OR
sudo yum install <tool>    # Linux
```

---

### "Permission denied"

**Cause**: Insufficient file permissions

**Solution**:
```bash
# Fix script permissions
chmod +x workflows/*.sh

# Fix SSH key permissions
chmod 600 <ssh-key-path>
```

---

### "Stack already exists"

**Cause**: Previous sensor deployment still active

**Solution**:
```bash
# Delete existing stack
./sensor_lifecycle.sh delete

# OR use different stack name
./sensor_lifecycle.sh create --stack-name my-unique-stack
```

---

### "Workflow state corrupted"

**Cause**: Interrupted workflow left invalid state

**Solution**:
```bash
# Remove corrupted state
rm .workflow_state/*.state

# Start fresh
./workflows/reproduce_jira_issue.sh CORE-5432
```

---

### "YAML parse error"

**Cause**: Invalid YAML syntax in test case

**Solution**:
```bash
# Validate YAML
python3 -c "import yaml; yaml.safe_load(open('test.yaml'))"

# Common issues:
# - Missing quotes around strings with colons
# - Incorrect indentation
# - Missing required fields
```

---

## Getting Help

### Debug Checklist

Before asking for help, run through this checklist:

- [ ] Run health check script
- [ ] Check recent logs for errors
- [ ] Try dry-run mode
- [ ] Verify VPN connection
- [ ] Check AWS credentials
- [ ] Review CloudFormation events
- [ ] Test SSH connection manually
- [ ] Check workflow state files

### Gathering Debug Information

```bash
# Create debug bundle
tar -czf debug-bundle-$(date +%Y%m%d).tar.gz \
    logs/ \
    .workflow_state/ \
    .sensor_state \
    .env

# Share debug bundle with team
```

### Contact Information

- **Project Documentation**: `docs/`
- **User Guide**: `docs/USER_GUIDE.md`
- **Developer Guide**: `docs/DEVELOPER_GUIDE.md`
- **API Reference**: `docs/API_REFERENCE.md`

---

**Version**: 1.0.0
**Last Updated**: 2025-10-10
