#!/usr/bin/env bash
set -euo pipefail

########################################
# USAGE:
# add-domain-read.sh <domain> <admin-password> <role> <provider_host>
#
# Example:
# ./add-domain-read.sh orca.in password pune-r1 192.168.192.164
########################################

########################################
# READ INPUT
########################################

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <domain> <admin-password> <role> <provider_host>"
  echo "Example: $0 orca.in password pune-r1 192.168.192.164"
  exit 1
fi

DOMAIN="$1"
ADMIN_PWD="$2"
MY_ROLE="$3"
PROVIDER_HOST="$4"

########################################
# VALIDATE ROLE
########################################

case "$MY_ROLE" in
  pune-r1|pune-r2|pune-r3|pune-r4|mumbai-r1|mumbai-r2|mumbai-r3|mumbai-r4)
    ;;
  *)
    echo "ERROR: Invalid role '$MY_ROLE'"
    exit 1
    ;;
esac

########################################
# DERIVE SUFFIX + DB DIR
########################################

IFS='.' read -ra PARTS <<< "$DOMAIN"
[[ ${#PARTS[@]} -lt 2 ]] && { echo "ERROR: Invalid domain"; exit 1; }

SUFFIX=""
for p in "${PARTS[@]}"; do
  [[ -z "$SUFFIX" ]] && SUFFIX="dc=$p" || SUFFIX="$SUFFIX,dc=$p"
done

FIRST_DC="${PARTS[0]}"
DB_DIR="/var/lib/ldap/$FIRST_DC"

echo "========== READ REPLICA DOMAIN SETUP =========="
echo "DOMAIN       = $DOMAIN"
echo "SUFFIX       = $SUFFIX"
echo "ROLE         = $MY_ROLE"
echo "PROVIDER     = $PROVIDER_HOST"
echo "DB DIRECTORY = $DB_DIR"
echo "================================================"
echo

########################################
# CHECK IF DB EXISTS
########################################

EXISTING_DB_DN=$(
  sudo ldapsearch -Y EXTERNAL -H ldapi:/// \
    -b cn=config -s one "(olcSuffix=$SUFFIX)" dn 2>/dev/null \
    | awk '/^dn: / {print $2}'
)

if [[ -n "${EXISTING_DB_DN:-}" ]]; then
  echo "[INFO] Database already exists: $EXISTING_DB_DN"
  exit 0
fi

########################################
# PREPARE DB DIRECTORY
########################################

sudo mkdir -p "$DB_DIR"
sudo chown openldap:openldap "$DB_DIR"
sudo chmod 700 "$DB_DIR"

########################################
# ROOT PASSWORD HASH
########################################

ROOTPW_HASH=$(slappasswd -s "$ADMIN_PWD")

########################################
# NEXT DB INDEX
########################################

EXISTING_NUMS=$(
  sudo ldapsearch -Y EXTERNAL -H ldapi:/// \
    -b cn=config -s one "(olcDatabase=mdb)" dn 2>/dev/null \
    | grep -o '{[0-9]\+}' | tr -d '{}' || true
)

if [[ -z "$EXISTING_NUMS" ]]; then
  DB_NUMBER=1
else
  DB_NUMBER=$(( $(echo "$EXISTING_NUMS" | sort -n | tail -1) + 1 ))
fi

DB_DN="olcDatabase={$DB_NUMBER}mdb,cn=config"

########################################
# CREATE READ-ONLY DATABASE
########################################

sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: $DB_DN
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {$DB_NUMBER}mdb
olcSuffix: $SUFFIX
olcDbDirectory: $DB_DIR
olcReadOnly: TRUE
olcRootDN: cn=admin,$SUFFIX
olcRootPW: $ROOTPW_HASH
EOF

########################################
# ACLs
########################################

sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: $DB_DN
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword by dn="cn=admin,$SUFFIX" write by self write by anonymous auth by * none
olcAccess: {1}to * by dn="cn=admin,$SUFFIX" write by users read by anonymous read
EOF

########################################
# SYNCREPL (CONSUMER)
########################################

sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: $DB_DN
changetype: modify
add: olcSyncrepl
olcSyncrepl: rid=201 provider=ldap://$PROVIDER_HOST:389 bindmethod=simple binddn="cn=admin,$SUFFIX" credentials=$ADMIN_PWD searchbase="$SUFFIX" type=refreshAndPersist retry="60 +" timeout=1
EOF

########################################
# RESTART SLAPD
########################################

sudo systemctl restart slapd

########################################
# SAFE VERIFICATION (NO STDOUT)
########################################

ldapsearch -x -H ldap://127.0.0.1:389 \
  -b "" -s base namingContexts >/dev/null 2>&1 || true

echo
echo "========== READ REPLICA SETUP COMPLETE =========="
echo "Role     : $MY_ROLE"
echo "Suffix   : $SUFFIX"
echo "Provider : $PROVIDER_HOST"
echo "DB DN    : $DB_DN"
echo "================================================"