# `parse_gitlab.sh`

`parse_gitlab.sh` parses a GitLab CI job log, extracts Vault-related JSON snippets from the log output, optionally enriches the result with a Vault token accessor lookup, and renders a report in text, JSON, or Markdown.

It is designed for GitLab-to-Vault debugging workflows where a CI job prints:

- Vault auth metadata
- optionally a retrieved secret payload
- optionally a Vault token accessor that can be looked up from the Vault CLI

## What It Does

- reads a GitLab job log file
- strips ANSI escape sequences and GitLab log prefix noise
- extracts the JSON block after the `VAULT AUTH METADATA` marker
- extracts the JSON block after the `READ SECRET` marker, if present
- optionally runs `vault token lookup -format=json -accessor <accessor>`
- builds a unified JSON report with:
  - script metadata
  - GitLab human identity
  - GitLab workload context
  - GitLab-side Vault policies
  - optional Vault-side token lookup details
  - optional retrieved secret payload
  - a simple verdict summary
- renders that result as:
  - text
  - JSON
  - Markdown

## Requirements

- Bash
- `jq`
- `vault` CLI only if `--accessor` is used and Vault-side enrichment is desired

## Usage

```bash
./parse_gitlab.sh <gitlab_log_file> [--accessor <vault_token_accessor>] [--format text|json|md] [--output <file>]
```

## Options

| Option | Description |
| --- | --- |
| `--accessor <vault_token_accessor>` | Optional Vault token accessor used for Vault-side lookup |
| `--format <text\|json\|md>` | Output format. Default: `text` |
| `--output <file>` | Write output to file |
| `-h`, `--help` | Show help |

## Examples

Basic parse:

```bash
./parse_gitlab.sh ./input/gitlab.log
```

Parse and enrich with Vault token lookup:

```bash
./parse_gitlab.sh ./input/gitlab.log --accessor eabJKPNZhWKVpyLxkMuw6AUB
```

Emit Markdown:

```bash
./parse_gitlab.sh ./input/gitlab.log --accessor eabJKPNZhWKVpyLxkMuw6AUB --format md
```

Emit JSON to a file:

```bash
./parse_gitlab.sh ./input/gitlab.log --format json --output report.json
```

## Expected Log Markers

The script looks for these marker strings in the cleaned log:

- `VAULT AUTH METADATA`
- `READ SECRET`

Behavior:

- `VAULT AUTH METADATA` is required
- `READ SECRET` is optional
- after a marker is found, the script captures the next JSON object block

If the Vault auth metadata block cannot be extracted and parsed as JSON, the script exits with an error.

## How Extraction Works

The script:

1. removes ANSI color codes
2. removes GitLab timestamp/prefix noise
3. searches for a marker
4. starts capturing when it sees a line containing only `{`
5. tracks brace depth until the JSON object closes

This is practical for controlled CI output, but it assumes the job log prints JSON in a clean, brace-balanced block.

## Output Formats

### `text`

Text mode prints:

- GitLab human identity
- GitLab workload context
- GitLab-side Vault policies
- optional retrieved secret JSON
- optional Vault-side token lookup details
- a verdict summary

### `json`

JSON mode emits the unified machine-readable report.

### `md`

Markdown mode emits the same report in a documentation-friendly format.

## JSON Schema Overview

The script currently emits a report with top-level metadata and three main sections:

- `gitlab`
- `vault`
- `secret`
- `verdict`

Top-level fields:

| Field | Type | Description |
| --- | --- | --- |
| `schema_version` | `string` | Current report schema version |
| `generated_at` | `string` | UTC report generation time |
| `source_file` | `string` | Input GitLab log path |
| `gitlab` | `object` | GitLab-derived identity and workload data |
| `vault` | `object \| null` | Optional Vault token lookup result |
| `secret` | `object \| null` | Secret payload extracted from log output |
| `verdict` | `object` | Summary view of the key access context |

### Top-level Example

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-03-21T17:30:00Z",
  "source_file": "./input/gitlab.log",
  "gitlab": {},
  "vault": null,
  "secret": null,
  "verdict": {}
}
```

### `gitlab.human_identity`

```json
{
  "user": "raymon",
  "email": "repping@gmail.com",
  "user_id": "3"
}
```

### `gitlab.workload_context`

```json
{
  "project": "root/vault-jwt-lab",
  "namespace": "root",
  "branch": "main",
  "pipeline": "3",
  "job": "7"
}
```

### `gitlab.vault_result`

```json
{
  "policies": [
    "default",
    "gitlab-vault-jwt-lab"
  ]
}
```

### `vault`

When `--accessor` is not provided:

```json
null
```

When `--accessor` is provided, the script emits:

| Field | Type | Description |
| --- | --- | --- |
| `lookup_attempted` | `boolean` | Whether the script attempted a Vault-side lookup |
| `lookup_succeeded` | `boolean` | Whether the lookup succeeded |
| `lookup_status` | `string` | One of `ok`, `lookup_failed`, `vault_cli_not_found`, `not_requested` |
| `accessor` | `string` | Requested accessor |
| `display_name` | `string` | Vault token display name |
| `path` | `string` | Token creation path |
| `entity_id` | `string` | Vault entity ID |
| `issue_time` | `string` | Token issue time |
| `expire_time` | `string` | Token expiry time |
| `policies` | `array` | Vault token policies |
| `role` | `string` | Vault role from token metadata |
| `metadata` | `object` | Vault-side metadata projection |

Example:

```json
{
  "lookup_attempted": true,
  "lookup_succeeded": true,
  "lookup_status": "ok",
  "accessor": "eabJKPNZhWKVpyLxkMuw6AUB",
  "display_name": "jwt-repping@gmail.com",
  "path": "auth/jwt/login",
  "entity_id": "ab9dde39-c4cd-adab-b415-8d0c7ebe2e84",
  "issue_time": "2026-03-19T15:33:12Z",
  "expire_time": "2026-03-19T16:33:12Z",
  "policies": [
    "default",
    "gitlab-vault-jwt-lab"
  ],
  "role": "gitlab-vault-jwt-lab",
  "metadata": {
    "user": "raymon",
    "email": "repping@gmail.com",
    "project": "root/vault-jwt-lab",
    "pipeline": "3",
    "job": "7",
    "branch": "main"
  }
}
```

### `secret`

This is the raw JSON object captured after the `READ SECRET` marker.

If the job log does not contain a parsable secret payload, `secret` is `null`.

### `verdict`

The verdict section summarizes the key access context:

```json
{
  "user": "raymon",
  "project": "root/vault-jwt-lab",
  "branch": "main",
  "pipeline": "3",
  "job": "7",
  "accessor": "eabJKPNZhWKVpyLxkMuw6AUB"
}
```

## Error Handling

The script exits on shell errors with:

```bash
set -euo pipefail
```

It also validates:

- that an input file was provided
- that the input file exists
- that the output format is one of `text`, `json`, or `md`
- that options requiring values actually receive one
- that Vault metadata can be extracted and parsed as JSON

## Notes and Limitations

- extraction depends on stable marker strings in the GitLab job log
- JSON extraction is brace-count based and assumes clean object blocks
- `READ SECRET` is optional and best-effort
- Vault-side lookup only happens when `--accessor` is provided
- if the `vault` CLI is not installed, Vault lookup status is reported as `vault_cli_not_found`
- this script is intended for controlled CI debugging output, not arbitrary unstructured logs

## Related Files

- Script: [parse_gitlab.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab/scripts/parse_gitlab.sh)
- Vault parser: [parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab/scripts/parse_vault.sh)

