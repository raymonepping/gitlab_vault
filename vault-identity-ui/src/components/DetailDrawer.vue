<template>
  <transition name="drawer-fade">
    <div v-if="open" class="drawer-backdrop" @click="$emit('close')">
      <aside class="drawer-panel" @click.stop>
        <div class="drawer-panel__header">
          <div>
            <div class="panel-kicker">Selected Detail</div>
            <div class="drawer-panel__title">{{ title }}</div>
          </div>

          <button class="drawer-panel__close" @click="$emit('close')">×</button>
        </div>

        <div class="drawer-panel__sections">
          <section
            v-for="section in sections"
            :key="section.title"
            class="drawer-section"
          >
            <div class="drawer-section__title">{{ section.title }}</div>

            <div class="drawer-section__grid">
              <div
                v-for="item in section.items"
                :key="item.label"
                class="drawer-field"
              >
                <div class="drawer-field__label">{{ item.label }}</div>
                <div class="drawer-field__value mono">{{ item.value || "—" }}</div>
              </div>
            </div>
          </section>
        </div>
      </aside>
    </div>
  </transition>
</template>

<script setup lang="ts">
import { computed } from "vue"
import type { HumanIdentity, TimelineEvent, WorkloadIdentity } from "../types/vault"

const props = defineProps<{
  open: boolean
  payload: HumanIdentity | WorkloadIdentity | TimelineEvent | null
}>()

defineEmits<{
  (e: "close"): void
}>()

const payloadRecord = computed<Record<string, unknown> | null>(() => {
  return props.payload ? (props.payload as unknown as Record<string, unknown>) : null
})

function readValue(
  payload: Record<string, unknown>,
  ...keys: string[]
): string {
  for (const key of keys) {
    const value = payload[key]
    if (value !== undefined && value !== null && value !== "") {
      return String(value)
    }
  }

  return ""
}

const title = computed(() => {
  const payload = payloadRecord.value
  if (!payload) return "No selection"

  return (
    readValue(payload, "user_login", "project_path", "path") || "Detail"
  )
})

const sections = computed(() => {
  const p = payloadRecord.value
  if (!p) return []

  return [
    {
      title: "Identity",
      items: [
        { label: "User", value: readValue(p, "user_login") },
        { label: "Email", value: readValue(p, "user_email") },
        { label: "User ID", value: readValue(p, "user_id") },
        { label: "Entity ID", value: readValue(p, "entity_id") },
        { label: "Display", value: readValue(p, "display_name") },
      ],
    },
    {
      title: "GitLab Context",
      items: [
        { label: "Project", value: readValue(p, "project_path") },
        { label: "Namespace", value: readValue(p, "namespace_path") },
        { label: "Pipeline", value: readValue(p, "pipeline_id") },
        { label: "Job", value: readValue(p, "job_id") },
        { label: "Ref", value: readValue(p, "ref") },
      ],
    },
    {
      title: "Vault Context",
      items: [
        { label: "Role", value: readValue(p, "role") },
        { label: "Path", value: readValue(p, "path") },
        { label: "Operation", value: readValue(p, "operation") },
        { label: "First Seen", value: readValue(p, "first_seen", "time") },
        { label: "Last Seen", value: readValue(p, "last_seen", "time") },
      ],
    },
  ]
})
</script>

<style scoped>
.drawer-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(4, 4, 6, 0.62);
  backdrop-filter: blur(8px);
  display: flex;
  justify-content: flex-end;
  z-index: 50;
}

.drawer-panel {
  width: min(460px, 100%);
  height: 100%;
  background:
    linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.03),
      rgba(255, 255, 255, 0.01)
    ),
    #111114;
  border-left: 1px solid rgba(245, 184, 65, 0.18);
  box-shadow: -20px 0 60px rgba(0, 0, 0, 0.35);
  padding: 24px;
  overflow-y: auto;
}

.drawer-panel__header {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: 12px;
  margin-bottom: 20px;
}

.drawer-panel__title {
  margin-top: 8px;
  font-size: 30px;
  line-height: 1.02;
  letter-spacing: -0.04em;
  font-weight: 760;
}

.drawer-panel__close {
  width: 38px;
  height: 38px;
  border-radius: 999px;
  border: 1px solid var(--border-default);
  background: rgba(255, 255, 255, 0.02);
  color: var(--text-primary);
  cursor: pointer;
}

.drawer-panel__sections {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.drawer-section {
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 18px;
  padding: 16px;
  background: rgba(255, 255, 255, 0.015);
}

.drawer-section__title {
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-muted);
  margin-bottom: 14px;
}

.drawer-section__grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 12px;
}

.drawer-field__label {
  font-size: 11px;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.1em;
  margin-bottom: 4px;
}

.drawer-field__value {
  color: var(--text-primary);
  font-size: 14px;
  word-break: break-word;
}

.drawer-fade-enter-active,
.drawer-fade-leave-active {
  transition: opacity 0.18s ease;
}

.drawer-fade-enter-active .drawer-panel,
.drawer-fade-leave-active .drawer-panel {
  transition: transform 0.2s ease;
}

.drawer-fade-enter-from,
.drawer-fade-leave-to {
  opacity: 0;
}

.drawer-fade-enter-from .drawer-panel,
.drawer-fade-leave-to .drawer-panel {
  transform: translateX(24px);
}
</style>
