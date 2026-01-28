### 1. Reset all nodes

```bash
ansible-playbook -i inventory.py reset_test.yaml -b
```
---
### 2.  Fresh install

```bash
ansible-playbook -i inventory.py test_install.yml -b -e "ldap_suffix=dc=innspark,dc=in ldap_admin_password=password"
```
---

### 3. Add a new domain

```bash
ansible-playbook -i inventory.py add-domain.yml -e "new_domain=shelsta.com new_domain_admin_password=password"
```
---
### 4. Add attributes to schema

```bash
ansible-playbook -i inventory.py add-schema.yml -b
```
---

### 5. Debug / Fix locks

```bash
ansible-playbook -i inventory.py debug/roles/fixlocks.yml -b
```
----
###  Ansible Quick Cheat Sheet (Node-Specific Runs & Variations)

---

## 1. Run a playbook on **ONE specific node**

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit pune-m1
```

---

## 2. Run on **multiple specific nodes**

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit "pune-m1,pune-m2"
```

---

## 3. Run on **ALL nodes except one**

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit '!pune-r3'
```

---

## 4. Run on a **group** (defined in inventory)

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit masters
```

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit replicas
```

---

## 5. Run on **group except one node**

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit "masters:!pune-m2"
```

---

## 6. Run on **single node after failure / recovery**

```bash
ansible-playbook -i inventory.py reset_test.yaml -b --limit pune-m1
```

Safe: does not touch healthy nodes.

---

## 7. Run **only tagged tasks** on a node

### Playbook task example

```yaml
- name: Add schema
  import_role:
    name: innspark_custom_schema
  tags: schema
```

### Command

```bash
ansible-playbook -i inventory.py add-schema.yml -b --tags schema --limit pune-m1
```

---

## 8. Skip specific tasks (tags)

```bash
ansible-playbook -i inventory.py add-schema.yml -b --skip-tags verify
```

---

## 9. Run **write operation only once** (leader node)

### Task

```yaml
- name: Add LDAP entry
  command: ldapadd ...
  run_once: true
  delegate_to: pune-m1
```

---

## 10. Verify data on **ALL nodes** (read-only)

```bash
ansible-playbook -i inventory.py verify.yml
```

---

## 11. Continue playbook even if one node is down

```bash
ansible-playbook -i inventory.py add-schema.yml -b --limit '!pune-r2'
```

---

## 12. Limit forks (safe for LDAP)

```bash
ansible-playbook -i inventory.py add-schema.yml -b --forks 1
```

---

## 13. Increase SSH timeout (slow nodes)

```bash
ansible-playbook -i inventory.py add-schema.yml -b --timeout 60
```

---

## 14. Dry run (see what will change)

```bash
ansible-playbook -i inventory.py add-schema.yml -b --check
```

---

## 15. Show what tasks will run (no execution)

```bash
ansible-playbook -i inventory.py add-schema.yml --list-tasks
```

---

## 16. Show hosts selected after `--limit`

```bash
ansible-playbook -i inventory.py add-schema.yml --list-hosts --limit pune-m1
```

---

## 17. Run with extra variables

```bash
ansible-playbook -i inventory.py add-domain.yml -b \
  -e "new_domain=shelsta.com new_domain_admin_password=password"
```

---

## 18. Debug output (useful for LDAP)

```bash
ansible-playbook -i inventory.py add-schema.yml -b -vvv
```

---

## 19. Run only one task at a time (step mode)

```bash
ansible-playbook -i inventory.py add-schema.yml -b --step
```

---

## 20. Emergency recovery mode (single node)

```bash
ansible-playbook -i inventory.py test_install.yml -b --limit pune-m1 --forks 1
```

---

## 21. Typical **safe LDAP workflow**

```bash
# Fix broken node only
ansible-playbook -i inventory.py reset_test.yaml -b --limit pune-m1
```

```bash
# Apply schema only on write node
ansible-playbook -i inventory.py add-schema.yml -b --limit pune-m1
```
---
