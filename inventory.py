#!/home/ansible-ldap/mysql-venv/bin/python

import json
import mysql.connector
import sys

DB_CONFIG = {
    "user": "ldap_automation",
    "password": "PASSWORD",
    "host": "localhost",
    "database": "ldap_automation",
}


def get_db_connection():
    return mysql.connector.connect(**DB_CONFIG)


def main():
    inventory = {
        "_meta": {"hostvars": {}},
        "all": {
            "children": [
                "writers",
                "readers",
                "ldap_nodes",
                "haproxy",
                "pune",
                "mumbai",
            ]
        },
        "writers": {"hosts": []},
        "readers": {"hosts": []},
        "ldap_nodes": {"hosts": []},
        "haproxy": {"hosts": []},
        "pune": {"hosts": []},
        "mumbai": {"hosts": []},
    }

    try:
        # -------------------------------------------------
        # LDAP NODES (FROM DATABASE)
        # -------------------------------------------------
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("""
            SELECT
                server_id,
                node_name,
                role,
                region,
                ssh_host,
                ldap_host,
                is_writer,
                is_reader,
                is_bootstrap
            FROM nodes;
        """)

        rows = cursor.fetchall()

        for row in rows:
            hostname = row["node_name"]
            region = row["region"]

            # -------------------------
            # GROUP ASSIGNMENT
            # -------------------------
            inventory["ldap_nodes"]["hosts"].append(hostname)

            if row["is_writer"]:
                inventory["writers"]["hosts"].append(hostname)

            if row["is_reader"]:
                inventory["readers"]["hosts"].append(hostname)

            if region in inventory:
                inventory[region]["hosts"].append(hostname)

            # -------------------------
            # HOST VARIABLES
            # -------------------------
            hostvars = {
                "ldap_host": row["ldap_host"],
                "region": region,
                "is_ldap": True,
                "is_writer": bool(row["is_writer"]),
                "is_reader": bool(row["is_reader"]),
                "is_bootstrap": bool(row["is_bootstrap"]),
                "server_id": int(row["server_id"]),
            }

            if row["is_writer"]:
                # Add public IP for cross-region sync
                PUBLIC_IP_MAP = {
                    "pune-m1": "192.168.50.19",
                    "pune-m2": "192.168.50.20",
                    "mumbai-m1": "192.168.50.22",
                    "mumbai-m2": "192.168.50.23",
                }
                hostvars["public_ip"] = PUBLIC_IP_MAP.get(hostname)


            # Pune → direct SSH using private IP
            # Mumbai → SSH config / ProxyJump (no ansible_host)
            if region == "pune":
                hostvars["ansible_host"] = row["ssh_host"]
                hostvars["ansible_user"] = "sysadmin"

            inventory["_meta"]["hostvars"][hostname] = hostvars

        cursor.close()
        conn.close()

        # -------------------------------------------------
        # HAPROXY NODES (STATIC INFRA)
        # -------------------------------------------------
        haproxy_nodes = [
            {
                "name": "pune-haproxy",
                "region": "pune",
                "private_ip": "192.168.192.162",
                "public_ip": "192.168.50.18",
            },
            {
                "name": "mumbai-haproxy",
                "region": "mumbai",
                "private_ip": "10.10.10.5",
                "public_ip": "192.168.50.21",
            },
        ]

        for node in haproxy_nodes:
            hostname = node["name"]
            region = node["region"]

            inventory["haproxy"]["hosts"].append(hostname)
            inventory[region]["hosts"].append(hostname)

            hostvars = {
                "region": region,
                "is_haproxy": True,
                "private_ip": node["private_ip"],
                "public_ip": node["public_ip"],
            }

            # Pune HAProxy → direct SSH using private IP
            # Mumbai HAProxy → SSH alias / ProxyJump
            if region == "pune":
                hostvars["ansible_host"] = node["private_ip"]
                hostvars["ansible_user"] = "sysadmin"

            inventory["_meta"]["hostvars"][hostname] = hostvars

        print(json.dumps(inventory, indent=2))

    except Exception as e:
        error_inventory = {
            "_meta": {"hostvars": {}},
            "all": {"children": ["ungrouped"]},
            "error": str(e),
        }
        print(json.dumps(error_inventory, indent=2))
        sys.exit(0)


if __name__ == "__main__":
    main()
