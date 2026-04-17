#!/usr/bin/env bash
set -euo pipefail

FILES=()
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
RETRIEVE_AUDIT_FILE=""
RETRIEVE_ALL_AUDIT_FILES_DIR=""
INPUT_DIR=""
LIST_AUDIT_FILES="false"
RUNTIME="${CONTAINER_RUNTIME:-${CONTAINER_ENGINE:-auto}}"
CONTAINER_ENGINE=""
VAULT_CONTAINER_NAME="${VAULT_CONTAINER_NAME:-}"
VAULT_AUDIT_PATH="${VAULT_AUDIT_PATH:-}"
RETRIEVED_AUDIT_FILE_USED=""
REDACT="false"
REDACT_MODE="pseudo"
DETECT_DRIFT="false"
EXPLAIN="false"

if [[ -t 1 ]]; then
  C_RESET="\033[0m"
  C_BOLD="\033[1m"
  C_DIM="\033[2m"
  C_YELLOW="\033[33m"
  C_CYAN="\033[36m"
  C_ORANGE="\033[38;5;214m"
else
  C_RESET="" C_BOLD="" C_DIM="" C_YELLOW="" C_CYAN="" C_ORANGE=""
fi

print_file_list() {
  local label="$1"
  shift
  local items=("$@")
  [[ ${#items[@]} -gt 0 ]] || return 0

  printf '\n'
  printf '%b\n' "${C_BOLD}${C_CYAN}${label}${C_RESET}"
  local item
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || continue
    printf '%b %s\n' "${C_YELLOW}-${C_RESET}" "$item"
  done
}

print_run_summary() {
  local retrieved_items=()
  if [[ -n "$RETRIEVED_AUDIT_FILE_USED" ]]; then
    mapfile -t retrieved_items < <(tr ',' '\n' <<<"$RETRIEVED_AUDIT_FILE_USED")
  fi

  printf '\n%b\n' "${C_BOLD}${C_ORANGE}Parse Summary${C_RESET}"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%b %s\n' "${C_YELLOW}Report:${C_RESET}" "$OUTPUT_FILE"
  else
    printf '%b %s\n' "${C_YELLOW}Report:${C_RESET}" "stdout"
  fi

  print_file_list "Used log file(s):" "${FILES[@]}"
  print_file_list "Retrieved from container path(s):" "${retrieved_items[@]}"
}

usage() {
  echo -e "
${C_BOLD}${C_ORANGE}parse_vault.sh${C_RESET} ${C_DIM}Vault Audit Log Parser${C_RESET}

${C_BOLD}USAGE${C_RESET}
  ${C_YELLOW}parse_vault.sh${C_RESET} ${C_CYAN}<vault_audit.log> [<vault_audit.log.1> ...]${C_RESET} [options]
  ${C_YELLOW}parse_vault.sh${C_RESET} ${C_CYAN}--retrieve-audit-file <output_path>${C_RESET} [options]
  ${C_YELLOW}parse_vault.sh${C_RESET} ${C_CYAN}--retrieve-all-audit-files${C_RESET} ${C_DIM}[directory]${C_RESET} [options]
  ${C_YELLOW}parse_vault.sh${C_RESET} ${C_CYAN}--list-audit-files${C_RESET} [--runtime <docker|podman|auto>]

${C_BOLD}OPTIONS${C_RESET}
  ${C_YELLOW}--format${C_RESET} ${C_CYAN}<text|json|md>${C_RESET}              Output format ${C_DIM}(default: text)${C_RESET}
  ${C_YELLOW}--output${C_RESET} ${C_CYAN}<file>${C_RESET}                      Write output to file
  ${C_YELLOW}--secrets-only${C_RESET}                       Keep only secret/data/* style events and exclude sys/internal/ui/mounts/*
  ${C_YELLOW}--path${C_RESET} ${C_CYAN}<exact_path>${C_RESET}                  Keep only events for an exact path
  ${C_YELLOW}--path-prefix${C_RESET} ${C_CYAN}<prefix>${C_RESET}               Keep only events whose path starts with prefix
  ${C_YELLOW}--exclude-path-prefix${C_RESET} ${C_CYAN}<prefix>${C_RESET}       Exclude events whose path starts with prefix
  ${C_YELLOW}--operation${C_RESET} ${C_CYAN}<op>${C_RESET}                     Keep only events for an exact Vault operation
  ${C_YELLOW}--since${C_RESET} ${C_CYAN}<timestamp>${C_RESET}                  Keep only events at or after this UTC timestamp
  ${C_YELLOW}--until${C_RESET} ${C_CYAN}<timestamp>${C_RESET}                  Keep only events at or before this UTC timestamp
  ${C_YELLOW}--date${C_RESET} ${C_CYAN}<YYYY-MM-DD>${C_RESET}                  Keep only events on this UTC date
  ${C_YELLOW}--top${C_RESET} ${C_CYAN}<n>${C_RESET}                            Show top N human identities by access count
  ${C_YELLOW}--timeline${C_RESET}                           Print a chronological event timeline
  ${C_YELLOW}--latest-only${C_RESET}                        Print only latest secret access and core metrics
  ${C_YELLOW}--retrieve-audit-file${C_RESET} ${C_CYAN}<path>${C_RESET}         Copy the audit file from the auto-detected Vault container/path and use it as input
  ${C_YELLOW}--retrieve-all-audit-files${C_RESET} ${C_DIM}[dir]${C_RESET}      Copy all matching audit files locally and use them as input
  ${C_YELLOW}--input${C_RESET} ${C_CYAN}<dir>${C_RESET}                        Input directory for --retrieve-all-audit-files (alternative to inline value)
  ${C_YELLOW}--list-audit-files${C_RESET}                   Show detected runtime, container, active audit path, and matching audit files
  ${C_YELLOW}--runtime${C_RESET} ${C_CYAN}<docker|podman|auto>${C_RESET}       Container runtime for retrieval ${C_DIM}(default: auto)${C_RESET}
  ${C_YELLOW}--redact${C_RESET}                             Redact sensitive details in output ${C_DIM}(default mode: pseudo)${C_RESET}
  ${C_YELLOW}--redact-mode${C_RESET} ${C_CYAN}<pseudo|mask|strict>${C_RESET}   Redaction mode ${C_DIM}(default: pseudo)${C_RESET}
  ${C_YELLOW}--summary${C_RESET}                            Print only a compact summary
  ${C_YELLOW}--detect-drift${C_RESET}                       ${C_DIM}Reserved for future drift detection support${C_RESET}
  ${C_YELLOW}--explain${C_RESET}                            ${C_DIM}Reserved for future explanatory output${C_RESET}
  ${C_YELLOW}-h, --help${C_RESET}                           Show this help

${C_BOLD}EXAMPLES${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log ./vault_audit.log.1 ./vault_audit.log.2${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log ./vault_audit.log.1.gz ./vault_audit.log.2.gz${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --secrets-only${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --path secret/data/gitlab-lab${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --path-prefix secret/data/${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --operation read${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --since 2026-03-19T13:00:00Z${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --until 2026-03-19T14:00:00Z${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --date 2026-03-19${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --top 10 --timeline${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --latest-only${C_RESET}
  ${C_YELLOW}./parse_vault.sh --list-audit-files --runtime podman${C_RESET}
  ${C_YELLOW}./parse_vault.sh --retrieve-audit-file ./input/vault_audit.log${C_RESET}
  ${C_YELLOW}./parse_vault.sh --retrieve-all-audit-files ./input --runtime podman --summary${C_RESET}
  ${C_YELLOW}./parse_vault.sh --runtime podman --retrieve-audit-file ./input/vault_audit.log${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --format json${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --format md --output vault_identities.md${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --secrets-only --summary${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --secrets-only --redact --format json${C_RESET}
  ${C_YELLOW}./parse_vault.sh ./vault_audit.log --secrets-only --redact --redact-mode strict --format md${C_RESET}
"
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || fail "$option requires a value"
}

detect_runtime() {
  if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    printf '%s\n' "podman"
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf '%s\n' "docker"
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    printf '%s\n' "podman"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    printf '%s\n' "docker"
    return 0
  fi

  fail "Could not detect a container runtime. Install Docker or Podman, or pass --runtime <docker|podman>"
}

find_compose_file() {
  local dir="$PWD"
  local candidate

  while [[ "$dir" != "/" ]]; do
    for candidate in \
      "$dir/docker-compose.yml" \
      "$dir/docker-compose.yaml" \
      "$dir/compose.yml" \
      "$dir/compose.yaml"
    do
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    dir="$(dirname "$dir")"
  done

  return 1
}

detect_compose_vault_container_name() {
  local compose_file=""
  local container_name=""

  compose_file="$(find_compose_file || true)"
  [[ -n "$compose_file" ]] || return 1

  container_name="$(
    awk '
      BEGIN {
        in_services = 0
        in_vault = 0
      }
      /^services:[[:space:]]*$/ {
        in_services = 1
        next
      }
      in_services && /^[^[:space:]]/ {
        in_services = 0
        in_vault = 0
      }
      in_services && /^[[:space:]]{2}vault:[[:space:]]*$/ {
        in_vault = 1
        next
      }
      in_vault && /^[[:space:]]{2}[A-Za-z0-9_-]+:[[:space:]]*$/ {
        in_vault = 0
      }
      in_vault && /^[[:space:]]{4}container_name:[[:space:]]*/ {
        sub(/^[[:space:]]{4}container_name:[[:space:]]*/, "", $0)
        gsub(/["'\''"]/, "", $0)
        print
        exit
      }
    ' "$compose_file"
  )"

  [[ -n "$container_name" ]] || return 1
  "$CONTAINER_ENGINE" inspect "$container_name" >/dev/null 2>&1 || return 1
  [[ "$("$CONTAINER_ENGINE" inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" == "true" ]] || return 1
  VAULT_CONTAINER_NAME="$container_name"
}

detect_vault_container_name() {
  if detect_compose_vault_container_name; then
    return 0
  fi

  local candidates
  candidates="$(
    "$CONTAINER_ENGINE" ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null | awk '
      BEGIN { IGNORECASE = 1 }
      {
        name = $1
        image = $2
        score = 0
        if (name == "gitlab-vault" || name == "vault-lab" || name == "vault") score += 100
        if (name ~ /vault/) score += 10
        if (image ~ /hashicorp\/vault/ || image ~ /vault-enterprise/ || image ~ /\/vault(:|$)/) score += 5
        if (name ~ /agent/ || name ~ /vault[_-]?agent/) score -= 50
        if (score > 0) print score "\t" name
      }
    ' | sort -rn -k1,1 -k2,2 | awk -F '\t' '!seen[$2]++ { print $2 }'
  )"

  if [[ -z "$candidates" ]]; then
    fail "Could not detect a Vault container. Set VAULT_CONTAINER_NAME or use a runtime where the Vault container exists"
  fi

  if [[ "$(printf '%s\n' "$candidates" | wc -l | tr -d ' ')" -gt 1 ]]; then
    VAULT_CONTAINER_NAME="$(printf '%s\n' "$candidates" | head -n 1)"
    return 0
  fi

  VAULT_CONTAINER_NAME="$candidates"
}

detect_vault_audit_path() {
  local candidate
  local candidates=(
    "/tmp/vault_audit.log"
    "/vault/audit/vault-audit.log"
    "/var/log/vault_audit.log"
    "/vault/logs/vault_audit.log"
    "/vault/file/vault_audit.log"
    "/tmp/audit.log"
    "/var/log/audit.log"
  )

  for candidate in "${candidates[@]}"; do
    if "$CONTAINER_ENGINE" exec "$VAULT_CONTAINER_NAME" sh -c "[ -f \"$candidate\" ]" >/dev/null 2>&1; then
      VAULT_AUDIT_PATH="$candidate"
      return 0
    fi
  done

  fail "Could not find a Vault audit log in common locations inside container '$VAULT_CONTAINER_NAME'. Audit logging may not be enabled. Set VAULT_AUDIT_PATH explicitly if the log is elsewhere"
}

resolve_runtime() {
  case "$RUNTIME" in
  auto)
    CONTAINER_ENGINE="$(detect_runtime)"
    ;;
  docker | podman)
    command -v "$RUNTIME" >/dev/null 2>&1 || fail "Selected runtime '$RUNTIME' is not installed"
    CONTAINER_ENGINE="$RUNTIME"
    ;;
  *)
    fail "Invalid --runtime: $RUNTIME. Expected one of: docker, podman, auto"
    ;;
  esac
}

emit_output() {
  local content="$1"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$content" >"$OUTPUT_FILE"
  else
    printf '%s\n' "$content"
  fi
  print_run_summary
}

while [[ $# -gt 0 && "${1:-}" != --* ]]; do
  FILES+=("$1")
  shift
done

while [[ $# -gt 0 ]]; do
  case "$1" in
  --format)
    require_value "$1" "${2:-}"
    FORMAT="${2:-}"
    shift 2
    ;;
  --output)
    require_value "$1" "${2:-}"
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
    require_value "$1" "${2:-}"
    PATH_EXACT="${2:-}"
    shift 2
    ;;
  --path-prefix)
    require_value "$1" "${2:-}"
    PATH_PREFIX="${2:-}"
    shift 2
    ;;
  --exclude-path-prefix)
    require_value "$1" "${2:-}"
    EXCLUDE_PATH_PREFIX="${2:-}"
    shift 2
    ;;
  --operation)
    require_value "$1" "${2:-}"
    OPERATION="${2:-}"
    shift 2
    ;;
  --since)
    require_value "$1" "${2:-}"
    SINCE="${2:-}"
    shift 2
    ;;
  --until)
    require_value "$1" "${2:-}"
    UNTIL="${2:-}"
    shift 2
    ;;
  --date)
    require_value "$1" "${2:-}"
    DATE_ONLY="${2:-}"
    shift 2
    ;;
  --top)
    require_value "$1" "${2:-}"
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
  --retrieve-audit-file)
    require_value "$1" "${2:-}"
    RETRIEVE_AUDIT_FILE="${2:-}"
    shift 2
    ;;
  --retrieve-all-audit-files)
    if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
      RETRIEVE_ALL_AUDIT_FILES_DIR="${2:-}"
      shift 2
    else
      RETRIEVE_ALL_AUDIT_FILES_DIR="__from_input__"
      shift
    fi
    ;;
  --input)
    require_value "$1" "${2:-}"
    INPUT_DIR="${2:-}"
    shift 2
    ;;
  --list-audit-files)
    LIST_AUDIT_FILES="true"
    shift
    ;;
  --runtime)
    require_value "$1" "${2:-}"
    RUNTIME="${2:-}"
    shift 2
    ;;
  --redact)
    REDACT="true"
    shift
    ;;
  --redact-mode)
    require_value "$1" "${2:-}"
    REDACT="true"
    REDACT_MODE="${2:-}"
    shift 2
    ;;
  --detect-drift)
    DETECT_DRIFT="true"
    shift
    ;;
  --explain)
    EXPLAIN="true"
    shift
    ;;    
  -h | --help)
    usage
    exit 0
    ;;
  *)
    fail "Unknown argument: $1"
    ;;
  esac
done

list_vault_audit_files() {
  local audit_dir audit_base audit_stem
  audit_dir="$(dirname "$VAULT_AUDIT_PATH")"
  audit_base="$(basename "$VAULT_AUDIT_PATH")"
  audit_stem="${audit_base%.log}"

  # shellcheck disable=SC2016
  "$CONTAINER_ENGINE" exec "$VAULT_CONTAINER_NAME" sh -c '
    dir="$1"
    base="$2"
    stem="$3"
    find "$dir" -maxdepth 1 -type f \
      \( -name "$base" -o -name "$stem*.log" -o -name "$stem*.log.gz" \) \
      | sort
  ' sh "$audit_dir" "$audit_base" "$audit_stem" 2>/dev/null
}

print_audit_file_listing() {
  local audit_files="$1"
  printf '%s\n' "Detected runtime   : $CONTAINER_ENGINE"
  printf '%s\n' "Vault container    : $VAULT_CONTAINER_NAME"
  printf '%s\n' "Active audit path  : $VAULT_AUDIT_PATH"
  printf '%s\n' "Available files"
  printf '%s\n' "---------------"
  if [[ -n "$audit_files" ]]; then
    printf '%s\n' "$audit_files"
  else
    printf '%s\n' "(none found)"
  fi
}

prepare_audit_retrieval() {
  resolve_runtime
  if [[ -z "$VAULT_CONTAINER_NAME" ]]; then
    detect_vault_container_name
  fi
  if [[ -z "$VAULT_AUDIT_PATH" ]]; then
    detect_vault_audit_path
  fi
}

# Resolve --input into the retrieve flags that need it
if [[ "$RETRIEVE_ALL_AUDIT_FILES_DIR" == "__from_input__" ]]; then
  [[ -n "$INPUT_DIR" ]] || fail "--retrieve-all-audit-files used without a directory value and --input was not set"
  RETRIEVE_ALL_AUDIT_FILES_DIR="$INPUT_DIR"
fi

if [[ "$LIST_AUDIT_FILES" == "true" || -n "$RETRIEVE_AUDIT_FILE" || -n "$RETRIEVE_ALL_AUDIT_FILES_DIR" ]]; then
  prepare_audit_retrieval
fi

if [[ "$LIST_AUDIT_FILES" == "true" ]]; then
  print_audit_file_listing "$(list_vault_audit_files)"
  exit 0
fi

if [[ -n "$RETRIEVE_AUDIT_FILE" ]]; then
  RETRIEVED_AUDIT_FILE_USED="$VAULT_AUDIT_PATH"
  mkdir -p "$(dirname "$RETRIEVE_AUDIT_FILE")"
  "$CONTAINER_ENGINE" cp "${VAULT_CONTAINER_NAME}:${VAULT_AUDIT_PATH}" "$RETRIEVE_AUDIT_FILE"
  FILES+=("$RETRIEVE_AUDIT_FILE")
fi

if [[ -n "$RETRIEVE_ALL_AUDIT_FILES_DIR" ]]; then
  local_audit_files=()
  remote_audit_files=()
  mkdir -p "$RETRIEVE_ALL_AUDIT_FILES_DIR"
  while IFS= read -r audit_file; do
    [[ -n "$audit_file" ]] || continue
    local_path="$RETRIEVE_ALL_AUDIT_FILES_DIR/$(basename "$audit_file")"
    "$CONTAINER_ENGINE" cp "${VAULT_CONTAINER_NAME}:${audit_file}" "$local_path"
    FILES+=("$local_path")
    local_audit_files+=("$local_path")
    remote_audit_files+=("$audit_file")
  done < <(list_vault_audit_files)

  [[ ${#local_audit_files[@]} -gt 0 ]] || fail "No audit files found to retrieve from '$VAULT_CONTAINER_NAME'"
  RETRIEVED_AUDIT_FILE_USED="$(printf '%s\n' "${remote_audit_files[@]}" | paste -sd ',' -)"
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  usage
  exit 1
fi

[[ ${#FILES[@]} -gt 0 ]] || fail "Provide at least one vault audit log file or use --retrieve-audit-file <path>"
for file_path in "${FILES[@]}"; do
  [[ -f "$file_path" ]] || fail "File not found: $file_path"
done

case "$FORMAT" in
text | json | md) ;;
*)
  fail "Invalid format: $FORMAT"
  ;;
esac

case "$REDACT_MODE" in
pseudo | mask | strict) ;;
*)
  fail "Invalid --redact-mode: $REDACT_MODE. Expected one of: pseudo, mask, strict"
  ;;
esac

if [[ "$DETECT_DRIFT" == "true" || "$EXPLAIN" == "true" ]]; then
  fail "--detect-drift and --explain are not implemented yet"
fi

if [[ -n "$TOP_N" && ! "$TOP_N" =~ ^[1-9][0-9]*$ ]]; then
  fail "--top must be a positive integer"
fi

if [[ -n "$OPERATION" ]]; then
  case "$OPERATION" in
  read | list | update | delete | create | patch) ;;
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

if [[ "$SECRETS_ONLY" == "true" && -z "$EXCLUDE_PATH_PREFIX" ]]; then
  EXCLUDE_PATH_PREFIX="sys/internal/ui/mounts/"
fi

read_logs() {
  local file_path
  for file_path in "${FILES[@]}"; do
    case "$file_path" in
      *.gz) gzip -dc "$file_path" ;;
      *) cat "$file_path" ;;
    esac
  done
}

SOURCE_FILES="$(IFS=,; echo "${FILES[*]}")"

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
  read_logs | jq -s \
    --argjson cfg "$FILTER_JSON" \
    --arg source_file "$SOURCE_FILES" \
    --arg retrieved_audit_file "$RETRIEVED_AUDIT_FILE_USED" \
    -f <(
      cat <<'EOF'
def normalize_time:
  sub("\\.[0-9]+(?=Z|[+-][0-9]{2}:[0-9]{2}$)"; "");

def to_epoch_or_null:
  try (normalize_time | fromdateiso8601) catch null;

def to_utc_date_or_empty:
  (to_epoch_or_null as $epoch
   | if $epoch == null then ""
     else ($epoch | gmtime | strftime("%Y-%m-%d"))
     end);

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
    then (
      ((.time // "") | to_epoch_or_null) as $event_time
      | ($cfg.since | to_epoch_or_null) as $since_time
      | if ($event_time == null or $since_time == null)
        then false
        else $event_time >= $since_time
        end
    )
    else true
    end
  )
  and (
    if ($cfg.until | length) > 0
    then (
      ((.time // "") | to_epoch_or_null) as $event_time
      | ($cfg.until | to_epoch_or_null) as $until_time
      | if ($event_time == null or $until_time == null)
        then false
        else $event_time <= $until_time
        end
    )
    else true
    end
  )
  and (
    if ($cfg.date_only | length) > 0
    then ((.time // "") | to_utc_date_or_empty) == $cfg.date_only
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
      auth_method: (
        if ((.auth.display_name // "") | startswith("jwt-")) then "jwt"
        elif ((.auth.display_name // "") | startswith("ldap-")) then "ldap"
        elif (.request.mount_type // "") == "token" then "token"
        else "other"
        end
      ),
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
    schema_version: "1.0",
    generated_at: (now | todateiso8601),
    source_file: $source_file,
    retrieved_audit_file: (
      if ($retrieved_audit_file | length) > 0
      then $retrieved_audit_file
      else null
      end
    ),
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
    total_secret_paths: (
      $events
      | map(select(.path | startswith("secret/data/")) | .path)
      | unique
      | length
    ),
    latest_secret_access: (
      $events
      | map(select(.path | startswith("secret/data/")))
      | sort_by(.time)
      | last // null
    ),
    top_path_overall: (
      $events
      | group_by(.path)
      | map({
          path: .[0].path,
          count: length
        })
      | sort_by(.count, .path)
      | reverse
      | .[0] // { path: "", count: 0 }
    ),

    top_secret_path: (
      $events
      | map(select(.path | startswith("secret/data/")))
      | group_by(.path)
      | map({
          path: .[0].path,
          count: length
        })
      | sort_by(.count, .path)
      | reverse
      | .[0] // { path: "", count: 0 }
    ),
    secret_paths: (
      $events
      | map(select(.path | startswith("secret/data/")))
      | sort_by(.path, .time)
      | group_by(.path)
      | map({
          path: .[0].path,
          count: length,
          first_seen: (map(.time) | sort | first),
          last_seen: (map(.time) | sort | last)
        })
      | sort_by(.count, .path)
      | reverse
    ),
    timeline_events: (
      $events
      | sort_by(.time)
      | map({
          time,
          auth_method,
          user_login,
          user_email,
          user_id,
          project_path,
          namespace_path,
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
    unique_entities: (
      $events
      | map(select((.entity_id // "") != "") | .entity_id)
      | unique
      | length
    ),

    unique_correlated_clients: (
      $events
      | map({
          entity_id,
          project_path,
          pipeline_id,
          job_id
        })
      | unique
      | length
    ),    
    correlations: (
      $events
      | map(select((.entity_id // "") != ""))
      | sort_by(.entity_id, .time)
      | group_by(.entity_id)
      | map({
          entity_id: .[0].entity_id,
          count: length,
          auth_methods: (map(.auth_method) | unique | sort),
          display_names: (map(.display_name) | map(select(length > 0)) | unique | sort),
          user_logins: (map(.user_login) | map(select(length > 0)) | unique | sort),
          user_emails: (map(.user_email) | map(select(length > 0)) | unique | sort),
          roles: (map(.role) | map(select(length > 0)) | unique | sort),
          projects: (map(.project_path) | map(select(length > 0)) | unique | sort),
          namespaces: (map(.namespace_path) | map(select(length > 0)) | unique | sort),
          pipelines: (map(.pipeline_id) | map(select(length > 0)) | unique | sort),
          jobs: (map(.job_id) | map(select(length > 0)) | unique | sort),
          refs: (map(.ref) | map(select(length > 0)) | unique | sort),
          secret_paths: (
            map(select(.path | startswith("secret/data/")) | .path)
            | unique
            | sort
          ),
          operations: (map(.operation) | unique | sort),
          first_seen: (map(.time) | sort | first),
          last_seen: (map(.time) | sort | last)
        })
      | sort_by(.last_seen, .entity_id)
      | reverse
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
EOF
    )
)"

if [[ "$REDACT" == "true" ]]; then
  case "$REDACT_MODE" in
  pseudo)
    IDENTITY_JSON="$(
      jq -f <(
        cat <<'EOF'
def nonempty:
  select(. != null and . != "");

def canonical_human_key($o):
  ($o.user_id // $o.user_email // $o.user_login // $o.display_name // "");

def build_map($values; $prefix):
  reduce ($values | map(nonempty) | unique | sort[]) as $v
    ({}; . + {($v): ($prefix + "-" + ((length + 1) | tostring))});

def lookup_or_blank($map; $value):
  if ($value // "") == "" then "" else ($map[$value] // "") end;

def human_lookup($human_map; $value):
  if ($value // "") == "" then ""
  else ($human_map[$value] // "Human-Unknown")
  end;

def pseudo_human_fields($human_map):
  . as $o
  | ($human_map[canonical_human_key($o)] // "Human-Unknown") as $h
  | .user_login = $h
  | .user_email = $h
  | .user_id = $h
  | .display_name = $h;

def pseudo_common_fields($entity_map; $project_map; $namespace_map; $pipeline_map; $job_map; $ref_map; $path_map):
  .entity_id = lookup_or_blank($entity_map; .entity_id)
  | .project_path = lookup_or_blank($project_map; .project_path)
  | .namespace_path = lookup_or_blank($namespace_map; .namespace_path)
  | .pipeline_id = lookup_or_blank($pipeline_map; .pipeline_id)
  | .job_id = lookup_or_blank($job_map; .job_id)
  | .ref = lookup_or_blank($ref_map; .ref)
  | .path = lookup_or_blank($path_map; .path);

def pseudo_correlation($human_map; $entity_map; $project_map; $namespace_map; $pipeline_map; $job_map; $ref_map; $path_map):
  .entity_id = lookup_or_blank($entity_map; .entity_id)
  | .display_names = (.display_names | map(human_lookup($human_map; .)) | unique | sort)
  | .user_logins = (.user_logins | map(human_lookup($human_map; .)) | unique | sort)
  | .user_emails = (.user_emails | map(human_lookup($human_map; .)) | unique | sort)
  | .projects = (.projects | map(lookup_or_blank($project_map; .)) | map(select(. != "")) | unique | sort)
  | .namespaces = (.namespaces | map(lookup_or_blank($namespace_map; .)) | map(select(. != "")) | unique | sort)
  | .pipelines = (.pipelines | map(lookup_or_blank($pipeline_map; .)) | map(select(. != "")) | unique | sort)
  | .jobs = (.jobs | map(lookup_or_blank($job_map; .)) | map(select(. != "")) | unique | sort)
  | .refs = (.refs | map(lookup_or_blank($ref_map; .)) | map(select(. != "")) | unique | sort)
  | .secret_paths = (.secret_paths | map(lookup_or_blank($path_map; .)) | map(select(. != "")) | unique | sort);

. as $root
| (
    [
      ($root.latest_secret_access? | canonical_human_key(.)),
      ($root.timeline_events[]? | canonical_human_key(.)),
      ($root.human_identities[]? | canonical_human_key(.)),
      ($root.workload_identities[]?.users[]? | canonical_human_key(.)),
      ($root.full_identity_bundles[]? | canonical_human_key(.)),
      ($root.correlations[]?.user_logins[]?),
      ($root.correlations[]?.user_emails[]?),
      ($root.correlations[]?.display_names[]?)
    ] | build_map(.; "Human")
  ) as $human_map
| (
    [
      ($root.latest_secret_access? | .entity_id?),
      ($root.timeline_events[]? | .entity_id?),
      ($root.human_identities[]?.entity_ids[]?),
      ($root.workload_identities[]?.entity_ids[]?),
      ($root.full_identity_bundles[]? | .entity_id?),
      ($root.correlations[]? | .entity_id?)
    ] | build_map(.; "Entity")
  ) as $entity_map
| (
    [
      ($root.latest_secret_access? | .project_path?),
      ($root.timeline_events[]? | .project_path?),
      ($root.human_identities[]?.projects[]?),
      ($root.workload_identities[]? | .project_path?),
      ($root.full_identity_bundles[]? | .project_path?),
      ($root.correlations[]?.projects[]?)
    ] | build_map(.; "Project")
  ) as $project_map
| (
    [
      ($root.latest_secret_access? | .namespace_path?),
      ($root.timeline_events[]? | .namespace_path?),
      ($root.human_identities[]?.namespaces[]?),
      ($root.workload_identities[]? | .namespace_path?),
      ($root.full_identity_bundles[]? | .namespace_path?),
      ($root.correlations[]?.namespaces[]?)
    ] | build_map(.; "Namespace")
  ) as $namespace_map
| (
    [
      ($root.latest_secret_access? | .pipeline_id?),
      ($root.timeline_events[]? | .pipeline_id?),
      ($root.human_identities[]?.pipelines[]?),
      ($root.workload_identities[]? | .pipeline_id?),
      ($root.full_identity_bundles[]? | .pipeline_id?),
      ($root.correlations[]?.pipelines[]?)
    ] | build_map(.; "Pipeline")
  ) as $pipeline_map
| (
    [
      ($root.latest_secret_access? | .job_id?),
      ($root.timeline_events[]? | .job_id?),
      ($root.human_identities[]?.jobs[]?),
      ($root.workload_identities[]? | .job_id?),
      ($root.full_identity_bundles[]? | .job_id?),
      ($root.correlations[]?.jobs[]?)
    ] | build_map(.; "Job")
  ) as $job_map
| (
    [
      ($root.latest_secret_access? | .ref?),
      ($root.timeline_events[]? | .ref?),
      ($root.human_identities[]?.refs[]?),
      ($root.workload_identities[]? | .ref?),
      ($root.full_identity_bundles[]? | .ref?),
      ($root.correlations[]?.refs[]?)
    ] | build_map(.; "Ref")
  ) as $ref_map
| (
    [
      ($root.latest_secret_access? | .path?),
      ($root.top_path? | .path?),
      ($root.secret_paths[]? | .path?),
      ($root.timeline_events[]? | .path?),
      ($root.human_identities[]?.paths[]?),
      ($root.workload_identities[]?.paths[]?),
      ($root.full_identity_bundles[]?.paths[]?),
      ($root.correlations[]?.secret_paths[]?)
    ] | build_map(.; "SecretPath")
  ) as $path_map
| .latest_secret_access |= (
    if . == null then .
    else
      pseudo_human_fields($human_map)
      | pseudo_common_fields($entity_map; $project_map; $namespace_map; $pipeline_map; $job_map; $ref_map; $path_map)
    end
  )
| .top_path.path |= lookup_or_blank($path_map; .)
| .secret_paths |= map(
    .path |= lookup_or_blank($path_map; .)
  )
| .timeline_events |= map(
    pseudo_human_fields($human_map)
    | pseudo_common_fields($entity_map; $project_map; $namespace_map; $pipeline_map; $job_map; $ref_map; $path_map)
  )
| .correlations |= map(
    pseudo_correlation($human_map; $entity_map; $project_map; $namespace_map; $pipeline_map; $job_map; $ref_map; $path_map)
  )
| .human_identities |= map(
    pseudo_human_fields($human_map)
    | .display_names = [(.user_login)]
    | .entity_ids = (.entity_ids | map(lookup_or_blank($entity_map; .)) | map(select(. != "")) | unique | sort)
    | .projects = (.projects | map(lookup_or_blank($project_map; .)) | map(select(. != "")) | unique | sort)
    | .namespaces = (.namespaces | map(lookup_or_blank($namespace_map; .)) | map(select(. != "")) | unique | sort)
    | .pipelines = (.pipelines | map(lookup_or_blank($pipeline_map; .)) | map(select(. != "")) | unique | sort)
    | .jobs = (.jobs | map(lookup_or_blank($job_map; .)) | map(select(. != "")) | unique | sort)
    | .refs = (.refs | map(lookup_or_blank($ref_map; .)) | map(select(. != "")) | unique | sort)
    | .paths = (.paths | map(lookup_or_blank($path_map; .)) | map(select(. != "")) | unique | sort)
  )
| .workload_identities |= map(
    .project_path = lookup_or_blank($project_map; .project_path)
    | .namespace_path = lookup_or_blank($namespace_map; .namespace_path)
    | .pipeline_id = lookup_or_blank($pipeline_map; .pipeline_id)
    | .job_id = lookup_or_blank($job_map; .job_id)
    | .ref = lookup_or_blank($ref_map; .ref)
    | .display_names = (
        .users
        | map($human_map[canonical_human_key(.)] // "Human-Unknown")
        | unique
        | sort
      )
    | .entity_ids = (.entity_ids | map(lookup_or_blank($entity_map; .)) | map(select(. != "")) | unique | sort)
    | .users |= map(
        pseudo_human_fields($human_map)
      )
    | .paths = (.paths | map(lookup_or_blank($path_map; .)) | map(select(. != "")) | unique | sort)
  )
| .full_identity_bundles |= map(
    pseudo_human_fields($human_map)
    | .entity_id = lookup_or_blank($entity_map; .entity_id)
    | .project_path = lookup_or_blank($project_map; .project_path)
    | .namespace_path = lookup_or_blank($namespace_map; .namespace_path)
    | .pipeline_id = lookup_or_blank($pipeline_map; .pipeline_id)
    | .job_id = lookup_or_blank($job_map; .job_id)
    | .ref = lookup_or_blank($ref_map; .ref)
    | .paths = (.paths | map(lookup_or_blank($path_map; .)) | map(select(. != "")) | unique | sort)
    | del(.path)
  )
| .redacted = true
| .redact_mode = "pseudo"
EOF
      ) <<<"$IDENTITY_JSON"
    )"
    ;;
  mask)
    IDENTITY_JSON="$(
      jq -f <(
        cat <<'EOF'
def mask_email:
  if . == null or . == "" then .
  elif contains("@") then
    (split("@") as $p
     | (($p[0][0:1] // "") + "***@" + $p[1]))
  else "[redacted]"
  end;

def mask_text:
  if . == null or . == "" then .
  elif contains("@") then mask_email
  elif length <= 2 then "[redacted]"
  else (.[0:1] + "***")
  end;

def mask_id:
  if . == null or . == "" then .
  elif length <= 8 then "[redacted]"
  else (.[0:8] + "...")
  end;

def mask_path:
  if . == null or . == "" then .
  elif startswith("secret/data/") then "secret/data/[redacted]"
  elif startswith("secret/metadata/") then "secret/metadata/[redacted]"
  elif contains("/") then ((split("/")[0]) + "/[redacted]")
  else "[redacted]"
  end;

def mask_project:
  if . == null or . == "" then .
  elif contains("/") then ((split("/")[0]) + "/[redacted]")
  else "[redacted-project]"
  end;

def mask_namespace:
  if . == null or . == "" then .
  else "[redacted-namespace]"
  end;

def redact:
  if type == "object" then
    with_entries(
      .value |= redact
      | if .key == "user_email" then .value |= mask_email
        elif .key == "user_login" then .value |= mask_text
        elif .key == "user_id" then .value = "[redacted]"
        elif .key == "display_name" then .value |= mask_text
        elif .key == "display_names" then .value |= map(mask_text)
        elif .key == "entity_id" then .value |= mask_id
        elif .key == "entity_ids" then .value |= map(mask_id)
        elif .key == "project_path" then .value |= mask_project
        elif .key == "projects" then .value |= map(mask_project)
        elif .key == "namespace_path" then .value |= mask_namespace
        elif .key == "namespaces" then .value |= map(mask_namespace)
        elif .key == "pipeline_id" then .value = "[redacted]"
        elif .key == "pipelines" then .value |= map("[redacted]")
        elif .key == "job_id" then .value = "[redacted]"
        elif .key == "jobs" then .value |= map("[redacted]")
        elif .key == "ref" then .value = "[redacted]"
        elif .key == "refs" then .value |= map("[redacted]")
        elif .key == "path" then .value |= mask_path
        elif .key == "paths" then .value |= map(mask_path)
        elif .key == "user_logins" then .value |= map(mask_text)
        elif .key == "user_emails" then .value |= map(mask_email)
        elif .key == "secret_paths" then .value |= map(mask_path)
        else .
        end
    )
  elif type == "array" then map(redact)
  else .
  end;

redact
| .redacted = true
| .redact_mode = "mask"
EOF
      ) <<<"$IDENTITY_JSON"
    )"
    ;;
  strict)
    IDENTITY_JSON="$(
      jq -f <(
        cat <<'EOF'
def redact_strict:
  if type == "object" then
    with_entries(
      .value |= redact_strict
      | if (.key | IN("user_login","user_email","user_id","display_name","project_path","namespace_path","pipeline_id","job_id","ref","path","entity_id","source_file","retrieved_audit_file","role")) then
          .value = "[redacted]"
        elif (.key | IN("display_names","entity_ids","projects","namespaces","pipelines","jobs","refs","paths","user_logins","user_emails","secret_paths","roles")) then
          .value = ["[redacted]"]
        else .
        end
    )
  elif type == "array" then map(redact_strict)
  else .
  end;

redact_strict
| .redacted = true
| .redact_mode = "strict"
EOF
      ) <<<"$IDENTITY_JSON"
    )"
    ;;
  esac
fi

TOTAL_EVENTS="$(jq -r '.total_events' <<<"$IDENTITY_JSON")"

render_text() {
  local latest_event=""
  latest_event="$(jq -r '.latest_secret_access' <<<"$IDENTITY_JSON")"

  printf '%s\n' ''
  printf '%s\n' '🔎 VAULT IDENTITY INVENTORY'
  printf '%s\n' '==========================='
  printf '%s\n' ''

  if [[ "$(jq -r '.redacted // false' <<<"$IDENTITY_JSON")" == "true" ]]; then
    printf '⚠️  Redaction enabled (%s)\n' "$(jq -r '.redact_mode // "unknown"' <<<"$IDENTITY_JSON")"
    printf '%s\n' ''
  fi

  if [[ "$latest_event" != "null" ]]; then
    printf '%s\n' '🔐 Latest Secret Access'
    printf '%s\n' '----------------------'
    printf 'User      : %s\n' "$(jq -r '.user_login' <<<"$latest_event")"
    printf 'Email     : %s\n' "$(jq -r '.user_email' <<<"$latest_event")"
    printf 'Project   : %s\n' "$(jq -r '.project_path' <<<"$latest_event")"
    printf 'Pipeline  : %s\n' "$(jq -r '.pipeline_id' <<<"$latest_event")"
    printf 'Job       : %s\n' "$(jq -r '.job_id' <<<"$latest_event")"
    printf 'Ref       : %s\n' "$(jq -r '.ref' <<<"$latest_event")"
    printf 'Role      : %s\n' "$(jq -r '.role' <<<"$latest_event")"
    printf 'Path      : %s\n' "$(jq -r '.path' <<<"$latest_event")"
    printf 'Operation : %s\n' "$(jq -r '.operation' <<<"$latest_event")"
    printf 'Time      : %s\n' "$(jq -r '.time' <<<"$latest_event")"
    printf '%s\n' ''
  fi

  printf 'Total audit events         : %s\n' "$(jq -r '.total_events' <<<"$IDENTITY_JSON")"
  printf 'Total read events          : %s\n' "$(jq -r '.read_events' <<<"$IDENTITY_JSON")"
  printf 'Total secret read events   : %s\n' "$(jq -r '.secret_read_events' <<<"$IDENTITY_JSON")"
  printf 'Unique human identities    : %s\n' "$(jq -r '.unique_humans' <<<"$IDENTITY_JSON")"
  printf 'Unique workload identities : %s\n' "$(jq -r '.unique_workloads' <<<"$IDENTITY_JSON")"
  printf 'Unique entities            : %s\n' "$(jq -r '.unique_entities' <<<"$IDENTITY_JSON")"
  printf 'Fully correlated workload clients : %s\n' "$(jq -r '.unique_correlated_clients' <<<"$IDENTITY_JSON")"
  printf 'Top path overall          : %s (%s)\n' \
    "$(jq -r '.top_path_overall.path' <<<"$IDENTITY_JSON")" \
    "$(jq -r '.top_path_overall.count' <<<"$IDENTITY_JSON")"
  printf 'Top secret path           : %s (%s)\n' \
    "$(jq -r '.top_secret_path.path' <<<"$IDENTITY_JSON")" \
    "$(jq -r '.top_secret_path.count' <<<"$IDENTITY_JSON")"
  printf '%s\n' ''

  printf '%s\n' 'Applied Filters'
  printf '%s\n' '---------------'
  printf 'Secrets only           : %s\n' "$(jq -r '.filters.secrets_only' <<<"$IDENTITY_JSON")"
  printf 'Exact path             : %s\n' "$(jq -r '.filters.path_exact // ""' <<<"$IDENTITY_JSON")"
  printf 'Path prefix            : %s\n' "$(jq -r '.filters.path_prefix // ""' <<<"$IDENTITY_JSON")"
  printf 'Excluded path prefix   : %s\n' "$(jq -r '.filters.exclude_path_prefix // ""' <<<"$IDENTITY_JSON")"
  printf 'Operation              : %s\n' "$(jq -r '.filters.operation // ""' <<<"$IDENTITY_JSON")"
  printf 'Since                  : %s\n' "$(jq -r '.filters.since // ""' <<<"$IDENTITY_JSON")"
  printf 'Until                  : %s\n' "$(jq -r '.filters.until // ""' <<<"$IDENTITY_JSON")"
  printf 'Date                   : %s\n' "$(jq -r '.filters.date_only // ""' <<<"$IDENTITY_JSON")"
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
    ' <<<"$IDENTITY_JSON"
    return
  fi

  printf '%s\n' '🔗 Identity Correlations'
  printf '%s\n' '------------------------'
  jq -r '
    .correlations[]
    | "Entity ID   : \(.entity_id)\n"
      + "Auth Method : \(.auth_methods | join(", "))\n"
      + "Display     : \(.display_names | join(", "))\n"
      + "User Login  : \(.user_logins | join(", "))\n"
      + "Email       : \(.user_emails | join(", "))\n"
      + "Project     : \(.projects | join(", "))\n"
      + "Pipeline    : \(.pipelines | join(", "))\n"
      + "Job         : \(.jobs | join(", "))\n"
      + "Secret Path : \(.secret_paths | join(", "))\n"
      + "Role        : \(.roles | join(", "))\n"
      + "Refs        : \(.refs | join(", "))\n"
      + "Ops         : \(.operations | join(", "))\n"
      + "Events      : \(.count)\n"
      + "First Seen  : \(.first_seen)\n"
      + "Last Seen   : \(.last_seen)\n"
  ' <<<"$IDENTITY_JSON"
  printf '%s\n' ''

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
    ' <<<"$IDENTITY_JSON"
    printf '%s\n' ''
  fi

  printf '%s\n' '👤 Human Identities'
  printf '%s\n' '-------------------'
  jq -r '
    .human_identities[]
    | "Events     : \(.count)\n"
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
  ' <<<"$IDENTITY_JSON"
  printf '%s\n' ''

  printf '%s\n' '⚙️ Workload Identities'
  printf '%s\n' '----------------------'
  jq -r '
    .workload_identities[]
    | "Events     : \(.count)\n"
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
  ' <<<"$IDENTITY_JSON"
  printf '%s\n' ''

  printf '%s\n' '🧩 Full Identity Bundles'
  printf '%s\n' '------------------------'
  jq -r '
    .full_identity_bundles[]
    | "Events     : \(.count)\n"
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
  ' <<<"$IDENTITY_JSON"

  if [[ "$TIMELINE" == "true" ]]; then
    printf '%s\n' ''
    printf '%s\n' '🕒 Timeline'
    printf '%s\n' '-----------'
    jq -r '
      .timeline_events[]
      | "\(.time)\t\(.auth_method)\t\(.user_login)\t\(.operation)\tpipeline=\(.pipeline_id)\tjob=\(.job_id)\t\(.path)"
    ' <<<"$IDENTITY_JSON"
    printf '%s\n' ''
  fi
}

render_md() {
  cat <<EOF
# 🔎 Vault Identity Inventory

$(if [[ "$(jq -r '.redacted // false' <<<"$IDENTITY_JSON")" == "true" ]]; then printf '> ⚠️ Redaction enabled (%s)\n' "$(jq -r '.redact_mode // "unknown"' <<<"$IDENTITY_JSON")"; fi)

- **Total audit events:** \`$(jq -r '.total_events' <<<"$IDENTITY_JSON")\`
- **Total read events:** \`$(jq -r '.read_events' <<<"$IDENTITY_JSON")\`
- **Total secret read events:** \`$(jq -r '.secret_read_events' <<<"$IDENTITY_JSON")\`
- **Unique human identities:** \`$(jq -r '.unique_humans' <<<"$IDENTITY_JSON")\`
- **Unique workload identities:** \`$(jq -r '.unique_workloads' <<<"$IDENTITY_JSON")\`
- **Unique entities:** \`$(jq -r '.unique_entities' <<<"$IDENTITY_JSON")\`
- **Unique correlated clients:** \`$(jq -r '.unique_correlated_clients' <<<"$IDENTITY_JSON")\`
- **Top path overall:** \`$(jq -r '.top_path_overall.path' <<<"$IDENTITY_JSON")\` (\`$(jq -r '.top_path_overall.count' <<<"$IDENTITY_JSON")\`)
- **Top secret path:** \`$(jq -r '.top_secret_path.path' <<<"$IDENTITY_JSON")\` (\`$(jq -r '.top_secret_path.count' <<<"$IDENTITY_JSON")\`)

## Applied Filters

- **Secrets only:** \`$(jq -r '.filters.secrets_only' <<<"$IDENTITY_JSON")\`
- **Exact path:** \`$(jq -r '.filters.path_exact // ""' <<<"$IDENTITY_JSON")\`
- **Path prefix:** \`$(jq -r '.filters.path_prefix // ""' <<<"$IDENTITY_JSON")\`
- **Excluded path prefix:** \`$(jq -r '.filters.exclude_path_prefix // ""' <<<"$IDENTITY_JSON")\`
- **Operation:** \`$(jq -r '.filters.operation // ""' <<<"$IDENTITY_JSON")\`
- **Since:** \`$(jq -r '.filters.since // ""' <<<"$IDENTITY_JSON")\`
- **Until:** \`$(jq -r '.filters.until // ""' <<<"$IDENTITY_JSON")\`
- **Date:** \`$(jq -r '.filters.date_only // ""' <<<"$IDENTITY_JSON")\`

EOF

  if [[ "$TOTAL_EVENTS" == "0" ]]; then
    printf '%s\n' 'No matching audit events found.'
    return
  fi

  if [[ "$(jq -r '.latest_secret_access != null' <<<"$IDENTITY_JSON")" == "true" ]]; then
    printf '%s\n' '## Latest Secret Access'
    printf '%s\n' ''
    jq -r '
      .latest_secret_access
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
    ' <<<"$IDENTITY_JSON"
    printf '%s\n' ''
  fi

  if [[ "$LATEST_ONLY" == "true" ]]; then
    if [[ "$TIMELINE" == "true" ]]; then
      printf '%s\n' '## Timeline'
      printf '%s\n' ''
      jq -r '
        .timeline_events[]
        | "- `\(.time)` `\(.auth_method)` `\(.operation)` `\(.user_login)` `pipeline=\(.pipeline_id)` `job=\(.job_id)` `\(.path)`"
      ' <<<"$IDENTITY_JSON"
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
    ' <<<"$IDENTITY_JSON"
    return
  fi

  printf '%s\n' '## Identity Correlations'
  printf '%s\n' ''
  jq -r '
    .correlations[]
    | "- **Entity ID:** `\(.entity_id)`\n"
      + "  - **Auth Methods:** `\(.auth_methods | join(", "))`\n"
      + "  - **Display Names:** `\(.display_names | join(", "))`\n"
      + "  - **User Logins:** `\(.user_logins | join(", "))`\n"
      + "  - **Emails:** `\(.user_emails | join(", "))`\n"
      + "  - **Projects:** `\(.projects | join(", "))`\n"
      + "  - **Pipelines:** `\(.pipelines | join(", "))`\n"
      + "  - **Jobs:** `\(.jobs | join(", "))`\n"
      + "  - **Secret Paths:** `\(.secret_paths | join(", "))`\n"
      + "  - **Roles:** `\(.roles | join(", "))`\n"
      + "  - **Refs:** `\(.refs | join(", "))`\n"
      + "  - **Operations:** `\(.operations | join(", "))`\n"
      + "  - **Count:** `\(.count)`\n"
      + "  - **First Seen:** `\(.first_seen)`\n"
      + "  - **Last Seen:** `\(.last_seen)`\n"
  ' <<<"$IDENTITY_JSON"
  printf '%s\n' ''

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
  ' <<<"$IDENTITY_JSON"
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
  ' <<<"$IDENTITY_JSON"
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
  ' <<<"$IDENTITY_JSON"

  if [[ "$TIMELINE" == "true" ]]; then
    printf '%s\n' ''
    printf '%s\n' '## Timeline'
    printf '%s\n' ''
    jq -r '
      .timeline_events[]
      | "- `\(.time)` `\(.auth_method)` `\(.operation)` `\(.user_login)` `pipeline=\(.pipeline_id)` `job=\(.job_id)` `\(.path)`"
    ' <<<"$IDENTITY_JSON"
  fi
}

case "$FORMAT" in
text)
  if [[ -n "$OUTPUT_FILE" ]]; then
    render_text >"$OUTPUT_FILE"
    print_run_summary
  else
    render_text
    print_run_summary
  fi
  ;;
json)
  emit_output "$(jq . <<<"$IDENTITY_JSON")"
  ;;
md)
  emit_output "$(render_md)"
  ;;
esac
