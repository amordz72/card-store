<template>
  <!-- One menu entry, several pages (owner 2026-10-29): «المراقبة» and «الإدارة» move between their pages here.
       Each tab keeps its own link, so the bell and old links still open the right one. Buttons that wrap to a
       second line (owner 2026-10-29: no swiping), so a fourth page never widens the screen. -->
  <div class="card section-tabs">
    <div class="tabs-row">
      <q-btn v-for="t in tabs" :key="t.to" :to="t.to" dense no-caps rounded size="sm" :icon="t.icon" :label="t.label"
        :unelevated="isOn(t)" :outline="!isOn(t)" :color="isOn(t) ? 'primary' : 'grey-7'" />
    </div>
    <div v-if="links.length" class="tabs-row justify-end q-pt-xs">
      <a v-for="l in links" :key="l.href" :href="l.href" target="_blank" rel="noopener" class="small">{{ l.label }}</a>
    </div>
  </div>
</template>

<script setup>
import { useRoute } from 'vue-router'

defineProps({
  tabs: { type: Array, required: true },
  links: { type: Array, default: () => [] }
})
const route = useRoute()
const isOn = (t) => route.path === t.to
</script>

<style scoped>
.section-tabs { margin-bottom: 8px; padding: 8px; min-width: 0; }
/* gap, not q-gutter (its negative margins pushed the last button 1–20px past the screen, owner N13) */
.tabs-row { display: flex; flex-wrap: wrap; gap: 4px 6px; min-width: 0; }
</style>
