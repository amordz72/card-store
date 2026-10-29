<template>
  <!-- One menu entry, several pages (owner 2026-10-29): «المراقبة» and «الإدارة» move between their pages here.
       Each tab keeps its own link, so the bell and old links still open the right one. -->
  <div class="card q-pa-none section-tabs">
    <q-tabs dense no-caps inline-label outside-arrows mobile-arrows active-color="primary" indicator-color="primary" align="justify">
      <q-route-tab v-for="t in tabs" :key="t.to" :to="t.to" exact :label="t.label" :icon="t.icon" />
    </q-tabs>
    <div v-if="links.length" class="row justify-end q-px-sm q-pb-xs q-gutter-sm">
      <a v-for="l in links" :key="l.href" :href="l.href" target="_blank" rel="noopener" class="small">{{ l.label }}</a>
    </div>
  </div>
</template>

<script setup>
defineProps({
  tabs: { type: Array, required: true },
  links: { type: Array, default: () => [] }
})
</script>

<style scoped>
.section-tabs { margin-bottom: 8px; }
</style>
