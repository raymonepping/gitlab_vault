<template>
  <div class="app-shell">
    <div class="app-frame">
      <DashboardHeader
        :generated="generatedDisplay"
        :source="sourceDisplay"
        :filters="filters"
        @export="handleExport"
      />

      <SummaryCards
        class="section-spacing"
        :summary="summaryData"
        :timeline="filteredTimelineEvents"
      />

      <FingerprintTable :timeline="filteredTimelineEvents" />

      <TimeFilterBar
        @apply="applyLocalTimeFilter"
        @reset="resetLocalTimeFilter"
      />

      <TopConsumers
        :humans="filteredHumanIdentities"
        :timeline="filteredTimelineEvents"
      />

      <InsightTabs
        :humans="filteredHumanIdentities"
        :workloads="filteredWorkloadIdentities"
        :timeline="filteredTimelineEvents"
        @select-human="openDrawer"
        @select-workload="openDrawer"
        @select-event="openDrawer"
      />

      <ComparePanel :bundles="filteredBundles" />
    </div>

    <DetailDrawer
      :open="drawerOpen"
      :payload="drawerPayload"
      @close="closeDrawer"
    />
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from "vue"
import { useVaultData } from "./composables/useVaultData"
import DashboardHeader from "./components/DashboardHeader.vue"
import SummaryCards from "./components/SummaryCards.vue"
import FingerprintTable from "./components/FingerprintTable.vue"
import TopConsumers from "./components/TopConsumers.vue"
import InsightTabs from "./components/InsightsTab.vue"
import DetailDrawer from "./components/DetailDrawer.vue"
import ComparePanel from "./components/ComparePanel.vue"
import TimeFilterBar from "./components/TimeFilterBar.vue"
import { exportMarkdown } from "./utils/exportMarkdown"
import type {
  HumanIdentity,
  SummaryMetrics,
  TimelineEvent,
  VaultData,
  WorkloadIdentity,
} from "./types/vault"

const { data } = useVaultData()

const localSince = ref("")
const localUntil = ref("")

const filters = computed(() => (data.value?.filters as Record<string, unknown> | null) ?? null)
const sourceDisplay = computed(() => String(data.value?.source_file ?? "vault_identity.json"))

const generatedDisplay = computed(() => {
  const raw = data.value?.generated_at
  if (!raw) return "—"

  const date = new Date(String(raw))
  if (Number.isNaN(date.getTime())) return String(raw)

  return date.toLocaleString()
})

function inLocalWindow(value: string): boolean {
  if (!value) return true

  const eventTime = new Date(value).getTime()
  if (Number.isNaN(eventTime)) return true

  const since = localSince.value ? new Date(localSince.value).getTime() : null
  const until = localUntil.value ? new Date(localUntil.value).getTime() : null

  if (since !== null && !Number.isNaN(since) && eventTime < since) return false
  if (until !== null && !Number.isNaN(until) && eventTime > until) return false
  return true
}

const filteredTimelineEvents = computed(() =>
  (data.value?.timeline_events ?? []).filter((e) => inLocalWindow(e.time)),
)

const filteredHumanIdentities = computed(() =>
  (data.value?.human_identities ?? []).filter((e) => inLocalWindow(e.last_seen)),
)

const filteredWorkloadIdentities = computed(() =>
  (data.value?.workload_identities ?? []).filter((e) => inLocalWindow(e.last_seen)),
)

const filteredBundles = computed(() =>
  (data.value?.full_identity_bundles ?? []).filter((e) => inLocalWindow(e.last_seen)),
)

const summaryData = computed<SummaryMetrics>(() => ({
  unique_humans: filteredHumanIdentities.value.length,
  unique_workloads: filteredWorkloadIdentities.value.length,
  secret_read_events: filteredTimelineEvents.value.filter(
    (e) => e.operation === "read" && e.path.startsWith("secret/data/"),
  ).length,
}))

const drawerOpen = ref(false)
const drawerPayload = ref<HumanIdentity | WorkloadIdentity | TimelineEvent | null>(null)

function handleExport(): void {
  if (!data.value) return

  const exportData: VaultData = {
    ...data.value,
    human_identities: filteredHumanIdentities.value,
    workload_identities: filteredWorkloadIdentities.value,
    full_identity_bundles: filteredBundles.value,
    timeline_events: filteredTimelineEvents.value,
    unique_humans: filteredHumanIdentities.value.length,
    unique_workloads: filteredWorkloadIdentities.value.length,
    read_events: filteredTimelineEvents.value.filter((e) => e.operation === "read").length,
    secret_read_events: filteredTimelineEvents.value.filter(
      (e) => e.operation === "read" && e.path.startsWith("secret/data/"),
    ).length,
    total_events: filteredTimelineEvents.value.length,
  }

  exportMarkdown(exportData)
}

function openDrawer(payload: HumanIdentity | WorkloadIdentity | TimelineEvent): void {
  drawerPayload.value = payload
  drawerOpen.value = true
}

function closeDrawer(): void {
  drawerOpen.value = false
}

function applyLocalTimeFilter(payload: { since: string; until: string }): void {
  localSince.value = payload.since
  localUntil.value = payload.until
}

function resetLocalTimeFilter(): void {
  localSince.value = ""
  localUntil.value = ""
}
</script>
