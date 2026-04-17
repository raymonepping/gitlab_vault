#!/usr/bin/env python3
"""
parse_vault.py – Vault audit-log identity inventory tool.

Drop-in Python replacement for parse_vault.sh.
Parses HashiCorp Vault audit logs, correlates identities, detects drift,
and renders reports in text / JSON / Markdown.
"""

from __future__ import annotations

import argparse
import copy
import gzip
import json
import os
import re
import subprocess
import sys
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# ── helpers ──────────────────────────────────────────────────────────────────

def fail(msg: str) -> None:
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


def normalize_time(ts: str) -> str:
    """Strip sub-second precision so fromisoformat can parse it."""
    return re.sub(r"\.\d+(?=Z|[+-]\d{2}:\d{2}$)", "", ts)


def to_epoch_or_none(ts: str) -> float | None:
    if not ts:
        return None
    try:
        normed = normalize_time(ts)
        normed = normed.replace("Z", "+00:00")
        return datetime.fromisoformat(normed).timestamp()
    except Exception:
        return None


def to_utc_date_or_empty(ts: str) -> str:
    epoch = to_epoch_or_none(ts)
    if epoch is None:
        return ""
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%d")


def now_iso() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def unique_sorted(lst: list) -> list:
    seen: set = set()
    out: list = []
    for v in lst:
        key = json.dumps(v, sort_keys=True) if isinstance(v, dict) else v
        if key not in seen:
            seen.add(key)
            out.append(v)
    out.sort(key=lambda x: json.dumps(x, sort_keys=True) if isinstance(x, dict) else x)
    return out


def nonempty(lst: list[str]) -> list[str]:
    return [v for v in lst if v]


def safe_get(d: dict, *keys: str, default: Any = "") -> Any:
    cur = d
    for k in keys:
        if isinstance(cur, dict):
            cur = cur.get(k, default)
        else:
            return default
    return cur if cur is not None else default


# ── CLI ──────────────────────────────────────────────────────────────────────

VALID_OPERATIONS = {"read", "list", "update", "delete", "create", "patch"}
VALID_FORMATS = {"text", "json", "md"}
VALID_REDACT_MODES = {"pseudo", "mask", "strict"}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="parse_vault.py",
        description="Vault audit-log identity inventory tool.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  ./parse_vault.py --retrieve-audit-file ./input/vault_audit.log
  ./parse_vault.py ./vault_audit.log
  ./parse_vault.py ./vault_audit.log ./vault_audit.log.1 ./vault_audit.log.2
  ./parse_vault.py ./vault_audit.log ./vault_audit.log.1.gz
  ./parse_vault.py ./vault_audit.log --secrets-only
  ./parse_vault.py ./vault_audit.log --path secret/data/gitlab-lab
  ./parse_vault.py ./vault_audit.log --path-prefix secret/data/
  ./parse_vault.py ./vault_audit.log --operation read
  ./parse_vault.py ./vault_audit.log --since 2026-03-19T13:00:00Z
  ./parse_vault.py ./vault_audit.log --until 2026-03-19T14:00:00Z
  ./parse_vault.py ./vault_audit.log --date 2026-03-19
  ./parse_vault.py ./vault_audit.log --top 10 --timeline
  ./parse_vault.py ./vault_audit.log --latest-only
  ./parse_vault.py ./vault_audit.log --format json
  ./parse_vault.py ./vault_audit.log --format md --output vault_identities.md
  ./parse_vault.py ./vault_audit.log --secrets-only --summary
  ./parse_vault.py ./vault_audit.log --secrets-only --redact --format json
  ./parse_vault.py ./vault_audit.log --secrets-only --redact --redact-mode strict --format md
""",
    )
    p.add_argument("files", nargs="*", metavar="vault_audit.log", help="Vault audit log file(s)")
    p.add_argument("--format", choices=VALID_FORMATS, default="text", help="Output format (default: text)")
    p.add_argument("--output", metavar="FILE", default="", help="Write output to file")
    p.add_argument("--secrets-only", action="store_true", help="Keep only secret/data/* events, exclude sys/internal/ui/mounts/*")
    p.add_argument("--path", metavar="EXACT_PATH", default="", help="Keep only events for an exact path")
    p.add_argument("--path-prefix", metavar="PREFIX", default="", help="Keep only events whose path starts with prefix")
    p.add_argument("--exclude-path-prefix", metavar="PREFIX", default="", help="Exclude events whose path starts with prefix")
    p.add_argument("--operation", metavar="OP", default="", help="Keep only events for an exact Vault operation")
    p.add_argument("--since", metavar="TIMESTAMP", default="", help="Keep only events at or after this UTC timestamp")
    p.add_argument("--until", metavar="TIMESTAMP", default="", help="Keep only events at or before this UTC timestamp")
    p.add_argument("--date", metavar="YYYY-MM-DD", default="", help="Keep only events on this UTC date")
    p.add_argument("--top", metavar="N", type=int, default=0, help="Show top N human identities by access count")
    p.add_argument("--timeline", action="store_true", help="Print a chronological event timeline")
    p.add_argument("--latest-only", action="store_true", help="Print only latest secret access and core metrics")
    p.add_argument("--retrieve-audit-file", metavar="PATH", default="", help="Copy audit file from Vault container and use it")
    p.add_argument("--redact", action="store_true", help="Redact sensitive details in output")
    p.add_argument("--redact-mode", choices=VALID_REDACT_MODES, default="pseudo", help="Redaction mode (default: pseudo)")
    p.add_argument("--summary", action="store_true", help="Print only a compact summary")
    p.add_argument("--detect-drift", action="store_true", help="Detect drift in secret values")
    p.add_argument("--explain", action="store_true", help="Provide explanations for detected issues")
    return p


def validate_args(args: argparse.Namespace) -> None:
    if args.operation and args.operation not in VALID_OPERATIONS:
        fail(f"Invalid operation: {args.operation}")
    if args.date and not re.match(r"^\d{4}-\d{2}-\d{2}$", args.date):
        fail("--date must be in YYYY-MM-DD format")
    if args.since and not re.match(r"^\d{4}-\d{2}-\d{2}T", args.since):
        fail("--since must look like an ISO timestamp, for example 2026-03-19T13:00:00Z")
    if args.until and not re.match(r"^\d{4}-\d{2}-\d{2}T", args.until):
        fail("--until must look like an ISO timestamp, for example 2026-03-19T14:00:00Z")
    if args.top and args.top < 1:
        fail("--top must be a positive integer")
    if args.redact_mode != "pseudo":
        args.redact = True


# ── log reading ──────────────────────────────────────────────────────────────

def read_logs(files: list[str]) -> list[dict]:
    """Read and parse all log files, returning a list of JSON objects."""
    records: list[dict] = []
    for fpath in files:
        opener = gzip.open if fpath.endswith(".gz") else open
        with opener(fpath, "rt", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return records


# ── filtering ────────────────────────────────────────────────────────────────

class Filters:
    def __init__(self, args: argparse.Namespace):
        self.secrets_only: bool = args.secrets_only
        self.path_exact: str = args.path
        self.path_prefix: str = args.path_prefix
        self.exclude_path_prefix: str = args.exclude_path_prefix
        self.operation: str = args.operation
        self.since: str = args.since
        self.until: str = args.until
        self.date_only: str = args.date

        # replicate bash behaviour: --secrets-only implies exclude sys/internal/ui/mounts/
        if self.secrets_only and not self.exclude_path_prefix:
            self.exclude_path_prefix = "sys/internal/ui/mounts/"

    def matches(self, record: dict) -> bool:
        path = safe_get(record, "request", "path")
        operation = safe_get(record, "request", "operation")
        time_str = record.get("time", "")

        if self.secrets_only and not path.startswith("secret/data/"):
            return False
        if self.path_exact and path != self.path_exact:
            return False
        if self.path_prefix and not path.startswith(self.path_prefix):
            return False
        if self.exclude_path_prefix and path.startswith(self.exclude_path_prefix):
            return False
        if self.operation and operation != self.operation:
            return False
        if self.since:
            evt = to_epoch_or_none(time_str)
            since = to_epoch_or_none(self.since)
            if evt is None or since is None or evt < since:
                return False
        if self.until:
            evt = to_epoch_or_none(time_str)
            until = to_epoch_or_none(self.until)
            if evt is None or until is None or evt > until:
                return False
        if self.date_only:
            if to_utc_date_or_empty(time_str) != self.date_only:
                return False
        return True

    def to_dict(self) -> dict:
        return {
            "secrets_only": self.secrets_only,
            "path_exact": self.path_exact,
            "path_prefix": self.path_prefix,
            "exclude_path_prefix": self.exclude_path_prefix,
            "operation": self.operation,
            "since": self.since,
            "until": self.until,
            "date_only": self.date_only,
        }


# ── event extraction ────────────────────────────────────────────────────────

def extract_event(record: dict) -> dict:
    """Transform a raw audit record into a normalised event dict."""
    auth = record.get("auth", {}) or {}
    meta = auth.get("metadata", {}) or {}
    display_name = auth.get("display_name", "") or ""

    if display_name.startswith("jwt-"):
        auth_method = "jwt"
    elif display_name.startswith("ldap-"):
        auth_method = "ldap"
    elif safe_get(record, "request", "mount_type") == "token":
        auth_method = "token"
    else:
        auth_method = "other"

    user_login = meta.get("user_login", "") or ""
    if not user_login and display_name.startswith("ldap-"):
        user_login = display_name.removeprefix("ldap-")

    user_email = meta.get("user_email", "") or ""
    if not user_email and display_name.startswith("ldap-"):
        user_email = display_name.removeprefix("ldap-") + "@ldap.local"

    return {
        "time": record.get("time", ""),
        "path": safe_get(record, "request", "path"),
        "operation": safe_get(record, "request", "operation"),
        "auth_method": auth_method,
        "display_name": display_name,
        "entity_id": auth.get("entity_id", "") or "",
        "role": meta.get("role", "") or "",
        "user_login": user_login,
        "user_email": user_email,
        "user_id": meta.get("user_id", "") or "",
        "project_path": meta.get("project_path", "") or "",
        "namespace_path": meta.get("namespace_path", "") or "",
        "pipeline_id": meta.get("pipeline_id", "") or "",
        "job_id": meta.get("job_id", "") or "",
        "ref": meta.get("ref", "") or "",
    }


def build_events(records: list[dict], filt: Filters) -> list[dict]:
    events: list[dict] = []
    for r in records:
        if r.get("type") != "request":
            continue
        auth = r.get("auth") or {}
        if auth.get("display_name") is None:
            continue
        if auth.get("metadata") is None:
            continue
        if not filt.matches(r):
            continue
        events.append(extract_event(r))
    return events


# ── analysis ─────────────────────────────────────────────────────────────────

def _group_by(lst: list[dict], key_fn) -> list[list[dict]]:
    groups: OrderedDict[str, list[dict]] = OrderedDict()
    for item in lst:
        k = json.dumps(key_fn(item), sort_keys=True)
        groups.setdefault(k, []).append(item)
    return list(groups.values())


def _workload_group_key(e: dict) -> dict:
    if any(e.get(f) for f in ("project_path", "namespace_path", "pipeline_id", "job_id", "ref", "role")):
        return {
            "mode": "workload",
            "project_path": e["project_path"],
            "namespace_path": e["namespace_path"],
            "pipeline_id": e["pipeline_id"],
            "job_id": e["job_id"],
            "ref": e["ref"],
            "role": e["role"],
        }
    return {
        "mode": "entity_fallback",
        "entity_id": e.get("entity_id", ""),
        "display_name": e.get("display_name", ""),
        "user_login": e.get("user_login", ""),
        "user_email": e.get("user_email", ""),
    }


def analyse(events: list[dict], source_files: str, retrieved_audit_file: str, filt: Filters) -> dict:
    secret_events = [e for e in events if e["path"].startswith("secret/data/")]
    read_events = [e for e in events if e["operation"] == "read"]
    secret_read_events = [e for e in events if e["operation"] == "read" and e["path"].startswith("secret/data/")]

    # latest secret access
    secret_sorted = sorted(secret_events, key=lambda e: e["time"])
    latest_secret = secret_sorted[-1] if secret_sorted else None

    # top path overall
    path_counts: dict[str, int] = {}
    for e in events:
        path_counts[e["path"]] = path_counts.get(e["path"], 0) + 1
    if path_counts:
        top_path_overall_path = max(path_counts, key=lambda p: (path_counts[p], p))
        top_path_overall = {"path": top_path_overall_path, "count": path_counts[top_path_overall_path]}
    else:
        top_path_overall = {"path": "", "count": 0}

    # top secret path
    secret_path_counts: dict[str, int] = {}
    for e in secret_events:
        secret_path_counts[e["path"]] = secret_path_counts.get(e["path"], 0) + 1
    if secret_path_counts:
        top_sp = max(secret_path_counts, key=lambda p: (secret_path_counts[p], p))
        top_secret_path = {"path": top_sp, "count": secret_path_counts[top_sp]}
    else:
        top_secret_path = {"path": "", "count": 0}

    # secret_paths
    secret_paths_info = []
    for grp in _group_by(sorted(secret_events, key=lambda e: (e["path"], e["time"])), lambda e: e["path"]):
        times = sorted(e["time"] for e in grp)
        secret_paths_info.append({
            "path": grp[0]["path"],
            "count": len(grp),
            "first_seen": times[0],
            "last_seen": times[-1],
        })
    secret_paths_info.sort(key=lambda x: (-x["count"], x["path"]))

    # timeline events
    timeline_events = sorted(events, key=lambda e: e["time"])
    timeline_events = [
        {k: e[k] for k in (
            "time", "auth_method", "user_login", "user_email", "user_id",
            "project_path", "namespace_path", "pipeline_id", "job_id", "ref",
            "role", "path", "operation", "display_name", "entity_id",
        )}
        for e in timeline_events
    ]

    # unique_workload_contexts
    wctx = []
    for e in events:
        if any(e.get(f) for f in ("project_path", "namespace_path", "pipeline_id", "job_id", "ref", "role")):
            wctx.append({f: e[f] for f in ("project_path", "namespace_path", "pipeline_id", "job_id", "ref", "role")})
    unique_workload_contexts = len(unique_sorted(wctx))

    # fallback_identity_groups
    fallback = []
    for e in events:
        if not any(e.get(f) for f in ("project_path", "namespace_path", "pipeline_id", "job_id", "ref", "role")):
            fallback.append({
                "entity_id": e.get("entity_id", ""),
                "display_name": e.get("display_name", ""),
                "user_login": e.get("user_login", ""),
                "user_email": e.get("user_email", ""),
            })
    fallback_identity_groups = len(unique_sorted(fallback))

    # unique humans
    humans_set = unique_sorted([{k: e[k] for k in ("user_login", "user_email", "user_id")} for e in events])
    unique_humans = len(humans_set)

    # unique workload groups
    wg_set = unique_sorted([_workload_group_key(e) for e in events])
    unique_workload_groups = len(wg_set)

    # unique entities
    ent_set = unique_sorted(nonempty([e.get("entity_id", "") for e in events]))
    unique_entities = len(ent_set)

    # unique client subjects
    cs_list: list[dict] = []
    for e in events:
        if e.get("user_login"):
            cs_list.append({"kind": "user_login", "value": e["user_login"]})
        elif e.get("user_email"):
            cs_list.append({"kind": "user_email", "value": e["user_email"]})
        elif e.get("entity_id"):
            cs_list.append({"kind": "entity_id", "value": e["entity_id"]})
    unique_client_subjects = len(unique_sorted(cs_list))

    # fully correlated workloads
    fcw: list[dict] = []
    for e in events:
        if all(e.get(f) for f in ("entity_id", "project_path", "pipeline_id", "job_id")):
            fcw.append({f: e[f] for f in ("entity_id", "project_path", "pipeline_id", "job_id")})
    fully_correlated = len(unique_sorted(fcw))

    # partial workload identities
    pwi: list[dict] = []
    for e in events:
        if e.get("entity_id") and not all(e.get(f) for f in ("project_path", "pipeline_id", "job_id")):
            pwi.append({f: e[f] for f in ("entity_id", "user_login", "user_email")})
    partial_workload = len(unique_sorted(pwi))

    # correlations
    correlations = _build_correlations(events)

    # identity lifecycle
    identity_lifecycle = _build_identity_lifecycle(events)

    # drift findings
    drift_findings = _build_drift_findings(events)

    # human identities
    human_identities = _build_human_identities(events)

    # workload identities
    workload_identities = _build_workload_identities(events)

    # full identity bundles
    full_identity_bundles = _build_full_identity_bundles(events)

    return {
        "schema_version": "1.0",
        "generated_at": now_iso(),
        "source_file": source_files,
        "retrieved_audit_file": retrieved_audit_file or None,
        "filters": filt.to_dict(),
        "total_events": len(events),
        "read_events": len(read_events),
        "secret_read_events": len(secret_read_events),
        "total_secret_paths": len(unique_sorted([e["path"] for e in secret_events])),
        "latest_secret_access": latest_secret,
        "top_path_overall": top_path_overall,
        "top_secret_path": top_secret_path,
        "secret_paths": secret_paths_info,
        "timeline_events": timeline_events,
        "unique_workload_contexts": unique_workload_contexts,
        "fallback_identity_groups": fallback_identity_groups,
        "unique_humans": unique_humans,
        "unique_workload_groups": unique_workload_groups,
        "unique_entities": unique_entities,
        "unique_client_subjects": unique_client_subjects,
        "fully_correlated_workloads": fully_correlated,
        "partial_workload_identities": partial_workload,
        "correlations": correlations,
        "identity_lifecycle": identity_lifecycle,
        "drift_findings": drift_findings,
        "human_identities": human_identities,
        "workload_identities": workload_identities,
        "full_identity_bundles": full_identity_bundles,
    }


def _build_correlations(events: list[dict]) -> list[dict]:
    entity_events = [e for e in events if e.get("entity_id")]
    entity_events.sort(key=lambda e: (e["entity_id"], e["time"]))
    result = []
    for grp in _group_by(entity_events, lambda e: e["entity_id"]):
        times = sorted(e["time"] for e in grp)
        result.append({
            "entity_id": grp[0]["entity_id"],
            "count": len(grp),
            "auth_methods": sorted(set(e["auth_method"] for e in grp)),
            "display_names": sorted(set(nonempty([e["display_name"] for e in grp]))),
            "user_logins": sorted(set(nonempty([e["user_login"] for e in grp]))),
            "user_emails": sorted(set(nonempty([e["user_email"] for e in grp]))),
            "roles": sorted(set(nonempty([e["role"] for e in grp]))),
            "projects": sorted(set(nonempty([e["project_path"] for e in grp]))),
            "namespaces": sorted(set(nonempty([e["namespace_path"] for e in grp]))),
            "pipelines": sorted(set(nonempty([e["pipeline_id"] for e in grp]))),
            "jobs": sorted(set(nonempty([e["job_id"] for e in grp]))),
            "refs": sorted(set(nonempty([e["ref"] for e in grp]))),
            "secret_paths": sorted(set(e["path"] for e in grp if e["path"].startswith("secret/data/"))),
            "operations": sorted(set(e["operation"] for e in grp)),
            "first_seen": times[0],
            "last_seen": times[-1],
        })
    result.sort(key=lambda x: (x["last_seen"], x["entity_id"]), reverse=True)
    return result


def _build_identity_lifecycle(events: list[dict]) -> list[dict]:
    events_s = sorted(events, key=lambda e: (e["user_login"], e["user_email"], e["time"]))
    result = []
    for grp in _group_by(events_s, lambda e: (e["user_login"], e["user_email"], e["user_id"])):
        entity_groups = _group_by(
            [e for e in grp if e.get("entity_id")],
            lambda e: e["entity_id"],
        )
        entities = []
        for eg in entity_groups:
            etimes = sorted(e["time"] for e in eg)
            entities.append({
                "entity_id": eg[0]["entity_id"],
                "first_seen": etimes[0],
                "last_seen": etimes[-1],
                "auth_methods": sorted(set(e["auth_method"] for e in eg)),
                "display_names": sorted(set(e["display_name"] for e in eg)),
                "projects": sorted(set(nonempty([e["project_path"] for e in eg]))),
                "pipelines": sorted(set(nonempty([e["pipeline_id"] for e in eg]))),
                "jobs": sorted(set(nonempty([e["job_id"] for e in eg]))),
            })
        entities.sort(key=lambda x: x["first_seen"])

        with_entity = [e for e in grp if e.get("entity_id")]
        current_entity = ""
        if with_entity:
            current_entity = sorted(with_entity, key=lambda e: e["time"])[-1]["entity_id"]

        result.append({
            "user_login": grp[0]["user_login"],
            "user_email": grp[0]["user_email"],
            "user_id": grp[0]["user_id"],
            "entities": entities,
            "current_entity": current_entity,
        })
    result.sort(key=lambda x: (x["user_login"], x["user_email"]))
    return result


def _build_drift_findings(events: list[dict]) -> list[dict]:
    findings: list[dict] = []

    # user_multiple_entities
    for grp in _group_by(events, lambda e: (e["user_login"], e["user_email"], e["user_id"])):
        eids = sorted(set(nonempty([e["entity_id"] for e in grp])))
        if len(eids) > 1:
            findings.append({
                "severity": "medium",
                "type": "user_multiple_entities",
                "user_login": grp[0]["user_login"],
                "user_email": grp[0]["user_email"],
                "user_id": grp[0]["user_id"],
                "entity_ids": eids,
                "message": f"User {grp[0]['user_login'] or '[unknown]'} is associated with multiple entity IDs",
            })

    # entity_multiple_users
    entity_events = [e for e in events if e.get("entity_id")]
    for grp in _group_by(entity_events, lambda e: e["entity_id"]):
        logins = sorted(set(nonempty([e["user_login"] for e in grp])))
        if len(logins) > 1:
            findings.append({
                "severity": "medium",
                "type": "entity_multiple_users",
                "entity_id": grp[0]["entity_id"],
                "user_logins": logins,
                "user_emails": sorted(set(nonempty([e["user_email"] for e in grp]))),
                "message": f"Entity {grp[0]['entity_id']} is associated with multiple user identities",
            })

    # entity_multiple_auth_methods
    for grp in _group_by(entity_events, lambda e: e["entity_id"]):
        methods = sorted(set(e["auth_method"] for e in grp))
        if len(methods) > 1:
            findings.append({
                "severity": "low",
                "type": "entity_multiple_auth_methods",
                "entity_id": grp[0]["entity_id"],
                "auth_methods": methods,
                "message": f"Entity {grp[0]['entity_id']} is used through multiple auth methods",
            })

    return findings


def _build_human_identities(events: list[dict]) -> list[dict]:
    events_s = sorted(events, key=lambda e: (e["user_login"], e["user_email"], e["user_id"]))
    result = []
    for grp in _group_by(events_s, lambda e: (e["user_login"], e["user_email"], e["user_id"])):
        times = sorted(e["time"] for e in grp)
        result.append({
            "count": len(grp),
            "user_login": grp[0]["user_login"],
            "user_email": grp[0]["user_email"],
            "user_id": grp[0]["user_id"],
            "display_names": sorted(set(e["display_name"] for e in grp)),
            "entity_ids": sorted(set(nonempty([e["entity_id"] for e in grp]))),
            "roles": sorted(set(nonempty([e["role"] for e in grp]))),
            "projects": sorted(set(nonempty([e["project_path"] for e in grp]))),
            "namespaces": sorted(set(nonempty([e["namespace_path"] for e in grp]))),
            "refs": sorted(set(nonempty([e["ref"] for e in grp]))),
            "pipelines": sorted(set(nonempty([e["pipeline_id"] for e in grp]))),
            "jobs": sorted(set(nonempty([e["job_id"] for e in grp]))),
            "paths": sorted(set(e["path"] for e in grp)),
            "operations": sorted(set(e["operation"] for e in grp)),
            "first_seen": times[0],
            "last_seen": times[-1],
        })
    result.sort(key=lambda x: (x["user_login"], x["user_email"]))
    return result


def _build_workload_identities(events: list[dict]) -> list[dict]:
    tagged = [(e, _workload_group_key(e)) for e in events]
    tagged.sort(key=lambda t: json.dumps(t[1], sort_keys=True))

    result = []
    for grp in _group_by(tagged, lambda t: t[1]):
        es = [t[0] for t in grp]
        key = grp[0][1]
        mode = key["mode"]
        times = sorted(e["time"] for e in es)
        users = unique_sorted([{k: e[k] for k in ("user_login", "user_email", "user_id")} for e in es])
        result.append({
            "count": len(es),
            "grouping_mode": mode,
            "project_path": es[0]["project_path"] if mode == "workload" else "",
            "namespace_path": es[0]["namespace_path"] if mode == "workload" else "",
            "pipeline_id": es[0]["pipeline_id"] if mode == "workload" else "",
            "job_id": es[0]["job_id"] if mode == "workload" else "",
            "ref": es[0]["ref"] if mode == "workload" else "",
            "role": es[0]["role"] if mode == "workload" else "",
            "fallback_entity_id": es[0]["entity_id"] if mode == "entity_fallback" else "",
            "display_names": sorted(set(e["display_name"] for e in es)),
            "entity_ids": sorted(set(nonempty([e["entity_id"] for e in es]))),
            "users": users,
            "paths": sorted(set(e["path"] for e in es)),
            "operations": sorted(set(e["operation"] for e in es)),
            "first_seen": times[0],
            "last_seen": times[-1],
        })
    result.sort(key=lambda x: (
        x["grouping_mode"],
        x["project_path"],
        x["pipeline_id"],
        x["job_id"],
        x["fallback_entity_id"],
    ))
    return result


def _build_full_identity_bundles(events: list[dict]) -> list[dict]:
    events_s = sorted(events, key=lambda e: (
        e["project_path"], e["pipeline_id"], e["job_id"],
        e["user_login"], e["display_name"],
    ))
    key_fields = (
        "display_name", "entity_id", "role", "user_login", "user_email",
        "user_id", "project_path", "namespace_path", "pipeline_id", "job_id", "ref",
    )
    result = []
    for grp in _group_by(events_s, lambda e: tuple(e[k] for k in key_fields)):
        times = sorted(e["time"] for e in grp)
        entry = {
            "count": len(grp),
            "first_seen": times[0],
            "last_seen": times[-1],
            "paths": sorted(set(e["path"] for e in grp)),
            "operations": sorted(set(e["operation"] for e in grp)),
        }
        for k in key_fields:
            entry[k] = grp[0][k]
        result.append(entry)
    result.sort(key=lambda x: (x["project_path"], x["pipeline_id"], x["job_id"], x["user_login"]))
    return result


# ── redaction ────────────────────────────────────────────────────────────────

def _build_pseudo_map(values: list[str], prefix: str) -> dict[str, str]:
    uniq = sorted(set(v for v in values if v))
    return {v: f"{prefix}-{i+1}" for i, v in enumerate(uniq)}


def _canonical_human_key(obj: dict) -> str:
    for k in ("user_id", "user_email", "user_login", "display_name"):
        v = obj.get(k, "")
        if v:
            return v
    return ""


def _lookup(mapping: dict[str, str], value: str) -> str:
    if not value:
        return ""
    return mapping.get(value, "")


def _human_lookup(mapping: dict[str, str], value: str) -> str:
    if not value:
        return ""
    return mapping.get(value, "Human-Unknown")


def redact_pseudo(data: dict) -> dict:
    """Pseudonymise all PII with stable tokens like Human-1, Entity-2, etc."""
    d = copy.deepcopy(data)

    # Collect all values for each category
    human_vals: list[str] = []
    entity_vals: list[str] = []
    project_vals: list[str] = []
    namespace_vals: list[str] = []
    pipeline_vals: list[str] = []
    job_vals: list[str] = []
    ref_vals: list[str] = []
    path_vals: list[str] = []

    def _collect_human(obj: dict | None) -> None:
        if obj is None:
            return
        human_vals.append(_canonical_human_key(obj))

    def _collect_event(obj: dict | None) -> None:
        if obj is None:
            return
        _collect_human(obj)
        for k, lst in [("entity_id", entity_vals), ("project_path", project_vals),
                        ("namespace_path", namespace_vals), ("pipeline_id", pipeline_vals),
                        ("job_id", job_vals), ("ref", ref_vals), ("path", path_vals)]:
            v = obj.get(k, "")
            if v:
                lst.append(v)

    if d.get("latest_secret_access"):
        _collect_event(d["latest_secret_access"])
    for e in d.get("timeline_events", []):
        _collect_event(e)
    for h in d.get("human_identities", []):
        _collect_human(h)
        entity_vals.extend(h.get("entity_ids", []))
        project_vals.extend(h.get("projects", []))
        namespace_vals.extend(h.get("namespaces", []))
        pipeline_vals.extend(h.get("pipelines", []))
        job_vals.extend(h.get("jobs", []))
        ref_vals.extend(h.get("refs", []))
        path_vals.extend(h.get("paths", []))
    for w in d.get("workload_identities", []):
        entity_vals.extend(w.get("entity_ids", []))
        for u in w.get("users", []):
            _collect_human(u)
        for k, lst in [("project_path", project_vals), ("namespace_path", namespace_vals),
                        ("pipeline_id", pipeline_vals), ("job_id", job_vals), ("ref", ref_vals)]:
            v = w.get(k, "")
            if v:
                lst.append(v)
        path_vals.extend(w.get("paths", []))
    for b in d.get("full_identity_bundles", []):
        _collect_event(b)
        path_vals.extend(b.get("paths", []))
    for c in d.get("correlations", []):
        entity_vals.append(c.get("entity_id", ""))
        human_vals.extend(c.get("user_logins", []))
        human_vals.extend(c.get("user_emails", []))
        human_vals.extend(c.get("display_names", []))
        project_vals.extend(c.get("projects", []))
        namespace_vals.extend(c.get("namespaces", []))
        pipeline_vals.extend(c.get("pipelines", []))
        job_vals.extend(c.get("jobs", []))
        ref_vals.extend(c.get("refs", []))
        path_vals.extend(c.get("secret_paths", []))

    # Also collect from top_path_overall, top_secret_path, secret_paths
    if d.get("top_path_overall"):
        path_vals.append(d["top_path_overall"].get("path", ""))
    if d.get("top_secret_path"):
        path_vals.append(d["top_secret_path"].get("path", ""))
    for sp in d.get("secret_paths", []):
        path_vals.append(sp.get("path", ""))

    hmap = _build_pseudo_map(human_vals, "Human")
    emap = _build_pseudo_map(entity_vals, "Entity")
    pmap = _build_pseudo_map(project_vals, "Project")
    nmap = _build_pseudo_map(namespace_vals, "Namespace")
    plmap = _build_pseudo_map(pipeline_vals, "Pipeline")
    jmap = _build_pseudo_map(job_vals, "Job")
    rmap = _build_pseudo_map(ref_vals, "Ref")
    pathmap = _build_pseudo_map(path_vals, "SecretPath")

    def pseudo_human(obj: dict) -> dict:
        h = _human_lookup(hmap, _canonical_human_key(obj))
        obj["user_login"] = h
        obj["user_email"] = h
        obj["user_id"] = h
        obj["display_name"] = h
        return obj

    def pseudo_common(obj: dict) -> dict:
        obj["entity_id"] = _lookup(emap, obj.get("entity_id", ""))
        obj["project_path"] = _lookup(pmap, obj.get("project_path", ""))
        obj["namespace_path"] = _lookup(nmap, obj.get("namespace_path", ""))
        obj["pipeline_id"] = _lookup(plmap, obj.get("pipeline_id", ""))
        obj["job_id"] = _lookup(jmap, obj.get("job_id", ""))
        obj["ref"] = _lookup(rmap, obj.get("ref", ""))
        obj["path"] = _lookup(pathmap, obj.get("path", ""))
        return obj

    def pseudo_list(lst: list[str], mapping: dict[str, str]) -> list[str]:
        return sorted(set(v for v in [_lookup(mapping, x) for x in lst] if v))

    def pseudo_human_list(lst: list[str]) -> list[str]:
        return sorted(set(_human_lookup(hmap, x) for x in lst if x))

    # Apply
    if d.get("latest_secret_access"):
        pseudo_human(d["latest_secret_access"])
        pseudo_common(d["latest_secret_access"])

    d["top_path_overall"]["path"] = _lookup(pathmap, d["top_path_overall"].get("path", ""))
    d["top_secret_path"]["path"] = _lookup(pathmap, d["top_secret_path"].get("path", ""))

    for sp in d.get("secret_paths", []):
        sp["path"] = _lookup(pathmap, sp.get("path", ""))

    for e in d.get("timeline_events", []):
        pseudo_human(e)
        pseudo_common(e)

    for c in d.get("correlations", []):
        c["entity_id"] = _lookup(emap, c.get("entity_id", ""))
        c["display_names"] = pseudo_human_list(c.get("display_names", []))
        c["user_logins"] = pseudo_human_list(c.get("user_logins", []))
        c["user_emails"] = pseudo_human_list(c.get("user_emails", []))
        c["projects"] = pseudo_list(c.get("projects", []), pmap)
        c["namespaces"] = pseudo_list(c.get("namespaces", []), nmap)
        c["pipelines"] = pseudo_list(c.get("pipelines", []), plmap)
        c["jobs"] = pseudo_list(c.get("jobs", []), jmap)
        c["refs"] = pseudo_list(c.get("refs", []), rmap)
        c["secret_paths"] = pseudo_list(c.get("secret_paths", []), pathmap)

    for h in d.get("human_identities", []):
        pseudo_human(h)
        h["display_names"] = [h["user_login"]]
        h["entity_ids"] = pseudo_list(h.get("entity_ids", []), emap)
        h["projects"] = pseudo_list(h.get("projects", []), pmap)
        h["namespaces"] = pseudo_list(h.get("namespaces", []), nmap)
        h["pipelines"] = pseudo_list(h.get("pipelines", []), plmap)
        h["jobs"] = pseudo_list(h.get("jobs", []), jmap)
        h["refs"] = pseudo_list(h.get("refs", []), rmap)
        h["paths"] = pseudo_list(h.get("paths", []), pathmap)

    for w in d.get("workload_identities", []):
        w["project_path"] = _lookup(pmap, w.get("project_path", ""))
        w["namespace_path"] = _lookup(nmap, w.get("namespace_path", ""))
        w["pipeline_id"] = _lookup(plmap, w.get("pipeline_id", ""))
        w["job_id"] = _lookup(jmap, w.get("job_id", ""))
        w["ref"] = _lookup(rmap, w.get("ref", ""))
        w["display_names"] = sorted(set(
            hmap.get(_canonical_human_key(u), "Human-Unknown") for u in w.get("users", [])
        ))
        w["entity_ids"] = pseudo_list(w.get("entity_ids", []), emap)
        w["users"] = [pseudo_human(u) for u in w.get("users", [])]
        w["paths"] = pseudo_list(w.get("paths", []), pathmap)

    for b in d.get("full_identity_bundles", []):
        pseudo_human(b)
        b["entity_id"] = _lookup(emap, b.get("entity_id", ""))
        b["project_path"] = _lookup(pmap, b.get("project_path", ""))
        b["namespace_path"] = _lookup(nmap, b.get("namespace_path", ""))
        b["pipeline_id"] = _lookup(plmap, b.get("pipeline_id", ""))
        b["job_id"] = _lookup(jmap, b.get("job_id", ""))
        b["ref"] = _lookup(rmap, b.get("ref", ""))
        b["paths"] = pseudo_list(b.get("paths", []), pathmap)

    d["redacted"] = True
    d["redact_mode"] = "pseudo"
    return d


def _mask_email(val: str) -> str:
    if not val:
        return val
    if "@" in val:
        parts = val.split("@", 1)
        return (parts[0][:1] or "") + "***@" + parts[1]
    return "[redacted]"


def _mask_text(val: str) -> str:
    if not val:
        return val
    if "@" in val:
        return _mask_email(val)
    if len(val) <= 2:
        return "[redacted]"
    return val[:1] + "***"


def _mask_id(val: str) -> str:
    if not val:
        return val
    if len(val) <= 8:
        return "[redacted]"
    return val[:8] + "..."


def _mask_path(val: str) -> str:
    if not val:
        return val
    if val.startswith("secret/data/"):
        return "secret/data/[redacted]"
    if val.startswith("secret/metadata/"):
        return "secret/metadata/[redacted]"
    if "/" in val:
        return val.split("/")[0] + "/[redacted]"
    return "[redacted]"


def _mask_project(val: str) -> str:
    if not val:
        return val
    if "/" in val:
        return val.split("/")[0] + "/[redacted]"
    return "[redacted-project]"


def redact_mask(data: dict) -> dict:
    d = copy.deepcopy(data)
    _mask_recursive(d)
    d["redacted"] = True
    d["redact_mode"] = "mask"
    return d


def _mask_recursive(obj: Any) -> Any:
    if isinstance(obj, dict):
        for key in obj:
            val = obj[key]
            if isinstance(val, (dict, list)):
                _mask_recursive(val)
            if key == "user_email":
                obj[key] = _mask_email(val) if isinstance(val, str) else val
            elif key == "user_login":
                obj[key] = _mask_text(val) if isinstance(val, str) else val
            elif key == "user_id":
                obj[key] = "[redacted]" if val else val
            elif key == "display_name":
                obj[key] = _mask_text(val) if isinstance(val, str) else val
            elif key == "display_names":
                obj[key] = [_mask_text(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "entity_id":
                obj[key] = _mask_id(val) if isinstance(val, str) else val
            elif key == "entity_ids":
                obj[key] = [_mask_id(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "project_path":
                obj[key] = _mask_project(val) if isinstance(val, str) else val
            elif key == "projects":
                obj[key] = [_mask_project(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "namespace_path":
                obj[key] = "[redacted-namespace]" if isinstance(val, str) and val else val
            elif key == "namespaces":
                obj[key] = ["[redacted-namespace]" if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key in ("pipeline_id", "job_id", "ref"):
                obj[key] = "[redacted]" if isinstance(val, str) and val else val
            elif key in ("pipelines", "jobs", "refs"):
                obj[key] = ["[redacted]" if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "path":
                obj[key] = _mask_path(val) if isinstance(val, str) else val
            elif key == "paths":
                obj[key] = [_mask_path(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "user_logins":
                obj[key] = [_mask_text(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "user_emails":
                obj[key] = [_mask_email(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
            elif key == "secret_paths":
                obj[key] = [_mask_path(v) if isinstance(v, str) else v for v in val] if isinstance(val, list) else val
    elif isinstance(obj, list):
        for item in obj:
            _mask_recursive(item)
    return obj


_STRICT_SINGLE = {
    "user_login", "user_email", "user_id", "display_name", "project_path",
    "namespace_path", "pipeline_id", "job_id", "ref", "path", "entity_id",
    "source_file", "retrieved_audit_file", "role",
}
_STRICT_LIST = {
    "display_names", "entity_ids", "projects", "namespaces", "pipelines",
    "jobs", "refs", "paths", "user_logins", "user_emails", "secret_paths", "roles",
}


def redact_strict(data: dict) -> dict:
    d = copy.deepcopy(data)
    _strict_recursive(d)
    d["redacted"] = True
    d["redact_mode"] = "strict"
    return d


def _strict_recursive(obj: Any) -> Any:
    if isinstance(obj, dict):
        for key in obj:
            val = obj[key]
            if isinstance(val, (dict, list)):
                _strict_recursive(val)
            if key in _STRICT_SINGLE:
                obj[key] = "[redacted]"
            elif key in _STRICT_LIST:
                obj[key] = ["[redacted]"]
    elif isinstance(obj, list):
        for item in obj:
            _strict_recursive(item)
    return obj


# ── rendering: text ──────────────────────────────────────────────────────────

def _ansi(is_tty: bool) -> dict[str, str]:
    if is_tty:
        return {
            "BOLD": "\033[1m", "DIM": "\033[2m", "CYAN": "\033[36m",
            "GREEN": "\033[32m", "YELLOW": "\033[33m", "RED": "\033[31m",
            "RESET": "\033[0m",
        }
    return {k: "" for k in ("BOLD", "DIM", "CYAN", "GREEN", "YELLOW", "RED", "RESET")}


def render_text(data: dict, args: argparse.Namespace) -> str:
    is_tty = sys.stdout.isatty() and not args.output
    c = _ansi(is_tty)
    B, D, C, G, Y, RED, R = c["BOLD"], c["DIM"], c["CYAN"], c["GREEN"], c["YELLOW"], c["RED"], c["RESET"]
    lines: list[str] = []
    p = lines.append

    p("")
    p(f"{B}🔎 VAULT IDENTITY INVENTORY{R}")
    p(f"{D}==========================={R}")
    p("")

    if data.get("redacted"):
        p(f"{Y}⚠️  Redaction enabled ({data.get('redact_mode', 'unknown')}){R}")
        p("")

    latest = data.get("latest_secret_access")
    if latest:
        p(f"{B}🔐 Latest Secret Access{R}")
        p(f"{D}----------------------{R}")
        for label, key in [("User", "user_login"), ("Email", "user_email"),
                           ("Project", "project_path"), ("Pipeline", "pipeline_id"),
                           ("Job", "job_id"), ("Ref", "ref"), ("Role", "role"),
                           ("Path", "path"), ("Operation", "operation")]:
            p(f"{C}{label:10s}:{R} {latest.get(key, '')}")
        p(f"{C}{'Time':10s}:{R} {D}{latest.get('time', '')}{R}")
        p("")

    p(f"{C}Total audit events          :{R} {G}{data['total_events']}{R}")
    p(f"{C}Total read events           :{R} {G}{data['read_events']}{R}")
    p(f"{C}Total secret read events    :{R} {G}{data['secret_read_events']}{R}")
    p("")
    p(f"{C}Unique human identities     :{R} {G}{data['unique_humans']}{R}")
    p(f"{C}Unique workload contexts    :{R} {G}{data['unique_workload_contexts']}{R}")
    p(f"{C}Fallback identity groups    :{R} {G}{data['fallback_identity_groups']}{R}")
    p(f"{C}Unique entities             :{R} {G}{data['unique_entities']}{R}")
    p("")
    p(f"{C}Unique client subjects      :{R} {G}{data['unique_client_subjects']}{R}")
    p(f"{C}Fully correlated workloads  :{R} {G}{data['fully_correlated_workloads']}{R}")
    p(f"{C}Identities without context  :{R} {G}{data['partial_workload_identities']}{R}")
    p("")
    tpo = data["top_path_overall"]
    tsp = data["top_secret_path"]
    p(f"{C}Top path overall            :{R} {tpo['path']} {D}({tpo['count']}){R}")
    p(f"{C}Top secret path             :{R} {tsp['path']} {D}({tsp['count']}){R}")

    if args.explain:
        p("")
        p(f"{B}🛡️ Zero Trust Narrative{R}")
        p(f"{D}-----------------------{R}")
        if latest is None:
            p("No secret access was found in the selected scope.")
        else:
            p(f"A workload authenticated to Vault using {C}{latest.get('auth_method', 'unknown')}{R}.")
            p(f"Vault mapped that workload to entity {C}{latest.get('entity_id', '[unknown]')}{R}.")
            p(
                f"The correlated client was user {C}{latest.get('user_login', '[unknown]')}{R}"
                f" in project {C}{latest.get('project_path', '[unknown]')}{R}"
                f", pipeline {C}{latest.get('pipeline_id', '[unknown]')}{R}"
                f", job {C}{latest.get('job_id', '[unknown]')}{R}."
            )
            p(
                f"Vault recorded {G}{data['total_events']}{R} audit events in scope,"
                f" of which {G}{data['secret_read_events']}{R} were actual secret reads."
            )
            p(f"The latest secret path was {C}{latest.get('path', '[unknown]')}{R}.")

    if args.explain:
        p("")
        p(f"{B}📊 Client Integrity{R}")
        p(f"{D}-------------------{R}")
        p(f"{C}Unique client subjects: {R}{G}{data['unique_client_subjects']}{R}")
        p(f"{C}Unique workload contexts: {R}{G}{data['unique_workload_contexts']}{R}")
        p(f"{C}Fallback identity groups: {R}{G}{data['fallback_identity_groups']}{R}")
        p(f"{C}Fully correlated workloads: {R}{G}{data['fully_correlated_workloads']}{R}")
        p(f"{C}Partial workload identities: {R}{G}{data['partial_workload_identities']}{R}")

    p("")
    p(f"{B}Applied Filters{R}")
    p(f"{D}---------------{R}")
    filt = data["filters"]
    p(f"{C}Secrets only           :{R} {filt['secrets_only']}")
    p(f"{C}Exact path             :{R} {filt['path_exact']}")
    p(f"{C}Path prefix            :{R} {filt['path_prefix']}")
    p(f"{C}Excluded path prefix   :{R} {filt['exclude_path_prefix']}")
    p(f"{C}Operation              :{R} {filt['operation']}")
    p(f"{C}Since                  :{R} {filt['since']}")
    p(f"{C}Until                  :{R} {filt['until']}")
    p(f"{C}Date                   :{R} {filt['date_only']}")
    p("")

    if data["total_events"] == 0:
        p(f"{Y}No matching audit events found.{R}")
        return "\n".join(lines)

    if args.latest_only:
        return "\n".join(lines)

    if args.summary:
        p(f"{B}Summary{R}")
        p(f"{D}-------{R}")
        for b in data["full_identity_bundles"]:
            p(f"{C}Count      : {R}{G}{b['count']}{R}")
            for label, key in [("User", "user_login"), ("Email", "user_email"),
                               ("Project", "project_path"), ("Pipeline", "pipeline_id"),
                               ("Job", "job_id"), ("Ref", "ref"), ("Role", "role")]:
                p(f"{C}{label:11s}: {R}{b.get(key, '')}")
            p(f"{C}First Seen : {R}{D}{b['first_seen']}{R}")
            p(f"{C}Last Seen  : {R}{D}{b['last_seen']}{R}")
            p("")
        return "\n".join(lines)

    # correlations
    p(f"{B}🔗 Identity Correlations{R}")
    p(f"{D}------------------------{R}")
    for cr in data["correlations"]:
        p(f"{C}Entity ID   : {R}{D}{cr['entity_id']}{R}")
        p(f"{C}Auth Method : {R}{', '.join(cr['auth_methods'])}")
        p(f"{C}Display     : {R}{', '.join(cr['display_names'])}")
        p(f"{C}User Login  : {R}{', '.join(cr['user_logins'])}")
        p(f"{C}Email       : {R}{', '.join(cr['user_emails'])}")
        p(f"{C}Project     : {R}{', '.join(cr['projects'])}")
        p(f"{C}Pipeline    : {R}{', '.join(cr['pipelines'])}")
        p(f"{C}Job         : {R}{', '.join(cr['jobs'])}")
        p(f"{C}Secret Path : {R}{', '.join(cr['secret_paths'])}")
        p(f"{C}Role        : {R}{', '.join(cr['roles'])}")
        p(f"{C}Refs        : {R}{', '.join(cr['refs'])}")
        p(f"{C}Ops         : {R}{', '.join(cr['operations'])}")
        p(f"{C}Events      : {R}{G}{cr['count']}{R}")
        p(f"{C}First Seen  : {R}{D}{cr['first_seen']}{R}")
        p(f"{C}Last Seen   : {R}{D}{cr['last_seen']}{R}")
        p("")
    p("")

    # drift findings
    if args.detect_drift:
        p("")
        p(f"{B}🚨 Drift Findings{R}")
        p(f"{D}-----------------{R}")
        if not data["drift_findings"]:
            p(f"{G}No drift findings detected.{R}")
        else:
            for df in data["drift_findings"]:
                sev_c = RED if df["severity"] == "medium" else Y if df["severity"] == "low" else ""
                p(f"{C}Severity   : {R}{sev_c}{df['severity']}{R}")
                p(f"{C}Type       : {R}{df['type']}")
                p(f"{C}Message    : {R}{df['message']}")
                p("")

    # identity lifecycle
    p("")
    p(f"{B}🧬 Identity Lifecycle{R}")
    p(f"{D}--------------------{R}")
    for il in data["identity_lifecycle"]:
        p(f"{C}User       : {R}{il['user_login']}")
        p(f"{C}Email      : {R}{il['user_email']}")
        for ent in il["entities"]:
            p(f"- {C}Entity {R}{D}{ent['entity_id']}{R} : {D}{ent['first_seen']}{R} → {D}{ent['last_seen']}{R}")
        p(f"{C}Current    : {R}{D}{il['current_entity']}{R}")
        p("")

    # top N
    if args.top:
        p(f"{B}🔥 Top Identities by Access Count{R}")
        p(f"{D}--------------------------------{R}")
        top_sorted = sorted(data["human_identities"], key=lambda x: -x["count"])[:args.top]
        for hi in top_sorted:
            proj = hi["projects"][0] if hi["projects"] else ""
            p(f"{G}{hi['count']}{R}\t{C}{hi['user_login']}{R}\t{proj}")
        p("")

    # human identities
    p(f"{B}👤 Human Identities{R}")
    p(f"{D}-------------------{R}")
    for hi in data["human_identities"]:
        p(f"{C}Events     : {R}{G}{hi['count']}{R}")
        p(f"{C}User       : {R}{hi['user_login']}")
        p(f"{C}Email      : {R}{hi['user_email']}")
        p(f"{C}User ID    : {R}{hi['user_id']}")
        p(f"{C}Projects   : {R}{', '.join(hi['projects'])}")
        p(f"{C}Namespaces : {R}{', '.join(hi['namespaces'])}")
        p(f"{C}Pipelines  : {R}{', '.join(hi['pipelines'])}")
        p(f"{C}Jobs       : {R}{', '.join(hi['jobs'])}")
        p(f"{C}Refs       : {R}{', '.join(hi['refs'])}")
        p(f"{C}Roles      : {R}{', '.join(hi['roles'])}")
        p(f"{C}Display    : {R}{', '.join(hi['display_names'])}")
        p(f"{C}Entity IDs : {R}{D}{', '.join(hi['entity_ids'])}{R}")
        p(f"{C}Paths      : {R}{', '.join(hi['paths'])}")
        p(f"{C}Ops        : {R}{', '.join(hi['operations'])}")
        p(f"{C}First Seen : {R}{D}{hi['first_seen']}{R}")
        p(f"{C}Last Seen  : {R}{D}{hi['last_seen']}{R}")
        p("")
    p("")

    # workload identities
    p(f"{B}⚙️ Execution Context Groups{R}")
    p(f"{D}----------------------{R}")
    for wi in data["workload_identities"]:
        users_str = ", ".join(
            f"{u.get('user_login', '')} <{u.get('user_email', '')}>" for u in wi["users"]
        )
        p(f"{C}Events     : {R}{G}{wi['count']}{R}")
        p(f"{C}Mode       : {R}{wi['grouping_mode']}")
        p(f"{C}Project    : {R}{wi['project_path']}")
        p(f"{C}Namespace  : {R}{wi['namespace_path']}")
        p(f"{C}Pipeline   : {R}{wi['pipeline_id']}")
        p(f"{C}Job        : {R}{wi['job_id']}")
        p(f"{C}Ref        : {R}{wi['ref']}")
        p(f"{C}Role       : {R}{wi['role']}")
        p(f"{C}Fallback   : {R}{D}{wi['fallback_entity_id']}{R}")
        p(f"{C}Users      : {R}{users_str}")
        p(f"{C}Display    : {R}{', '.join(wi['display_names'])}")
        p(f"{C}Entity IDs : {R}{D}{', '.join(wi['entity_ids'])}{R}")
        p(f"{C}Paths      : {R}{', '.join(wi['paths'])}")
        p(f"{C}Ops        : {R}{', '.join(wi['operations'])}")
        p(f"{C}First Seen : {R}{D}{wi['first_seen']}{R}")
        p(f"{C}Last Seen  : {R}{D}{wi['last_seen']}{R}")
        p("")
    p("")

    # full identity bundles
    p(f"{B}🧩 Full Identity Bundles{R}")
    p(f"{D}------------------------{R}")
    for fb in data["full_identity_bundles"]:
        p(f"{C}Events     : {R}{G}{fb['count']}{R}")
        p(f"{C}Display    : {R}{fb['display_name']}")
        p(f"{C}Entity ID  : {R}{D}{fb['entity_id']}{R}")
        p(f"{C}Role       : {R}{fb['role']}")
        p(f"{C}User       : {R}{fb['user_login']}")
        p(f"{C}Email      : {R}{fb['user_email']}")
        p(f"{C}User ID    : {R}{fb['user_id']}")
        p(f"{C}Project    : {R}{fb['project_path']}")
        p(f"{C}Namespace  : {R}{fb['namespace_path']}")
        p(f"{C}Pipeline   : {R}{fb['pipeline_id']}")
        p(f"{C}Job        : {R}{fb['job_id']}")
        p(f"{C}Ref        : {R}{fb['ref']}")
        p(f"{C}First Seen : {R}{D}{fb['first_seen']}{R}")
        p(f"{C}Last Seen  : {R}{D}{fb['last_seen']}{R}")
        p(f"{C}Paths      : {R}{', '.join(fb['paths'])}")
        p(f"{C}Ops        : {R}{', '.join(fb['operations'])}")
        p("")

    # timeline
    if args.timeline:
        p("")
        p(f"{B}🕒 Timeline{R}")
        p(f"{D}-----------{R}")
        for te in data["timeline_events"]:
            p(
                f"{D}{te['time']}{R}\t{te['auth_method']}\t{C}{te['user_login']}{R}\t"
                f"{te['operation']}\tpipeline={te['pipeline_id']}\tjob={te['job_id']}\t{te['path']}"
            )
        p("")

    return "\n".join(lines)


# ── rendering: markdown ─────────────────────────────────────────────────────

def render_md(data: dict, args: argparse.Namespace) -> str:
    lines: list[str] = []
    p = lines.append

    p("# 🔎 Vault Identity Inventory")
    p("")
    if data.get("redacted"):
        p(f"> ⚠️ Redaction enabled ({data.get('redact_mode', 'unknown')})")
        p("")

    p(f"- **Total audit events:** `{data['total_events']}`")
    p(f"- **Total read events:** `{data['read_events']}`")
    p(f"- **Total secret read events:** `{data['secret_read_events']}`")
    p(f"- **Unique human identities:** `{data['unique_humans']}`")
    p(f"- **Unique workload contexts:** `{data['unique_workload_contexts']}`")
    p(f"- **Fallback identity groups:** `{data['fallback_identity_groups']}`")
    p(f"- **Unique entities:** `{data['unique_entities']}`")
    p(f"- **Unique client subjects:** `{data['unique_client_subjects']}`")
    p(f"- **Fully correlated workloads:** `{data['fully_correlated_workloads']}`")
    p(f"- **Partial workload identities:** `{data['partial_workload_identities']}`")
    tpo = data["top_path_overall"]
    tsp = data["top_secret_path"]
    p(f"- **Top path overall:** `{tpo['path']}` (`{tpo['count']}`)")
    p(f"- **Top secret path:** `{tsp['path']}` (`{tsp['count']}`)")
    p("")

    p("## Applied Filters")
    p("")
    filt = data["filters"]
    p(f"- **Secrets only:** `{filt['secrets_only']}`")
    p(f"- **Exact path:** `{filt['path_exact']}`")
    p(f"- **Path prefix:** `{filt['path_prefix']}`")
    p(f"- **Excluded path prefix:** `{filt['exclude_path_prefix']}`")
    p(f"- **Operation:** `{filt['operation']}`")
    p(f"- **Since:** `{filt['since']}`")
    p(f"- **Until:** `{filt['until']}`")
    p(f"- **Date:** `{filt['date_only']}`")
    p("")

    if data["total_events"] == 0:
        p("No matching audit events found.")
        return "\n".join(lines)

    latest = data.get("latest_secret_access")
    if latest:
        p("## Latest Secret Access")
        p("")
        p(f"- **User:** `{latest['user_login']}`")
        p(f"  - **Email:** `{latest['user_email']}`")
        p(f"  - **Project:** `{latest['project_path']}`")
        p(f"  - **Pipeline:** `{latest['pipeline_id']}`")
        p(f"  - **Job:** `{latest['job_id']}`")
        p(f"  - **Ref:** `{latest['ref']}`")
        p(f"  - **Role:** `{latest['role']}`")
        p(f"  - **Path:** `{latest['path']}`")
        p(f"  - **Operation:** `{latest['operation']}`")
        p(f"  - **Time:** `{latest['time']}`")
        p("")

    if args.latest_only:
        if args.timeline:
            p("## Timeline")
            p("")
            for te in data["timeline_events"]:
                p(
                    f"- `{te['time']}` `{te['auth_method']}` `{te['operation']}`"
                    f" `{te['user_login']}` `pipeline={te['pipeline_id']}`"
                    f" `job={te['job_id']}` `{te['path']}`"
                )
        return "\n".join(lines)

    if args.summary:
        p("## Summary")
        p("")
        for b in data["full_identity_bundles"]:
            p(f"- **User:** `{b['user_login']}`")
            p(f"  - **Email:** `{b['user_email']}`")
            p(f"  - **Project:** `{b['project_path']}`")
            p(f"  - **Pipeline:** `{b['pipeline_id']}`")
            p(f"  - **Job:** `{b['job_id']}`")
            p(f"  - **Ref:** `{b['ref']}`")
            p(f"  - **Role:** `{b['role']}`")
            p(f"  - **Count:** `{b['count']}`")
            p(f"  - **First Seen:** `{b['first_seen']}`")
            p(f"  - **Last Seen:** `{b['last_seen']}`")
            p("")
        return "\n".join(lines)

    # correlations
    p("## Identity Correlations")
    p("")
    for cr in data["correlations"]:
        p(f"- **Entity ID:** `{cr['entity_id']}`")
        p(f"  - **Auth Methods:** `{', '.join(cr['auth_methods'])}`")
        p(f"  - **Display Names:** `{', '.join(cr['display_names'])}`")
        p(f"  - **User Logins:** `{', '.join(cr['user_logins'])}`")
        p(f"  - **Emails:** `{', '.join(cr['user_emails'])}`")
        p(f"  - **Projects:** `{', '.join(cr['projects'])}`")
        p(f"  - **Pipelines:** `{', '.join(cr['pipelines'])}`")
        p(f"  - **Jobs:** `{', '.join(cr['jobs'])}`")
        p(f"  - **Secret Paths:** `{', '.join(cr['secret_paths'])}`")
        p(f"  - **Roles:** `{', '.join(cr['roles'])}`")
        p(f"  - **Refs:** `{', '.join(cr['refs'])}`")
        p(f"  - **Operations:** `{', '.join(cr['operations'])}`")
        p(f"  - **Count:** `{cr['count']}`")
        p(f"  - **First Seen:** `{cr['first_seen']}`")
        p(f"  - **Last Seen:** `{cr['last_seen']}`")
        p("")
    p("")

    # human identities
    p("## Human Identities")
    p("")
    for hi in data["human_identities"]:
        p(f"- **User:** `{hi['user_login']}`")
        p(f"  - **Email:** `{hi['user_email']}`")
        p(f"  - **User ID:** `{hi['user_id']}`")
        p(f"  - **Count:** `{hi['count']}`")
        p(f"  - **Projects:** `{', '.join(hi['projects'])}`")
        p(f"  - **Namespaces:** `{', '.join(hi['namespaces'])}`")
        p(f"  - **Pipelines:** `{', '.join(hi['pipelines'])}`")
        p(f"  - **Jobs:** `{', '.join(hi['jobs'])}`")
        p(f"  - **Refs:** `{', '.join(hi['refs'])}`")
        p(f"  - **Roles:** `{', '.join(hi['roles'])}`")
        p(f"  - **Display Names:** `{', '.join(hi['display_names'])}`")
        p(f"  - **Entity IDs:** `{', '.join(hi['entity_ids'])}`")
        p(f"  - **Paths:** `{', '.join(hi['paths'])}`")
        p(f"  - **Operations:** `{', '.join(hi['operations'])}`")
        p(f"  - **First Seen:** `{hi['first_seen']}`")
        p(f"  - **Last Seen:** `{hi['last_seen']}`")
        p("")
    p("")

    # workload identities
    p("## Workload Identities")
    p("")
    for wi in data["workload_identities"]:
        users_str = ", ".join(
            f"{u.get('user_login', '')} <{u.get('user_email', '')}>" for u in wi["users"]
        )
        p(f"- **Mode:** `{wi['grouping_mode']}`")
        p(f"  - **Project:** `{wi['project_path']}`")
        p(f"  - **Namespace:** `{wi['namespace_path']}`")
        p(f"  - **Pipeline:** `{wi['pipeline_id']}`")
        p(f"  - **Job:** `{wi['job_id']}`")
        p(f"  - **Ref:** `{wi['ref']}`")
        p(f"  - **Role:** `{wi['role']}`")
        p(f"  - **Fallback Entity ID:** `{wi['fallback_entity_id']}`")
        p(f"  - **Count:** `{wi['count']}`")
        p(f"  - **Users:** `{users_str}`")
        p(f"  - **Display Names:** `{', '.join(wi['display_names'])}`")
        p(f"  - **Entity IDs:** `{', '.join(wi['entity_ids'])}`")
        p(f"  - **Paths:** `{', '.join(wi['paths'])}`")
        p(f"  - **Operations:** `{', '.join(wi['operations'])}`")
        p(f"  - **First Seen:** `{wi['first_seen']}`")
        p(f"  - **Last Seen:** `{wi['last_seen']}`")
        p("")
    p("")

    # full identity bundles
    p("## Full Identity Bundles")
    p("")
    for fb in data["full_identity_bundles"]:
        p(f"- **Display:** `{fb['display_name']}`")
        p(f"  - **Entity ID:** `{fb['entity_id']}`")
        p(f"  - **Role:** `{fb['role']}`")
        p(f"  - **User:** `{fb['user_login']}`")
        p(f"  - **Email:** `{fb['user_email']}`")
        p(f"  - **User ID:** `{fb['user_id']}`")
        p(f"  - **Project:** `{fb['project_path']}`")
        p(f"  - **Namespace:** `{fb['namespace_path']}`")
        p(f"  - **Pipeline:** `{fb['pipeline_id']}`")
        p(f"  - **Job:** `{fb['job_id']}`")
        p(f"  - **Ref:** `{fb['ref']}`")
        p(f"  - **Count:** `{fb['count']}`")
        p(f"  - **First Seen:** `{fb['first_seen']}`")
        p(f"  - **Last Seen:** `{fb['last_seen']}`")
        p(f"  - **Paths:** `{', '.join(fb['paths'])}`")
        p(f"  - **Operations:** `{', '.join(fb['operations'])}`")
        p("")

    # timeline
    if args.timeline:
        p("")
        p("## Timeline")
        p("")
        for te in data["timeline_events"]:
            p(
                f"- `{te['time']}` `{te['auth_method']}` `{te['operation']}`"
                f" `{te['user_login']}` `pipeline={te['pipeline_id']}`"
                f" `job={te['job_id']}` `{te['path']}`"
            )

    return "\n".join(lines)


# ── container retrieval ──────────────────────────────────────────────────────

def retrieve_audit_file(
    dest: str,
    container_engine: str = "docker",
    container_name: str = "gitlab-vault",
    audit_path: str = "/tmp/vault_audit.log",
) -> None:
    Path(dest).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [container_engine, "cp", f"{container_name}:{audit_path}", dest],
        check=True,
    )


# ── main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    # If --redact-mode is set, imply --redact
    validate_args(args)

    files: list[str] = list(args.files)
    retrieved_audit_file = ""

    # --retrieve-audit-file
    if args.retrieve_audit_file:
        container_engine = os.environ.get("CONTAINER_ENGINE", "docker")
        container_name = os.environ.get("VAULT_CONTAINER_NAME", "gitlab-vault")
        audit_path = os.environ.get("VAULT_AUDIT_PATH", "/tmp/vault_audit.log")
        retrieved_audit_file = args.retrieve_audit_file
        retrieve_audit_file(
            args.retrieve_audit_file,
            container_engine=container_engine,
            container_name=container_name,
            audit_path=audit_path,
        )
        files.append(args.retrieve_audit_file)

    if not files:
        fail("Provide at least one vault audit log file or use --retrieve-audit-file <path>")

    for f in files:
        if not os.path.isfile(f):
            fail(f"File not found: {f}")

    # Read & parse
    records = read_logs(files)

    # Build filters
    filt = Filters(args)

    # Extract & analyse
    events = build_events(records, filt)
    source_files = ",".join(files)
    data = analyse(events, source_files, retrieved_audit_file, filt)

    # Redaction
    if args.redact:
        if args.redact_mode == "pseudo":
            data = redact_pseudo(data)
        elif args.redact_mode == "mask":
            data = redact_mask(data)
        elif args.redact_mode == "strict":
            data = redact_strict(data)

    # Render
    if args.format == "json":
        output = json.dumps(data, indent=2, ensure_ascii=False)
    elif args.format == "md":
        output = render_md(data, args)
    else:
        output = render_text(data, args)

    # Emit
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(output + "\n")
        print(f"Wrote report to {args.output}")
    else:
        print(output)


if __name__ == "__main__":
    main()