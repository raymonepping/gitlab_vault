<template>
  <CollapsiblePanel
    title="Local Time Filter"
    kicker="Filter Window"
    subtitle="Filter activity by time window without reprocessing logs."
    :preview="previewText"
    storage-key="vault-insights-time-filter"
  >
    <div class="time-filter-bar">
      <div class="time-filter-bar__left">
        <div class="time-filter-bar__presets">
          <button
            v-for="preset in presets"
            :key="preset.label"
            class="time-filter-bar__preset"
            @click="applyPreset(preset.hours)"
          >
            {{ preset.label }}
          </button>
        </div>
      </div>

      <div class="time-filter-bar__controls">
        <input v-model="sinceLocal" type="datetime-local" class="time-filter-bar__input" />
        <input v-model="untilLocal" type="datetime-local" class="time-filter-bar__input" />

        <button class="time-filter-bar__button" @click="apply">
          Apply
        </button>

        <button class="time-filter-bar__button time-filter-bar__button--ghost" @click="reset">
          Reset
        </button>
      </div>
    </div>
  </CollapsiblePanel>
</template>

<script setup lang="ts">
import { computed, ref } from "vue"
import CollapsiblePanel from "./CollapsiblePanel.vue"

const emit = defineEmits<{
  (e: "apply", payload: { since: string; until: string }): void
  (e: "reset"): void
}>()

const presets = [
  { label: "24h", hours: 24 },
  { label: "7d", hours: 24 * 7 },
  { label: "30d", hours: 24 * 30 },
] as const

const sinceLocal = ref("")
const untilLocal = ref("")
const previewText = computed(() => {
  if (sinceLocal.value || untilLocal.value) {
    return `Current window ${sinceLocal.value || "start open"} → ${untilLocal.value || "end open"}`
  }

  return "Preset windows: 24h, 7d, 30d, or choose an exact from/until range"
})

function toLocalInputValue(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  const hours = String(date.getHours()).padStart(2, "0")
  const minutes = String(date.getMinutes()).padStart(2, "0")
  return `${year}-${month}-${day}T${hours}:${minutes}`
}

function applyPreset(hours: number): void {
  const now = new Date()
  const since = new Date(now.getTime() - hours * 60 * 60 * 1000)
  sinceLocal.value = toLocalInputValue(since)
  untilLocal.value = toLocalInputValue(now)
  apply()
}

function apply(): void {
  emit("apply", {
    since: sinceLocal.value,
    until: untilLocal.value,
  })
}

function reset(): void {
  sinceLocal.value = ""
  untilLocal.value = ""
  emit("reset")
}
</script>

<style scoped>
.time-filter-bar {
  display: flex;
  justify-content: space-between;
  align-items: end;
  gap: 18px;
  padding: 20px 24px;
}

.time-filter-bar__subtitle {
  color: var(--text-secondary);
  font-size: 14px;
  margin-top: 6px;
}

.time-filter-bar__presets {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  margin-top: 14px;
}

.time-filter-bar__preset {
  min-height: 32px;
  border-radius: 999px;
  border: 1px solid var(--border-default);
  background: rgba(255, 255, 255, 0.02);
  color: var(--text-secondary);
  padding: 0 12px;
  cursor: pointer;
}

.time-filter-bar__controls {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.time-filter-bar__input,
.time-filter-bar__button {
  min-height: 42px;
  border-radius: 12px;
  border: 1px solid var(--border-default);
  background: rgba(255, 255, 255, 0.03);
  color: var(--text-primary);
  padding: 0 12px;
}

.time-filter-bar__button {
  cursor: pointer;
}

.time-filter-bar__button--ghost {
  background: rgba(255, 255, 255, 0.015);
}

@media (max-width: 980px) {
  .time-filter-bar {
    flex-direction: column;
    align-items: stretch;
  }
}
</style>
