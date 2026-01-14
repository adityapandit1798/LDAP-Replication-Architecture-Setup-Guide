#!/usr/bin/env bash
set -euo pipefail

########################################
# USAGE:
# add-domain-master.sh <domain> <admin-password> <role> <replication_json>
#
# Example:
# ./add-domain-master.sh example.com password pune-m1 \
# '[{"rid":2,"provider":"ldap://192.168.192.164"},
#   {"rid":3,"provider":"ldap://192.168.50.22"},
#   {"rid":4,"provider":"ldap://192.168.50.23"}]'
########################################

########################################
# INPUT
########################################

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <domain> <admin-password> <role> <replication_json>"
  exit 1
fi

DOMAIN="$1"
ADMIN_PWD="$2"
MY_ROLE="$3"
REPL_JSON="$4"

########################################
# VALIDATION
########################################

case "$MY_ROLE" in
  pune-m1|pune-m2|mumbai-m1|mumbai-m2) ;;
  *)
    echo "ERROR: Invalid role $MY_ROLE"
    exit 1
    ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required"
  exit 1
}

########################################
# DERIVE SUFFIX
########################################

IFS='.' read -ra PARTS <<< "$DOMAIN"
[[ ${#PARTS[@]} -lt 2 ]] && { echo "Invalid domain"; exit 1; }

SUFFIX=""
for p in "${PARTS[@]}"; do
  [[ -z "$SUFFIX" ]] && SUFFIX="dc=$p" || SUFFIX="$SUFFIX,dc=$p"
done

FIRST_DC="${PARTS[0]}"
DB_DIR="/var/lib/ldap/$FIRST_DC"

echo "========== DOMAIN SETUP START =========="
echo "DOMAIN       = $DOMAIN"
echo "SUFFIX       = $SUFFIX"
echo "ROLE         = $MY_ROLE"
echo "DB DIRECTORY = $DB_DIR"
echo "========================================="
echo

########################################
# PREPARE DB DIR
########################################

sudo mkdir -p "$DB_DIR"
sudo chown openldap:openldap "$DB_DIR"
sudo chmod 700 "$DB_DIR"

########################################
# ROOT PASSWORD
########################################

ROOTPW_HASH=$(slappasswd -s "$ADMIN_PWD")

########################################
# NEXT DB INDEX
########################################

EXISTING=$(sudo ldapsearch -Y EXTERNAL -H ldapi:/// \
  -b cn=config -s one "(olcDatabase=mdb)" dn \
  | grep -o '{[0-9]\+}' | tr -d '{}' || true)

if [[ -z "$EXISTING" ]]; then
  DB_NUMBER=1
else
  DB_NUMBER=$(( $(echo "$EXISTING" | sort -n | tail -1) + 1 ))
fi

DB_DN="olcDatabase={$DB_NUMBER}mdb,cn=config"

########################################
# ENSURE MAIN DB PROVIDER FLAGS
########################################

sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF || true
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcMultiProvider
olcMultiProvider: TRUE
-
replace: olcMirrorMode
olcMirrorMode: TRUE
-
replace: olcSyncUseSubentry
olcSyncUseSubentry: TRUE
EOF

########################################
# CREATE DATABASE
########################################

sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: $DB_DN
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {$DB_NUMBER}mdb
olcSuffix: $SUFFIX
olcDbDirectory: $DB_DIR
olcRootDN: cn=admin,$SUFFIX
olcRootPW: $ROOTPW_HASH
olcDbIndex: objectClass eq
olcDbIndex: cn,sn,uid eq,sub
olcDbIndex: mail eq,sub
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
# SYNC PROVIDER OVERLAY
########################################

sudo ldapadd -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay=syncprov,$DB_DN
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
EOF

########################################
# SYNCREPL (JSON-DRIVEN)
########################################

TMP_REPL=$(mktemp)
{
  echo "dn: $DB_DN"
  echo "changetype: modify"
  echo "add: olcSyncrepl"

  echo "$REPL_JSON" | jq -c '.[]' | while read -r row; do
    RID=$(jq -r '.rid' <<<"$row")
    PROVIDER=$(jq -r '.provider' <<<"$row")

    echo "olcSyncrepl: rid=$RID provider=$PROVIDER bindmethod=simple binddn=\"cn=admin,$SUFFIX\" credentials=$ADMIN_PWD searchbase=\"$SUFFIX\" type=refreshAndPersist retry=\"5 +\" timeout=1"
  done
} > "$TMP_REPL"

sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f "$TMP_REPL"
rm -f "$TMP_REPL"

########################################
# ENABLE MIRROR MODE (AFTER SYNCREPL)
########################################

sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: $DB_DN
changetype: modify
replace: olcMultiProvider
olcMultiProvider: TRUE
-
replace: olcMirrorMode
olcMirrorMode: TRUE
EOF

########################################
# BASE ENTRIES (NOW WRITEABLE)
########################################

ldapadd -x -H ldap://127.0.0.1:389 \
  -D "cn=admin,$SUFFIX" -w "$ADMIN_PWD" <<EOF
dn: $SUFFIX
objectClass: top
objectClass: domain
dc: ${PARTS[0]}

dn: ou=People,$SUFFIX
objectClass: organizationalUnit
ou: People
EOF

echo "========== DOMAIN SETUP COMPLETE =========="
echo "Domain $SUFFIX successfully configured on $MY_ROLE"
