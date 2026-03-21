<template>
  <CollapsiblePanel
    title="Top Consumers"
    kicker="Usage Signals"
    subtitle="The identities and paths that appear most often in the current view."
    :preview="previewText"
    storage-key="vault-insights-top-consumers"
  >
    <div class="top-consumers">

      <div class="top-consumers__grid">
        <div class="top-consumers__card">
          <div class="top-consumers__card-title">Top Individuals</div>

          <div v-if="topUsers.length" class="top-consumers__list">
            <div
              v-for="item in topUsers"
              :key="item.user_login"
              class="top-consumers__item card-lift"
            >
              <div class="top-consumers__content">
                <div class="top-consumers__name">{{ item.user_login }}</div>
                <div class="top-consumers__meta">{{ item.user_email }}</div>
                <div class="metric-bar top-consumers__bar">
                  <span :style="{ width: `${userBarWidth(item.count)}%` }" />
                </div>
              </div>
              <div class="top-consumers__count">{{ item.count }}</div>
            </div>
          </div>

          <div v-else class="empty-state">No identity activity available.</div>
        </div>

        <div class="top-consumers__card">
          <div class="top-consumers__card-title">Top Paths</div>

          <div v-if="topPaths.length" class="top-consumers__list">
            <div
              v-for="item in topPaths"
              :key="item.path"
              class="top-consumers__item card-lift"
            >
              <div class="top-consumers__content">
                <div class="top-consumers__path mono">
                  <span class="path-prefix">{{ splitPath(item.path).prefix }}</span>
                  <span class="path-leaf">{{ splitPath(item.path).leaf }}</span>
                </div>
                <div class="metric-bar top-consumers__bar">
                  <span :style="{ width: `${pathBarWidth(item.count)}%` }" />
                </div>
              </div>
              <div class="top-consumers__count">{{ item.count }}</div>
            </div>
          </div>

          <div v-else class="empty-state">No secret paths available.</div>
        </div>
      </div>
    </div>
  </CollapsiblePanel>
</template>

<script setup lang="ts">
import { computed } from "vue"
import CollapsiblePanel from "./CollapsiblePanel.vue"
import type { HumanIdentity, TimelineEvent } from "../types/vault"

const props = defineProps<{
  humans: HumanIdentity[]
  timeline: TimelineEvent[]
}>()

const topUsers = computed(() => {
  return [...props.humans].sort((a, b) => b.count - a.count).slice(0, 5)
})

const topPaths = computed(() => {
  const counts = new Map<string, number>()

  for (const event of props.timeline) {
    if (!event.path) continue
    counts.set(event.path, (counts.get(event.path) ?? 0) + 1)
  }

  return [...counts.entries()]
    .map(([path, count]) => ({ path, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5)
})

const maxUserCount = computed(() => Math.max(...topUsers.value.map((x) => x.count), 1))
const maxPathCount = computed(() => Math.max(...topPaths.value.map((x) => x.count), 1))
const previewText = computed(() => {
  const topUser = topUsers.value[0]
  const topPath = topPaths.value[0]
  const parts = [`${topUsers.value.length} identities`]

  if (topUser) {
    parts.push(`lead: ${topUser.user_login} (${topUser.count})`)
  }

  if (topPath) {
    parts.push(`dominant path: ${splitPath(topPath.path).leaf}`)
  } else {
    parts.push("dominant path: none")
  }

  return parts.join(" • ")
})

function userBarWidth(count: number): number {
  return (count / maxUserCount.value) * 100
}

function pathBarWidth(count: number): number {
  return (count / maxPathCount.value) * 100
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
.top-consumers {
  padding: 24px;
}

.top-consumers__grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 18px;
}

.top-consumers__card {
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.015);
  padding: 18px;
}

.top-consumers__card-title {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--text-muted);
  margin-bottom: 14px;
}

.top-consumers__list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.top-consumers__item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  min-height: 56px;
  padding: 12px 14px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.018);
  transition: background-color 0.16s ease;
}

.top-consumers__item:hover {
  background: rgba(245, 184, 65, 0.04);
}

.top-consumers__content {
  flex: 1;
  min-width: 0;
}

.top-consumers__name,
.top-consumers__path {
  color: var(--text-primary);
  font-size: 14px;
}

.top-consumers__meta {
  color: var(--text-secondary);
  font-size: 12px;
  margin-top: 2px;
}

.top-consumers__count {
  color: #f8d37c;
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -0.03em;
}

.top-consumers__bar {
  margin-top: 10px;
}

@media (max-width: 980px) {
  .top-consumers__grid {
    grid-template-columns: 1fr;
  }
}
</style>
