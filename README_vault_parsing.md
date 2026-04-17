# Vault Audit Parsing Guide

This guide explains how to use the Vault audit parsing script in this repository:

- [scripts/parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab_vault/scripts/parse_vault.sh)

It is intended for both:

- technical readers who need to run the parser and work with the output
- non-technical readers who want to understand what the report is telling them

## Purpose

Vault audit logs are detailed, but they are difficult to read directly. This script turns raw Vault audit events into a structured report that shows:

- who accessed Vault
- which secret paths were touched
- when the access happened
- whether the request came from a human user or a workload
- which GitLab project, pipeline, job, and ref were involved when that data exists

This is useful for:

- incident review
- audit preparation
- access validation
- workshop demonstrations
- stakeholder reporting

## What The Script Supports

The current script is a Bash-based parser with support for:

- local log file parsing
- multiple input files in one run
- rotated log retrieval from a Vault container
- plain text, JSON, and Markdown output
- path and time filtering
- summary and timeline views
- redaction modes for safer sharing

## Input Sources

The parser can work from two different sources:

1. Local files you already have on disk
2. Audit log files copied directly from the Vault container

It also supports rotated log collections, not just the active audit log.

## Output Formats

The script can generate:

- `text`: shell-friendly human-readable output
- `json`: machine-readable structured output
- `md`: Markdown report suitable for documentation or sharing

## Typical Questions It Helps Answer

For application owners:

- Which application or team accessed a secret?
- Did access happen recently?
- Was the access tied to a known pipeline or job?
- Are there signs of inconsistent identity usage?

For engineers:

- Which Vault entity ID was used?
- Which auth path or workload context was involved?
- Which paths were read most often?
- Are the same users appearing under multiple identities?
- Which rotated log files were included in the report?

## Basic Usage

### Parse One Local Log File

```bash
./scripts/parse_vault.sh ./input/vault_audit.log
```

### Parse Several Local Files

This is useful when you already copied rotated logs to disk.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  ./input/vault_audit.log.1 \
  ./input/vault_audit.log.2.gz
```

### Write Markdown Output To A File

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --format md \
  --output ./output/report.md
```

### Write JSON Output To A File

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --format json \
  --output ./output/report.json
```

## Container Retrieval

### List The Audit Files The Script Can See

Use this first when you want to confirm which files exist in the Vault container.

```bash
./scripts/parse_vault.sh --list-audit-files
```

You can also set the runtime explicitly:

```bash
./scripts/parse_vault.sh --list-audit-files --runtime podman
```

### Retrieve The Active Audit File

```bash
./scripts/parse_vault.sh \
  --retrieve-audit-file ./input/vault_audit.log \
  --format md \
  --output ./output/report.md
```

### Retrieve All Matching Audit Files, Including Rotated Files

This is the best option when you want the report to include the full available audit history from the container, not just the active log.

```bash
./scripts/parse_vault.sh \
  --retrieve-all-audit-files \
  --input ./input \
  --output ./output/report.md \
  --format md
```

You can also pass the destination directory inline:

```bash
./scripts/parse_vault.sh \
  --retrieve-all-audit-files ./input \
  --output ./output/report.md \
  --format md
```

### What The Summary Means

When retrieval is used, the script prints a summary like:

- `Report:` where the final output was written
- `Used log file(s):` the local files actually parsed
- `Retrieved from container path(s):` the original file locations inside the Vault container

That makes it clear which rotated files were included in the final report.

## Runtime Detection

The script supports:

- `docker`
- `podman`
- `auto`

By default it uses `auto`, which tries to detect the working container runtime.

You can override that:

```bash
./scripts/parse_vault.sh --list-audit-files --runtime podman
```

## Common Filters

### Secrets Only

Use this when you want to focus on actual secret access and ignore Vault internal UI and mount lookups.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --secrets-only
```

### Exact Secret Path

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --path secret/data/gitlab-lab
```

### Path Prefix

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --path-prefix secret/data/
```

### Exclude A Path Prefix

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --exclude-path-prefix sys/internal/ui/mounts/
```

### Operation Filter

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --operation read
```

Supported operations are:

- `read`
- `list`
- `update`
- `delete`
- `create`
- `patch`

### Time Filters

Since a timestamp:

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --since 2026-03-19T13:00:00Z
```

Until a timestamp:

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --until 2026-03-19T14:00:00Z
```

Only one UTC date:

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --date 2026-03-19
```

## Report Modes

### Compact Summary

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --summary
```

### Latest Access Only

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --latest-only
```

### Timeline

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --timeline
```

### Top N Identities

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --top 10
```

## Redaction

Redaction is useful when you want to share a report more broadly without exposing usernames, emails, entity IDs, or exact secret paths.

### Pseudonymized Redaction

This keeps relationships intact while replacing sensitive values with stable labels.

```bash
./scripts/parse_vault.sh \
  --retrieve-all-audit-files \
  --input ./input \
  --output ./output/report.md \
  --format md \
  --redact-mode pseudo
```

### Masked Redaction

This keeps some structure but partially hides the original values.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --format md \
  --redact-mode mask
```

### Strict Redaction

This replaces sensitive values with `[redacted]`.

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --format md \
  --redact-mode strict
```

## Practical Examples

### Stakeholder-Friendly Markdown Report

```bash
./scripts/parse_vault.sh \
  --retrieve-all-audit-files \
  --input ./input \
  --output ./output/report.md \
  --format md \
  --secrets-only \
  --summary \
  --redact-mode pseudo
```

### Engineering Investigation Across Rotated Logs

```bash
./scripts/parse_vault.sh \
  --retrieve-all-audit-files \
  --input ./input \
  --format json \
  --output ./output/report.json \
  --timeline \
  --top 10
```

### Focus On One Secret During A Defined Window

```bash
./scripts/parse_vault.sh \
  ./input/vault_audit.log \
  --path secret/data/gitlab-lab \
  --since 2026-03-19T13:00:00Z \
  --until 2026-03-19T14:00:00Z \
  --format md
```

## Important Operational Notes

- `--retrieve-all-audit-files` is the feature that handles rotated Vault logs automatically.
- `--retrieve-audit-file` copies only one audit log file.
- `--input` is used only with `--retrieve-all-audit-files`.
- The script creates output directories when needed.
- The script supports compressed `.gz` files when they are already local input files.
- `--detect-drift` and `--explain` are present in the CLI, but the help text marks them as reserved for future support. Do not treat them as mature report features in this version.

## Recommended Workflow

For non-technical review:

1. Retrieve all audit files.
2. Filter to `--secrets-only`.
3. Use `--summary`.
4. Use `--redact-mode pseudo`.
5. Write the report as Markdown.

For engineering review:

1. Run `--list-audit-files`.
2. Retrieve all audit files into `./input`.
3. Generate JSON for deeper analysis.
4. Generate Markdown for documentation.
5. Re-run with narrower path or time filters if needed.

## Troubleshooting

### No Files Found In The Container

Check:

- the container runtime
- the Vault container name
- the audit path configured in Vault

Start with:

```bash
./scripts/parse_vault.sh --list-audit-files
```

### The Report Is Empty

Common reasons:

- the wrong log files were used
- the selected filters are too narrow
- the logs do not contain matching request events

### The Report Does Not Include Older Activity

This usually means only the active log was parsed. Use `--retrieve-all-audit-files` instead of `--retrieve-audit-file`.

## Related Files

- Parser: [scripts/parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab_vault/scripts/parse_vault.sh)
- Project README: [README.md](/Users/raymon.epping/Documents/VSC/Personal/gitlab_vault/README.md)
