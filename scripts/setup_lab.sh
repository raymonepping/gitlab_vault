#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIG
# -----------------------------------------------------------------------------

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

JWT_AUTH_PATH="jwt"
JWT_ROLE_NAME="gitlab-vault-jwt-lab"
JWT_POLICY_NAME="gitlab-vault-jwt-lab"

GITLAB_ISSUER="http://gitlab.local:8929"

SECRET_PATH="secret/gitlab-lab"
SECRET_USERNAME="demo"
SECRET_PASSWORD="demo123"

AUDIT_PATH="file"
AUDIT_FILE="/tmp/vault_audit.log"

# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------

ACTION="setup"
FORCE_SECRET=false

usage() {
cat <<EOF
Usage: $0 [options]

Actions:
  --setup           Run full setup (default)
  --verify          Validate configuration only (no changes)
  --teardown        Remove lab setup (with confirmation)

Options:
  --force-secret    Overwrite demo secret if it exists
  --help            Show this help

Examples:
  $0 --setup
  $0 --verify
  $0 --setup --force-secret
  $0 --teardown
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup) ACTION="setup"; shift ;;
    --verify) ACTION="verify"; shift ;;
    --teardown) ACTION="teardown"; shift ;;
    --force-secret) FORCE_SECRET=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------

log() {
  echo
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null || fail "Missing required command: $1"
}

vault_ok() {
  vault status >/dev/null 2>&1
}

auth_enabled() {
  vault auth list -format=json | jq -e "has(\"${JWT_AUTH_PATH}/\")" >/dev/null
}

audit_enabled() {
  vault audit list -format=json | jq -e "has(\"${AUDIT_PATH}/\")" >/dev/null
}

policy_exists() {
  vault policy read "$JWT_POLICY_NAME" >/dev/null 2>&1
}

role_exists() {
  vault read "auth/${JWT_AUTH_PATH}/role/${JWT_ROLE_NAME}" >/dev/null 2>&1
}

secret_exists() {
  vault kv get "$SECRET_PATH" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# VERIFY
# -----------------------------------------------------------------------------

verify() {
  log "Running verification checks"

  echo "== Vault status =="
  vault status

  echo
  echo "== Auth methods =="
  vault auth list

  echo
  echo "== Audit devices =="
  vault audit list

  echo
  echo "== JWT config =="
  vault read auth/${JWT_AUTH_PATH}/config || true

  echo
  echo "== JWT role =="
  vault read auth/${JWT_AUTH_PATH}/role/${JWT_ROLE_NAME} || true

  echo
  echo "== Policy =="
  vault policy read ${JWT_POLICY_NAME} || true

  echo
  echo "== Secret test =="
  if vault kv get "$SECRET_PATH" >/dev/null 2>&1; then
    echo "✔ Secret readable"
  else
    echo "✖ Secret NOT readable"
  fi

  echo
  echo "== GitLab OIDC =="
  curl -s "${GITLAB_ISSUER}/.well-known/openid-configuration" | jq '.issuer'

  log "Verification complete"
}

# -----------------------------------------------------------------------------
# TEARDOWN
# -----------------------------------------------------------------------------

teardown() {
  echo
  echo "⚠️  This will REMOVE:"
  echo "   - JWT auth method"
  echo "   - Policy: ${JWT_POLICY_NAME}"
  echo "   - Secret: ${SECRET_PATH}"
  echo "   - Audit device: ${AUDIT_PATH}/"
  echo

  read -r -p "Type 'destroy' to continue: " confirm

  if [[ "$confirm" != "destroy" ]]; then
    echo "Aborted."
    exit 0
  fi

  log "Removing JWT auth"
  vault auth disable "${JWT_AUTH_PATH}" || true

  log "Removing policy"
  vault policy delete "${JWT_POLICY_NAME}" || true

  log "Deleting secret"
  vault kv delete "${SECRET_PATH}" || true

  log "Disabling audit"
  vault audit disable "${AUDIT_PATH}" || true

  log "Teardown complete"
}

# -----------------------------------------------------------------------------
# SETUP
# -----------------------------------------------------------------------------

setup() {
  require_cmd vault
  require_cmd jq
  require_cmd curl

  log "Checking Vault status"
  vault_ok || fail "Vault is not reachable"

  log "Checking GitLab OIDC endpoint"
  curl -s "${GITLAB_ISSUER}/.well-known/openid-configuration" >/dev/null \
    || fail "Cannot reach GitLab OIDC endpoint"

  # -----------------------------
  # Audit
  # -----------------------------
  if audit_enabled; then
    log "Audit already enabled"
  else
    log "Enabling audit logging"
    vault audit enable file file_path="$AUDIT_FILE"
  fi

  # -----------------------------
  # JWT Auth
  # -----------------------------
  if auth_enabled; then
    log "JWT auth already enabled"
  else
    log "Enabling JWT auth"
    vault auth enable jwt
  fi

  log "Configuring JWT"
  vault write auth/${JWT_AUTH_PATH}/config \
    oidc_discovery_url="${GITLAB_ISSUER}" \
    bound_issuer="${GITLAB_ISSUER}"

  # -----------------------------
  # Policy
  # -----------------------------
  log "Applying policy"
  vault policy write ${JWT_POLICY_NAME} - <<EOF
path "secret/data/gitlab-lab" {
  capabilities = ["read"]
}
EOF

  # -----------------------------
  # Role
  # -----------------------------
  log "Applying role"
  vault write auth/${JWT_AUTH_PATH}/role/${JWT_ROLE_NAME} -<<EOF
{
  "role_type": "jwt",
  "bound_audiences": ["vault"],
  "user_claim": "user_email",
  "bound_claims": {
    "project_id": "1",
    "ref": "main",
    "ref_protected": "true"
  },
  "claim_mappings": {
    "project_path": "project_path",
    "namespace_path": "namespace_path",
    "user_email": "user_email",
    "user_login": "user_login",
    "user_id": "user_id",
    "pipeline_id": "pipeline_id",
    "job_id": "job_id",
    "ref": "ref"
  },
  "token_policies": ["gitlab-vault-jwt-lab"],
  "token_ttl": "15m"
}
EOF

  # -----------------------------
  # Secret
  # -----------------------------
  if secret_exists; then
    if [[ "$FORCE_SECRET" == true ]]; then
      log "Overwriting secret (--force-secret)"
      vault kv put "$SECRET_PATH" \
        username="$SECRET_USERNAME" \
        password="$SECRET_PASSWORD"
    else
      log "Secret exists, skipping"
    fi
  else
    log "Creating secret"
    vault kv put "$SECRET_PATH" \
      username="$SECRET_USERNAME" \
      password="$SECRET_PASSWORD"
  fi

  log "Setup complete"
}

# -----------------------------------------------------------------------------
# EXECUTION
# -----------------------------------------------------------------------------

case "$ACTION" in
  setup)
    setup
    ;;
  verify)
    verify
    ;;
  teardown)
    teardown
    ;;
  *)
    fail "Unknown action: $ACTION"
    ;;
esac