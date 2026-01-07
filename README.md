# LDAP-Replication-Architecture-Setup-Guide
This document provides a **step-by-step guide** to create a production-ready LDAP cluster with:

- 1 Master (Read/Write)
- 2 Replicas (Read-Only)
- 1 HAProxy Load Balancer
- Proper domain: `dc=innspark,dc=in`
```
Internal Sync (Pune):
Master 1 <----------> Master 2 (Master-Master Sync)
Master 2 -----------> Read 1 (Master-Read Sync)
Master 2 -----------> Read 2 (Master-Read Sync)
Master 1 -----------> Read 3 (Master-Read Sync)
Master 1 -----------> Read 4 (Master-Read Sync)

Internal Sync (Mumbai):
Master 1 <----------> Master 2 (Master-Master Sync)
Master 2 -----------> Read 1 (Master-Read Sync)
Master 2 -----------> Read 2 (Master-Read Sync)
Master 1 -----------> Read 3 (Master-Read Sync)
Master 2 -----------> Read 4 (Master-Read Sync)

Cross-Region Sync:
Pune Master 1 <----------> Mumbai Master 1 (ORCA Sync)
Pune Master 2 <----------> Mumbai Master 2 (ORCA Sync)

Failover Sync (Pune):
If Master 1 fails:
   Master 2 -----------> Read 1 (Master-Read Sync)
   Master 2 -----------> Read 2 (Master-Read Sync)
   Master 2 -----------> Read 3 (Master-Read Sync)
   Master 2 -----------> Read 4 (Master-Read Sync)

Failover Sync (Mumbai):
If Master 1 fails:
   Master 2 -----------> Read 1 (Master-Read Sync)
   Master 2 -----------> Read 2 (Master-Read Sync)
   Master 2 -----------> Read 3 (Master-Read Sync)
   Master 2 -----------> Read 4 (Master-Read Sync)

```

This guide provides **detailed, step-by-step instructions** for setting up an **OpenLDAP cluster** with 4 **write masters**, 8 **read replicas**, and an 2 **HAProxy load balancers in 2 regions** . It also includes instructions for **scaling** the cluster by adding more nodes.

### ✅ **Phase 1: Pune Region Setup**

### **Step 1: Configure Master 1 (`192.168.192.163`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

#configure this like this : 
sudo dpkg-reconfigure slapd
# During installation, you will be prompted:
# 1. Omit OpenLDAP server configuration? → No
# 2. DNS domain name? → innspark.in
# 3. Organization name? → innspark
# 4. Administrator password? → password
# 5. Confirm password? → password
# 7. Do you want the database to be removed when slapd is purged? → No
# 8. Move old database? → Yes
# 9. Allow LDAPv2 protocol? → No

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Set Server ID and Mirror Mode
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 1

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

# 5. Create replicator user
ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=replicator,dc=innspark,dc=in
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: replicator
userPassword: password
EOF

# 6. Set ACLs
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,dc=innspark,dc=in" write by anonymous auth by self write by * none
-
replace: olcAccess
olcAccess: {1}to * by dn="cn=replicator,dc=innspark,dc=in" read by dn="cn=admin,dc=innspark,dc=in" write by * read
EOF

# 7. Configure syncrepl to Master 2 (private IP)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://192.168.192.164:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

---

## ✅ **Masters Requiring `olcMirrorMode: TRUE`**

### **Set `olcMultiProvider` (and `olcMirrorMode` )**

```bash
# On each master server 
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMultiProvider
olcMultiProvider: TRUE
-
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

```

### **Step 2: Configure Master 2 (`192.168.192.164`)**

```bash
# 1. Install OpenLDAP (same as above)
sudo apt update
sudo apt install -y slapd ldap-utils
sudo dpkg-reconfigure slapd

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Set Server ID and Mirror Mode
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 2

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

# 5. Create replicator user
ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=replicator,dc=innspark,dc=in
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: replicator
userPassword: password
EOF

# 6. Set ACLs
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,dc=innspark,dc=in" write by anonymous auth by self write by * none
-
replace: olcAccess
olcAccess: {1}to * by dn="cn=replicator,dc=innspark,dc=in" read by dn="cn=admin,dc=innspark,dc=in" write by * read
EOF

# 7. Configure syncrepl to Master 1 (private IP)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://192.168.192.163:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

---

## ✅ **Masters Requiring `olcMirrorMode: TRUE`**

### **Set `olcMultiProvider` (and `olcMirrorMode` )**

```bash
# On each master server 
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMultiProvider
olcMultiProvider: TRUE
-
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

```

### **Step 3: Configure Read Nodes in Pune**

### **Read Node 1 (`192.168.192.165`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils
sudo dpkg-reconfigure slapd

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 1 to sync from both Pune Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 3

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://192.168.192.163:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://192.168.192.164:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

### **Read Node 2 (`192.168.192.166`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils
sudo dpkg-reconfigure slapd

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 2 to sync from both Pune Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 4

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://192.168.192.163:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://192.168.192.164:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

### **Read Node 3 (`192.168.192.167`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils
sudo dpkg-reconfigure slapd

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 3 to sync from both Pune Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 5

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://192.168.192.163:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://192.168.192.164:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

### **Read Node 4 (`192.168.192.170`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils
sudo dpkg-reconfigure slapd

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 4 to sync from both Pune Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 6

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://192.168.192.163:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://192.168.192.164:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

---

### **Step 4: Configure Pune HAProxy (`192.168.192.162`)**

```bash
# 1. Install HAProxy
sudo apt update
sudo apt install -y haproxy

# 2. Configure HAProxy
sudo nano /etc/haproxy/haproxy.cfg

```

Replace the content with:

```
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # See: <https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate>
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log global
    mode tcp              # <- CRITICAL FOR LDAP
    option tcplog
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# LDAP Write Operations (to Masters)
frontend ldap_write
    bind *:389
    mode tcp
    default_backend ldap_master

backend ldap_master
    mode tcp
    balance leastconn
    server ldap-m1 192.168.192.163:389 check
    server ldap-m2 192.168.192.164:389 check

# LDAP Read Operations (to Replicas)
frontend ldap_read
    bind *:390
    mode tcp
    default_backend ldap_replicas

backend ldap_replicas
    mode tcp
    balance roundrobin
    server ldap-r1 192.168.192.165:389 check
    server ldap-r2 192.168.192.166:389 check
    server ldap-r3 192.168.192.167:389 check
    server ldap-r4 192.168.192.170:389 check

```

```bash
# 3. Start HAProxy
sudo systemctl enable haproxy
sudo systemctl start haproxy

```

---

### ✅ **Phase 2: Mumbai Region Setup**

### **Step 1: Configure Master 1 (`10.10.10.6`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Set Server ID and Mirror Mode
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 7

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

# 5. Create replicator user
ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=replicator,dc=innspark,dc=in
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: replicator
userPassword: password
EOF

# 6. Set ACLs
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,dc=innspark,dc=in" write by anonymous auth by self write by * none
-
replace: olcAccess
olcAccess: {1}to * by dn="cn=replicator,dc=innspark,dc=in" read by dn="cn=admin,dc=innspark,dc=in" write by * read
EOF

# 7. Configure syncrepl to Master 2 (private IP)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://10.10.10.7:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

---

## ✅ **Masters Requiring `olcMirrorMode: TRUE`**

### **Set `olcMultiProvider` (and `olcMirrorMode` )**

```bash
# On each master server 
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMultiProvider
olcMultiProvider: TRUE
-
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

```

### **Step 2: Configure Master 2 (`10.10.10.7`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Set Server ID and Mirror Mode
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 8

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

# 5. Create replicator user
ldapadd -x -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=replicator,dc=innspark,dc=in
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: replicator
userPassword: password
EOF

# 6. Set ACLs
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange by dn="cn=admin,dc=innspark,dc=in" write by anonymous auth by self write by * none
-
replace: olcAccess
olcAccess: {1}to * by dn="cn=replicator,dc=innspark,dc=in" read by dn="cn=admin,dc=innspark,dc=in" write by * read
EOF

# 7. Configure syncrepl to Master 1 (private IP)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://10.10.10.6:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

---

## ✅ **Masters Requiring `olcMirrorMode: TRUE`**

### **Set `olcMultiProvider` (and `olcMirrorMode` )**

```bash
# On each master server 
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMultiProvider
olcMultiProvider: TRUE
-
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

```

### **Step 3: Configure Read Nodes in Mumbai**

### **Read Node 1 (`10.10.10.8`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 1 to sync from both Mumbai Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 9

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://10.10.10.6:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://10.10.10.7:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

### **Read Node 2 (`10.10.10.9`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 2 to sync from both Mumbai Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 10

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://10.10.10.6:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://10.10.10.7:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

### **Read Node 3 (`10.10.10.10`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 3 to sync from both Mumbai Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 11

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://10.10.10.6:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://10.10.10.7:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

### **Read Node 4 (`10.10.10.11`)**

```bash
# 1. Install OpenLDAP
sudo apt update
sudo apt install -y slapd ldap-utils

# 2. Load syncprov module
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
EOF

# 3. Create syncprov overlay
sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
olcOverlay: syncprov
EOF

# 4. Configure Read Node 4 to sync from both Mumbai Masters (private IPs)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 12

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=innspark,dc=in

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: password

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=001 provider=ldap://10.10.10.6:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=002 provider=ldap://10.10.10.7:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"

dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMirrorMode
olcMirrorMode: FALSE
EOF

# 5. Clear database and restart
sudo systemctl stop slapd
sudo rm -rf /var/lib/ldap/*
sudo systemctl start slapd

```

---

### **Step 4: Configure Mumbai HAProxy (`10.10.10.5`)**

```bash
# 1. Install HAProxy
sudo apt update
sudo apt install -y haproxy

# 2. Configure HAProxy
sudo nano /etc/haproxy/haproxy.cfg

```

Replace the content with:

```
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # See: <https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate>
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log global
    mode tcp              # <- CRITICAL FOR LDAP
    option tcplog
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# LDAP Write Operations (to Masters)
frontend ldap_write
    bind *:389
    mode tcp
    default_backend ldap_master

backend ldap_master
    mode tcp
    balance leastconn
    server ldap-m1 10.10.10.6:389 check
    server ldap-m2 10.10.10.7:389 check

# LDAP Read Operations (to Replicas)
frontend ldap_read
    bind *:390
    mode tcp
    default_backend ldap_replicas

backend ldap_replicas
    mode tcp
    balance roundrobin
    server ldap-r1 10.10.10.8:389 check
    server ldap-r2 10.10.10.9:389 check
    server ldap-r3 10.10.10.10:389 check
    server ldap-r4 10.10.10.11:389 check

```

```bash
# 3. Start HAProxy
sudo systemctl enable haproxy
sudo systemctl start haproxy

```

---

### ✅ **Phase 3: Cross-Region Sync (Pune <-> Mumbai)**

### **Step 1: Configure Pune Master 1 to Sync with Mumbai Masters (public IPs)**

On **Master 1 (`192.168.192.163`)**:

```bash
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=003 provider=ldap://192.168.50.22:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=004 provider=ldap://192.168.50.23:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

### **Step 2: Configure Pune Master 2 to Sync with Mumbai Masters (public IPs)**

On **Master 2 (`192.168.192.164`)**:

```bash
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=003 provider=ldap://192.168.50.22:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=004 provider=ldap://192.168.50.23:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

### **Step 3: Configure Mumbai Master 1 to Sync with Pune Masters (public IPs)**

On **Master 1 (`10.10.10.6`)**:

```bash
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=003 provider=ldap://192.168.50.19:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=004 provider=ldap://192.168.50.20:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

### **Step 4: Configure Mumbai Master 2 to Sync with Pune Masters (public IPs)**

On **Master 2 (`10.10.10.7`)**:

```bash
sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=003 provider=ldap://192.168.50.19:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
-
add: olcSyncrepl
olcSyncrepl: rid=004 provider=ldap://192.168.50.20:389 bindmethod=simple binddn="cn=replicator,dc=innspark,dc=in" credentials=password searchbase="dc=innspark,dc=in" schemachecking=on type=refreshAndPersist retry="60 +"
EOF

```

---

## 🧪 **Verification Steps**

### **Test 1: Basic Connectivity**

From a client machine:

```bash
# Test Pune HAProxy
ldapsearch -x -H ldap://192.168.50.18:389 -b "" -s base namingContexts | grep "dc=innspark,dc=in"
ldapsearch -x -H ldap://192.168.50.18:390 -b "" -s base namingContexts | grep "dc=innspark,dc=in"

# Test Mumbai HAProxy
ldapsearch -x -H ldap://192.168.50.21:389 -b "" -s base namingContexts | grep "dc=innspark,dc=in"
ldapsearch -x -H ldap://192.168.50.21:390 -b "" -s base namingContexts | grep "dc=innspark,dc=in"

```

### **Test 2: Multi-Master Replication Within Region**

```bash
# Write to Pune Master 1
ldapadd -x -H ldap://192.168.50.19:389 -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=test-pune,dc=innspark,dc=in
objectClass: organizationalRole
cn: test-pune
EOF

# Wait 15 seconds, then check Pune Master 2
ldapsearch -x -H ldap://192.168.50.20:389 -b "dc=innspark,dc=in" "(cn=test-pune)" dn

# Write to Mumbai Master 1
ldapadd -x -H ldap://192.168.50.22:389 -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=test-mumbai,dc=innspark,dc=in
objectClass: organizationalRole
cn: test-mumbai
EOF

# Wait 15 seconds, then check Mumbai Master 2
ldapsearch -x -H ldap://192.168.50.23:389 -b "dc=innspark,dc=in" "(cn=test-mumbai)" dn

```

### **Test 3: Cross-Region Replication**

```bash
# Write to Pune Master 1
ldapadd -x -H ldap://192.168.50.19:389 -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=test-inter-region,dc=innspark,dc=in
objectClass: organizationalRole
cn: test-inter-region
EOF

# Wait 30 seconds, then check Mumbai Master 1
ldapsearch -x -H ldap://192.168.50.22:389 -b "dc=innspark,dc=in" "(cn=test-inter-region)" dn

# Write to Mumbai Master 1
ldapadd -x -H ldap://192.168.50.22:389 -D "cn=admin,dc=innspark,dc=in" -w password <<EOF
dn: cn=test-inter-region-mumbai,dc=innspark,dc=in
objectClass: organizationalRole
cn: test-inter-region-mumbai
EOF

# Wait 30 seconds, then check Pune Master 1
ldapsearch -x -H ldap://192.168.50.19:389 -b "dc=innspark,dc=in" "(cn=test-inter-region-mumbai)" dn

```

### **Test 4: Replica Sync**

```bash
# Check if entries are on Pune Read Nodes
ldapsearch -x -H ldap://192.168.192.165:389 -b "dc=innspark,dc=in" "(cn=test-pune)" dn
ldapsearch -x -H ldap://192.168.192.166:389 -b "dc=innspark,dc=in" "(cn=test-pune)" dn
ldapsearch -x -H ldap://192.168.192.167:389 -b "dc=innspark,dc=in" "(cn=test-pune)" dn
ldapsearch -x -H ldap://192.168.192.170:389 -b "dc=innspark,dc=in" "(cn=test-pune)" dn

# Check if entries are on Mumbai Read Nodes
ldapsearch -x -H ldap://10.10.10.8:389 -b "dc=innspark,dc=in" "(cn=test-mumbai)" dn
ldapsearch -x -H ldap://10.10.10.9:389 -b "dc=innspark,dc=in" "(cn=test-mumbai)" dn
ldapsearch -x -H ldap://10.10.10.10:389 -b "dc=innspark,dc=in" "(cn=test-mumbai)" dn
ldapsearch -x -H ldap://10.10.10.11:389 -b "dc=innspark,dc=in" "(cn=test-mumbai)" dn

```

---
