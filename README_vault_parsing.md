# Vault Audit Parsing Guide

This document explains how to use the Vault audit parsing script in this repository:

- [scripts/parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab_vault/scripts/parse_vault.sh)

It is written for two audiences:

- application owners who want to understand who accessed secrets and from where
- engineers who want to run the tool, filter the data, and generate reports

## What This Tool Does

The parser reads Vault audit log files and turns raw line-by-line JSON events into a structured identity report.

In practical terms, it helps answer questions like:

- who accessed a secret
- when that access happened
- whether the request came from a human user or an automated workload
- which GitLab project, pipeline, job, and ref were involved
- which Vault entity IDs and auth methods were used
- whether the same user appears under multiple identities

This is useful for:

- security reviews
- audit conversations
- troubleshooting unexpected secret access
- explaining access patterns to non-technical stakeholders

## Important Note About The File Name

The file is named `parse_vault.sh`, but it is actually a Python 3 script.

That means:

- you can execute it directly if it is marked executable
- or you can run it with `python3`

Examples:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log
```

```bash
python3 ./scripts/parse_vault.sh ./input/vault_audit.log
```

## What The Script Produces

The script builds a normalized identity dataset from Vault audit records and can render it in three formats:

- `text`: terminal-friendly report
- `json`: machine-readable structured output
- `md`: Markdown report for documentation and sharing

The output includes:

- overall event counts
- latest secret access
- top paths and top secret paths
- human identities
- workload identities
- identity correlations
- identity lifecycle information
- optional drift findings
- optional event timeline

## Typical Use Cases

### 1. Quick Terminal Review

Use this when you want a fast human-readable summary in the shell.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log
```

### 2. Generate A Markdown Report

Use this when you want a shareable report for documentation, review, or handoff.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --format md \
  --output ./output/report.md
```

### 3. Generate JSON For Dashboards Or Automation

Use this when another tool or UI will consume the parsed data.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --format json \
  --output ./output/report.json
```

### 4. Focus Only On Secret Reads

Use this when you want to ignore internal Vault UI and mount lookups and focus on actual secret activity.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --secrets-only
```

### 5. Retrieve The Audit Log Directly From The Vault Container

Use this when the audit file is inside the container and you want the script to copy it first.

```bash
./scripts/parse_vault.sh \
  --retrieve-audit-file ./input/vault_audit.log \
  --format md \
  --output ./output/report.md
```

By default, retrieval uses:

- container engine: `docker`
- container name: `gitlab-vault`
- audit path: `/tmp/vault_audit.log`

You can override those with environment variables:

- `CONTAINER_ENGINE`
- `VAULT_CONTAINER_NAME`
- `VAULT_AUDIT_PATH`

Example:

```bash
CONTAINER_ENGINE=podman \
VAULT_CONTAINER_NAME=gitlab-vault \
VAULT_AUDIT_PATH=/tmp/vault_audit.log \
./scripts/parse_vault.sh --retrieve-audit-file ./input/vault_audit.log
```

## Filters

The parser supports several filters so you can narrow the analysis to the activity you care about.

### Path Filters

Exact path:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --path secret/data/gitlab-lab
```

Path prefix:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --path-prefix secret/data/
```

Exclude a path prefix:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --exclude-path-prefix sys/internal/ui/mounts/
```

### Operation Filter

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --operation read
```

Supported operations are:

- `read`
- `list`
- `update`
- `delete`
- `create`
- `patch`

### Time Filters

From a point in time:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --since 2026-03-19T13:00:00Z
```

Up to a point in time:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --until 2026-03-19T14:00:00Z
```

Specific UTC date:

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --date 2026-03-19
```

## Reporting Modes

### `--summary`

Shows a compact identity summary instead of the full report.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --summary
```

### `--latest-only`

Shows the latest secret access and core metrics only.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --latest-only
```

### `--timeline`

Adds a chronological timeline of matching events.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --timeline
```

### `--top`

Shows the top N human identities by access count.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --top 10
```

### `--detect-drift`

Adds drift findings, such as users tied to multiple entity IDs or entities linked to multiple users.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --detect-drift
```

### `--explain`

Adds more narrative output in text mode to help explain findings.

```bash
./scripts/parse_vault.sh ./input/vault_audit.log --explain
```

## Redaction Options

The script can redact identity and path information before writing the report.

This is useful when:

- sharing reports outside engineering
- presenting examples in workshops or demos
- avoiding exposure of usernames, emails, entity IDs, or secret paths

### Pseudonymized Redaction

Replaces sensitive values with stable labels such as `Human-1` or `Entity-2`.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --redact \
  --redact-mode pseudo \
  --format md
```

### Masked Redaction

Keeps partial structure while hiding most of the value.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --redact-mode mask \
  --format md
```

### Strict Redaction

Replaces sensitive fields with `[redacted]`.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --redact-mode strict \
  --format md
```

Note:

- if `--redact-mode` is set to `mask` or `strict`, redaction is automatically enabled

## Input Expectations

The script expects Vault audit logs where each line is a JSON object.

It supports:

- normal text log files
- `.gz` compressed log files
- multiple files in one run

Example with multiple files:

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  ./input/vault_audit.log.1 \
  ./input/vault_audit.log.2.gz
```

The script reads all supplied files and treats them as one dataset for analysis.

## How Identity Correlation Works

The parser extracts fields from Vault audit records such as:

- `display_name`
- `entity_id`
- `user_login`
- `user_email`
- `user_id`
- `role`
- `project_path`
- `namespace_path`
- `pipeline_id`
- `job_id`
- `ref`
- `path`
- `operation`
- `time`

It then groups those records into several views:

- human identities
- workload identities
- full identity bundles
- correlations by entity ID
- identity lifecycle records

This makes it easier to understand both:

- who the actor was
- what execution context they were operating in

## What Non-Technical Readers Should Focus On

If you are reading the report as an application owner or manager, the most useful sections are usually:

- total audit events
- latest secret access
- top secret path
- human identities
- workload identities
- drift findings

Those sections usually answer:

- was a secret accessed
- by whom
- from which system context
- whether anything looks inconsistent

## What Engineers Should Focus On

If you are reading the report as an engineer, the most useful sections are usually:

- applied filters
- identity correlations
- full identity bundles
- timeline
- drift findings
- redact mode used

Those sections help with:

- verifying Vault auth behavior
- tracing GitLab-to-Vault workload activity
- checking entity consistency
- identifying ambiguous or inconsistent identity mapping

## Example End-To-End Commands

### Markdown Report For Stakeholders

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --secrets-only \
  --summary \
  --redact \
  --redact-mode pseudo \
  --format md \
  --output ./output/vault_report.md
```

### Detailed JSON For Engineering Analysis

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --secrets-only \
  --timeline \
  --detect-drift \
  --format json \
  --output ./output/vault_report.json
```

### Focus On One Secret Path During A Time Window

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --path secret/data/gitlab-lab \
  --since 2026-03-19T13:00:00Z \
  --until 2026-03-19T14:00:00Z \
  --timeline
```

## Operational Notes

- The script only parses files you explicitly provide, unless `--retrieve-audit-file` is used.
- Invalid JSON lines are skipped silently.
- Only records of type `request` are included in the analysis.
- Records without usable auth display name or metadata are skipped.
- `--secrets-only` automatically excludes `sys/internal/ui/mounts/` unless you set a different exclusion prefix.
- Output directories are created automatically when `--output` is used.

## Troubleshooting

### No Matching Audit Events Found

Common reasons:

- the file path is wrong
- the file is empty
- the selected filters are too strict
- the log does not contain matching `request` events

### Container Retrieval Fails

Check:

- the container engine value, for example `docker` or `podman`
- the Vault container name
- the audit path inside the container
- whether you can run the equivalent `cp` command manually

### Markdown Report Looks Sparse

This usually means:

- `--summary` or `--latest-only` was used
- the filters reduced the event set heavily
- redaction removed most human-readable detail

## File Reference

- Script: [scripts/parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab_vault/scripts/parse_vault.sh)
- Project README: [README.md](/Users/raymon.epping/Documents/VSC/Personal/gitlab_vault/README.md)
