# LDAP-Replication-Architecture-Setup-Guide
This document provides a **step-by-step guide** to create a production-ready LDAP cluster with:

- 1 Master (Read/Write)
- 2 Replicas (Read-Only)
- 1 HAProxy Load Balancer
- Proper domain: `dc=innspark,dc=in`

---
```markdown
# LDAP Architecture Diagram

```
                    +--------------------------------------------------+
                    |                APPLICATION SERVER                |
                    |  (Your web app, authentication system, etc.)     |
                    +--------------------------------------------------+
                                        |
                                        | LDAP Requests
                                        ↓
                    +--------------------------------------------------+
                    |                HAProxy LOAD BALANCER             |
                    |  IP: 192.168.192.162                            |
                    |  Port 389 → Master (Writes)                     |
                    |  Port 390 → Replicas (Reads)                    |
                    +--------------------------------------------------+
                                        |
          +-----------------------------+-----------------------------+
          |                                                           |
          | (Port 389 - Write Traffic)                                | (Port 390 - Read Traffic)
          ↓                                                           ↓
+---------------------+                                   +---------------------+
|   MASTER SERVER     |                                   |   REPLICA SERVERS   |
|   IP: 192.168.192.157|                                   |                     |
|   Role: Read/Write  |                                   |  +----------------+ |
|   Database: Primary |                                   |  | Replica 1      | |
|                     |                                   |  | IP: 192.168.192.158| |
|                     |                                   |  | Role: Read-Only | |
|                     |                                   |  +----------------+ |
|                     |                                   |          |          |
|                     |                                   |  +----------------+ |
|                     |                                   |  | Replica 2      | |
|                     |                                   |  | IP: 192.168.192.159| |
|                     |                                   |  | Role: Read-Only | |
+---------------------+                                   |  +----------------+ |
          ↑                                                           |
          |                                                           |
          +------------------- REPLICATION TRAFFIC -------------------+
                              (Port 389, syncprov → syncrepl)
```


## 🖥️ **VM Requirements**

| VM Name | IP Address | Role | OS |
| --- | --- | --- | --- |
| `ldap-master` | `192.168.192.157` | Master (RW) | Ubuntu 22.04 |
| `ldap-r1` | `192.168.192.158` | Replica 1 (RO) | Ubuntu 22.04 |
| `ldap-r2` | `192.168.192.159` | Replica 2 (RO) | Ubuntu 22.04 |
| `ldap-lb` | `192.168.192.162` | Load Balancer | Ubuntu 22.04 |

---

## 🔧 **Part 1: Master Server Setup (`192.168.192.157`)**

### Step 1.1: Install and Configure OpenLDAP

```bash
# Install packages
sudo apt update
sudo apt install slapd ldap-utils -y

# Reconfigure with proper domain
sudo dpkg-reconfigure slapd

```

**Configuration Answers:**

- Omit OpenLDAP server configuration? → **No**
- DNS domain name: → **`innspark.in`**
- Organization name: → **`Innspark`**
- Administrator password: → **`password`**
- Database backend: → **`MDB`**
- Remove database when purged? → **No**
- Move old database? → **Yes**
- Allow LDAPv2? → **No**

### Step 1.2: Load syncprov Module

**File: `load-syncprov.ldif`**

```
# Load the syncprov module to enable replication provider functionality
# This module provides the syncprov overlay
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov

```

Apply:

```bash
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f load-syncprov.ldif

```

### Step 1.3: Enable syncprov Overlay

**File: `enable-syncprov.ldif`**

```
# Create syncprov overlay on the main database
# This enables the master to serve replication data to consumers
# Uses minimal config to avoid objectClass issues
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov

```

Apply:

```bash
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f enable-syncprov.ldif

```

### Step 1.4: Create Replicator User

**File: `replicator.ldif`**

```
# Service account for replicas to authenticate and sync data
# Uses plain text password (OpenLDAP auto-hashes it)
# DN: cn=replicator,dc=innspark,dc=in
dn: cn=replicator,dc=innspark,dc=in
objectClass: simpleSecurityObject    # Allows userPassword attribute
objectClass: organizationalRole     # Generic role objectClass
cn: replicator                      # Common name
description: LDAP replication user  # Description
userPassword: password              # Plain text (will be hashed automatically)

```

Apply:

```bash
ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password -f replicator.ldif

```

### Step 1.5: Configure Replication ACLs

**File: `acl-replicator.ldif`**

```
# Access Control Lists for replication
# Rule {0}: Password security - only admin can modify passwords
# Rule {1}: Replication access - replicator can read everything, admin can write, others can read
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,dc=innspark,dc=in" write by anonymous auth by self write by * none
-
add: olcAccess
olcAccess: {1}to * by dn="cn=replicator,dc=innspark,dc=in" read by dn="cn=admin,dc=innspark,dc=in" write by * read

```

Apply:

```bash
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f acl-replicator.ldif

```

### Step 1.6: Verify Master Setup

```bash
# Test replicator authentication
ldapwhoami -x -D "cn=replicator,dc=innspark,dc=in" -w password -H ldap://192.168.192.157

# Expected output: dn:cn=replicator,dc=innspark,dc=in

```

---

## 🔧 **Part 2: Replica Server Setup (`192.168.192.158` and `192.168.192.159`)**

### Step 2.1: Install OpenLDAP (Same on both replicas)

```bash
# Install packages (use any password during setup - it will be overwritten)
sudo apt update
sudo apt install slapd ldap-utils -y

```

### Step 2.2: Configure as Consumer

**File: `consumer-config.ldif`**

```
# Configure this server as a replication consumer
# Unique Server ID for this replica (r1=2, r2=3)
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 2  # Use 3 for the second replica

# Set the correct base DN to match master
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

# Set root DN to match master
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

# Set root password to match master
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

# Configure syncrepl to pull from master
# rid=001: unique replication ID
# provider: master server IP
# binddn: replicator user from master
# credentials: replicator password
# searchbase: base DN to replicate
# type=refreshAndPersist: real-time sync with persistent connection
# retry: retry strategy if connection fails
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://192.168.192.157:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

# Ensure this is not a mirror mode (read-only consumer)
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE

```

### Step 2.3: Apply Configuration (Same on both replicas)

```bash
# Stop slapd to clear database
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*

# Start slapd to apply config
sudo systemctl start slapd

# Apply consumer configuration
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f consumer-config.ldif

# Clear database again for fresh sync from master
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

> Note for second replica (192.168.192.159): Change olcServerID: 2 to olcServerID: 3 in the LDIF file.
> 

### Step 2.4: Verify Replica Setup

```bash
# Wait 20-30 seconds for initial sync
sleep 30

# Verify base entry exists
ldapsearch -x -b "dc=innspark,dc=in" -s base

# Verify replicator user exists
ldapsearch -x -b "dc=innspark,dc=in" "(cn=replicator)" dn

# Verify write operations are blocked
ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=test-replica,dc=innspark,dc=in
objectClass: organizationalRole
cn: test-replica
EOF
# Expected: ldap_add: Server is unwilling to perform (53)

```

---

## 🔧 **Part 3: Load Balancer Setup (`192.168.192.162`)**

### Step 3.1: Install HAProxy

```bash
sudo apt update
sudo apt install haproxy -y
sudo systemctl enable haproxy

```

### Step 3.2: Configure HAProxy

**File: `/etc/haproxy/haproxy.cfg`**

```
# Global HAProxy configuration
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # SSL settings (not used for LDAP but good to have)
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

# Default settings for all frontends/backends
defaults
    log global
    mode tcp                    # LDAP uses TCP (not HTTP)
    option tcplog              # Log TCP connection details
    option dontlognull         # Don't log null connections
    timeout connect 5000       # 5s connection timeout
    timeout client 50000       # 50s client timeout
    timeout server 50000       # 50s server timeout

# Frontend for LDAP WRITE operations (port 389)
# Routes all traffic to master only
frontend ldap_write
    bind *:389                 # Listen on standard LDAP port
    mode tcp
    default_backend ldap_master

# Backend for master server (write operations)
backend ldap_master
    mode tcp
    balance first              # Always use first available server (master only)
    server ldap-m1 192.168.192.157:389 check  # Master server with health check

# Frontend for LDAP READ operations (port 390)
# Routes traffic to replicas for read scaling
frontend ldap_read
    bind *:390                 # Custom port for read operations
    mode tcp
    default_backend ldap_replicas

# Backend for replica servers (read operations)
backend ldap_replicas
    mode tcp
    balance roundrobin        # Distribute reads evenly across replicas
    server ldap-r1 192.168.192.158:389 check  # Replica 1 with health check
    server ldap-r2 192.168.192.159:389 check  # Replica 2 with health check

```

### Step 3.3: Start and Verify HAProxy

```bash
# Test configuration
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Restart HAProxy
sudo systemctl restart haproxy

# Verify status
sudo systemctl status haproxy

```

---

## 🧪 **Part 4: End-to-End Testing**

### Test 4.1: Write Through Load Balancer

```bash
# Write to master via HAProxy port 389
ldapadd -x -H ldap://192.168.192.162:389 -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=write-test,dc=innspark,dc=in
objectClass: organizationalRole
cn: write-test
EOF

# Expected: adding new entry "cn=write-test,dc=innspark,dc=in"

```

### Test 4.2: Read Through Load Balancer

```bash
# Read from replicas via HAProxy port 390
ldapsearch -x -H ldap://192.168.192.162:390 -b "dc=innspark,dc=in" "(cn=write-test)" dn

# Expected: dn: cn=write-test,dc=innspark,dc=in

```

### Test 4.3: Verify Replication

```bash
# Check CSN consistency across all servers
echo "Master CSN:"
ldapsearch -x -b "dc=innspark,dc=in" -s base contextCSN

echo "Replica 1 CSN:"
ldapsearch -x -H ldap://192.168.192.158 -b "dc=innspark,dc=in" -s base contextCSN

echo "Replica 2 CSN:"
ldapsearch -x -H ldap://192.168.192.159 -b "dc=innspark,dc=in" -s base contextCSN

# All should have identical or very close CSN values

```

---

## 🔍 **Part 5: How Replication Works**

### Key Concepts:

- **CSN (Change Sequence Number)**: `{timestamp}#{serverID}#{operationID}` - uniquely identifies each change
- **syncprov**: Master overlay that tracks changes and serves them to consumers
- **syncrepl**: Consumer configuration that pulls changes from provider
- **refreshAndPersist**: Real-time replication mode with persistent connections
- **Session Log**: Circular buffer of recent changes for offline replica catch-up

### Data Flow:

1. Client writes to HAProxy:389 → Master
2. Master generates CSN and logs change in session log
3. Replicas (persistent connections) receive change notification
4. Replicas pull new data using replicator credentials
5. Replicas apply changes and update local CSN
6. Client reads from HAProxy:390 → Replicas (fresh data)

---

## 📋 **Summary of All Configuration Files**

| File | Purpose | Location |
| --- | --- | --- |
| `load-syncprov.ldif` | Load syncprov module on master | Master |
| `enable-syncprov.ldif` | Enable syncprov overlay on master | Master |
| `replicator.ldif` | Create replicator user on master | Master |
| `acl-replicator.ldif` | Set replication ACLs on master | Master |
| `consumer-config.ldif` | Configure replicas as consumers | Each Replica |
| `/etc/haproxy/haproxy.cfg` | Load balancer routing rules | Load Balancer |

---

## 🚀 **Application Usage**

Your applications should connect to:

- **Write Operations**: `ldap://192.168.192.162:389`
- **Read Operations**: `ldap://192.168.192.162:390`
- **Base DN**: `dc=innspark,dc=in`
- **Admin DN**: `cn=admin,dc=innspark,dc=in`
- **Password**: `password`

This architecture provides **read scaling**, **high availability**, and **automatic failover** for your LDAP infrastructure! 🎉
