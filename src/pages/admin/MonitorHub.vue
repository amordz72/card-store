<template>
  <!-- «المراقبة والإحصائيات» (owner 2026-10-30: «متقاربان ويخلطان؛ تبويب لكل معنى، والمهمات مجتمعة»):
       three tabs, each with the count of what waits in it. A tab asks the server only once opened (weak internet,
       owner 2026-10-30), then stays, so «نسخ الشاشة» copies every tab opened.
       ?tab=now|judge|db: the bar and the menu open the right one. -->
  <q-page class="page">
    <div class="hub-head column gap-sm">
      <SectionTabs :tabs="MONITOR_TABS" />
      <q-tabs v-model="tab" dense no-caps align="justify" active-color="primary" indicator-color="primary" class="text-grey-8">
        <q-tab v-for="t in TABS" :key="t.id" :name="t.id" :label="t.label">
          <q-badge v-if="t.count()" floating :color="t.color" :label="t.count()" />
        </q-tab>
      </q-tabs>
    </div>
    <div v-if="seen.now" v-show="tab === 'now'" class="hub-panel" data-title="الآن"><MonitorSection :active="tab === 'now'" /></div>
    <div v-if="seen.judge" v-show="tab === 'judge'" class="hub-panel column gap-sm" data-title="حكمك والفشل">
      <ReviewCard />
      <RejudgeCard />
      <FailuresCard />
    </div>
    <div v-if="seen.db" v-show="tab === 'db'" class="hub-panel" data-title="القاعدة وSQL"><StatsSection /></div>
  </q-page>
</template>

<script setup>
import { computed, reactive, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import SectionTabs from 'src/components/SectionTabs.vue'
import ReviewCard from 'src/components/ReviewCard.vue'
import FailuresCard from 'src/components/FailuresCard.vue'
import RejudgeCard from 'src/components/RejudgeCard.vue'
import MonitorSection from './MonitorSection.vue'
import StatsSection from './StatsSection.vue'
import { MONITOR_TABS } from 'src/api/sections'
import { useBell } from 'src/composables/useBell'

const { monitorAlerts, reviewWaiting, failuresOpen, automixAlert, sqlPending } = useBell()
const TABS = [
  { id: 'now', label: 'الآن', color: 'negative', count: () => monitorAlerts.value || 0 },
  { id: 'judge', label: 'حكمك والفشل', color: 'deep-orange', count: () => (reviewWaiting.value || 0) + (failuresOpen.value || 0) + (automixAlert.value ? 1 : 0) },
  { id: 'db', label: 'القاعدة وSQL', color: 'indigo-8', count: () => sqlPending.value || 0 }
]
const route = useRoute()
const router = useRouter()
const tab = computed({
  get: () => (TABS.some((t) => t.id === route.query.tab) ? route.query.tab : 'now'),
  set: (v) => router.replace({ query: { ...route.query, tab: v } })
})
const seen = reactive({})
watch(tab, (t) => { seen[t] = true }, { immediate: true })
</script>
