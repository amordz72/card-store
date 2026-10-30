<template>
  <!-- «الإحصائيات و SQL» (owner 2026-10-30, Flexy Core 0084): the database's load (Supabase warned of its Disk IO
       first), and a place to paste the SQL Claude gives him instead of Supabase's SQL Editor. Read only by default
       (no secrets); «كتابة» runs the whole script with full rights, all or nothing, after «نعم». All kept in the log. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />

    <!-- The SQL first: the page is opened mostly to paste a script -->
    <div class="card column q-gutter-sm">
      <div class="row items-center">
        <div class="col text-weight-bold">SQL</div>
        <q-btn-toggle v-model="write" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: 'قراءة', value: false }, { label: 'كتابة', value: true }]" />
      </div>
      <!-- Long lines scroll inside the box, never widen the page (owner 2026-10-30: «شاشة عريضة») -->
      <q-input v-model="text" type="textarea" outlined class="sql" input-class="ltr" :input-style="{ whiteSpace: 'pre', overflowX: 'auto' }"
        rows="8" wrap="off" placeholder="الصق SQL هنا" :disable="busy === 'sql'" />
      <div class="small" :class="write ? 'text-deep-orange' : 'muted'">
        {{ write ? 'كتابة: كل الأوامر معًا بصلاحيات كاملة، إما تنجح كلها أو لا يتغيّر شيء. يُسجَّل.' : 'قراءة: SELECT واحد فقط، بلا أسرار، 200 سطر على الأكثر.' }}
      </div>
      <div class="row q-gutter-sm">
        <q-btn unelevated no-caps :color="write ? 'deep-orange' : 'primary'" :icon="write ? 'play_arrow' : 'search'" :label="write ? 'نفّذ' : 'اقرأ'"
          :loading="busy === 'sql'" :disable="!text.trim()" @click="run" />
        <q-btn flat no-caps label="مسح" :disable="!text" @click="text = ''; result = null" />
      </div>
      <div class="row q-gutter-xs">
        <q-btn v-for="r in ready" :key="r.key" outline dense rounded no-caps size="sm" color="grey-8" :label="r.name"
          :loading="busy === r.key" @click="runReady(r)" />
      </div>
    </div>

    <div v-if="result" ref="resultBox" class="card column q-gutter-xs">
      <div v-if="result.ok" class="small text-positive">
        تم في {{ result.ms }} ms<span v-if="result.count !== null && result.count !== undefined"> · {{ result.count }} سطر</span><span v-if="result.more"> · يظهر أول 200</span>
      </div>
      <div v-else class="small text-negative ltr">{{ result.message || result.error }}</div>
      <div v-if="result.ok && result.columns?.length" class="table-wrap">
        <table class="grid">
          <thead><tr><th v-for="c in result.columns" :key="c">{{ c }}</th></tr></thead>
          <tbody><tr v-for="(row, i) in result.rows" :key="i"><td v-for="c in result.columns" :key="c">{{ cell(row[c]) }}</td></tr></tbody>
        </table>
      </div>
      <q-btn v-if="result.ok && result.rows?.length" flat dense no-caps icon="content_copy" label="نسخ" class="self-start" @click="copy" />
    </div>

    <!-- The database load, measured by the program every hour (Flexy Core 0085): nothing to press -->
    <div class="card column q-gutter-xs">
      <div class="row items-center">
        <div class="col text-weight-bold">ضغط القاعدة</div>
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy === 'load'" @click="loadDb" />
      </div>
      <div v-if="!hours?.last_at" class="small muted">البرنامج يأخذ صورة كل ساعة: تظهر الأرقام بعد ساعتين من تطبيق 0085.</div>
      <template v-else>
        <div class="small muted">آخر قياس {{ when(hours.last_at) }} · يقيس البرنامج وحده كل ساعة</div>
        <div class="text-weight-medium q-mt-xs">آخر ساعة</div>
        <div v-for="r in hours.last_hour" :key="r.what" class="line row items-center no-wrap q-gutter-sm">
          <div class="col">{{ nameOf(r.what) }}</div>
          <div class="small text-right" style="min-width:76px"><b>{{ r.per_minute }}</b>/دقيقة</div>
          <div class="small text-right" style="min-width:70px" :class="r.writes > 1000 ? 'text-deep-orange' : 'muted'">✎ {{ r.writes }}</div>
        </div>
        <div class="text-weight-medium q-mt-sm">ساعة بساعة (24 ساعة)</div>
        <div v-for="h in hours.hours" :key="h.at" class="row items-center no-wrap q-gutter-sm small">
          <div style="min-width:44px" class="muted">{{ hourOf(h.at) }}</div>
          <div class="col"><div class="bar" :style="{ width: barWidth(h.calls) }" /></div>
          <div style="min-width:70px" class="text-right">{{ h.per_minute }}/د</div>
        </div>
      </template>
    </div>

    <div class="card column q-gutter-xs">
      <div class="text-weight-bold">أكبر الجداول</div>
      <div v-for="t in sizes" :key="t.table" class="line row no-wrap q-gutter-sm">
        <div class="col ltr small">{{ t.table }}</div><div class="small muted">{{ t.rows }} سطر</div><div class="small" style="min-width:64px">{{ t.size }}</div>
      </div>
    </div>

    <q-expansion-item class="card q-pa-none" dense icon="history" label="سجل SQL" header-class="text-weight-bold">
      <div v-for="(l, i) in log" :key="i" class="line small">
        <span class="muted">{{ when(l.at) }}</span> · <span :class="l.error ? 'text-negative' : ''">{{ l.error ? 'خطأ' : (l.rows ?? '—') + ' سطر' }}</span>
        <div class="ltr ellipsis-2-lines">{{ l.ready ? '★ ' + l.ready : l.query }}</div>
      </div>
    </q-expansion-item>
    <div v-if="error" class="small text-negative">{{ error }}</div>
  </q-page>
</template>

<script setup>
import { nextTick, onMounted, ref } from 'vue'
import { Dialog, Notify, copyToClipboard } from 'quasar'
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import * as flexy from 'src/api/flexy'

// What each heavy call is, in words
const NAMES = {
  station_connect_claim_job: 'المحطة تسأل: هل عندي عملية؟',
  station_connect_claim_command: 'المحطة تسأل: هل عندي أمر USSD؟',
  station_connect_sync_hardware: 'مزامنة المودمات',
  station_connect_heartbeat: 'نبضة المحطة',
  station_connect_status: 'حالة المحطة',
  station_connect_sync_usb_inventory: 'قائمة USB',
  store_exec_claim_v2: 'المنفّذ يسأل عن عمل',
  'flexy.station_report_save': 'حفظ تقرير المحطة'
}
const nameOf = (w) => NAMES[w] || (w.startsWith('insert into cron') || w.startsWith('update cron') ? 'سجل الدورة الآلية' : w)

const text = ref('')
const write = ref(false)
const ready = ref([])
const result = ref(null)
const hours = ref(null)
const sizes = ref([])
const log = ref([])
const busy = ref('')
const resultBox = ref(null)
const error = ref('')

async function call (key, fn) {
  busy.value = key
  error.value = ''
  try {
    const res = await fn()
    if (res.status !== 200) throw new Error(res.body?.error || 'FLEXY_CORE')
    return res.body
  } catch (e) {
    error.value = 'لم يُقبل (' + (e.message || 'FLEXY_CORE') + ').'
    // Never silent: what failed shows where the owner looks
    if (key === 'sql' || ready.value.some((r) => r.key === key)) Notify.create({ type: 'negative', message: error.value, position: 'top' })
    return null
  } finally {
    busy.value = ''
  }
}
async function loadLog () {
  const b = await call('', () => flexy.ownerSql())
  if (b?.ok) { ready.value = b.ready.filter((r) => r.key !== 'db_hours' && r.key !== 'db_sizes'); log.value = b.log || [] }
}
async function loadDb () {
  const a = await call('load', () => flexy.runReady('db_hours'))
  if (a?.ok) hours.value = a.rows?.[0]?.hours || null
  const b = await call('load', () => flexy.runReady('db_sizes'))
  if (b?.ok) sizes.value = b.rows?.[0]?.sizes || []
}
// One run at a time; the answer always shows (a toast, then the page goes to it); a written script is cleared
async function show (r, wrote) {
  result.value = r
  if (!r) return
  const secs = r.ms !== undefined ? (r.ms / 1000).toFixed(1) + ' ث' : ''
  Notify.create(r.ok
    ? { type: 'positive', message: '✓ تم في ' + secs + (r.count !== null && r.count !== undefined ? ' · ' + r.count + ' سطر' : ''), position: 'top' }
    : { type: 'negative', message: '✗ خطأ: ' + (r.message || r.error || ''), position: 'top', timeout: 8000 })
  if (r.ok && wrote) text.value = ''
  await nextTick()
  resultBox.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
function run () {
  if (busy.value) return
  const wrote = write.value
  const go = async () => {
    await show(await call('sql', () => flexy.runSql(text.value, wrote)), wrote)
    loadLog()
  }
  if (!wrote) return go()
  Dialog.create({ title: 'تنفيذ بصلاحيات كاملة', message: 'ينفّذ كل الأوامر معًا. إن فشل أحدها لا يتغيّر شيء. متابعة؟', cancel: 'لا', ok: 'نعم، نفّذ' }).onOk(go)
}
async function runReady (r) {
  if (busy.value) return
  await show(await call(r.key, () => flexy.runReady(r.key)), false)
  loadLog()
}
const cell = (v) => (v === null || v === undefined ? '—' : typeof v === 'object' ? JSON.stringify(v) : String(v))
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '—')
const hourOf = (t) => new Date(t).toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' })
const barWidth = (n) => Math.max(2, Math.round((n / Math.max(1, ...(hours.value?.hours || []).map((h) => h.calls))) * 100)) + '%'
function copy () {
  const r = result.value
  copyToClipboard([r.columns.join('\t'), ...r.rows.map((row) => r.columns.map((c) => cell(row[c])).join('\t'))].join('\n'))
}
onMounted(() => { loadLog(); loadDb() })
</script>

<style scoped>
.bar { height: 8px; border-radius: 4px; background: var(--q-primary); }
.line { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 6px 4px; }
.ltr { direction: ltr; text-align: left; }
.sql { max-width: 100%; min-width: 0; }
.sql :deep(textarea) { font-family: monospace; font-size: 13px; overflow-x: auto; white-space: pre; }
.card { min-width: 0; max-width: 100%; overflow-x: hidden; }
.grid { border-collapse: collapse; font-size: 12px; direction: ltr; }
.grid th, .grid td { border: 1px solid rgba(0, 0, 0, 0.1); padding: 3px 6px; white-space: nowrap; max-width: 260px; overflow: hidden; text-overflow: ellipsis; }
</style>
