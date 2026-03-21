import type { VaultData } from "../types/vault"

export function exportMarkdown(data: VaultData): void {
  const latest = [...(data.timeline_events ?? [])]
    .sort((a, b) => a.time.localeCompare(b.time))
    .at(-1)

  const topHumans = [...(data.human_identities ?? [])]
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)

  const timeline = (data.timeline_events ?? [])
    .map(
      (e) =>
        `- ${e.time} | ${e.user_login} | ${e.operation} | pipeline=${e.pipeline_id} | job=${e.job_id} | ${e.path}`,
    )
    .join("\n")

  const humans = (data.human_identities ?? [])
    .map(
      (h) => `- ${h.user_login} <${h.user_email}> | count=${h.count} | last_seen=${h.last_seen}`,
    )
    .join("\n")

  const md = `# Vault Identity Report

Generated: ${data.generated_at ?? new Date().toISOString()}
Source: ${data.source_file ?? "vault_identity.json"}

## Executive Summary

- Total audit events: ${data.total_events}
- Total read events: ${data.read_events}
- Total secret read events: ${data.secret_read_events}
- Unique individuals: ${data.unique_humans}
- Unique workloads: ${data.unique_workloads}

## Latest Secret Access

- User: ${latest?.user_login ?? "—"}
- Email: ${latest?.user_email ?? "—"}
- Project: ${latest?.project_path ?? "—"}
- Pipeline: ${latest?.pipeline_id ?? "—"}
- Job: ${latest?.job_id ?? "—"}
- Path: ${latest?.path ?? "—"}
- Operation: ${latest?.operation ?? "—"}
- Time: ${latest?.time ?? "—"}

## Top Individuals

${topHumans.length ? topHumans.map((h) => `- ${h.user_login} (${h.count})`).join("\n") : "- None"}

## Individuals

${humans || "- None"}

## Timeline

${timeline || "- None"}
`

  const blob = new Blob([md], { type: "text/markdown;charset=utf-8" })
  const url = URL.createObjectURL(blob)

  const link = document.createElement("a")
  link.href = url
  link.download = `vault-identity-report-${Date.now()}.md`
  link.click()

  URL.revokeObjectURL(url)
}