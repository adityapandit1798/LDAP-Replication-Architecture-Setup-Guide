

# SSH Proxy Jump Configuration Guide

## Table of Contents
1. [Overview](#overview)
2. [What is SSH ProxyJump?](#what-is-ssh-proxyjump)
3. [Architecture](#architecture)
4. [SSH Config File Structure](#ssh-config-file-structure)
5. [Step-by-Step Setup](#step-by-step-setup)
6. [Configuration Examples](#configuration-examples)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)
9. [Adding a New LDAP Read Node](#adding-a-new-ldap-read-node)

---

## Overview

SSH ProxyJump (also known as SSH Jump Host or SSH Bastion Host) allows you to connect to remote servers that are not directly accessible from your local machine by "jumping" through an intermediate server (bastion/jump host).

### Use Case
In your setup:
- **Local Machine**: `ansible-ldap@ansible-ldao`
- **Bastion/Jump Hosts**: `mumbai-bastion-m1` (192.168.50.22), `mumbai-bastion-m2` (192.168.50.23)
- **Target Servers**: Multiple servers in the 10.10.10.x network (not directly accessible)

---

## What is SSH ProxyJump?

**ProxyJump** is an SSH feature that allows you to reach a target server through one or more intermediate servers.

### Without ProxyJump (Manual Method):
```bash
# Step 1: SSH to bastion
ssh sysadmin@192.168.50.22

# Step 2: From bastion, SSH to target
ssh sysadmin@10.10.10.6
```

### With ProxyJump (Automated):
```bash
# Single command - SSH automatically routes through bastion
ssh mumbai-m1
```

---

## Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Local Machine  │────────▶│  Bastion Host    │────────▶│  Target Server  │
│  ansible-ldao   │         │  192.168.50.22   │         │  10.10.10.6     │
│                 │         │  (Jump Host)     │         │  (mumbai-m1)    │
└─────────────────┘         └──────────────────┘         └─────────────────┘
     Your PC              Publicly Accessible         Private Network Server
```

**Network Flow:**
1. Your local machine connects to the bastion (192.168.50.22)
2. Bastion forwards the connection to the target server (10.10.10.6)
3. You interact with the target server as if directly connected

---

## SSH Config File Structure

### Location
- **Linux/Mac**: `~/.ssh/config`
- **Windows**: `C:\Users\YourUsername\.ssh\config`

### Basic Syntax

```ssh-config
Host <alias-name>
    HostName <actual-ip-or-hostname>
    User <username>
    IdentityFile <path-to-private-key>
    ProxyJump <jump-host-alias>
    Port <port-number>              # Optional, default is 22
    StrictHostKeyChecking <yes|no>  # Optional
```

---

## Step-by-Step Setup

### Step 1: Generate SSH Key Pair (if not exists)

```bash
# Check if you have an SSH key
ls -la ~/.ssh/id_*.pub

# If no key exists, generate one
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
# Or for ED25519 (more modern)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Press Enter to accept default location
# Press Enter twice for no passphrase (for automation)
```

### Step 2: Copy SSH Key to Bastion Host

```bash
# Copy your public key to the bastion server
ssh-copy-id -i ~/.ssh/id_rsa.pub sysadmin@192.168.50.22

# Enter password when prompted - this is the LAST time you'll need it
```

**What this does:**
- Copies your public key to `~/.ssh/authorized_keys` on the bastion
- Sets correct permissions automatically

### Step 3: Copy SSH Key to Target Servers

You need to do this for EACH target server you want to access:

```bash
# Method 1: Direct copy through bastion (if already configured)
ssh-copy-id -i ~/.ssh/id_rsa.pub -o ProxyJump=sysadmin@192.168.50.22 sysadmin@10.10.10.6

# Method 2: Manual copy (if above doesn't work)
# First, SSH to bastion
ssh sysadmin@192.168.50.22

# From bastion, copy key to target
ssh-copy-id -i ~/.ssh/id_rsa.pub sysadmin@10.10.10.6

# Exit bastion
exit
```

### Step 4: Create/Edit SSH Config File

```bash
# Create the config file if it doesn't exist
touch ~/.ssh/config
chmod 600 ~/.ssh/config

# Edit the file
nano ~/.ssh/config
# or
vim ~/.ssh/config
```

### Step 5: Add Bastion Host Configuration

```ssh-config
# ============================
# Bastion/Jump Host
# ============================
Host mumbai-bastion-m1
    HostName 192.168.50.22
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    StrictHostKeyChecking no
```

**Parameter Explanations:**
- `Host`: Alias name you'll use (e.g., `ssh mumbai-bastion-m1`)
- `HostName`: Actual IP address or FQDN
- `User`: Username on the remote server
- `IdentityFile`: Path to your private SSH key
- `StrictHostKeyChecking no`: Automatically accepts new host keys (use with caution)

### Step 6: Add Target Server Configuration

```ssh-config
# ============================
# Target Server (through bastion)
# ============================
Host mumbai-m1
    HostName 10.10.10.6
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1
```

**Key Addition:**
- `ProxyJump mumbai-bastion-m1`: Routes connection through the bastion

### Step 7: Test the Connection

```bash
# Test bastion connection
ssh mumbai-bastion-m1

# Test target server through bastion
ssh mumbai-m1
```

If configured correctly, **both should connect without asking for a password!**

---

## Configuration Examples

### Example 1: Simple ProxyJump

```ssh-config
# Bastion
Host bastion
    HostName 192.168.50.22
    User sysadmin
    IdentityFile ~/.ssh/id_rsa

# Target through bastion
Host server1
    HostName 10.10.10.6
    User sysadmin
    IdentityFile ~/.ssh/id_rsa
    ProxyJump bastion
```

### Example 2: Multiple Bastions (High Availability)

```ssh-config
# Primary Bastion
Host mumbai-bastion-m1
    HostName 192.168.50.22
    User sysadmin
    IdentityFile ~/.ssh/id_rsa

# Backup Bastion
Host mumbai-bastion-m2
    HostName 192.168.50.23
    User sysadmin
    IdentityFile ~/.ssh/id_rsa

# Target can use either bastion
Host mumbai-m1
    HostName 10.10.10.6
    User sysadmin
    IdentityFile ~/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1  # Change to m2 if m1 is down
```

### Example 3: Multi-Hop (Chained Jumps)

```ssh-config
# First jump
Host bastion1
    HostName 203.0.113.10
    User admin

# Second jump
Host bastion2
    HostName 10.0.1.5
    User admin
    ProxyJump bastion1

# Final target
Host final-server
    HostName 172.16.0.10
    User admin
    ProxyJump bastion1,bastion2  # Chain multiple jumps
```

### Example 4: Wildcard Configuration

```ssh-config
# Apply to all mumbai servers
Host mumbai-*
    User sysadmin
    IdentityFile ~/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1
    StrictHostKeyChecking no

# Specific servers
Host mumbai-m1
    HostName 10.10.10.6

Host mumbai-m2
    HostName 10.10.10.7
```

### Example 5: Your Complete Current Setup

```ssh-config
# ============================
# Mumbai Bastions
# ============================
Host mumbai-bastion-m1
    HostName 192.168.50.22
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    StrictHostKeyChecking no

Host mumbai-bastion-m2
    HostName 192.168.50.23
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    StrictHostKeyChecking no

# ============================
# Mumbai Masters
# ============================
Host mumbai-m1
    HostName 10.10.10.6
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

Host mumbai-m2
    HostName 10.10.10.7
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

# ============================
# Mumbai Readers
# ============================
Host mumbai-r1
    HostName 10.10.10.8
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

Host mumbai-r2
    HostName 10.10.10.9
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

Host mumbai-r3
    HostName 10.10.10.10
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

Host mumbai-r4
    HostName 10.10.10.11
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

# ============================
# Mumbai HAProxy
# ============================
Host mumbai-haproxy
    HostName 10.10.10.5
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1

# ============================
# Mumbai Readers - New Node
# ============================
Host mumbai-read-5
    HostName 10.10.10.12
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    ProxyJump mumbai-bastion-m1
```

---

## Troubleshooting

### Issue 1: Still Asking for Password

**Problem**: SSH still prompts for password despite key setup

**Solutions:**

1. **Check if key is copied to ALL hosts:**
   ```bash
   # Verify on bastion
   ssh mumbai-bastion-m1 'cat ~/.ssh/authorized_keys'
   
   # Verify on target
   ssh -J mumbai-bastion-m1 sysadmin@10.10.10.6 'cat ~/.ssh/authorized_keys'
   ```

2. **Check SSH config points to correct key:**
   ```bash
   cat ~/.ssh/config | grep -A 3 "mumbai-m1"
   # Ensure IdentityFile matches the key you copied
   ```

3. **Verify permissions on remote server:**
   ```bash
   ssh mumbai-m1
   ls -la ~/.ssh/
   # Should show:
   # drwx------ .ssh (700)
   # -rw------- authorized_keys (600)
   
   # Fix if needed:
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

4. **Check SSH daemon config on remote server:**
   ```bash
   ssh mumbai-m1
   sudo grep "PubkeyAuthentication" /etc/ssh/sshd_config
   # Should be: PubkeyAuthentication yes
   
   # If changed, restart SSH:
   sudo systemctl restart sshd
   ```

### Issue 2: Connection Timeout

**Problem**: SSH connection times out

**Solutions:**

1. **Test bastion connectivity:**
   ```bash
   ping 192.168.50.22
   telnet 192.168.50.22 22
   ```

2. **Add timeout settings to config:**
   ```ssh-config
   Host *
       ServerAliveInterval 60
       ServerAliveCountMax 3
       ConnectTimeout 10
   ```

### Issue 3: Host Key Verification Failed

**Problem**: Warning about host key change

**Solutions:**

1. **Remove old host key:**
   ```bash
   ssh-keygen -R 192.168.50.22
   ssh-keygen -R 10.10.10.6
   ```

2. **Or disable strict checking (less secure):**
   ```ssh-config
   Host *
       StrictHostKeyChecking no
       UserKnownHostsFile /dev/null
   ```

### Issue 4: Wrong Key Being Used

**Problem**: SSH offers wrong key file

**Debug:**
```bash
# See which keys are being offered
ssh -vv mumbai-m1 2>&1 | grep "Offering\|Authenticat"
```

**Solution:**
```ssh-config
# Explicitly specify the key and disable all others
Host mumbai-m1
    HostName 10.10.10.6
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/id_rsa
    IdentitiesOnly yes  # Only use specified key
    ProxyJump mumbai-bastion-m1
```

### Issue 5: Permission Denied (publickey)

**Debug verbose output:**
```bash
ssh -vvv mumbai-m1
```

**Common causes:**
- Wrong username
- Key not in authorized_keys
- Wrong permissions on ~/.ssh or authorized_keys
- SELinux blocking (on RHEL/CentOS)

**Fix SELinux issue:**
```bash
ssh mumbai-m1
sudo restorecon -R ~/.ssh
```

---

## Best Practices

### 1. Key Management

```bash
# Use strong keys
ssh-keygen -t ed25519 -a 100  # Modern, secure

# Or RSA with 4096 bits
ssh-keygen -t rsa -b 4096

# Use different keys for different environments
ssh-keygen -f ~/.ssh/production_key -t ed25519
ssh-keygen -f ~/.ssh/staging_key -t ed25519
```

### 2. Config Organization

```ssh-config
# Group by environment or location
# ============================
# PRODUCTION - Mumbai
# ============================
Host prod-mumbai-*
    User sysadmin
    IdentityFile ~/.ssh/production_key
    ProxyJump mumbai-bastion-m1

# ============================
# STAGING
# ============================
Host staging-*
    User admin
    IdentityFile ~/.ssh/staging_key
```

### 3. Security Settings

```ssh-config
# Apply to all hosts
Host *
    # Keep connections alive
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
    # Disable password authentication
    PasswordAuthentication no
    
    # Use only specified keys
    IdentitiesOnly yes
    
    # Security options
    HashKnownHosts yes
    
    # Compression for slow links
    Compression yes
```

### 4. Use SSH Agent for Key Management

```bash
# Start SSH agent
eval $(ssh-agent)

# Add your key
ssh-add ~/.ssh/id_rsa

# Verify loaded keys
ssh-add -l

# Now SSH won't ask for key passphrase
```

### 5. Backup Your Keys and Config

```bash
# Backup SSH directory
tar -czf ssh_backup_$(date +%Y%m%d).tar.gz ~/.ssh/

# Store securely (NOT in version control!)
```

### 6. Logging and Auditing

```ssh-config
# Enable detailed logging for debugging
Host *
    LogLevel INFO
```

```bash
# View SSH logs
sudo tail -f /var/log/auth.log    # Ubuntu/Debian
sudo tail -f /var/log/secure      # RHEL/CentOS
```

---

## Advanced Usage

### SCP Through ProxyJump

```bash
# Copy file TO remote server
scp -o ProxyJump=mumbai-bastion-m1 file.txt sysadmin@10.10.10.6:/tmp/

# Or using config alias
scp file.txt mumbai-m1:/tmp/

# Copy file FROM remote server
scp mumbai-m1:/tmp/file.txt ./
```

### SFTP Through ProxyJump

```bash
# Interactive SFTP session
sftp -o ProxyJump=mumbai-bastion-m1 sysadmin@10.10.10.6

# Or using config alias
sftp mumbai-m1
```

### Port Forwarding Through ProxyJump

```bash
# Forward local port 8080 to remote port 80
ssh -L 8080:localhost:80 mumbai-m1

# Access in browser: http://localhost:8080
```

### Run Command Remotely

```bash
# Single command
ssh mumbai-m1 'uptime'

# Multiple commands
ssh mumbai-m1 'uptime && df -h && free -m'

# Interactive script
ssh mumbai-m1 'bash -s' < local_script.sh
```

---

## Testing Checklist

After setup, verify everything works:

- [ ] Can SSH to bastion without password: `ssh mumbai-bastion-m1`
- [ ] Can SSH to target without password: `ssh mumbai-m1`
- [ ] Can copy files: `scp test.txt mumbai-m1:/tmp/`
- [ ] Can run remote commands: `ssh mumbai-m1 'hostname'`
- [ ] Ansible connectivity works: `ansible mumbai-m1 -m ping`

---

## Quick Reference Commands

```bash
# Test connection with verbose output
ssh -vv hostname

# Test specific key
ssh -i ~/.ssh/id_rsa hostname

# Bypass config file
ssh -F /dev/null user@host

# Test ProxyJump manually
ssh -J bastion-user@bastion-host target-user@target-host

# Check which config is being used
ssh -G hostname

# List loaded SSH keys
ssh-add -l

# Remove all loaded keys
ssh-add -D

# Reload SSH config (reconnect)
# No command needed - just start new connection
```

---

## Adding a New LDAP Read Node

This section covers the complete process of adding a new LDAP read node to your existing cluster.

### Overview

When adding a new read node, you need to:
1. Add the node to the database
2. Configure SSH access
3. Update inventory
4. Install and configure LDAP
5. Update replication chains on existing nodes

### Prerequisites

- Access to the `ldap_automation` database
- SSH access to bastion hosts
- Private IP available for the new node
- Ansible control node access

### Step 1: Add Node to Database

Connect to the database and insert the new node record:

```bash
# Connect to MySQL
mysql -u ldap_automation -p'LdapAuto@2025!' -h localhost ldap_automation

# Insert new read node (example: mumbai-read-5 with IP 10.10.10.12)
INSERT INTO nodes (
    node_name, 
    role, 
    region, 
    ssh_host, 
    ldap_host, 
    is_writer, 
    is_reader, 
    is_bootstrap, 
    server_id, 
    created_at
) VALUES (
    'mumbai-read-5', 
    'read', 
    'mumbai', 
    '10.10.10.12', 
    '10.10.10.12', 
    0, 
    1, 
    0, 
    0, 
    NOW()
);

# Verify the insertion
SELECT * FROM nodes WHERE node_name = 'mumbai-read-5';

# Exit MySQL
exit
```

### Step 2: Configure SSH Access

#### 2.1 Add SSH Config Entry

Add the new node to your `~/.ssh/config` file:

```ssh-config
# ============================
# Mumbai Readers - New Node
# ============================
Host mumbai-read-5
    HostName 10.10.10.12
    User sysadmin
    IdentityFile /home/ansible-ldap/.ssh/ansible_ldap
    ProxyJump mumbai-bastion-m1
    StrictHostKeyChecking no
```

#### 2.2 Test SSH Connectivity

```bash
# Test SSH connection to the new node
ssh mumbai-read-5

# Should connect via: Ansible Host → mumbai-bastion-m1 → mumbai-read-5
# If successful, you should see the command prompt of the new node
```

#### 2.3 Copy SSH Key to New Node

If SSH key authentication is not working:

```bash
# Copy SSH key to the new node through bastion
ssh-copy-id -i ~/.ssh/ansible_ldap.pub -o ProxyJump=mumbai-bastion-m1 sysadmin@10.10.10.12

# Or manually:
# 1. SSH to bastion
ssh mumbai-bastion-m1

# 2. From bastion, copy key to new node
ssh-copy-id -i ~/.ssh/ansible_ldap.pub sysadmin@10.10.10.12

# 3. Exit bastion
exit
```

### Step 3: Regenerate Dynamic Inventory

```bash
cd /home/ansible-ldap/ldap-cluster-new
source ~/mysql-venv/bin/activate
python3 inventory.py > inventory.txt

# Verify the new node appears in inventory
grep -A 10 "mumbai-read-5" inventory.txt
```

The new node should appear in:
- `_meta.hostvars` section
- `readers.hosts` array
- `ldap_nodes.hosts` array
- `mumbai.hosts` array

### Step 4: Install and Configure LDAP on New Node

```bash
# Run the LDAP installation on the new node only
ansible-playbook -i inventory.txt test_install.yml \
    -b \
    -e "ldap_suffix=dc=innspark,dc=in ldap_admin_password=password" \
    --limit mumbai-read-5

# Monitor the installation progress
# The role will:
# 1. Install OpenLDAP packages
# 2. Configure basic LDAP settings
# 3. Set up replication from local masters
# 4. Configure the node as a read-only replica
```

### Step 5: Verify New Node Configuration

#### 5.1 Check LDAP Service Status

```bash
# Test LDAP service on new node
ssh mumbai-read-5 'systemctl status slapd'

# Test LDAP connectivity
ssh mumbai-read-5 'ldapsearch -x -H ldap://localhost:389 -b "" -s base namingContexts'
```

#### 5.2 Test Replication Configuration

```bash
# Check syncrepl configuration on new node
ssh mumbai-read-5 'ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={1}mdb,cn=config" olcSyncrepl'

# Should show entries pointing to mumbai-m1 (10.10.10.6) and mumbai-m2 (10.10.10.7)
```

#### 5.3 Test Data Replication

```bash
# From any master, add a test entry
ssh mumbai-m1 'ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=test-replication,dc=innspark,dc=in
objectClass: person
cn: test-replication
sn: test
EOF'

# Verify it appears on the new reader
ssh mumbai-read-5 'ldapsearch -x -H ldap://localhost:389 -b "dc=innspark,dc=in" "(cn=test-replication)"'

# Clean up test entry
ssh mumbai-m1 'ldapdelete -x -D "cn=admin,dc=innspark,dc=in" -w password "cn=test-replication,dc=innspark,dc=in"'
```

### Step 6: Final Verification and Monitoring

#### 6.1 Ansible Connectivity Test

```bash
# Test Ansible can reach all nodes
ansible -i inventory.txt all -m ping --limit mumbai

# Test specifically the new node
ansible -i inventory.txt mumbai-read-5 -m ping
```

#### 6.2 Cluster Health Check

```bash
# Check all LDAP nodes are responding
ansible -i inventory.txt ldap_nodes -m shell -a 'systemctl is-active slapd'

# Check replication status across all nodes
ansible -i inventory.txt readers -m shell -a 'ldapsearch -x -H ldap://localhost:389 -b "dc=innspark,dc=in" "(objectClass=*)" | grep -c "^dn:"'
```

### Quick Reference Commands

```bash
# Database insertion
mysql -u ldap_automation -p'LdapAuto@2025!' -h localhost ldap_automation -e "INSERT INTO nodes (node_name, role, region, ssh_host, ldap_host, is_writer, is_reader, is_bootstrap, server_id, created_at) VALUES ('mumbai-read-X', 'read', 'mumbai', '10.10.10.XX', '10.10.10.XX', 0, 1, 0, 0, NOW());"

# Regenerate inventory
cd /home/ansible-ldap/ldap-cluster-new && source ~/mysql-venv/bin/activate && python3 inventory.py > inventory.txt

# Install LDAP on new node
ansible-playbook -i inventory.txt test_install.yml -b -e "ldap_suffix=dc=innspark,dc=in ldap_admin_password=password" --limit mumbai-read-X

# Test replication
ansible -i inventory.txt mumbai-read-X -m shell -a 'ldapsearch -x -H ldap://localhost:389 -b "dc=innspark,dc=in" "(objectClass=*)" | head -5'
```

### Checklist for New Read Node

- [ ] Database entry created with correct parameters
- [ ] SSH configuration added to `~/.ssh/config`
- [ ] SSH connectivity tested and working
- [ ] Dynamic inventory regenerated and verified
- [ ] LDAP software installed successfully
- [ ] Replication configured from local masters
- [ ] Data replication tested and working
- [ ] Ansible connectivity verified
- [ ] Monitoring and backup systems updated
- [ ] Documentation updated

---

## Summary

**What You've Accomplished:**

1. ✅ SSH keys generated and distributed
2. ✅ Bastion hosts configured
3. ✅ ProxyJump configured for all target servers
4. ✅ Passwordless authentication working
5. ✅ Simplified access with host aliases

**Your Workflow Now:**

```bash
# Before (manual multi-step):
ssh sysadmin@192.168.50.22
# Then from bastion:
ssh sysadmin@10.10.10.6

# After (single command):
ssh mumbai-m1
# Done! ✨
```

**Key Files:**
- `~/.ssh/config` - SSH configuration
- `~/.ssh/id_rsa` - Private key (keep secure!)
- `~/.ssh/id_rsa.pub` - Public key (copy to servers)
- `~/.ssh/known_hosts` - Trusted host keys

---



## Fix: Configure Passwordless Sudo on mumbai-read-5 , do it for all nodes

SSH into the server and configure sudo:

```bash
ssh mumbai-read-5
```

Once logged in, run:

```bash
sudo visudo
```

Add this line at the end of the file:

```
sysadmin ALL=(ALL) NOPASSWD: ALL
```

Save and exit (Ctrl+X, then Y, then Enter if using nano, or `:wq` if using vi).

## Verify it works:

```bash
sudo whoami
```

This should return `root` without asking for a password.

```bash
exit
```

Now run your Ansible playbook again - it should work for `mumbai-read-5`!





## Additional Resources

- Official OpenSSH Documentation: https://www.openssh.com/manual.html
- ProxyJump Documentation: `man ssh_config`
- SSH Best Practices: https://infosec.mozilla.org/guidelines/openssh

---

**Document Version**: 1.0  
**Last Updated**: January 30, 2026  
**Author**: System Administrator  
**Environment**: Ubuntu 22.04 LTS