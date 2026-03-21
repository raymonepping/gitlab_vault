# 🔎 Vault Identity Inventory

- **Total audit events:** `1`
- **Total read events:** `1`
- **Total secret read events:** `1`
- **Unique human identities:** `1`
- **Unique workload identities:** `1`

## Applied Filters

- **Secrets only:** `true`
- **Exact path:** ``
- **Path prefix:** ``
- **Excluded path prefix:** `sys/internal/ui/mounts/`
- **Operation:** ``

## Latest Secret Access

- **User:** `root`
  - **Email:** `gitlab_admin_726ef0@example.com`
  - **Project:** `root/vault-jwt-lab`
  - **Pipeline:** `3`
  - **Job:** `6`
  - **Ref:** `main`
  - **Role:** `gitlab-vault-jwt-lab`
  - **Path:** `secret/data/gitlab-lab`
  - **Operation:** `read`
  - **Time:** `2026-03-19T13:29:09.954946259Z`


## Human Identities

- **User:** `root`
  - **Email:** `gitlab_admin_726ef0@example.com`
  - **User ID:** `1`
  - **Count:** `1`
  - **Projects:** `root/vault-jwt-lab`
  - **Namespaces:** `root`
  - **Pipelines:** `3`
  - **Jobs:** `6`
  - **Refs:** `main`
  - **Roles:** `gitlab-vault-jwt-lab`
  - **Display Names:** `jwt-gitlab_admin_726ef0@example.com`
  - **Entity IDs:** `417d9475-9b67-7790-2053-24c20f42d641`
  - **Paths:** `secret/data/gitlab-lab`
  - **Operations:** `read`
  - **First Seen:** `2026-03-19T13:29:09.954946259Z`
  - **Last Seen:** `2026-03-19T13:29:09.954946259Z`


## Workload Identities

- **Project:** `root/vault-jwt-lab`
  - **Namespace:** `root`
  - **Pipeline:** `3`
  - **Job:** `6`
  - **Ref:** `main`
  - **Role:** `gitlab-vault-jwt-lab`
  - **Count:** `1`
  - **Users:** `root <gitlab_admin_726ef0@example.com>`
  - **Display Names:** `jwt-gitlab_admin_726ef0@example.com`
  - **Entity IDs:** `417d9475-9b67-7790-2053-24c20f42d641`
  - **Paths:** `secret/data/gitlab-lab`
  - **Operations:** `read`
  - **First Seen:** `2026-03-19T13:29:09.954946259Z`
  - **Last Seen:** `2026-03-19T13:29:09.954946259Z`


## Full Identity Bundles

- **Display:** `jwt-gitlab_admin_726ef0@example.com`
  - **Entity ID:** `417d9475-9b67-7790-2053-24c20f42d641`
  - **Role:** `gitlab-vault-jwt-lab`
  - **User:** `root`
  - **Email:** `gitlab_admin_726ef0@example.com`
  - **User ID:** `1`
  - **Project:** `root/vault-jwt-lab`
  - **Namespace:** `root`
  - **Pipeline:** `3`
  - **Job:** `6`
  - **Ref:** `main`
  - **Count:** `1`
  - **First Seen:** `2026-03-19T13:29:09.954946259Z`
  - **Last Seen:** `2026-03-19T13:29:09.954946259Z`
  - **Paths:** `secret/data/gitlab-lab`
  - **Operations:** `read`
