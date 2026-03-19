#!/usr/bin/env bash
set -euo pipefail

FILE=""
FORMAT="text"
OUTPUT_FILE=""
SECRETS_ONLY="false"
SUMMARY_ONLY="false"
PATH_EXACT=""
PATH_PREFIX=""
EXCLUDE_PATH_PREFIX=""
OPERATION=""
TOP_N=""
TIMELINE="false"
LATEST_ONLY="false"
SINCE=""
UNTIL=""
DATE_ONLY=""

usage() {
  cat <<'EOF'
Usage:
  parse_vault.sh <vault_audit.log> [options]

Options:
  --format <text|json|md>           Output format. Default: text
  --output <file>                   Write output to file
  --secrets-only                    Keep only secret/data/* style events and exclude sys/internal/ui/mounts/*
  --path <exact_path>               Keep only events for an exact path
  --path-prefix <prefix>            Keep only events whose path starts with prefix
  --exclude-path-prefix <prefix>    Exclude events whose path starts with prefix
  --operation <op>                  Keep only events for an exact Vault operation
  --since <timestamp>               Keep only events at or after this UTC timestamp
  --until <timestamp>               Keep only events at or before this UTC timestamp
  --date <YYYY-MM-DD>               Keep only events on this UTC date
  --top <n>                         Show top N human identities by access count
  --timeline                        Print a chronological event timeline
  --latest-only                     Print only latest secret access and core metrics
  --summary                         Print only a compact summary
  -h, --help                        Show this help

Examples:
  ./parse_vault.sh ./vault_audit.log
  ./parse_vault.sh ./vault_audit.log --secrets-only
  ./parse_vault.sh ./vault_audit.log --path secret/data/gitlab-lab
  ./parse_vault.sh ./vault_audit.log --path-prefix secret/data/
  ./parse_vault.sh ./vault_audit.log --operation read
  ./parse_vault.sh ./vault_audit.log --since 2026-03-19T13:00:00Z
  ./parse_vault.sh ./vault_audit.log --until 2026-03-19T14:00:00Z
  ./parse_vault.sh ./vault_audit.log --date 2026-03-19
  ./parse_vault.sh ./vault_audit.log --top 10 --timeline
  ./parse_vault.sh ./vault_audit.log --latest-only
  ./parse_vault.sh ./vault_audit.log --format json
  ./parse_vault.sh ./vault_audit.log --format md --output vault_identities.md
  ./parse_vault.sh ./vault_audit.log --secrets-only --summary
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
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

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

FILE="$1"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --secrets-only)
      SECRETS_ONLY="true"
      shift
      ;;
    --summary)
      SUMMARY_ONLY="true"
      shift
      ;;
    --path)
      PATH_EXACT="${2:-}"
      shift 2
      ;;
    --path-prefix)
      PATH_PREFIX="${2:-}"
      shift 2
      ;;
    --exclude-path-prefix)
      EXCLUDE_PATH_PREFIX="${2:-}"
      shift 2
      ;;
    --operation)
      OPERATION="${2:-}"
      shift 2
      ;;
    --since)
      SINCE="${2:-}"
      shift 2
      ;;
    --until)
      UNTIL="${2:-}"
      shift 2
      ;;
    --date)
      DATE_ONLY="${2:-}"
      shift 2
      ;;
    --top)
      TOP_N="${2:-}"
      shift 2
      ;;
    --timeline)
      TIMELINE="true"
      shift
      ;;
    --latest-only)
      LATEST_ONLY="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -f "$FILE" ]] || fail "File not found: $FILE"

case "$FORMAT" in
  text|json|md) ;;
  *)
    fail "Invalid format: $FORMAT"
    ;;
esac

if [[ -n "$TOP_N" && ! "$TOP_N" =~ ^[1-9][0-9]*$ ]]; then
  fail "--top must be a positive integer"
fi

if [[ -n "$OPERATION" ]]; then
  case "$OPERATION" in
    read|list|update|delete|create|patch) ;;
    *)
      fail "Invalid operation: $OPERATION"
      ;;
  esac
fi

if [[ -n "$DATE_ONLY" && ! "$DATE_ONLY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  fail "--date must be in YYYY-MM-DD format"
fi

if [[ -n "$SINCE" && ! "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  fail "--since must look like an ISO timestamp, for example 2026-03-19T13:00:00Z"
fi

if [[ -n "$UNTIL" && ! "$UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
  fail "--until must look like an ISO timestamp, for example 2026-03-19T14:00:00Z"
fi

# Default exclusions when focusing on secrets
if [[ "$SECRETS_ONLY" == "true" && -z "$EXCLUDE_PATH_PREFIX" ]]; then
  EXCLUDE_PATH_PREFIX="sys/internal/ui/mounts/"
fi

FILTER_JSON="$(jq -n \
  --arg path_exact "$PATH_EXACT" \
  --arg path_prefix "$PATH_PREFIX" \
  --arg exclude_path_prefix "$EXCLUDE_PATH_PREFIX" \
  --arg secrets_only "$SECRETS_ONLY" \
  --arg operation "$OPERATION" \
  --arg since "$SINCE" \
  --arg until "$UNTIL" \
  --arg date_only "$DATE_ONLY" '
{
  path_exact: $path_exact,
  path_prefix: $path_prefix,
  exclude_path_prefix: $exclude_path_prefix,
  secrets_only: ($secrets_only == "true"),
  operation: $operation,
  since: $since,
  until: $until,
  date_only: $date_only
}
')"

IDENTITY_JSON="$(
  jq -s \
    --argjson cfg "$FILTER_JSON" '
    def matches($cfg):
      (
        if $cfg.secrets_only
        then ((.request.path // "") | startswith("secret/data/"))
        else true
        end
      )
      and (
        if ($cfg.path_exact | length) > 0
        then (.request.path // "") == $cfg.path_exact
        else true
        end
      )
      and (
        if ($cfg.path_prefix | length) > 0
        then ((.request.path // "") | startswith($cfg.path_prefix))
        else true
        end
      )
      and (
        if ($cfg.exclude_path_prefix | length) > 0
        then (((.request.path // "") | startswith($cfg.exclude_path_prefix)) | not)
        else true
        end
      )
      and (
        if ($cfg.operation | length) > 0
        then (.request.operation // "") == $cfg.operation
        else true
        end
      )
      and (
        if ($cfg.since | length) > 0
        then (.time // "") >= $cfg.since
        else true
        end
      )
      and (
        if ($cfg.until | length) > 0
        then (.time // "") <= $cfg.until
        else true
        end
      )
      and (
        if ($cfg.date_only | length) > 0
        then ((.time // "") | startswith($cfg.date_only))
        else true
        end
      );

    map(
      select(.type == "request")
      | select(.auth.display_name != null)
      | select(.auth.metadata != null)
      | select(matches($cfg))
      | {
          time: .time,
          path: (.request.path // ""),
          operation: (.request.operation // ""),
          display_name: .auth.display_name,
          entity_id: (.auth.entity_id // ""),
          role: (.auth.metadata.role // ""),
          user_login: (.auth.metadata.user_login // ""),
          user_email: (.auth.metadata.user_email // ""),
          user_id: (.auth.metadata.user_id // ""),
          project_path: (.auth.metadata.project_path // ""),
          namespace_path: (.auth.metadata.namespace_path // ""),
          pipeline_id: (.auth.metadata.pipeline_id // ""),
          job_id: (.auth.metadata.job_id // ""),
          ref: (.auth.metadata.ref // "")
      }
    ) as $events
    | {
        filters: $cfg,
        total_events: ($events | length),
        read_events: (
          $events | map(select(.operation == "read")) | length
        ),
        secret_read_events: (
          $events
          | map(select(.operation == "read" and (.path | startswith("secret/data/"))))
          | length
        ),
        timeline_events: (
          $events
          | sort_by(.time)
          | map({
              time,
              user_login,
              user_email,
              project_path,
              pipeline_id,
              job_id,
              ref,
              role,
              path,
              operation,
              display_name,
              entity_id
            })
        ),
        unique_humans: (
          $events
          | map({user_login, user_email, user_id})
          | unique
          | length
        ),
        unique_workloads: (
          $events
          | map({project_path, namespace_path, pipeline_id, job_id, ref, role})
          | unique
          | length
        ),

        human_identities: (
          $events
          | sort_by(.user_login, .user_email, .user_id)
          | group_by({
              user_login,
              user_email,
              user_id
            })
          | map({
              count: length,
              user_login: .[0].user_login,
              user_email: .[0].user_email,
              user_id: .[0].user_id,
              display_names: (map(.display_name) | unique | sort),
              entity_ids: (map(.entity_id) | map(select(length > 0)) | unique | sort),
              roles: (map(.role) | map(select(length > 0)) | unique | sort),
              projects: (map(.project_path) | map(select(length > 0)) | unique | sort),
              namespaces: (map(.namespace_path) | map(select(length > 0)) | unique | sort),
              refs: (map(.ref) | map(select(length > 0)) | unique | sort),
              pipelines: (map(.pipeline_id) | map(select(length > 0)) | unique | sort),
              jobs: (map(.job_id) | map(select(length > 0)) | unique | sort),
              paths: (map(.path) | unique | sort),
              operations: (map(.operation) | unique | sort),
              first_seen: (map(.time) | sort | first),
              last_seen: (map(.time) | sort | last)
            })
          | sort_by(.user_login, .user_email)
        ),

        workload_identities: (
          $events
          | sort_by(.project_path, .pipeline_id, .job_id, .ref, .role)
          | group_by({
              project_path,
              namespace_path,
              pipeline_id,
              job_id,
              ref,
              role
            })
          | map({
              count: length,
              project_path: .[0].project_path,
              namespace_path: .[0].namespace_path,
              pipeline_id: .[0].pipeline_id,
              job_id: .[0].job_id,
              ref: .[0].ref,
              role: .[0].role,
              display_names: (map(.display_name) | unique | sort),
              entity_ids: (map(.entity_id) | map(select(length > 0)) | unique | sort),
              users: (
                map({
                  user_login,
                  user_email,
                  user_id
                }) | unique
              ),
              paths: (map(.path) | unique | sort),
              operations: (map(.operation) | unique | sort),
              first_seen: (map(.time) | sort | first),
              last_seen: (map(.time) | sort | last)
            })
          | sort_by(.project_path, .pipeline_id, .job_id)
        ),

        full_identity_bundles: (
          $events
          | sort_by(.project_path, .pipeline_id, .job_id, .user_login, .display_name)
          | group_by({
              display_name,
              entity_id,
              role,
              user_login,
              user_email,
              user_id,
              project_path,
              namespace_path,
              pipeline_id,
              job_id,
              ref
            })
          | map({
              count: length,
              display_name: .[0].display_name,
              entity_id: .[0].entity_id,
              role: .[0].role,
              user_login: .[0].user_login,
              user_email: .[0].user_email,
              user_id: .[0].user_id,
              project_path: .[0].project_path,
              namespace_path: .[0].namespace_path,
              pipeline_id: .[0].pipeline_id,
              job_id: .[0].job_id,
              ref: .[0].ref,
              paths: (map(.path) | unique | sort),
              operations: (map(.operation) | unique | sort),
              first_seen: (map(.time) | sort | first),
              last_seen: (map(.time) | sort | last)
            })
          | sort_by(.project_path, .pipeline_id, .job_id, .user_login)
        )
      }
  ' "$FILE"
)"

TOTAL_EVENTS="$(jq -r '.total_events' <<< "$IDENTITY_JSON")"

render_text() {
  local latest_event=""

  latest_event="$(jq -r '
    .timeline_events
    | map(select(.path | startswith("secret/data/")))
    | sort_by(.time)
    | last
  ' <<< "$IDENTITY_JSON")"

  printf '%s\n' ''
  printf '%s\n' '🔎 VAULT IDENTITY INVENTORY'
  printf '%s\n' '==========================='
  printf '%s\n' ''

  if [[ "$latest_event" != "null" ]]; then
    printf '%s\n' '🔐 Latest Secret Access'
    printf '%s\n' '----------------------'
    printf 'User      : %s\n' "$(jq -r '.user_login' <<< "$latest_event")"
    printf 'Email     : %s\n' "$(jq -r '.user_email' <<< "$latest_event")"
    printf 'Project   : %s\n' "$(jq -r '.project_path' <<< "$latest_event")"
    printf 'Pipeline  : %s\n' "$(jq -r '.pipeline_id' <<< "$latest_event")"
    printf 'Job       : %s\n' "$(jq -r '.job_id' <<< "$latest_event")"
    printf 'Ref       : %s\n' "$(jq -r '.ref' <<< "$latest_event")"
    printf 'Role      : %s\n' "$(jq -r '.role' <<< "$latest_event")"
    printf 'Path      : %s\n' "$(jq -r '.path' <<< "$latest_event")"
    printf 'Operation : %s\n' "$(jq -r '.operation' <<< "$latest_event")"
    printf 'Time      : %s\n' "$(jq -r '.time' <<< "$latest_event")"
    printf '%s\n' ''
  fi

  printf 'Total audit events         : %s\n' "$(jq -r '.total_events' <<< "$IDENTITY_JSON")"
  printf 'Total read events          : %s\n' "$(jq -r '.read_events' <<< "$IDENTITY_JSON")"
  printf 'Total secret read events   : %s\n' "$(jq -r '.secret_read_events' <<< "$IDENTITY_JSON")"
  printf 'Unique human identities    : %s\n' "$(jq -r '.unique_humans' <<< "$IDENTITY_JSON")"
  printf 'Unique workload identities : %s\n' "$(jq -r '.unique_workloads' <<< "$IDENTITY_JSON")"
  printf '%s\n' ''

  printf '%s\n' 'Applied Filters'
  printf '%s\n' '---------------'
  printf 'Secrets only           : %s\n' "$(jq -r '.filters.secrets_only' <<< "$IDENTITY_JSON")"
  printf 'Exact path             : %s\n' "$(jq -r '.filters.path_exact // ""' <<< "$IDENTITY_JSON")"
  printf 'Path prefix            : %s\n' "$(jq -r '.filters.path_prefix // ""' <<< "$IDENTITY_JSON")"
  printf 'Excluded path prefix   : %s\n' "$(jq -r '.filters.exclude_path_prefix // ""' <<< "$IDENTITY_JSON")"
  printf 'Operation              : %s\n' "$(jq -r '.filters.operation // ""' <<< "$IDENTITY_JSON")"
  printf 'Since                  : %s\n' "$(jq -r '.filters.since // ""' <<< "$IDENTITY_JSON")"
  printf 'Until                  : %s\n' "$(jq -r '.filters.until // ""' <<< "$IDENTITY_JSON")"
  printf 'Date                   : %s\n' "$(jq -r '.filters.date_only // ""' <<< "$IDENTITY_JSON")"
  printf '%s\n' ''

  if [[ "$TOTAL_EVENTS" == "0" ]]; then
    printf '%s\n' 'No matching audit events found.'
    return
  fi

  if [[ "$LATEST_ONLY" == "true" ]]; then
    return
  fi

  if [[ "$SUMMARY_ONLY" == "true" ]]; then
    printf '%s\n' 'Summary'
    printf '%s\n' '-------'
    jq -r '
      .full_identity_bundles[]
      | "Count      : \(.count)\n"
        + "User       : \(.user_login)\n"
        + "Email      : \(.user_email)\n"
        + "Project    : \(.project_path)\n"
        + "Pipeline   : \(.pipeline_id)\n"
        + "Job        : \(.job_id)\n"
        + "Ref        : \(.ref)\n"
        + "Role       : \(.role)\n"
        + "First Seen : \(.first_seen)\n"
        + "Last Seen  : \(.last_seen)\n"
    ' <<< "$IDENTITY_JSON"
    return
  fi

  if [[ -n "$TOP_N" ]]; then
    printf '%s\n' '🔥 Top Identities by Access Count'
    printf '%s\n' '--------------------------------'
    jq -r --argjson top "$TOP_N" '
      .human_identities
      | sort_by(.count)
      | reverse
      | .[:$top]
      | .[]
      | "\(.count)\t\(.user_login)\t\(.projects[0])"
    ' <<< "$IDENTITY_JSON"
    printf '%s\n' ''
  fi

  printf '%s\n' '👤 Human Identities'
  printf '%s\n' '-------------------'
  jq -r '
    .human_identities[]
    | "Count      : \(.count)\n"
      + "User       : \(.user_login)\n"
      + "Email      : \(.user_email)\n"
      + "User ID    : \(.user_id)\n"
      + "Projects   : \(.projects | join(", "))\n"
      + "Namespaces : \(.namespaces | join(", "))\n"
      + "Pipelines  : \(.pipelines | join(", "))\n"
      + "Jobs       : \(.jobs | join(", "))\n"
      + "Refs       : \(.refs | join(", "))\n"
      + "Roles      : \(.roles | join(", "))\n"
      + "Display    : \(.display_names | join(", "))\n"
      + "Entity IDs : \(.entity_ids | join(", "))\n"
      + "Paths      : \(.paths | join(", "))\n"
      + "Ops        : \(.operations | join(", "))\n"
      + "First Seen : \(.first_seen)\n"
      + "Last Seen  : \(.last_seen)\n"
  ' <<< "$IDENTITY_JSON"
  printf '%s\n' ''

  printf '%s\n' '⚙️ Workload Identities'
  printf '%s\n' '----------------------'
  jq -r '
    .workload_identities[]
    | "Count      : \(.count)\n"
      + "Project    : \(.project_path)\n"
      + "Namespace  : \(.namespace_path)\n"
      + "Pipeline   : \(.pipeline_id)\n"
      + "Job        : \(.job_id)\n"
      + "Ref        : \(.ref)\n"
      + "Role       : \(.role)\n"
      + "Users      : \(.users | map(.user_login + " <" + .user_email + ">") | join(", "))\n"
      + "Display    : \(.display_names | join(", "))\n"
      + "Entity IDs : \(.entity_ids | join(", "))\n"
      + "Paths      : \(.paths | join(", "))\n"
      + "Ops        : \(.operations | join(", "))\n"
      + "First Seen : \(.first_seen)\n"
      + "Last Seen  : \(.last_seen)\n"
  ' <<< "$IDENTITY_JSON"
  printf '%s\n' ''

  printf '%s\n' '🧩 Full Identity Bundles'
  printf '%s\n' '------------------------'
  jq -r '
    .full_identity_bundles[]
    | "Count      : \(.count)\n"
      + "Display    : \(.display_name)\n"
      + "Entity ID  : \(.entity_id)\n"
      + "Role       : \(.role)\n"
      + "User       : \(.user_login)\n"
      + "Email      : \(.user_email)\n"
      + "User ID    : \(.user_id)\n"
      + "Project    : \(.project_path)\n"
      + "Namespace  : \(.namespace_path)\n"
      + "Pipeline   : \(.pipeline_id)\n"
      + "Job        : \(.job_id)\n"
      + "Ref        : \(.ref)\n"
      + "First Seen : \(.first_seen)\n"
      + "Last Seen  : \(.last_seen)\n"
      + "Paths      : \(.paths | join(", "))\n"
      + "Ops        : \(.operations | join(", "))\n"
  ' <<< "$IDENTITY_JSON"

  if [[ "$TIMELINE" == "true" ]]; then
    printf '%s\n' ''
    printf '%s\n' '🕒 Timeline'
    printf '%s\n' '-----------'
    jq -r '
      .timeline_events[]
      | "\(.time)\t\(.user_login)\t\(.operation)\tpipeline=\(.pipeline_id)\tjob=\(.job_id)\t\(.path)"
    ' <<< "$IDENTITY_JSON"
    printf '%s\n' ''
  fi
}

render_md() {
  cat <<EOF
# 🔎 Vault Identity Inventory

- **Total audit events:** \`$(jq -r '.total_events' <<< "$IDENTITY_JSON")\`
- **Total read events:** \`$(jq -r '.read_events' <<< "$IDENTITY_JSON")\`
- **Total secret read events:** \`$(jq -r '.secret_read_events' <<< "$IDENTITY_JSON")\`
- **Unique human identities:** \`$(jq -r '.unique_humans' <<< "$IDENTITY_JSON")\`
- **Unique workload identities:** \`$(jq -r '.unique_workloads' <<< "$IDENTITY_JSON")\`

## Applied Filters

- **Secrets only:** \`$(jq -r '.filters.secrets_only' <<< "$IDENTITY_JSON")\`
- **Exact path:** \`$(jq -r '.filters.path_exact // ""' <<< "$IDENTITY_JSON")\`
- **Path prefix:** \`$(jq -r '.filters.path_prefix // ""' <<< "$IDENTITY_JSON")\`
- **Excluded path prefix:** \`$(jq -r '.filters.exclude_path_prefix // ""' <<< "$IDENTITY_JSON")\`
- **Operation:** \`$(jq -r '.filters.operation // ""' <<< "$IDENTITY_JSON")\`
- **Since:** \`$(jq -r '.filters.since // ""' <<< "$IDENTITY_JSON")\`
- **Until:** \`$(jq -r '.filters.until // ""' <<< "$IDENTITY_JSON")\`
- **Date:** \`$(jq -r '.filters.date_only // ""' <<< "$IDENTITY_JSON")\`

EOF

  if [[ "$TOTAL_EVENTS" == "0" ]]; then
    printf '%s\n' 'No matching audit events found.'
    return
  fi

  if [[ "$(jq -r '.timeline_events | map(select(.path | startswith("secret/data/"))) | length' <<< "$IDENTITY_JSON")" != "0" ]]; then
    printf '%s\n' '## Latest Secret Access'
    printf '%s\n' ''
    jq -r '
      .timeline_events
      | map(select(.path | startswith("secret/data/")))
      | sort_by(.time)
      | last
      | "- **User:** `\(.user_login)`\n"
        + "  - **Email:** `\(.user_email)`\n"
        + "  - **Project:** `\(.project_path)`\n"
        + "  - **Pipeline:** `\(.pipeline_id)`\n"
        + "  - **Job:** `\(.job_id)`\n"
        + "  - **Ref:** `\(.ref)`\n"
        + "  - **Role:** `\(.role)`\n"
        + "  - **Path:** `\(.path)`\n"
        + "  - **Operation:** `\(.operation)`\n"
        + "  - **Time:** `\(.time)`\n"
    ' <<< "$IDENTITY_JSON"
    printf '%s\n' ''
  fi

  if [[ "$LATEST_ONLY" == "true" ]]; then
    if [[ "$TIMELINE" == "true" ]]; then
      printf '%s\n' '## Timeline'
      printf '%s\n' ''
      jq -r '
        .timeline_events[]
        | "- `\(.time)` `\(.operation)` `\(.user_login)` `pipeline=\(.pipeline_id)` `job=\(.job_id)` `\(.path)`"
      ' <<< "$IDENTITY_JSON"
    fi
    return
  fi

  if [[ "$SUMMARY_ONLY" == "true" ]]; then
    printf '%s\n' '## Summary'
    printf '%s\n' ''
    jq -r '
      .full_identity_bundles[]
      | "- **User:** `\(.user_login)`\n"
        + "  - **Email:** `\(.user_email)`\n"
        + "  - **Project:** `\(.project_path)`\n"
        + "  - **Pipeline:** `\(.pipeline_id)`\n"
        + "  - **Job:** `\(.job_id)`\n"
        + "  - **Ref:** `\(.ref)`\n"
        + "  - **Role:** `\(.role)`\n"
        + "  - **Count:** `\(.count)`\n"
        + "  - **First Seen:** `\(.first_seen)`\n"
        + "  - **Last Seen:** `\(.last_seen)`\n"
    ' <<< "$IDENTITY_JSON"
    return
  fi

  printf '%s\n' '## Human Identities'
  printf '%s\n' ''
  jq -r '
    .human_identities[]
    | "- **User:** `\(.user_login)`\n"
      + "  - **Email:** `\(.user_email)`\n"
      + "  - **User ID:** `\(.user_id)`\n"
      + "  - **Count:** `\(.count)`\n"
      + "  - **Projects:** `\(.projects | join(", "))`\n"
      + "  - **Namespaces:** `\(.namespaces | join(", "))`\n"
      + "  - **Pipelines:** `\(.pipelines | join(", "))`\n"
      + "  - **Jobs:** `\(.jobs | join(", "))`\n"
      + "  - **Refs:** `\(.refs | join(", "))`\n"
      + "  - **Roles:** `\(.roles | join(", "))`\n"
      + "  - **Display Names:** `\(.display_names | join(", "))`\n"
      + "  - **Entity IDs:** `\(.entity_ids | join(", "))`\n"
      + "  - **Paths:** `\(.paths | join(", "))`\n"
      + "  - **Operations:** `\(.operations | join(", "))`\n"
      + "  - **First Seen:** `\(.first_seen)`\n"
      + "  - **Last Seen:** `\(.last_seen)`\n"
  ' <<< "$IDENTITY_JSON"
  printf '%s\n' ''

  printf '%s\n' '## Workload Identities'
  printf '%s\n' ''
  jq -r '
    .workload_identities[]
    | "- **Project:** `\(.project_path)`\n"
      + "  - **Namespace:** `\(.namespace_path)`\n"
      + "  - **Pipeline:** `\(.pipeline_id)`\n"
      + "  - **Job:** `\(.job_id)`\n"
      + "  - **Ref:** `\(.ref)`\n"
      + "  - **Role:** `\(.role)`\n"
      + "  - **Count:** `\(.count)`\n"
      + "  - **Users:** `\(.users | map(.user_login + " <" + .user_email + ">") | join(", "))`\n"
      + "  - **Display Names:** `\(.display_names | join(", "))`\n"
      + "  - **Entity IDs:** `\(.entity_ids | join(", "))`\n"
      + "  - **Paths:** `\(.paths | join(", "))`\n"
      + "  - **Operations:** `\(.operations | join(", "))`\n"
      + "  - **First Seen:** `\(.first_seen)`\n"
      + "  - **Last Seen:** `\(.last_seen)`\n"
  ' <<< "$IDENTITY_JSON"
  printf '%s\n' ''

  printf '%s\n' '## Full Identity Bundles'
  printf '%s\n' ''
  jq -r '
    .full_identity_bundles[]
    | "- **Display:** `\(.display_name)`\n"
      + "  - **Entity ID:** `\(.entity_id)`\n"
      + "  - **Role:** `\(.role)`\n"
      + "  - **User:** `\(.user_login)`\n"
      + "  - **Email:** `\(.user_email)`\n"
      + "  - **User ID:** `\(.user_id)`\n"
      + "  - **Project:** `\(.project_path)`\n"
      + "  - **Namespace:** `\(.namespace_path)`\n"
      + "  - **Pipeline:** `\(.pipeline_id)`\n"
      + "  - **Job:** `\(.job_id)`\n"
      + "  - **Ref:** `\(.ref)`\n"
      + "  - **Count:** `\(.count)`\n"
      + "  - **First Seen:** `\(.first_seen)`\n"
      + "  - **Last Seen:** `\(.last_seen)`\n"
      + "  - **Paths:** `\(.paths | join(", "))`\n"
      + "  - **Operations:** `\(.operations | join(", "))`\n"
  ' <<< "$IDENTITY_JSON"

  if [[ "$TIMELINE" == "true" ]]; then
    printf '%s\n' ''
    printf '%s\n' '## Timeline'
    printf '%s\n' ''
    jq -r '
      .timeline_events[]
      | "- `\(.time)` `\(.operation)` `\(.user_login)` `pipeline=\(.pipeline_id)` `job=\(.job_id)` `\(.path)`"
    ' <<< "$IDENTITY_JSON"
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
    emit_output "$(jq . <<< "$IDENTITY_JSON")"
    ;;
  md)
    emit_output "$(render_md)"
    ;;
esac
