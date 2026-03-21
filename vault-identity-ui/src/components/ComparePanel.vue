<template>
  <CollapsiblePanel
    title="Compare Identity Fingerprints"
    kicker="Comparison"
    subtitle="Compare two access fingerprints touching the same secret path."
    :preview="previewText"
    storage-key="vault-insights-compare-panel"
  >
    <div class="compare-panel">

      <div class="compare-panel__controls">
        <select v-model="leftId" class="compare-panel__select">
          <option value="">Select first identity</option>
          <option
            v-for="item in bundles"
            :key="bundleKey(item)"
            :value="bundleKey(item)"
          >
            {{ item.user_login }} • {{ item.paths[0] || "no-path" }} • job
            {{ item.job_id }}
          </option>
        </select>

        <select v-model="rightId" class="compare-panel__select">
          <option value="">Select second identity</option>
          <option
            v-for="item in bundles"
            :key="bundleKey(item)"
            :value="bundleKey(item)"
          >
            {{ item.user_login }} • {{ item.paths[0] || "no-path" }} • job
            {{ item.job_id }}
          </option>
        </select>
      </div>

      <div class="compare-panel__grid">
        <div class="compare-panel__card card-lift">
          <div class="compare-panel__card-title">Identity A</div>
          <div v-if="left" class="compare-panel__fields">
            <div><strong>User:</strong> {{ left.user_login }}</div>
            <div><strong>Email:</strong> {{ left.user_email }}</div>
            <div><strong>Project:</strong> {{ left.project_path }}</div>
            <div><strong>Pipeline:</strong> {{ left.pipeline_id }}</div>
            <div><strong>Job:</strong> {{ left.job_id }}</div>
            <div><strong>Role:</strong> {{ left.role }}</div>
            <div><strong>Path:</strong> {{ left.paths.join(", ") }}</div>
            <div>
              <strong>Entity ID:</strong>
              <span class="mono">{{ left.entity_id }}</span>
            </div>
            <div><strong>Last Seen:</strong> {{ formatTime(left.last_seen) }}</div>
          </div>
          <div v-else class="empty-state">Select an identity bundle.</div>
        </div>

        <div class="compare-panel__card card-lift">
          <div class="compare-panel__card-title">Identity B</div>
          <div v-if="right" class="compare-panel__fields">
            <div><strong>User:</strong> {{ right.user_login }}</div>
            <div><strong>Email:</strong> {{ right.user_email }}</div>
            <div><strong>Project:</strong> {{ right.project_path }}</div>
            <div><strong>Pipeline:</strong> {{ right.pipeline_id }}</div>
            <div><strong>Job:</strong> {{ right.job_id }}</div>
            <div><strong>Role:</strong> {{ right.role }}</div>
            <div><strong>Path:</strong> {{ right.paths.join(", ") }}</div>
            <div>
              <strong>Entity ID:</strong>
              <span class="mono">{{ right.entity_id }}</span>
            </div>
            <div><strong>Last Seen:</strong> {{ formatTime(right.last_seen) }}</div>
          </div>
          <div v-else class="empty-state">Select an identity bundle.</div>
        </div>
      </div>
    </div>
  </CollapsiblePanel>
</template>

<script setup lang="ts">
import { computed, ref } from "vue"
import CollapsiblePanel from "./CollapsiblePanel.vue"
import type { IdentityBundle } from "../types/vault"

const props = defineProps<{
  bundles: IdentityBundle[]
}>()

const leftId = ref("")
const rightId = ref("")

function bundleKey(item: IdentityBundle): string {
  return `${item.user_login}|${item.job_id}|${item.entity_id}|${item.paths[0] || ""}`
}

const left = computed(() => props.bundles.find((x) => bundleKey(x) === leftId.value) ?? null)
const right = computed(() => props.bundles.find((x) => bundleKey(x) === rightId.value) ?? null)
const previewText = computed(() => {
  if (left.value && right.value) {
    return `${left.value.user_login} vs ${right.value.user_login} • ${left.value.paths[0] || "no-path"}`
  }

  const samePathDetected =
    new Set(props.bundles.flatMap((bundle) => bundle.paths)).size < props.bundles.length

  return `${props.bundles.length} bundles available • ${samePathDetected ? "same path detected" : "multiple paths observed"}`
})

function formatTime(value: string): string {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }
  return date.toLocaleString()
}
</script>

<style scoped>
.compare-panel {
  padding: 24px;
}

.compare-panel__controls {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-bottom: 18px;
}

.compare-panel__select {
  min-height: 44px;
  border-radius: 14px;
  border: 1px solid var(--border-default);
  background: rgba(255, 255, 255, 0.03);
  color: var(--text-primary);
  padding: 0 14px;
}

.compare-panel__grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 18px;
}

.compare-panel__card {
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 18px;
  padding: 18px;
  background: rgba(255, 255, 255, 0.015);
}

.compare-panel__card-title {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--text-muted);
  margin-bottom: 14px;
}

.compare-panel__fields {
  display: grid;
  gap: 10px;
  color: var(--text-secondary);
  font-size: 14px;
}

.compare-panel__fields strong {
  color: var(--text-primary);
}

@media (max-width: 980px) {
  .compare-panel__controls,
  .compare-panel__grid {
    grid-template-columns: 1fr;
  }
}
</style>
