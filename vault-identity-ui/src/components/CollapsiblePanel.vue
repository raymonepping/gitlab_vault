<template>
  <section
    class="panel section-spacing collapsible-panel card-lift"
    :class="{
      'collapsible-panel--open': isOpen,
      'collapsible-panel--hovered': isHovered,
    }"
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
  >
    <button
      class="collapsible-panel__header"
      type="button"
      @click="toggle"
      :aria-expanded="isOpen"
    >
      <div class="collapsible-panel__header-main">
        <div class="panel-kicker">{{ kicker }}</div>
        <div class="collapsible-panel__title-row">
          <div class="panel-title collapsible-panel__title">{{ title }}</div>
          <span class="collapsible-panel__chevron" :class="{ 'is-open': isOpen }" aria-hidden="true">
            ▾
          </span>
        </div>
        <div class="panel-subtitle">{{ subtitle }}</div>

        <div class="collapsible-panel__preview" :class="{ 'collapsible-panel__preview--visible': !isOpen && previewItems.length > 0 }">
          <div class="collapsible-preview">
            <span v-for="item in previewItems" :key="item">{{ item }}</span>
          </div>
        </div>
      </div>
    </button>

    <div
      ref="contentOuter"
      class="collapsible-panel__content"
      :style="{ maxHeight: maxHeight, opacity: isOpen ? '1' : '0' }"
      :aria-hidden="!isOpen"
    >
      <div ref="contentInner" class="collapsible-panel__body" :class="{ 'collapsible-content': isOpen }">
        <slot />
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue"

const props = withDefaults(
  defineProps<{
    title: string
    subtitle?: string
    kicker?: string
    preview?: string
    defaultOpen?: boolean
    storageKey?: string
  }>(),
  {
    subtitle: "",
    kicker: "Section",
    preview: "",
    defaultOpen: false,
    storageKey: "",
  },
)

const isOpen = ref(props.defaultOpen)
const isHovered = ref(false)
const maxHeight = ref(props.defaultOpen ? "none" : "0px")
const contentOuter = ref<HTMLDivElement | null>(null)
const contentInner = ref<HTMLDivElement | null>(null)
let resizeObserver: ResizeObserver | null = null
const previewItems = props.preview
  .split("•")
  .map((item) => item.trim())
  .filter(Boolean)

onMounted(() => {
  if (props.storageKey) {
    const stored = localStorage.getItem(props.storageKey)
    if (stored !== null) {
      isOpen.value = stored === "true"
    } else {
      isOpen.value = props.defaultOpen
    }
  }

  syncHeight(false)

  if (typeof ResizeObserver !== "undefined" && contentInner.value) {
    resizeObserver = new ResizeObserver(() => {
      if (isOpen.value) {
        syncHeight(false)
      }
    })
    resizeObserver.observe(contentInner.value)
  }
})

watch(isOpen, (value) => {
  if (props.storageKey) {
    localStorage.setItem(props.storageKey, String(value))
  }

  syncHeight(true)
})

function toggle(): void {
  isOpen.value = !isOpen.value
}

function syncHeight(animated: boolean): void {
  nextTick(() => {
    const outer = contentOuter.value
    const inner = contentInner.value
    if (!outer || !inner) return

    const measured = `${inner.scrollHeight}px`

    if (isOpen.value) {
      maxHeight.value = measured
      window.setTimeout(() => {
        if (isOpen.value) {
          maxHeight.value = "none"
        }
      }, animated ? 220 : 0)
      return
    }

    if (animated) {
      maxHeight.value = measured
      requestAnimationFrame(() => {
        maxHeight.value = "0px"
      })
    } else {
      maxHeight.value = "0px"
    }
  })
}

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
})
</script>

<style scoped>
.collapsible-panel {
  overflow: hidden;
  position: relative;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    background-color 0.2s ease,
    transform 0.2s ease;
}

.collapsible-panel::before {
  content: "";
  position: absolute;
  inset: 0 auto 0 0;
  width: 2px;
  background: linear-gradient(
    180deg,
    rgba(245, 184, 65, 0.85),
    rgba(249, 115, 22, 0.6)
  );
  opacity: 0;
  transition: opacity 0.2s ease;
  pointer-events: none;
}

.collapsible-panel::after {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  transition: opacity 0.2s ease;
  opacity: 0;
}

.collapsible-panel__header {
  width: 100%;
  background: transparent;
  border: 0;
  color: inherit;
  text-align: left;
  padding: 24px;
  cursor: pointer;
}

.collapsible-panel__header:hover .collapsible-panel__chevron {
  opacity: 1;
}

.collapsible-panel__title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.collapsible-panel__title {
  margin-right: auto;
}

.collapsible-panel__preview {
  margin-top: 14px;
  color: var(--text-secondary);
  font-size: 14px;
  line-height: 1.5;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  max-height: 0;
  opacity: 0;
  overflow: hidden;
  transition:
    max-height 0.2s ease,
    opacity 0.2s ease;
}

.collapsible-panel__preview--visible {
  max-height: 72px;
  opacity: 1;
}

.collapsible-preview {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  opacity: 0.85;
}

.collapsible-preview span {
  padding: 2px 8px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.04);
}

.collapsible-panel__chevron {
  color: #f8d37c;
  font-size: 18px;
  line-height: 1;
  transform-origin: center;
  transition:
    transform 0.2s ease,
    opacity 0.2s ease,
    color 0.2s ease;
  opacity: 0.72;
}

.collapsible-panel:hover .collapsible-panel__chevron {
  color: #facc15;
  transform: translateY(1px);
}

.collapsible-panel__chevron.is-open {
  transform: rotate(180deg);
}

.collapsible-panel:hover .collapsible-panel__chevron.is-open {
  transform: rotate(180deg) translateY(-1px);
}

.collapsible-panel__content {
  max-height: 0;
  overflow: hidden;
  transition:
    max-height 0.2s ease,
    opacity 0.2s ease;
  will-change: max-height, opacity;
}

.collapsible-panel__body {
  padding: 0 24px 24px;
}

.collapsible-content {
  animation: fadeSlide 0.2s ease;
}

.collapsible-panel--hovered,
.collapsible-panel--open {
  border-color: rgba(245, 184, 65, 0.2);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.03),
    0 0 0 1px rgba(245, 184, 65, 0.08),
    0 18px 45px rgba(245, 184, 65, 0.06);
}

.collapsible-panel--hovered::before,
.collapsible-panel--open::before {
  opacity: 1;
}

.collapsible-panel:hover::after {
  opacity: 1;
  box-shadow:
    inset 0 0 0 1px rgba(245, 184, 65, 0.08),
    0 10px 30px rgba(245, 184, 65, 0.06);
}

.collapsible-panel--open {
  background:
    linear-gradient(
      180deg,
      rgba(255, 255, 255, 0.025),
      rgba(255, 255, 255, 0.01)
    ),
    var(--bg-secondary);
}

@keyframes fadeSlide {
  from {
    opacity: 0;
    transform: translateY(-6px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
