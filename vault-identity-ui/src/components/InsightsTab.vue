<template>
  <CollapsiblePanel
    title="Identity Views"
    kicker="Exploration"
    subtitle="Switch between people, workloads, and raw access sequence."
    :preview="previewText"
    storage-key="vault-insights-identity-views"
  >
    <div class="insight-tabs">
      <div class="insight-tabs__header">

        <div class="insight-tabs__tabbar">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            class="insight-tabs__tab card-lift"
            :class="{ 'insight-tabs__tab--active': activeTab === tab.key }"
            @click="activeTab = tab.key"
          >
            {{ tab.label }}
          </button>
        </div>
      </div>

      <div class="insight-tabs__body">
        <table v-if="activeTab === 'humans'" class="data-table">
          <thead>
            <tr>
              <th>User</th>
              <th>Email</th>
              <th>Count</th>
              <th>Projects</th>
              <th>Last Seen</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="item in humans"
              :key="`${item.user_login}-${item.user_email}`"
              @click="$emit('select-human', item)"
            >
              <td>{{ item.user_login }}</td>
              <td class="muted">{{ item.user_email }}</td>
              <td>{{ item.count }}</td>
              <td>{{ item.projects.join(', ') }}</td>
              <td class="dim">{{ formatTime(item.last_seen) }}</td>
            </tr>
          </tbody>
        </table>

        <table v-else-if="activeTab === 'workloads'" class="data-table">
          <thead>
            <tr>
              <th>Project</th>
              <th>Pipeline</th>
              <th>Job</th>
              <th>Users</th>
              <th>Last Seen</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="item in workloads"
              :key="`${item.project_path}-${item.pipeline_id}-${item.job_id}`"
              @click="$emit('select-workload', item)"
            >
              <td>{{ item.project_path }}</td>
              <td>{{ item.pipeline_id }}</td>
              <td>{{ item.job_id }}</td>
              <td>
                {{ item.users.map((u) => u.user_login).join(", ") }}
              </td>
              <td class="dim">{{ formatTime(item.last_seen) }}</td>
            </tr>
          </tbody>
        </table>

        <table v-else class="data-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>User</th>
              <th>Operation</th>
              <th>Pipeline</th>
              <th>Job</th>
              <th>Path</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="item in timeline"
              :key="`${item.time}-${item.job_id}`"
              @click="$emit('select-event', item)"
            >
              <td class="dim">{{ formatTime(item.time) }}</td>
              <td>{{ item.user_login }}</td>
              <td>
                <span
                  v-if="item.operation === 'read'"
                  class="badge badge-read"
                >
                  {{ item.operation }}
                </span>
                <span v-else class="timeline-op">
                  {{ item.operation }}
                </span>
              </td>
              <td>{{ item.pipeline_id }}</td>
              <td>{{ item.job_id }}</td>
              <td class="mono">
                <span class="path-token">
                  <span v-if="splitPath(item.path).prefix" class="path-prefix">{{ splitPath(item.path).prefix }}</span>
                  <span class="path-leaf">{{ splitPath(item.path).leaf }}</span>
                </span>
              </td>
            </tr>
          </tbody>
        </table>

        <div
          v-if="
            (activeTab === 'humans' && !humans.length) ||
            (activeTab === 'workloads' && !workloads.length) ||
            (activeTab === 'timeline' && !timeline.length)
          "
          class="empty-state"
        >
          No data available in this view.
        </div>
      </div>
    </div>
  </CollapsiblePanel>
</template>

<script setup lang="ts">
import { computed, ref } from "vue"
import CollapsiblePanel from "./CollapsiblePanel.vue"
import type {
  HumanIdentity,
  TimelineEvent,
  WorkloadIdentity,
} from "../types/vault"

const props = defineProps<{
  humans: HumanIdentity[]
  workloads: WorkloadIdentity[]
  timeline: TimelineEvent[]
}>()

defineEmits<{
  (e: "select-human", value: HumanIdentity): void
  (e: "select-workload", value: WorkloadIdentity): void
  (e: "select-event", value: TimelineEvent): void
}>()

const tabs = [
  { key: "humans", label: "Individuals" },
  { key: "workloads", label: "Workloads" },
  { key: "timeline", label: "Timeline" },
] as const

const activeTab = ref<(typeof tabs)[number]["key"]>("humans")
const previewText = computed(() => {
  const latest = props.timeline.at(-1)
  const lastActivity = latest ? formatTimeShort(latest.time) : "—"
  return `${props.humans.length} humans • ${props.workloads.length} workloads • last activity ${lastActivity}`
})

function formatTime(value: string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }
  return date.toLocaleString()
}

function formatTimeShort(value: string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }

  return date.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  })
}

function splitPath(path: string): { prefix: string; leaf: string } {
  const idx = path.lastIndexOf("/")
  if (idx === -1) {
    return { prefix: "", leaf: path || "—" }
  }

  return {
    prefix: path.slice(0, idx + 1),
    leaf: path.slice(idx + 1) || "—",
  }
}
</script>

<style scoped>
.insight-tabs {
  padding: 24px;
}

.insight-tabs__header {
  display: flex;
  justify-content: space-between;
  gap: 18px;
  align-items: end;
  margin-bottom: 18px;
}

.insight-tabs__tabbar {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.insight-tabs__tab {
  min-height: 38px;
  padding: 0 14px;
  border-radius: 999px;
  border: 1px solid var(--border-default);
  background: rgba(255, 255, 255, 0.02);
  color: var(--text-secondary);
  cursor: pointer;
  transition:
    background-color 0.16s ease,
    border-color 0.16s ease,
    color 0.16s ease,
    transform 0.1s ease,
    box-shadow 0.16s ease;
}

.insight-tabs__tab:hover {
  border-color: rgba(245, 184, 65, 0.18);
  color: var(--text-primary);
  transform: translateY(-1px);
}

.insight-tabs__tab:active {
  transform: scale(0.98);
}

.insight-tabs__tab--active {
  border-color: rgba(245, 184, 65, 0.36);
  background: rgba(245, 184, 65, 0.1);
  color: #f8d37c;
  box-shadow:
    0 0 0 1px rgba(245, 184, 65, 0.12),
    0 0 18px rgba(245, 184, 65, 0.08);
}

.timeline-op {
  color: #facc15;
  text-transform: lowercase;
}

@media (max-width: 980px) {
  .insight-tabs__header {
    flex-direction: column;
    align-items: flex-start;
  }
}
</style>
