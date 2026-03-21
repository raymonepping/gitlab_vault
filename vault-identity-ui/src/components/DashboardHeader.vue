<template>
  <header class="dashboard-header">
    <div class="dashboard-header__main">
      <div class="panel-kicker">Local Identity Demo</div>
      <h1 class="dashboard-header__title">Vault Identity Insights</h1>
      <p class="dashboard-header__subtitle">
        Distinguish GitLab identities accessing Vault and turn audit logs into
        explainable access patterns.
      </p>
    </div>

    <div class="dashboard-header__meta panel">
      <div class="dashboard-header__meta-grid">
        <div class="dashboard-header__meta-item">
          <span class="dashboard-header__meta-label">Source</span>
          <span class="dashboard-header__meta-value mono">
            {{ source || "vault_identity.json" }}
          </span>
        </div>

        <div class="dashboard-header__meta-item">
          <span class="dashboard-header__meta-label">Generated</span>
          <span class="dashboard-header__meta-value">
            {{ generated || "—" }}
          </span>
        </div>
      </div>

      <div v-if="filterPills.length" class="dashboard-header__pills">
        <span v-for="pill in filterPills" :key="pill" class="pill filter-pill">
          <span class="pill-dot" />
          {{ pill }}
        </span>
      </div>

      <button class="export-button" @click="$emit('export')">
        <span>Export Report</span>
        <span class="mono">.md</span>
      </button>
    </div>
  </header>
</template>

<script setup lang="ts">
import { computed } from "vue"

const props = defineProps<{
  generated?: string
  source?: string
  filters?: Record<string, unknown> | null
}>()

defineEmits<{
  (e: "export"): void
}>()

const filterPills = computed(() => {
  if (!props.filters) {
    return []
  }

  const entries = Object.entries(props.filters).filter(([, value]) => {
    if (typeof value === "boolean") {
      return value
    }
    return value !== "" && value !== null && value !== undefined
  })

  return entries.map(([key, value]) => {
    if (typeof value === "boolean") {
      return key.replaceAll("_", " ")
    }
    return `${key.replaceAll("_", " ")}: ${String(value)}`
  })
})
</script>

<style scoped>
.dashboard-header {
  display: grid;
  grid-template-columns: 1.8fr minmax(320px, 430px);
  gap: 24px;
  align-items: stretch;
}

.dashboard-header__main {
  padding: 8px 0 0;
}

.dashboard-header__title {
  margin: 10px 0 0;
  font-size: clamp(2.75rem, 4.6vw, 4.8rem);
  line-height: 0.95;
  letter-spacing: -0.055em;
  font-weight: 800;
  color: var(--text-primary);
}

.dashboard-header__subtitle {
  margin: 20px 0 0;
  max-width: 800px;
  font-size: 18px;
  line-height: 1.6;
  color: var(--text-secondary);
}

.dashboard-header__meta {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: 18px;
  padding: 20px;
  min-height: 196px;
}

.dashboard-header__meta-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 14px;
}

.dashboard-header__meta-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.dashboard-header__meta-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--text-muted);
}

.dashboard-header__meta-value {
  font-size: 15px;
  color: var(--text-primary);
}

.dashboard-header__pills {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

@media (max-width: 1080px) {
  .dashboard-header {
    grid-template-columns: 1fr;
  }

  .dashboard-header__meta {
    min-height: auto;
  }
}

@media (max-width: 768px) {
  .dashboard-header__subtitle {
    font-size: 16px;
  }
}
</style>
