<template>
  <section class="summary-grid">
    <article class="summary-card metric-card summary-card--hero glow-gold">
      <div class="summary-card__label">Latest Identity</div>

      <template v-if="latest">
        <div class="summary-card__headline">
          {{ latest.user_login || "Unknown" }}
        </div>
        <div class="summary-card__subline">
          {{ latest.user_email || "No email" }}
        </div>
        <div class="summary-card__context-label">last access:</div>
        <div class="summary-card__meta summary-card__meta--stack">
          <span class="mono summary-card__meta-path">{{ latest.path || "—" }}</span>
          <span>pipeline {{ latest.pipeline_id || "—" }} • job {{ latest.job_id || "—" }}</span>
        </div>
      </template>

      <template v-else>
        <div class="summary-card__headline">No activity</div>
        <div class="summary-card__subline">No latest identity available</div>
      </template>
    </article>

    <article class="summary-card">
      <div class="summary-card__label">Unique Individuals</div>
      <div class="summary-card__value">{{ uniqueHumans }}</div>
      <div class="summary-card__foot">Distinct human-linked fingerprints</div>
    </article>

    <article class="summary-card metric-card">
      <div class="summary-card__label">Projects</div>
      <div class="summary-card__value">{{ uniqueProjects }}</div>
      <div class="summary-card__foot">Workload scope in this dataset</div>
    </article>

    <article class="summary-card metric-card glow-orange">
      <div class="summary-card__label">Secret Reads</div>
      <div class="summary-card__value">{{ secretReads }}</div>
      <div class="summary-card__foot">Read operations against secret paths</div>
    </article>

    <article class="summary-card metric-card">
      <div class="summary-card__label">Top Path</div>
      <div class="summary-card__headline summary-card__headline--small summary-card__headline--path mono">
        {{ topPath || "—" }}
      </div>
      <div class="summary-card__foot">
        {{ topPathCount }} matching event<span v-if="topPathCount !== 1">s</span>
      </div>
    </article>

    <article class="summary-card metric-card">
      <div class="summary-card__label">Last Activity</div>
      <div class="summary-card__headline summary-card__headline--small">
        {{ lastActivityDisplay }}
      </div>
      <div class="summary-card__foot">Most recent secret access event</div>
    </article>
  </section>
</template>

<script setup lang="ts">
import { computed } from "vue"
import type { SummaryMetrics, TimelineEvent } from "../types/vault"

const props = defineProps<{
  summary?: SummaryMetrics | null
  timeline?: TimelineEvent[] | null
}>()

const latest = computed(() => {
  const items = props.timeline ?? []
  if (!items.length) {
    return null
  }
  return [...items].sort((a, b) => (a.time || "").localeCompare(b.time || "")).at(-1) ?? null
})

const uniqueHumans = computed(() => Number(props.summary?.unique_humans ?? 0))
const uniqueProjects = computed(() => Number(props.summary?.unique_workloads ?? 0))
const secretReads = computed(() => Number(props.summary?.secret_read_events ?? 0))

const pathStats = computed(() => {
  const counts = new Map<string, number>()
  for (const item of props.timeline ?? []) {
    if (!item.path) {
      continue
    }
    counts.set(item.path, (counts.get(item.path) ?? 0) + 1)
  }

  const sorted = [...counts.entries()].sort((a, b) => b[1] - a[1])
  return sorted[0] ?? null
})

const topPath = computed(() => pathStats.value?.[0] ?? "")
const topPathCount = computed(() => pathStats.value?.[1] ?? 0)

const lastActivityDisplay = computed(() => {
  const value = latest.value?.time
  if (!value) {
    return "—"
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return value
  }

  return date.toLocaleString()
})
</script>

<style scoped>
.summary-grid {
  display: grid;
  grid-template-columns: 1.3fr repeat(5, 1fr);
  gap: 18px;
}

.summary-card {
  position: relative;
  min-height: 168px;
  padding: 20px;
  border-radius: 22px;
  border: 1px solid var(--border-default);
  background:
    linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.02),
      rgba(255, 255, 255, 0.01)
    ),
    var(--bg-secondary);
  overflow: hidden;
  transition:
    transform 0.16s ease,
    border-color 0.16s ease,
    box-shadow 0.16s ease;
}

.summary-card::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    radial-gradient(
      circle at top right,
      rgba(255, 255, 255, 0.035),
      transparent 35%
    );
  pointer-events: none;
}

.summary-card:hover {
  transform: translateY(-2px);
  border-color: var(--border-strong);
}

.metric-card:hover {
  background:
    linear-gradient(
      180deg,
      rgba(245, 184, 65, 0.08),
      rgba(245, 184, 65, 0.02)
    );
  border-color: rgba(245, 184, 65, 0.25);
}

.summary-card--hero {
  background:
    radial-gradient(
      circle at top left,
      rgba(245, 184, 65, 0.12),
      transparent 32%
    ),
    linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.03),
      rgba(255, 255, 255, 0.01)
    ),
    var(--bg-secondary);
}

.summary-card__label {
  position: relative;
  z-index: 1;
  font-size: 11px;
  line-height: 1;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.summary-card__value {
  position: relative;
  z-index: 1;
  margin-top: 22px;
  font-size: 42px;
  line-height: 1;
  letter-spacing: -0.05em;
  font-weight: 750;
  color: var(--text-primary);
}

.summary-card__headline {
  position: relative;
  z-index: 1;
  margin-top: 26px;
  font-size: 30px;
  line-height: 1.02;
  letter-spacing: -0.045em;
  font-weight: 760;
  color: var(--text-primary);
}

.summary-card__headline--small {
  font-size: 20px;
  line-height: 1.25;
  letter-spacing: -0.03em;
}

.summary-card__headline--path {
  font-size: 16px;
  line-height: 1.35;
  word-break: break-word;
}

.summary-card__subline {
  position: relative;
  z-index: 1;
  margin-top: 8px;
  font-size: 14px;
  color: var(--text-secondary);
}

.summary-card__context-label {
  position: relative;
  z-index: 1;
  margin-top: 18px;
  font-size: 11px;
  line-height: 1;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.summary-card__meta {
  position: relative;
  z-index: 1;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 18px;
  font-size: 12px;
  color: var(--text-secondary);
}

.summary-card__meta--stack {
  flex-direction: column;
  align-items: flex-start;
  gap: 6px;
  margin-top: 10px;
}

.summary-card__meta-path {
  color: #f8d37c;
}

.summary-card__divider {
  color: var(--text-muted);
}

.summary-card__foot {
  position: absolute;
  left: 20px;
  right: 20px;
  bottom: 18px;
  z-index: 1;
  font-size: 12px;
  color: var(--text-secondary);
}

@media (max-width: 1380px) {
  .summary-grid {
    grid-template-columns: repeat(3, 1fr);
  }
}

@media (max-width: 820px) {
  .summary-grid {
    grid-template-columns: 1fr;
  }
}
</style>
