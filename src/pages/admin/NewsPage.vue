<template>
  <!-- «ما الجديد» (owner 2026-10-31): every update in short lines, newest first; what is new since the last visit is marked -->
  <q-page class="page">
    <div v-for="e in CHANGELOG" :key="e.id" class="card column q-gutter-xs">
      <div class="row items-center no-wrap q-gutter-sm">
        <div class="col text-weight-bold">{{ e.title }}</div>
        <q-badge v-if="isNew(e)" color="purple-6" label="جديد" />
        <span class="small muted">{{ e.date }}</span>
      </div>
      <div v-for="(it, i) in e.items" :key="i" class="news-line row no-wrap items-start q-gutter-xs">
        <span class="dot">•</span>
        <span class="col">
          <router-link v-if="it.to" :to="it.to" class="news-link">{{ it.text }}</router-link>
          <span v-else>{{ it.text }}</span>
          <span v-if="it.pr" class="tiny muted"> · {{ it.pr }}</span>
        </span>
      </div>
    </div>
  </q-page>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { CHANGELOG } from 'src/data/changelog'
import { newsSeen, markNewsSeen } from 'src/composables/useNews'

// What was new when the page opened stays marked while it is open
const seenAtOpen = ref(newsSeen())
const isNew = (e) => !seenAtOpen.value || e.id > seenAtOpen.value
onMounted(() => markNewsSeen())
</script>

<style scoped>
.news-line { font-size: 14px; }
.dot { color: var(--q-primary); font-weight: 800; }
.news-link { color: inherit; text-decoration: none; border-bottom: 1px dashed var(--q-primary); }
.tiny { font-size: 11px; }
</style>
