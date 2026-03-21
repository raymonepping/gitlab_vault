# `parse_vault.sh`

`parse_vault.sh` parses Vault audit log request events, filters them, derives identity-oriented summaries, and renders the result as text, JSON, or Markdown.

It is designed around GitLab-style Vault JWT metadata and produces a JSON shape that can be consumed directly by the `vault-identity-ui` demo.

## What It Does

- reads a Vault audit log file
- optionally retrieves `/tmp/vault_audit.log` from a running Vault lab container
- filters request events by path, path prefix, excluded prefix, operation, and time window
- focuses optionally on `secret/data/*` events
- computes:
  - total event counts
  - latest secret access
  - top path
  - secret path summaries
  - human identities
  - workload identities
  - full identity bundles
- renders the result as:
  - human-readable text
  - JSON
  - Markdown

## Requirements

- Bash
- `jq`
- `docker` only if `--retrieve-audit-file` is used, unless you override the container engine

## Usage

```bash
./parse_vault.sh <vault_audit.log> [options]
./parse_vault.sh --retrieve-audit-file <output_path> [options]
```

## Options

| Option | Description |
| --- | --- |
| `--format <text\|json\|md>` | Output format. Default: `text` |
| `--output <file>` | Write output to file |
| `--secrets-only` | Keep only `secret/data/*` events and exclude `sys/internal/ui/mounts/*` by default |
| `--path <exact_path>` | Keep only events for an exact path |
| `--path-prefix <prefix>` | Keep only events whose path starts with the prefix |
| `--exclude-path-prefix <prefix>` | Exclude events whose path starts with the prefix |
| `--operation <op>` | Keep only events for a Vault operation: `read`, `list`, `update`, `delete`, `create`, `patch` |
| `--since <timestamp>` | Keep only events at or after this ISO-like timestamp |
| `--until <timestamp>` | Keep only events at or before this ISO-like timestamp |
| `--date <YYYY-MM-DD>` | Keep only events whose UTC date matches the prefix |
| `--top <n>` | Show top N human identities by access count in text mode |
| `--timeline` | Include a chronological event timeline in text and Markdown modes |
| `--latest-only` | Print only latest secret access and core metrics |
| `--retrieve-audit-file <path>` | Copy the audit log from the configured container path to a local file and then use it as input |
| `--summary` | Print only a compact identity summary |
| `-h`, `--help` | Show help |

## Environment Variables

These only affect audit retrieval:

| Variable | Default | Description |
| --- | --- | --- |
| `CONTAINER_ENGINE` | `docker` | Command used for container copy |
| `VAULT_CONTAINER_NAME` | `vault-lab` | Container name |
| `VAULT_AUDIT_PATH` | `/tmp/vault_audit.log` | Path inside the container |

Example:

```bash
CONTAINER_ENGINE=podman \
VAULT_CONTAINER_NAME=my-vault \
VAULT_AUDIT_PATH=/var/log/vault_audit.log \
./parse_vault.sh --retrieve-audit-file ./input/vault_audit.log --format json
```

## Examples

Basic parse:

```bash
./parse_vault.sh ./vault_audit.log
```

Secrets-only view:

```bash
./parse_vault.sh ./vault_audit.log --secrets-only
```

Exact path filter:

```bash
./parse_vault.sh ./vault_audit.log --path secret/data/gitlab-lab
```

Path prefix filter:

```bash
./parse_vault.sh ./vault_audit.log --path-prefix secret/data/
```

Operation filter:

```bash
./parse_vault.sh ./vault_audit.log --operation read
```

Time window:

```bash
./parse_vault.sh ./vault_audit.log \
  --since 2026-03-19T13:00:00Z \
  --until 2026-03-19T14:00:00Z
```

UTC date filter:

```bash
./parse_vault.sh ./vault_audit.log --date 2026-03-19
```

Top users with timeline:

```bash
./parse_vault.sh ./vault_audit.log --top 10 --timeline
```

Retrieve the audit file first:

```bash
./parse_vault.sh --retrieve-audit-file ./input/vault_audit.log --format json
```

Write Markdown report to disk:

```bash
./parse_vault.sh ./vault_audit.log --format md --output vault_identities.md
```

## Filter Semantics

Filters are combined with logical `and`.

Important behavior:

- `--secrets-only` keeps only events whose path starts with `secret/data/`
- when `--secrets-only` is used and `--exclude-path-prefix` is not supplied, the script defaults to excluding `sys/internal/ui/mounts/`
- `--since` and `--until` are parsed into epochs inside `jq`
- `--date` is a simple string-prefix match against `.time`
- only audit entries with:
  - `.type == "request"`
  - `.auth.display_name != null`
  - `.auth.metadata != null`
  are considered

## Output Formats

### `text`

Text mode prints:

- latest secret access
- core counts
- applied filters
- optional top identities section
- human identities
- workload identities
- full identity bundles
- optional timeline

### `json`

JSON mode emits the full derived model, intended for automation and UI consumption.

### `md`

Markdown mode renders the same core data in report form for export or documentation.

## JSON Schema Overview

Current schema version:

```json
"schema_version": "1.0"
```

Top-level fields currently emitted:

| Field | Type | Description |
| --- | --- | --- |
| `schema_version` | `string` | Output schema version |
| `generated_at` | `string` | Report generation timestamp |
| `source_file` | `string` | Local input file path used by the script |
| `retrieved_audit_file` | `string \| null` | Local retrieval target if `--retrieve-audit-file` was used, otherwise `null` |
| `filters` | `object` | Effective filter configuration |
| `total_events` | `number` | Number of matching request events |
| `read_events` | `number` | Matching events with `operation == "read"` |
| `secret_read_events` | `number` | Matching `read` events under `secret/data/` |
| `total_secret_paths` | `number` | Count of unique secret paths under `secret/data/` |
| `latest_secret_access` | `object \| null` | Most recent secret path event |
| `top_path` | `object` | Most frequently accessed path |
| `secret_paths` | `array` | Per-secret path rollup |
| `timeline_events` | `array` | Time-sorted event list |
| `unique_humans` | `number` | Count of unique `{user_login, user_email, user_id}` tuples |
| `unique_workloads` | `number` | Count of unique workload tuples |
| `human_identities` | `array` | Aggregated human identity view |
| `workload_identities` | `array` | Aggregated workload identity view |
| `full_identity_bundles` | `array` | Most specific identity/workload grouping |

### `filters`

```json
{
  "path_exact": "",
  "path_prefix": "",
  "exclude_path_prefix": "",
  "secrets_only": true,
  "operation": "",
  "since": "",
  "until": "",
  "date_only": ""
}
```

### `latest_secret_access`

Example:

```json
{
  "time": "2026-03-19T15:33:13.477904295Z",
  "path": "secret/data/gitlab-lab",
  "operation": "read",
  "display_name": "jwt-repping@gmail.com",
  "entity_id": "ab9dde39-c4cd-adab-b415-8d0c7ebe2e84",
  "role": "gitlab-vault-jwt-lab",
  "user_login": "raymon",
  "user_email": "repping@gmail.com",
  "user_id": "3",
  "project_path": "root/vault-jwt-lab",
  "namespace_path": "root",
  "pipeline_id": "3",
  "job_id": "7",
  "ref": "main"
}
```

### `top_path`

Example:

```json
{
  "path": "secret/data/gitlab-lab",
  "count": 2
}
```

### `secret_paths`

Example:

```json
[
  {
    "path": "secret/data/gitlab-lab",
    "count": 2,
    "first_seen": "2026-03-19T13:29:09.954946259Z",
    "last_seen": "2026-03-19T15:33:13.477904295Z"
  }
]
```

### `timeline_events`

Each event includes:

- `time`
- `user_login`
- `user_email`
- `project_path`
- `pipeline_id`
- `job_id`
- `ref`
- `role`
- `path`
- `operation`
- `display_name`
- `entity_id`

### `human_identities`

Human identities are grouped by:

- `user_login`
- `user_email`
- `user_id`

Each record includes counts, projects, namespaces, refs, pipelines, jobs, paths, operations, display names, entity IDs, and first/last seen timestamps.

### `workload_identities`

Workload identities are grouped by:

- `project_path`
- `namespace_path`
- `pipeline_id`
- `job_id`
- `ref`
- `role`

Each record includes user summaries, paths, operations, display names, entity IDs, and first/last seen timestamps.

### `full_identity_bundles`

Full identity bundles are grouped by the combined identity and workload tuple:

- `display_name`
- `entity_id`
- `role`
- `user_login`
- `user_email`
- `user_id`
- `project_path`
- `namespace_path`
- `pipeline_id`
- `job_id`
- `ref`

This is the most specific rollup emitted by the script.

## Audit Retrieval Flow

When `--retrieve-audit-file <path>` is used:

1. the target local directory is created if needed
2. the script copies the configured audit file from the configured container
3. the copied file becomes the active input file
4. `retrieved_audit_file` is set in the JSON output

If retrieval is not used:

- `source_file` is still set
- `retrieved_audit_file` is `null`

## Error Handling

The script exits on errors with:

```bash
set -euo pipefail
```

It also validates:

- required file input
- output format
- operation value
- `--top` as a positive integer
- `--date` format
- `--since` and `--until` shape
- missing option values for flags that require one

## Notes and Limitations

- the script slurps the full audit log into memory with `jq -s`
- `--date` is a UTC prefix filter, not a full timezone-aware date conversion
- only request records with GitLab-style auth metadata are included
- the script is intentionally specialized for GitLab-to-Vault identity analysis, not general Vault audit reporting

## Related Files

- Script: [parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab/scripts/parse_vault.sh)
- UI consumer: [vault-identity-ui/public/data/vault_identity.json](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/public/data/vault_identity.json)

