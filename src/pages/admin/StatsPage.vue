<template>
  <!-- «الإحصائيات و SQL» (owner 2026-10-30, Flexy Core 0084): the database's load (Supabase warned of its Disk IO
       first), and a place to paste the SQL Claude gives him instead of Supabase's SQL Editor. Read only by default
       (no secrets); «كتابة» runs the whole script with full rights, all or nothing, after «نعم». All kept in the log. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />

    <!-- The database load, measured by the program every hour (Flexy Core 0085): nothing to press.
         Indicators first (owner 2026-10-30: «الناس لا يقرؤون الكتابات»): tiles, then standing bars, the words folded. -->
    <div class="card column q-gutter-sm">
      <div class="row items-center">
        <div class="col text-weight-bold">ضغط القاعدة</div>
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy === 'load'" @click="loadDb" />
      </div>
      <div v-if="!hours?.last_at" class="small muted">البرنامج يأخذ صورة كل ساعة: تظهر الأرقام بعد ساعتين من تطبيق 0085.</div>
      <template v-else>
        <div class="tiles">
          <div v-for="t in tiles" :key="t.label" class="tile" :class="t.cls">
            <div class="n">{{ t.n }}</div><div class="small">{{ t.label }}</div>
          </div>
        </div>
        <div class="small muted">كل عمود ساعة · اضغط عمودًا لترى رقمه<span v-if="callsLimit"> · الخط المتقطع: الحد {{ callsLimit }}/ساعة</span></div>
        <BarChart :items="hourBars" :limit="callsLimit" :height="130" />
        <q-expansion-item dense dense-toggle switch-toggle-side label="التفاصيل: آخر ساعة" header-class="small text-grey-8 q-px-none">
          <div v-for="r in hours.last_hour" :key="r.what" class="line row items-center no-wrap q-gutter-sm">
            <div class="col">{{ nameOf(r.what) }}</div>
            <div class="small text-right" style="min-width:76px"><b>{{ r.per_minute }}</b>/دقيقة</div>
            <div class="small text-right" style="min-width:70px" :class="r.writes > 1000 ? 'text-deep-orange' : 'muted'">✎ {{ r.writes }}</div>
          </div>
          <div class="small muted q-pt-xs">آخر قياس {{ when(hours.last_at) }} · يقيس البرنامج وحده كل ساعة</div>
        </q-expansion-item>
      </template>
    </div>


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
        <q-btn outline dense rounded no-caps size="sm" color="primary" icon="table_chart" label="الجداول"
          :loading="busy === 'tables'" @click="toggleTables" />
        <q-btn v-for="r in ready" :key="r.key" outline dense rounded no-caps size="sm" color="grey-8" :label="r.name"
          :loading="busy === r.key" @click="runReady(r)" />
      </div>
      <!-- «الجداول» (owner 2026-10-30: «أريد أن أتعمق في قواعد البيانات»): what may be read; a tap shows its first 20 rows -->
      <div v-if="tables" class="column q-gutter-xs">
        <q-input v-model="tableFilter" dense outlined clearable placeholder="ابحث عن جدول" input-class="ltr" />
        <div class="tables-list">
          <button v-for="t in shownTables" :key="t.schema + '.' + t.table" type="button" class="table-row" @click="openTable(t)">
            <span class="ltr">{{ t.schema }}.<b>{{ t.table }}</b></span>
            <span class="small muted">{{ t.rows }} سطر · {{ (t.columns || []).length }} عمود</span>
          </button>
        </div>
      </div>
    </div>

    <div v-if="result" ref="resultBox" class="card column q-gutter-xs">
      <div v-if="result.ok" class="small text-positive">
        تم في {{ result.ms }} ms<span v-if="result.count !== null && result.count !== undefined"> · {{ result.count }} سطر</span><span v-if="result.more"> · يظهر أول 200</span>
      </div>
      <div v-else class="small text-negative ltr">{{ result.message || result.error }}</div>
      <div v-if="result.ok && !result.write && !result.rows?.length" class="small text-deep-orange">لا يوجد سطر يطابق.</div>
      <div v-if="result.ok && result.columns?.length" class="table-wrap">
        <table class="grid">
          <thead><tr><th v-for="c in result.columns" :key="c">{{ c }}</th></tr></thead>
          <tbody><tr v-for="(row, i) in result.rows" :key="i"><td v-for="c in result.columns" :key="c">{{ cell(row[c]) }}</td></tr></tbody>
        </table>
      </div>
      <q-btn v-if="result.ok && result.rows?.length" flat dense no-caps icon="content_copy" label="نسخ" class="self-start" @click="copy" />
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
import { computed, nextTick, onMounted, ref } from 'vue'
import { Dialog, Notify, copyToClipboard } from 'quasar'
import SectionTabs from 'src/components/SectionTabs.vue'
import BarChart from 'src/components/BarChart.vue'
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
  if (b?.ok) { ready.value = b.ready.filter((r) => !['db_hours', 'db_sizes', 'tables'].includes(r.key)); log.value = b.log || [] }
}
async function loadDb () {
  flexy.ownerAuto().then((r) => {
    const l = (r.body?.limits || []).find((x) => x.key === 'monitor.db_calls_per_hour')
    callsLimit.value = l ? Number(l.value) || 0 : 0
  }).catch(() => {})
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
// «الجداول»: loaded once, filtered here; a table opens as «its readable columns, first 20 rows», read only
const tables = ref(null)
const tableFilter = ref('')
const shownTables = computed(() => {
  const f = (tableFilter.value || '').trim().toLowerCase()
  return (tables.value || []).filter((t) => !f || (t.schema + '.' + t.table).toLowerCase().includes(f))
})
async function toggleTables () {
  if (tables.value) { tables.value = null; return }
  const b = await call('tables', () => flexy.runReady('tables'))
  if (b?.ok) tables.value = b.rows?.[0]?.tables || []
}
function openTable (t) {
  const cols = (t.columns || []).map((c) => '"' + c + '"').join(', ') || '*'
  text.value = `select ${cols} from ${t.schema}."${t.table}" limit 20`
  write.value = false
  run()
}
async function runReady (r) {
  if (busy.value) return
  await show(await call(r.key, () => flexy.runReady(r.key)), false)
  loadLog()
}
const cell = (v) => (v === null || v === undefined ? '—' : typeof v === 'object' ? JSON.stringify(v) : String(v))
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '—')
const hourOf = (t) => new Date(t).toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' })
// The owner's limit (0085, «المفاتيح»): the dashed line, and red bars above it
const callsLimit = ref(0)
const hourBars = computed(() => (hours.value?.hours || []).map((h) => ({
  value: h.calls, text: h.per_minute + '/دقيقة', label: hourOf(h.at), short: hourOf(h.at).slice(0, 2)
})))
const tiles = computed(() => {
  const hs = hours.value?.hours || []
  const last = hs[hs.length - 1]
  const top = hs.reduce((a, h) => (!a || h.calls > a.calls ? h : a), null)
  const over = callsLimit.value && last && last.calls > callsLimit.value
  return [
    { label: 'آخر ساعة (طلب/دقيقة)', n: last ? last.per_minute : '—', cls: over ? 'bad' : '' },
    { label: 'أعلى ساعة اليوم', n: top ? hourOf(top.at) : '—' },
    { label: 'كتابة على القرص آخر ساعة', n: last ? last.writes : '—' },
    { label: 'الحالة', n: over ? 'فوق الحد' : 'عادي ✓', cls: over ? 'bad' : 'good' }
  ]
})
function copy () {
  const r = result.value
  copyToClipboard([r.columns.join('\t'), ...r.rows.map((row) => r.columns.map((c) => cell(row[c])).join('\t'))].join('\n'))
}
onMounted(() => { loadLog(); loadDb() })
</script>

<style scoped>
.tiles { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.tile { background: rgba(0, 0, 0, 0.04); border-radius: 12px; padding: 8px 10px; }
.tile .n { font-size: 20px; font-weight: 700; }
.tile.bad { background: rgba(193, 0, 21, 0.1); color: var(--q-negative); }
.tile.good .n { color: var(--q-positive); }
body.body--dark .tile { background: rgba(255, 255, 255, 0.06); }
.line { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 6px 4px; }
.ltr { direction: ltr; text-align: left; }
.sql { max-width: 100%; min-width: 0; }
.sql :deep(textarea) { font-family: monospace; font-size: 13px; overflow-x: auto; white-space: pre; }
.tables-list { max-height: 320px; overflow-y: auto; border: 1px solid rgba(0, 0, 0, 0.08); border-radius: 8px; }
.table-row { display: flex; justify-content: space-between; align-items: center; gap: 8px; width: 100%; padding: 8px 10px;
  border: 0; border-bottom: 1px solid rgba(0, 0, 0, 0.06); background: none; font: inherit; color: inherit; cursor: pointer; text-align: left; }
.card { min-width: 0; max-width: 100%; overflow-x: hidden; }
.grid { border-collapse: collapse; font-size: 12px; direction: ltr; }
.grid th, .grid td { border: 1px solid rgba(0, 0, 0, 0.1); padding: 3px 6px; white-space: nowrap; max-width: 260px; overflow: hidden; text-overflow: ellipsis; }
</style>
