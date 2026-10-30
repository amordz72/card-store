<template>
  <!-- Standing bars, one per item (owner 2026-10-30: «مستطيلات واقفة مثل Word»): read at a glance, tap a bar for its
       number. One series, one hue; a bar over the limit turns red and says so in the tooltip (never color alone). -->
  <div class="bars-wrap" dir="ltr">
    <div class="plot" :style="{ height: height + 'px' }">
      <div v-if="limit" class="limit" :style="{ bottom: pct(limit) + '%' }"><span>{{ limitLabel }}</span></div>
      <button v-for="(it, i) in items" :key="i" type="button" class="col-bar" :aria-label="it.label + ': ' + it.text"
        @click="picked = picked === i ? null : i" @mouseenter="picked = i" @mouseleave="picked = null">
        <span class="bar" :class="{ over: limit && it.value > limit, on: picked === i, partial: it.partial }" :style="{ height: pct(it.value) + '%' }" />
        <span v-if="picked === i" class="tip" :class="{ end: i > items.length / 2 }" dir="rtl">
          <b>{{ it.text }}</b> · {{ it.label }}<template v-if="limit && it.value > limit"> · فوق الحد</template>
        </span>
      </button>
    </div>
    <div class="axis">
      <span v-for="(it, i) in items" :key="i" class="tick">{{ i % every === 0 ? it.short : '' }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'

const props = defineProps({
  // [{ value, text (shown), label (in the tooltip), short (under the axis) }]
  items: { type: Array, required: true },
  height: { type: Number, default: 120 },
  limit: { type: Number, default: 0 },
  limitLabel: { type: String, default: 'الحد' }
})
const picked = ref(null)
const max = computed(() => Math.max(1, props.limit || 0, ...props.items.map((x) => x.value || 0)))
const pct = (v) => Math.max(0, Math.min(100, ((v || 0) / max.value) * 100))
// About 6 labels under the axis, whatever the count
const every = computed(() => Math.max(1, Math.ceil(props.items.length / 6)))
</script>

<style scoped>
.bars-wrap { width: 100%; }
.plot { position: relative; display: flex; align-items: flex-end; gap: 2px; border-bottom: 1px solid rgba(0, 0, 0, 0.2); }
.col-bar { flex: 1 1 0; min-width: 0; height: 100%; display: flex; align-items: flex-end; justify-content: center;
  background: none; border: 0; padding: 0; cursor: pointer; position: relative; }
.bar { width: 100%; max-width: 22px; border-radius: 4px 4px 0 0; background: var(--q-primary); opacity: 0.75; min-height: 2px; }
.bar.on { opacity: 1; }
.bar.partial { opacity: 0.35; outline: 1px dashed currentColor; }
.bar.over { background: var(--q-negative); opacity: 0.9; }
.limit { position: absolute; left: 0; right: 0; border-top: 1px dashed rgba(0, 0, 0, 0.35); pointer-events: none; }
.limit span { position: absolute; right: 0; top: -16px; font-size: 10px; color: rgba(0, 0, 0, 0.55); }
.tip { position: absolute; bottom: 100%; left: 0; z-index: 2; white-space: nowrap; font-size: 12px; padding: 3px 8px;
  border-radius: 6px; background: rgba(20, 24, 40, 0.92); color: #fff; margin-bottom: 4px; }
.tip.end { left: auto; right: 0; }
.axis { display: flex; gap: 2px; }
.tick { flex: 1 1 0; min-width: 0; text-align: center; font-size: 10px; color: rgba(0, 0, 0, 0.55); white-space: nowrap; overflow: visible; }
body.body--dark .limit span, body.body--dark .tick { color: rgba(255, 255, 255, 0.6); }
body.body--dark .plot { border-bottom-color: rgba(255, 255, 255, 0.25); }
</style>
