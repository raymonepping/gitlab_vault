<template>
  <CollapsiblePanel
    class="panel-core-proof"
    title="Same Secret, Different Fingerprints"
    kicker="Core Proof"
    subtitle="Identical secret access paths, preserved as distinct identity traces across separate GitLab executions."
    :preview="previewText"
    :default-open="true"
    storage-key="vault-insights-core-proof"
  >
    <div class="fingerprint-panel__inner">

      <div v-if="rows.length" class="fingerprint-table-wrap">
        <table class="data-table">
          <thead>
            <tr>
              <th>Path</th>
              <th>User</th>
              <th>Email</th>
              <th>Project</th>
              <th>Pipeline</th>
              <th>Job</th>
              <th>Time</th>
            </tr>
          </thead>

          <tbody>
            <tr v-for="row in rows" :key="`${row.time}-${row.user_login}-${row.job_id}`">
              <td class="mono fingerprint-table__path">
                <template v-if="splitPath(row.path).prefix">
                  <span class="path-prefix">{{ splitPath(row.path).prefix }}</span>
                  <span class="path-leaf">{{ splitPath(row.path).leaf }}</span>
                </template>
                <template v-else>
                  {{ row.path }}
                </template>
              </td>
              <td>{{ row.user_login }}</td>
              <td class="muted">{{ row.user_email }}</td>
              <td>{{ row.project_path }}</td>
              <td>{{ row.pipeline_id }}</td>
              <td>{{ row.job_id }}</td>
              <td class="dim">{{ formatTime(row.time) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-else class="empty-state">
        No matching secret-access fingerprints found in the current dataset.
      </div>
    </div>
  </CollapsiblePanel>
</template>

<script setup lang="ts">
import { computed } from "vue"
import CollapsiblePanel from "./CollapsiblePanel.vue"

type TimelineEvent = {
  time: string
  user_login: string
  user_email: string
  project_path: string
  pipeline_id: string
  job_id: string
  path: string
}

const props = defineProps<{
  timeline: TimelineEvent[] | null | undefined
}>()

const rows = computed(() => {
  const items = (props.timeline ?? []).filter((item) => item.path?.startsWith("secret/data/"))
  return [...items].sort((a, b) => a.path.localeCompare(b.path) || a.time.localeCompare(b.time))
})
const previewText = computed(() => {
  const uniqueUsers = new Set(rows.value.map((row) => row.user_login)).size
  const firstPath = rows.value[0]?.path
  const parts = [
    `${rows.value.length} matching fingerprint events`,
    `${uniqueUsers} distinct identities`,
  ]

  if (firstPath) {
    parts.push(`shared path ${splitPath(firstPath).leaf}`)
  }

  return parts.join(" • ")
})

function formatTime(value: string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }
  return date.toLocaleString()
}

function splitPath(path: string): { prefix: string; leaf: string } {
  const idx = path.lastIndexOf("/")
  if (idx === -1) {
    return { prefix: "", leaf: path }
  }
  return {
    prefix: path.slice(0, idx + 1),
    leaf: path.slice(idx + 1),
  }
}
</script>

<style scoped>
.fingerprint-panel__inner {
  padding: 24px 24px 18px;
}

.panel-core-proof {
  border: 1px solid rgba(245, 184, 65, 0.18);
  box-shadow:
    0 0 0 1px rgba(245, 184, 65, 0.06),
    0 12px 40px rgba(245, 184, 65, 0.08);
}

.fingerprint-table-wrap {
  overflow-x: auto;
  border-radius: 18px;
  border: 1px solid rgba(255, 255, 255, 0.05);
  background: rgba(255, 255, 255, 0.015);
}

.fingerprint-table__path {
  color: #f8d37c;
  font-size: 13px;
}
</style>
