<template>
  <!-- «المراقبة» on the owner's home (owner 2026-11-01): opens and folds, remembered on this device; the red and purple
       lines live inside it now. «لوحة المراقبة» is the full screen. -->
  <div class="watch card q-pa-none">
    <button type="button" class="watch-head" @click="toggle">
      <span class="dot" :class="w.problems.value.some((p) => p.level === 'down') || bell.monitorBar.value?.level === 'down' ? 'off' : w.problems.value.length ? 'warn' : 'on'"></span>
      <span class="col text-weight-bold">المراقبة</span>
      <span class="small" :class="w.problems.value.length ? 'text-negative' : 'text-positive'">
        {{ w.problems.value.length ? w.problems.value.length + (w.problems.value.length === 1 ? ' مشكلة' : ' مشاكل') : 'كل شيء يعمل' }}</span>
      <q-icon :name="open ? 'expand_less' : 'expand_more'" size="20px" />
    </button>
    <div v-if="open" class="body">
      <div v-if="w.speed.value?.level" class="line" :class="w.speed.value.level === 'server' ? 'bg-deep-orange-8' : 'bg-blue-grey-7'">
        {{ w.speed.value.level === 'server' ? '🐢 الخادم بطيء الآن' : '📶 الإنترنت عندك بطيء الآن' }}
        ({{ w.speed.value.db === Infinity ? 'لا رد' : (w.speed.value.db / 1000).toFixed(1) + ' ث' }})</div>
      <div class="kpis">
        <router-link class="kpi" to="/watch">💻 {{ w.counts.value.pcOn }}/{{ w.counts.value.pcAll }} متصل</router-link>
        <router-link class="kpi" to="/watch">📶 {{ w.counts.value.simReady }}/{{ w.counts.value.simAll }} جاهزة</router-link>
        <router-link class="kpi" :class="{ bad: w.counts.value.lowBal }" to="/watch">💰 {{ w.counts.value.lowBal }} تحت الحد</router-link>
        <router-link class="kpi" :class="{ bad: w.counts.value.lowStock }" to="/stock?tab=low">🃏 {{ w.counts.value.lowStock }} تنفد</router-link>
      </div>
      <router-link v-if="w.counts.value.byType.length" to="/watch" class="bytype">
        <span v-for="x in w.counts.value.byType" :key="x.t" :class="{ 'text-negative': x.ready < x.all }">{{ x.name }} {{ x.ready }}/{{ x.all }}<template v-if="x.low"> · 💰{{ x.low }}</template></span>
      </router-link>
      <router-link v-if="bell.monitorBar.value" to="/flexy/monitor?tab=now" class="line" :class="bell.monitorBar.value.level === 'down' ? 'bg-negative' : 'bg-orange-9'">⚠ {{ bell.monitorBar.value.text }}</router-link>
      <div v-for="p in w.problems.value.slice(0, 6)" :key="p.key" class="prob row items-center no-wrap">
        <router-link :to="p.to" class="col ellipsis" :class="p.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ p.text }}</router-link>
        <q-btn flat dense no-caps size="sm" color="grey-7" label="أخفِ" @click="w.hide(p.key, 60)">
          <q-menu auto-close><q-list dense>
            <q-item clickable @click="w.hide(p.key, 60)"><q-item-section>ساعة</q-item-section></q-item>
            <q-item clickable @click="w.hide(p.key, 240)"><q-item-section>4 ساعات</q-item-section></q-item>
            <q-item clickable @click="w.hide(p.key, 1440)"><q-item-section>حتى الغد</q-item-section></q-item>
          </q-list></q-menu>
        </q-btn>
      </div>
      <router-link v-if="newsCount" to="/news" class="line bg-purple-7">🆕 {{ newsCount }} {{ newsCount === 1 ? 'جديد' : 'جديدة' }} في البرنامج</router-link>
      <div class="row q-gutter-xs q-mt-xs">
        <q-btn unelevated dense no-caps color="primary" icon="monitor_heart" label="لوحة المراقبة" to="/watch" class="col" />
        <q-btn outline dense no-caps color="primary" icon="battery_charging_full" label="تغذية الشرائح" to="/watch#feed" class="col" />
        <q-btn outline dense no-caps color="primary" icon="inventory_2" label="دفتر المخزون" to="/stock?tab=ledger" class="col" />
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { useWatch } from 'src/composables/useWatch'
import { useBell } from 'src/composables/useBell'
import { unseenNews, newsSeenRef } from 'src/composables/useNews'

const KEY = 'watch.card.open'
const open = ref((() => { try { return localStorage.getItem(KEY) !== '0' } catch { return true } })())
function toggle () {
  open.value = !open.value
  try { localStorage.setItem(KEY, open.value ? '1' : '0') } catch { /* private mode */ }
}
const w = useWatch(60000)
const bell = useBell()
const newsCount = computed(() => { void newsSeenRef.value; return unseenNews() })
</script>

<style scoped>
.watch { contain: inline-size; min-width: 0; max-width: 100%; overflow: hidden; }
.body { display: flex; flex-direction: column; flex-wrap: nowrap; gap: 4px; padding: 8px; min-width: 0; }
.body > * { min-width: 0; max-width: 100%; }
.kpis { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; }
.watch-head { width: 100%; min-width: 0; display: flex; align-items: center; gap: 8px; padding: 10px 12px; border: 0; background: transparent; font: inherit; color: inherit; cursor: pointer; text-align: right; }
.dot { display: inline-block; width: 12px; height: 12px; border-radius: 50%; }
.dot.on { background: #2FAE1E; box-shadow: 0 0 6px #2FAE1E; }
.dot.warn { background: #F59E0B; }
.dot.off { background: #D32F2F; }
.kpi { min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-align: center; font-size: 12px; padding: 4px 8px; border-radius: 12px; background: #EEF2FF; color: #3730A3; text-decoration: none; }
.kpi.bad { background: #FEE2E2; color: #B91C1C; }
.bytype { display: flex; flex-wrap: wrap; gap: 4px 10px; font-size: 12px; color: #374151; text-decoration: none; margin-top: 6px; }
.line { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #fff; text-decoration: none; border-radius: 8px; padding: 5px 10px; font-size: 13px; }
.prob { min-width: 0; font-size: 13px; border-top: 1px solid #EEF0F4; padding-top: 2px; }
.prob a { text-decoration: none; }
</style>
