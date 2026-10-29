<template>
  <q-page class="page">
    <!-- «المراقبة» (owner 2026-10-29, Flexy Core 0068): what needs the owner now, then the balances.
         One request to Flexy Core; refreshed every 30 seconds while this page is open and visible. -->
    <!-- The three tiles filter what is below (owner 2026-10-29): critical or orange alerts only, or the ready SIMs
         with their details. A second press, or ✕, shows everything again. -->
    <div class="counts">
      <button v-for="t in TILES" :key="t.key" type="button" class="count" :class="[t.key, { picked: filter === t.key, dim: filter && filter !== t.key }]"
        :aria-pressed="filter === t.key" @click="pick(t.key)">
        <q-icon name="filter_alt" size="14px" class="funnel" />
        <div class="n">{{ view?.counts[t.key] ?? '—' }}</div><div class="small">{{ t.label }}</div>
      </button>
    </div>
    <div class="row items-center q-mt-sm">
      <div class="col small muted">آخر تحديث {{ view ? clock(view.checked_at) : '—' }}<template v-if="filter"> · <button type="button" class="link text-primary" @click="filter = null">مفلتر: {{ TILES.find((t) => t.key === filter).label }} ✕</button></template></div>
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
    </div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <template v-if="filter !== 'ok'">
    <div class="section-title q-mt-sm">يحتاجك الآن</div>
    <div v-if="view && !shownAlerts.length" class="card small muted">لا شيء يحتاجك الآن.</div>
    <div v-for="a in shownAlerts" :key="a.key" class="card column q-gutter-xs">
      <div class="row items-center q-gutter-xs">
        <span class="dot" :class="a.level" />
        <span class="small text-weight-bold" :class="a.level === 'down' ? 'text-negative' : 'text-deep-orange-9'">{{ a.level === 'down' ? 'حرج' : 'قبل الحرج' }} · {{ KIND[a.kind] }}</span>
        <span class="col" />
        <span v-if="a.since" class="small muted">{{ ago(a.since) }}</span>
      </div>
      <div class="text-weight-bold">{{ a.title }}</div>
      <div class="small">{{ a.text }}</div>
      <div class="row q-gutter-sm">
        <q-btn v-if="a.kind !== 'unavailable' && a.kind !== 'low_balance'" outline no-caps color="primary" label="المحطات والشرائح" to="/flexy/devices" class="col" />
        <q-btn v-if="a.kind === 'unavailable'" outline no-caps color="primary" label="فليكسي المحلات" to="/flexy/shops" class="col" />
        <q-btn unelevated no-caps color="grey-4" text-color="dark" label="تم" :loading="acking === a.key" class="col" @click="ack(a)" />
      </div>
    </div>
    </template>

    <q-tabs v-model="tab" dense no-caps class="card q-mt-md q-pa-none" active-color="white" active-bg-color="primary" indicator-color="transparent">
      <q-tab name="balances" label="الأرصدة" />
      <q-tab name="stock" label="المخزون" />
      <q-tab name="top" label="الأكثر استهلاكًا" />
    </q-tabs>

    <template v-if="tab === 'balances'">
      <div class="ops q-mt-sm">
        <div v-for="o in view?.operators || []" :key="o.operator" class="card op" :class="{ bad: o.level === 'down' }">
          <div class="small muted">{{ o.name }} · متاح الآن</div>
          <div class="big" :class="{ 'text-negative': o.ready === 0 }">{{ money(o.available) }}</div>
          <div v-if="o.available_unknown" class="small text-deep-orange-9">{{ o.available_unknown }} شريحة جاهزة بلا رصيد مقروء</div>
          <div class="small muted">محجوز {{ money(o.reserved) }}</div>
          <button v-if="o.unavailable_sims" type="button" class="link small text-negative" @click="openUnavailable(o)">
            غير متاح {{ money(o.unavailable) }} · {{ o.unavailable_sims }} شريحة ‹
          </button>
          <div v-else class="small text-positive">كل الشرائح متاحة ({{ o.ready }})</div>
          <div class="tiny muted">المجموع {{ money(o.total) }}</div>
          <div v-if="o.ready === 0" class="small text-negative text-weight-bold">حرج: لا شريحة جاهزة</div>
        </div>
      </div>
      <div class="small muted q-mt-xs">«متاح الآن» = شرائح معتمدة ومتصلة وترد، ناقص المحجوز في عمليات جارية. الحرج أقل من {{ money(view?.limits.critical || 2000) }}، وقبل الحرج أقل من {{ money(view?.limits.beforeCritical || 4000) }}.</div>

      <div class="card q-mt-sm q-pa-none sims">
        <div class="sim head small"><span>الشريحة</span><span>الرصيد</span><span>المتاح</span><span>الحالة</span></div>
        <div v-for="s in sortedSims" :key="s.sim_uuid" class="sim small">
          <span class="column"><span class="text-weight-bold"><span class="dot" :class="s.ready ? 'ok' : s.approved ? 'down' : 'muted'" /> {{ s.code || 'شريحة' }}</span>
            <span class="tiny muted">{{ [s.station_code, s.usb != null ? 'USB ' + s.usb : null].filter(Boolean).join(' · ') }}<template v-if="s.reserved"> · محجوز {{ money(s.reserved) }}</template></span></span>
          <span>{{ s.balance == null ? '—' : money(s.balance) }}</span>
          <span>{{ s.available == null ? '؟' : money(s.available) }}</span>
          <span :class="s.ready ? 'text-positive' : 'text-negative'">{{ s.ready ? 'جاهزة' : SHORT[s.reason] || 'غير متاحة' }}</span>
        </div>
      </div>
    </template>
    <div v-else class="card q-mt-sm small muted">
      {{ tab === 'stock' ? 'المخزون (أيام التغطية لكل منتج وبطاقات التعبئة)' : 'الأكثر استهلاكًا (اليوم، 7 أيام، 30 يومًا)' }}: المرحلة التالية، بعد الأرصدة.
    </div>

    <q-dialog v-model="unavailableOpen">
      <q-card v-if="picked" style="min-width: 300px">
        <q-card-section class="text-weight-bold">{{ picked.name }} · غير متاح</q-card-section>
        <q-card-section class="column q-gutter-sm">
          <div v-for="s in pickedSims" :key="s.sim_uuid" class="column">
            <div class="row"><b class="col">{{ s.code || 'شريحة' }}</b><span>{{ s.balance == null ? '—' : money(s.balance) }}</span></div>
            <div class="small muted">{{ s.reason_text }}</div>
          </div>
        </q-card-section>
        <q-card-actions align="left">
          <q-btn flat no-caps color="primary" label="المحطات والشرائح" to="/flexy/devices" />
          <q-btn flat no-caps color="primary" label="إغلاق" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import { useBell } from 'src/composables/useBell'

const KIND = { sim_gone: 'أجهزة', no_reply: 'أجهزة', none_ready: 'أجهزة', low_balance: 'رصيد', unavailable: 'المحلات' }
const SHORT = {
  NOT_APPROVED: 'غير معتمدة', NO_PIN: 'بلا PIN', STATION_OFF: 'الكمبيوتر مطفأ', STATION_NOT_APPROVED: 'كمبيوتر غير معتمد',
  MODEM_MISSING: 'المودم غائب', SIM_MISSING: 'غائبة', NO_REPLY: 'لا ترد',
}

const { refreshBell } = useBell()
const view = ref(null)
const busy = ref(false)
const error = ref('')
const acking = ref('')
const tab = ref('balances')
const picked = ref(null)
const unavailableOpen = ref(false)

const TILES = [{ key: 'down', label: 'حرج' }, { key: 'warn', label: 'قبل الحرج' }, { key: 'ok', label: 'شريحة جاهزة' }]
const filter = ref(null)
function pick (key) {
  filter.value = filter.value === key ? null : key
  if (key === 'ok' && filter.value) tab.value = 'balances'
}
const shownAlerts = computed(() => (view.value?.alerts || []).filter((a) => !filter.value || a.level === filter.value))
const sortedSims = computed(() => [...(view.value?.sims || [])].filter((s) => filter.value !== 'ok' || s.ready).sort((a, b) =>
  (a.ready === b.ready ? 0 : a.ready ? 1 : -1) || (a.approved === b.approved ? 0 : a.approved ? -1 : 1) || String(a.code).localeCompare(String(b.code))))
const pickedSims = computed(() => (view.value?.sims || []).filter((s) => picked.value && s.operator === picked.value.operator && !s.ready))

const clock = (t) => new Date(t).toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
function ago (t) {
  const min = Math.max(0, Math.floor((Date.now() - Date.parse(t)) / 60000))
  if (min < 1) return 'الآن'
  if (min < 60) return `منذ ${min} د`
  if (min < 48 * 60) return `منذ ${Math.floor(min / 60)} س`
  return `منذ ${Math.floor(min / 1440)} ي`
}

async function load () {
  busy.value = true
  try {
    const res = await flexy.ownerMonitor()
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      error.value = ''
    } else {
      error.value = `تعذّرت القراءة (${res.body?.error || res.status})`
    }
  } finally {
    busy.value = false
  }
}
async function ack (a) {
  acking.value = a.key
  try {
    const res = await flexy.ownerMonitorAck(a.key)
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      refreshBell()
    } else {
      Notify.create({ type: 'negative', message: `لم يُحفظ (${res.body?.error || res.status})` })
    }
  } finally {
    acking.value = ''
  }
}
function openUnavailable (o) {
  picked.value = o
  unavailableOpen.value = true
}

let timer = null
onMounted(() => {
  load()
  timer = setInterval(() => { if (document.visibilityState === 'visible') load() }, 30000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<style scoped>
.counts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
.count { position: relative; border: 2px solid transparent; border-radius: 10px; padding: 10px; text-align: center; font: inherit; cursor: pointer; min-height: 44px; }
.count.picked { border-color: currentColor; }
.count.dim { opacity: 0.55; }
.funnel { position: absolute; top: 6px; inset-inline-start: 6px; opacity: 0.6; }
.count .n { font-size: 22px; font-weight: 700; }
.count.down { background: #FEE2E2; color: #991B1B; }
.count.warn { background: #FFEDD5; color: #9A3412; }
.count.ok { background: #DCFCE7; color: #166534; }
.dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #9CA3AF; }
.dot.down { background: #B91C1C; }
.dot.warn { background: #C2410C; }
.dot.ok { background: #15803D; }
.ops { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.op { display: flex; flex-direction: column; gap: 2px; margin: 0; }
.op.bad { outline: 2px solid #B91C1C; }
.big { font-size: 18px; font-weight: 700; }
.tiny { font-size: 11px; }
.link { background: none; border: 0; padding: 0; text-align: start; cursor: pointer; font: inherit; }
.sims { overflow: hidden; }
.sim { display: grid; grid-template-columns: 1.3fr 1fr 1fr 1fr; gap: 4px; padding: 10px; border-top: 1px solid #EEF0F3; }
.sim.head { background: #EEF2FF; font-weight: 600; border-top: 0; }
</style>
