#!/usr/bin/env bash
set -euo pipefail

INPUT_FILE=""
ACCESSOR=""
FORMAT="text"
OUTPUT_FILE=""
TMP_CLEAN="$(mktemp)"
TMP_VAULT="$(mktemp)"

cleanup() {
  rm -f "$TMP_CLEAN" "$TMP_VAULT"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  parse_vault_ci.sh <gitlab_log_file> [--accessor <vault_token_accessor>] [--format text|json|md] [--output <file>]

Examples:
  ./parse_vault_ci.sh ./input/gitlab.log
  ./parse_vault_ci.sh ./input/gitlab.log --accessor eabJKPNZhWKVpyLxkMuw6AUB
  ./parse_vault_ci.sh ./input/gitlab.log --accessor eabJKPNZhWKVpyLxkMuw6AUB --format md
  ./parse_vault_ci.sh ./input/gitlab.log --format json --output report.json
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

INPUT_FILE="$1"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --accessor)
      ACCESSOR="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-text}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

case "$FORMAT" in
  text|json|md) ;;
  *)
    echo "Invalid format: $FORMAT"
    exit 1
    ;;
esac

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input file not found: $INPUT_FILE"
  exit 1
fi

# Strip ANSI escape codes and GitLab timestamp/prefix noise
sed -E 's/\x1b\[[0-9;]*m//g' "$INPUT_FILE" \
  | sed -E 's/^[0-9T:\.\-]+Z [0-9]{2}O\+? ?//' \
  > "$TMP_CLEAN"

extract_json_after_marker() {
  local marker="$1"

  awk -v marker="$marker" '
    $0 ~ marker {found=1; next}
    found {
      if (!capturing && $0 ~ /^[[:space:]]*\{[[:space:]]*$/) {
        capturing=1
      }
      if (capturing) {
        print
      }
    }
  ' "$TMP_CLEAN" | awk '
    BEGIN { depth=0; started=0 }
    {
      line=$0
      if (!started && line ~ /^[[:space:]]*\{[[:space:]]*$/) {
        started=1
      }
      if (started) {
        print line
        tmp=line
        opens=gsub(/\{/, "{", tmp)
        tmp=line
        closes=gsub(/\}/, "}", tmp)
        depth += opens - closes
        if (depth == 0) {
          exit
        }
      }
    }
  '
}

safe_jq() {
  local query="$1"
  local input="${2:-}"
  printf '%s\n' "$input" | jq -r "$query // empty" 2>/dev/null || true
}

VAULT_METADATA="$(extract_json_after_marker "VAULT AUTH METADATA")"
SECRET_DATA="$(extract_json_after_marker "READ SECRET")"

if ! printf '%s\n' "$VAULT_METADATA" | jq . >/dev/null 2>&1; then
  echo "Could not extract Vault metadata from GitLab log"
  exit 1
fi

# GitLab-side parsed values
GL_USER="$(safe_jq '.metadata.user_login' "$VAULT_METADATA")"
GL_EMAIL="$(safe_jq '.metadata.user_email' "$VAULT_METADATA")"
GL_USER_ID="$(safe_jq '.metadata.user_id' "$VAULT_METADATA")"
GL_PROJECT="$(safe_jq '.metadata.project_path' "$VAULT_METADATA")"
GL_NAMESPACE="$(safe_jq '.metadata.namespace_path' "$VAULT_METADATA")"
GL_PIPELINE="$(safe_jq '.metadata.pipeline_id' "$VAULT_METADATA")"
GL_JOB="$(safe_jq '.metadata.job_id' "$VAULT_METADATA")"
GL_BRANCH="$(safe_jq '.metadata.ref' "$VAULT_METADATA")"
GL_POLICIES="$(printf '%s\n' "$VAULT_METADATA" | jq -r '.policies // [] | join(", ")' 2>/dev/null || true)"

# Optional Vault-side lookup
VAULT_LOOKUP_JSON=""
VT_DISPLAY=""
VT_ENTITY_ID=""
VT_ISSUE_TIME=""
VT_EXPIRE_TIME=""
VT_PATH=""
VT_POLICIES=""
VT_META_USER=""
VT_META_EMAIL=""
VT_META_PROJECT=""
VT_META_PIPELINE=""
VT_META_JOB=""
VT_META_REF=""
VT_ROLE=""

if [[ -n "$ACCESSOR" ]]; then
  if command -v vault >/dev/null 2>&1; then
    if vault token lookup -format=json -accessor "$ACCESSOR" > "$TMP_VAULT" 2>/dev/null; then
      VAULT_LOOKUP_JSON="$(cat "$TMP_VAULT")"
      VT_DISPLAY="$(safe_jq '.data.display_name' "$VAULT_LOOKUP_JSON")"
      VT_ENTITY_ID="$(safe_jq '.data.entity_id' "$VAULT_LOOKUP_JSON")"
      VT_ISSUE_TIME="$(safe_jq '.data.issue_time' "$VAULT_LOOKUP_JSON")"
      VT_EXPIRE_TIME="$(safe_jq '.data.expire_time' "$VAULT_LOOKUP_JSON")"
      VT_PATH="$(safe_jq '.data.path' "$VAULT_LOOKUP_JSON")"
      VT_POLICIES="$(printf '%s\n' "$VAULT_LOOKUP_JSON" | jq -r '.data.policies // [] | join(", ")' 2>/dev/null || true)"
      VT_META_USER="$(safe_jq '.data.meta.user_login' "$VAULT_LOOKUP_JSON")"
      VT_META_EMAIL="$(safe_jq '.data.meta.user_email' "$VAULT_LOOKUP_JSON")"
      VT_META_PROJECT="$(safe_jq '.data.meta.project_path' "$VAULT_LOOKUP_JSON")"
      VT_META_PIPELINE="$(safe_jq '.data.meta.pipeline_id' "$VAULT_LOOKUP_JSON")"
      VT_META_JOB="$(safe_jq '.data.meta.job_id' "$VAULT_LOOKUP_JSON")"
      VT_META_REF="$(safe_jq '.data.meta.ref' "$VAULT_LOOKUP_JSON")"
      VT_ROLE="$(safe_jq '.data.meta.role' "$VAULT_LOOKUP_JSON")"
    fi
  fi
fi

# Build unified JSON document
REPORT_JSON="$(jq -n \
  --arg gl_user "$GL_USER" \
  --arg gl_email "$GL_EMAIL" \
  --arg gl_user_id "$GL_USER_ID" \
  --arg gl_project "$GL_PROJECT" \
  --arg gl_namespace "$GL_NAMESPACE" \
  --arg gl_pipeline "$GL_PIPELINE" \
  --arg gl_job "$GL_JOB" \
  --arg gl_branch "$GL_BRANCH" \
  --arg gl_policies "$GL_POLICIES" \
  --arg accessor "$ACCESSOR" \
  --arg vt_display "$VT_DISPLAY" \
  --arg vt_entity_id "$VT_ENTITY_ID" \
  --arg vt_issue_time "$VT_ISSUE_TIME" \
  --arg vt_expire_time "$VT_EXPIRE_TIME" \
  --arg vt_path "$VT_PATH" \
  --arg vt_policies "$VT_POLICIES" \
  --arg vt_meta_user "$VT_META_USER" \
  --arg vt_meta_email "$VT_META_EMAIL" \
  --arg vt_meta_project "$VT_META_PROJECT" \
  --arg vt_meta_pipeline "$VT_META_PIPELINE" \
  --arg vt_meta_job "$VT_META_JOB" \
  --arg vt_meta_ref "$VT_META_REF" \
  --arg vt_role "$VT_ROLE" \
  --argjson secret "$(printf '%s\n' "$SECRET_DATA" | jq -c . 2>/dev/null || echo 'null')" \
  '{
    gitlab: {
      human_identity: {
        user: $gl_user,
        email: $gl_email,
        user_id: $gl_user_id
      },
      workload_context: {
        project: $gl_project,
        namespace: $gl_namespace,
        branch: $gl_branch,
        pipeline: $gl_pipeline,
        job: $gl_job
      },
      vault_result: {
        policies: ($gl_policies | split(", ") | map(select(length > 0)))
      }
    },
    vault: (
      if $accessor == "" then null
      else {
        accessor: $accessor,
        display_name: $vt_display,
        path: $vt_path,
        entity_id: $vt_entity_id,
        issue_time: $vt_issue_time,
        expire_time: $vt_expire_time,
        policies: ($vt_policies | split(", ") | map(select(length > 0))),
        role: $vt_role,
        metadata: {
          user: $vt_meta_user,
          email: $vt_meta_email,
          project: $vt_meta_project,
          pipeline: $vt_meta_pipeline,
          job: $vt_meta_job,
          branch: $vt_meta_ref
        }
      }
      end
    ),
    secret: $secret,
    verdict: {
      user: $gl_user,
      project: $gl_project,
      branch: $gl_branch,
      pipeline: $gl_pipeline,
      job: $gl_job,
      accessor: $accessor
    }
  }'
)"

render_text() {
  local BLUE="\033[1;34m"
  local CYAN="\033[1;36m"
  local GREEN="\033[1;32m"
  local YELLOW="\033[1;33m"
  local MAGENTA="\033[1;35m"
  local RESET="\033[0m"

  echo
  echo -e "${BLUE}🔐 VAULT IDENTITY REPORT${RESET}"
  echo -e "${BLUE}========================${RESET}"
  echo

  echo -e "${CYAN}👤 GitLab Human Identity${RESET}"
  echo "   User       : $GL_USER"
  echo "   Email      : $GL_EMAIL"
  echo "   User ID    : $GL_USER_ID"
  echo

  echo -e "${CYAN}⚙️  GitLab Workload Context${RESET}"
  echo "   Project    : $GL_PROJECT"
  echo "   Namespace  : $GL_NAMESPACE"
  echo "   Branch     : $GL_BRANCH"
  echo "   Pipeline   : $GL_PIPELINE"
  echo "   Job        : $GL_JOB"
  echo

  echo -e "${CYAN}🔐 GitLab-side Vault Access Result${RESET}"
  echo "   Policies   : $GL_POLICIES"
  echo

  if printf '%s\n' "$SECRET_DATA" | jq . >/dev/null 2>&1; then
    echo -e "${CYAN}📦 Retrieved Secret${RESET}"
    printf '%s\n' "$SECRET_DATA" | jq .
    echo
  fi

  if [[ -n "$ACCESSOR" ]]; then
    echo -e "${MAGENTA}🏦 Vault-side Token Lookup${RESET}"
    echo "   Accessor   : $ACCESSOR"

    if [[ -n "$VAULT_LOOKUP_JSON" ]]; then
      echo "   Display    : $VT_DISPLAY"
      echo "   Path       : $VT_PATH"
      echo "   Entity ID  : $VT_ENTITY_ID"
      echo "   Issued     : $VT_ISSUE_TIME"
      echo "   Expires    : $VT_EXPIRE_TIME"
      echo "   Policies   : $VT_POLICIES"
      echo "   Role       : $VT_ROLE"
      echo
      echo -e "${MAGENTA}🧾 Vault-side Metadata${RESET}"
      echo "   User       : $VT_META_USER"
      echo "   Email      : $VT_META_EMAIL"
      echo "   Project    : $VT_META_PROJECT"
      echo "   Pipeline   : $VT_META_PIPELINE"
      echo "   Job        : $VT_META_JOB"
      echo "   Branch     : $VT_META_REF"
      echo
    else
      echo "   Status     : lookup failed"
      echo
    fi
  fi

  echo -e "${GREEN}✅ Verdict${RESET}"
  echo -e "   Secret accessed by ${YELLOW}${GL_USER:-unknown}${RESET}"
  echo -e "   via pipeline ${YELLOW}${GL_PIPELINE:-unknown}${RESET} (job ${YELLOW}${GL_JOB:-unknown}${RESET})"
  echo -e "   from ${YELLOW}${GL_PROJECT:-unknown}${RESET} on branch ${YELLOW}${GL_BRANCH:-unknown}${RESET}"

  if [[ -n "$ACCESSOR" && -n "$VAULT_LOOKUP_JSON" ]]; then
    echo -e "   Vault confirms token ${YELLOW}$ACCESSOR${RESET}"
    echo -e "   with display ${YELLOW}${VT_DISPLAY:-unknown}${RESET}"
    echo -e "   and role ${YELLOW}${VT_ROLE:-unknown}${RESET}"
  fi

  echo
}

render_json() {
  printf '%s\n' "$REPORT_JSON" | jq .
}

render_md() {
  cat <<EOF
# 🔐 Vault Identity Report

## GitLab Human Identity

- **User:** \`$GL_USER\`
- **Email:** \`$GL_EMAIL\`
- **User ID:** \`$GL_USER_ID\`

## GitLab Workload Context

- **Project:** \`$GL_PROJECT\`
- **Namespace:** \`$GL_NAMESPACE\`
- **Branch:** \`$GL_BRANCH\`
- **Pipeline:** \`$GL_PIPELINE\`
- **Job:** \`$GL_JOB\`

## GitLab-side Vault Access Result

- **Policies:** \`$GL_POLICIES\`

EOF

  if printf '%s\n' "$SECRET_DATA" | jq . >/dev/null 2>&1; then
    echo "## Retrieved Secret"
    echo
    echo '```json'
    printf '%s\n' "$SECRET_DATA" | jq .
    echo '```'
    echo
  fi

  if [[ -n "$ACCESSOR" ]]; then
    cat <<EOF
## Vault-side Token Lookup

- **Accessor:** \`$ACCESSOR\`
- **Display Name:** \`$VT_DISPLAY\`
- **Path:** \`$VT_PATH\`
- **Entity ID:** \`$VT_ENTITY_ID\`
- **Issued:** \`$VT_ISSUE_TIME\`
- **Expires:** \`$VT_EXPIRE_TIME\`
- **Policies:** \`$VT_POLICIES\`
- **Role:** \`$VT_ROLE\`

## Vault-side Metadata

- **User:** \`$VT_META_USER\`
- **Email:** \`$VT_META_EMAIL\`
- **Project:** \`$VT_META_PROJECT\`
- **Pipeline:** \`$VT_META_PIPELINE\`
- **Job:** \`$VT_META_JOB\`
- **Branch:** \`$VT_META_REF\`

EOF
  fi

  cat <<EOF
## Verdict

Secret accessed by **$GL_USER** via pipeline **$GL_PIPELINE** job **$GL_JOB** from **$GL_PROJECT** on branch **$GL_BRANCH**.

EOF

  if [[ -n "$ACCESSOR" && -n "$VAULT_LOOKUP_JSON" ]]; then
    cat <<EOF
Vault confirms token **$ACCESSOR** with display **$VT_DISPLAY** and role **$VT_ROLE**.

EOF
  fi
}

emit_output() {
  local content="$1"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$content" > "$OUTPUT_FILE"
    echo "Wrote report to $OUTPUT_FILE"
  else
    printf '%s\n' "$content"
  fi
}

case "$FORMAT" in
  text)
    if [[ -n "$OUTPUT_FILE" ]]; then
      render_text > "$OUTPUT_FILE"
      echo "Wrote report to $OUTPUT_FILE"
    else
      render_text
    fi
    ;;
  json)
    emit_output "$(render_json)"
    ;;
  md)
    emit_output "$(render_md)"
    ;;
esac