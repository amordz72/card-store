<template>
  <!-- «الإحصائيات و SQL» (owner 2026-10-30, Flexy Core 0084): the database's load (Supabase warned of its Disk IO
       first), and a place to paste the SQL Claude gives him instead of Supabase's SQL Editor. Read only by default
       (no secrets); «كتابة» runs the whole script with full rights, all or nothing, after «نعم». All kept in the log. -->
  <div class="column gap-sm">
    <!-- «سجل البطء» (owner 2026-10-30): this device's calls in the last 24 hours, slowest first, and the cause:
         the internet (the trip) or the server (its own time, x-flexy-ms). All devices: the ready query «البطء». -->
    <div class="card column gap-xs">
      <div class="row items-center">
        <div class="col text-weight-bold">البطء على هذا الجهاز (24 ساعة)</div>
        <q-btn flat round dense icon="smart_toy" aria-label="نسخ لـClaude" @click="copyForClaude('البطء على هذا الجهاز', perf)" />
        <q-btn flat round dense icon="refresh" aria-label="تحديث" @click="perf = perfSummary()" />
      </div>
      <div v-if="!perf.length" class="small muted">لا شيء مسجّل بعد.</div>
      <div v-for="g in perf.slice(0, perfAll ? 40 : 6)" :key="g.what" class="line row items-center no-wrap gap-sm small">
        <div class="col ltr ellipsis">{{ g.what }}</div>
        <div style="min-width:52px" :class="g.avg > 3000 ? 'text-negative text-weight-bold' : ''">{{ (g.avg / 1000).toFixed(1) }} ث</div>
        <div style="min-width:70px" class="muted">{{ g.serverAvg !== null ? 'الخادم ' + (g.serverAvg / 1000).toFixed(1) : '' }}</div>
        <div style="min-width:64px" :class="g.cause === 'الخادم' ? 'text-deep-orange' : 'text-primary'">{{ g.cause }}</div>
        <div class="muted" style="min-width:28px">×{{ g.n }}</div>
      </div>
      <a v-if="perf.length > 6 && !perfAll" href="#" class="small" @click.prevent="perfAll = true">كل الطلبات ({{ perf.length }})</a>
    </div>

    <!-- The database load, measured by the program every hour (Flexy Core 0085): nothing to press.
         Indicators first (owner 2026-10-30: «الناس لا يقرؤون الكتابات»): tiles, then standing bars, the words folded. -->
    <div class="card column gap-sm">
      <div class="row items-center">
        <div class="col text-weight-bold">ضغط القاعدة</div>
        <q-btn flat round dense icon="smart_toy" aria-label="نسخ لـClaude" @click="copyForClaude('ضغط القاعدة', loadForClaude())" />
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="loadState === 'busy'" @click="loadDb" />
      </div>
      <!-- Never a spinner forever (owner 2026-10-30): 15 s, then «أعد المحاولة» -->
      <div v-if="loadState === 'failed'" class="small text-negative">لم تصل الأرقام · <a href="#" @click.prevent="loadDb">أعد المحاولة</a></div>
      <div v-else-if="loadState !== 'busy' && !hours?.last_at" class="small muted">البرنامج يأخذ صورة كل ساعة: تظهر الأرقام بعد ساعتين من تطبيق 0085.</div>
      <template v-else>
        <div class="tiles">
          <div v-for="t in tiles" :key="t.label" class="tile" :class="t.cls">
            <div class="n">{{ t.n }}</div><div class="small">{{ t.label }}</div>
          </div>
        </div>
        <!-- Each bar = one measured window (its time under it), in requests per minute; the running hour light (partial) -->
        <div class="small muted">كل عمود = ساعة مقيسة، ارتفاعه طلبات في الدقيقة · الفاتح = الساعة الجارية حتى الآن<span v-if="callsLimit"> · المتقطع: الحد {{ Math.round(callsLimit / 60) }}/دقيقة</span></div>
        <BarChart :items="hourBars" :limit="callsLimit ? callsLimit / 60 : 0" :height="130" />
        <q-expansion-item dense dense-toggle switch-toggle-side label="التفاصيل: آخر ساعة" header-class="small text-grey-8 q-px-none">
          <div v-for="r in hours.last_hour" :key="r.what" class="line row items-center no-wrap gap-sm">
            <div class="col">{{ nameOf(r.what) }}</div>
            <div class="small text-right" style="min-width:76px"><b>{{ r.per_minute }}</b>/دقيقة</div>
            <div class="small text-right" style="min-width:70px" :class="r.writes > 1000 ? 'text-deep-orange' : 'muted'">✎ {{ r.writes }}</div>
          </div>
          <div class="small muted q-pt-xs">آخر قياس {{ when(hours.last_at) }} · يقيس البرنامج وحده كل ساعة</div>
        </q-expansion-item>
      </template>
    </div>


    <!-- «ينتظر تطبيقك» (Flexy Core 0087): what Claude put, one button; its SQL only to look at -->
    <div v-for="p in pendingOpen" :key="p.uid" class="card column gap-xs pending">
      <div class="row items-center no-wrap gap-sm">
        <q-icon name="build" color="indigo-8" size="22px" />
        <div class="col"><div class="text-weight-bold">ينتظر تطبيقك</div><div>{{ p.title }}</div></div>
        <q-btn unelevated no-caps color="indigo-8" icon="play_arrow" label="طبّق" :loading="busy === 'apply' + p.uid" :disable="!!p.mig && p.uid !== pendingOpen[0]?.uid" @click="apply(p)" />
      </div>
      <div v-if="p.last_error" class="small text-negative ltr">آخر محاولة فشلت: {{ p.last_error }}</div>
      <q-expansion-item dense dense-toggle switch-toggle-side label="عرض SQL" header-class="small text-grey-8 q-px-none">
        <pre class="sql-view ltr">{{ p.sql }}</pre>
      </q-expansion-item>
    </div>

    <!-- Manual SQL, rarely used now (owner 2026-10-30: scripts come in «ينتظر تطبيقك»): folded -->
    <q-expansion-item class="card q-pa-none" dense icon="code" label="SQL يدوي والجداول" header-class="text-weight-bold">
    <div class="column gap-sm q-pa-sm">
      <!-- No «قراءة/كتابة» to choose (owner 2026-10-30): one SELECT reads, anything else executes -->
      <!-- Long lines scroll inside the box, never widen the page (owner 2026-10-30: «شاشة عريضة») -->
      <q-input v-model="text" type="textarea" outlined class="sql" input-class="ltr" :input-style="{ whiteSpace: 'pre', overflowX: 'auto' }"
        rows="8" wrap="off" placeholder="الصق SQL هنا" :disable="busy === 'sql'" />
      <div v-if="text.trim()" class="small" :class="write ? 'text-deep-orange' : 'muted'">
        {{ write ? 'تعديل: كل الأوامر معًا بصلاحيات كاملة، إما تنجح كلها أو لا يتغيّر شيء. يُسجَّل.' : 'قراءة فقط: بلا أسرار، 200 سطر على الأكثر.' }}
      </div>
      <div class="row gap-sm">
        <q-btn unelevated no-caps :color="write ? 'deep-orange' : 'primary'" :icon="write ? 'play_arrow' : 'search'" :label="write ? 'نفّذ' : 'اقرأ'"
          :loading="busy === 'sql'" :disable="!text.trim()" @click="run" />
        <q-btn flat no-caps label="مسح" :disable="!text" @click="text = ''; result = null" />
      </div>
      <div class="row gap-xs">
        <q-btn outline dense rounded no-caps size="sm" color="primary" icon="table_chart" label="الجداول"
          :loading="busy === 'tables'" @click="toggleTables" />
        <q-btn v-for="r in ready" :key="r.key" outline dense rounded no-caps size="sm" color="grey-8" :label="r.name"
          :loading="busy === r.key" @click="runReady(r)" />
      </div>
      <!-- «الجداول» (owner 2026-10-30: «أريد أن أتعمق في قواعد البيانات»): what may be read; a tap shows its first 20 rows -->
      <div v-if="tables" class="column gap-xs">
        <q-input v-model="tableFilter" dense outlined clearable placeholder="ابحث عن جدول" input-class="ltr" />
        <div class="tables-list">
          <button v-for="t in shownTables" :key="t.schema + '.' + t.table" type="button" class="table-row" @click="openTable(t)">
            <span class="ltr">{{ t.schema }}.<b>{{ t.table }}</b></span>
            <span class="small muted">{{ t.rows }} سطر · {{ (t.columns || []).length }} عمود</span>
          </button>
        </div>
      </div>
    </div>
    </q-expansion-item>

    <div v-if="result" ref="resultBox" class="card column gap-xs">
      <div v-if="result.ok" class="small text-positive">
        تم في {{ result.ms }} ms<span v-if="result.count !== null && result.count !== undefined"> · {{ result.count }} سطر</span><span v-if="result.more"> · يظهر أول 200</span>
      </div>
      <div v-else class="small text-negative ltr">{{ result.message || result.error }}</div>
      <div v-if="result.ok && !result.write && !result.rows?.length" class="small text-deep-orange">لا يوجد سطر يطابق.</div>
      <div v-if="result.ok && result.columns?.length" class="table-wrap">
        <table class="grid">
          <thead><tr><th v-for="c in result.columns" :key="c">{{ HEADERS[c] || c }}</th></tr></thead>
          <tbody><tr v-for="(row, i) in result.rows" :key="i"><td v-for="c in result.columns" :key="c">{{ cell(row[c]) }}</td></tr></tbody>
        </table>
      </div>
      <q-btn v-if="result.ok && result.rows?.length" flat dense no-caps icon="content_copy" label="نسخ" class="self-start" @click="copy" />
    </div>

    <!-- Counted only when opened: nothing asked of the database on every visit -->
    <q-expansion-item class="card q-pa-none" dense icon="dataset" label="أكبر الجداول" header-class="text-weight-bold" @show="loadSizes">
      <div class="column gap-xs q-pa-sm">
        <div v-if="sizesState === 'busy'" class="small muted">يُحسب…</div>
        <div v-else-if="sizesState === 'failed'" class="small text-negative">لم تصل · <a href="#" @click.prevent="loadSizes">أعد المحاولة</a></div>
        <div v-for="t in sizes" :key="t.table" class="line row no-wrap gap-sm">
          <div class="col ltr small">{{ t.table }}</div><div class="small muted">{{ t.rows >= 0 ? t.rows + ' سطر' : '—' }}</div><div class="small" style="min-width:64px">{{ t.size }}</div>
        </div>
      </div>
    </q-expansion-item>

    <q-expansion-item class="card q-pa-none" dense icon="history" label="سجل SQL" header-class="text-weight-bold">
      <div v-for="(l, i) in log" :key="i" class="line small">
        <span class="muted">{{ when(l.at) }}</span> · <span :class="l.error ? 'text-negative' : ''">{{ l.error ? 'خطأ' : (l.rows ?? '—') + ' سطر' }}</span>
        <div class="ltr ellipsis-2-lines">{{ l.ready ? '★ ' + l.ready : l.query }}</div>
      </div>
    </q-expansion-item>
    <div v-if="error" class="small text-negative">{{ error }}</div>
  </div>
</template>

<script setup>
import { computed, nextTick, onMounted, ref } from 'vue'
import { Dialog, Notify, copyToClipboard } from 'quasar'
import BarChart from 'src/components/BarChart.vue'
import { copyForClaude, registerForClaude } from 'src/composables/useClaudeCopy'
import { perfSummary } from 'src/api/perfLog'
import * as flexy from 'src/api/flexy'
import { useBell } from 'src/composables/useBell'

const { refreshBell } = useBell()

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

const perf = ref(perfSummary())
const perfAll = ref(false)
registerForClaude('البطء على هذا الجهاز', () => perf.value.slice(0, 15).map(({ what, n, avg, serverAvg, cause, fails, offline }) => ({ what, n, avg, serverAvg, cause, fails, offline })))
const text = ref('')
// One SELECT/WITH (a trailing «;» allowed) reads; anything else is a script to execute
const write = computed(() => {
  const q = text.value.trim().replace(/;\s*$/, '')
  return !(/^(select|with)\b/i.test(q) && !q.includes(';'))
})
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
// «ينتظر تطبيقك»: applied by its id (the server reads the SQL), then the bar goes
const pendingOpen = ref([])
function apply (p) {
  if (busy.value) return
  Dialog.create({ title: 'طبّق: ' + p.title, message: 'ينفّذ كل الأوامر معًا بصلاحيات كاملة. إن فشل أحدها لا يتغيّر شيء. متابعة؟', cancel: 'لا', ok: 'نعم، طبّق' })
    .onOk(async () => {
      await show(await call('apply' + p.uid, () => (p.mig ? flexy.applyMigration(p.mig) : flexy.applyPending(p.id))), false)
      await loadLog()
      refreshBell()
    })
}
async function loadLog () {
  const b = await call('', () => flexy.ownerSql())
  if (b?.ok) { // The migrations this deploy carries, not applied yet, then the scripts put in the database (0087)
    pendingOpen.value = [
      ...(b.migrations || []).map((m) => ({ uid: 'm' + m.key, mig: m.key, title: m.title, sql: m.sql })),
      ...(b.pending?.open || []).map((p) => ({ ...p, uid: 'p' + p.id }))
    ]; ready.value = b.ready.filter((r) => !['db_hours', 'db_sizes', 'tables', 'failed_ops', 'failed_reads', 'review_ops'].includes(r.key)); log.value = b.log || [] }
}
// Each card its own state and a 15-second limit: a request lost on the phone's network never spins forever
const loadState = ref('')
const sizesState = ref('')
const withLimit = (p, ms = 15000) => Promise.race([p, new Promise((resolve) => setTimeout(() => resolve({ status: 0, body: { ok: false, error: 'TIMEOUT' } }), ms))])
async function loadDb () {
  if (loadState.value === 'busy') return
  loadState.value = 'busy'
  const [lim, a] = await Promise.all([withLimit(flexy.ownerAuto()).catch(() => null), withLimit(flexy.runReady('db_hours')).catch(() => null)])
  const l = (lim?.body?.limits || []).find((x) => x.key === 'monitor.db_calls_per_hour')
  callsLimit.value = l ? Number(l.value) || 0 : 0
  if (a?.status === 200 && a.body?.ok) {
    hours.value = a.body.rows?.[0]?.hours || null
    loadState.value = ''
  } else {
    loadState.value = 'failed'
  }
}
async function loadSizes () {
  if (sizesState.value === 'busy' || sizes.value.length) return
  sizesState.value = 'busy'
  const b = await withLimit(flexy.runReady('db_sizes')).catch(() => null)
  if (b?.status === 200 && b.body?.ok) { sizes.value = b.body.rows?.[0]?.sizes || []; sizesState.value = '' } else sizesState.value = 'failed'
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
  const go = async (again = false) => {
    const r = await call('sql', () => flexy.runSql(text.value, wrote, again))
    // Already applied with success (Flexy Core 0088): never twice by mistake, only on purpose
    if (r && r.error === 'ALREADY_APPLIED') {
      return Dialog.create({
        title: 'طُبّق من قبل',
        message: 'هذا الـSQL نفسه طُبّق بنجاح ' + when(r.at) + '. إعادته قد تكرر ما فعله.',
        cancel: 'إلغاء', ok: { label: 'أعد التنفيذ عمدًا', color: 'deep-orange' }
      }).onOk(() => go(true))
    }
    await show(r, wrote)
    loadLog()
  }
  if (!wrote) return go()
  Dialog.create({ title: 'تنفيذ بصلاحيات كاملة', message: 'ينفّذ كل الأوامر معًا. إن فشل أحدها لا يتغيّر شيء. متابعة؟', cancel: 'لا', ok: 'نعم، نفّذ' }).onOk(() => go())
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
  run()
}
async function runReady (r) {
  if (busy.value) return
  await show(await call(r.key, () => flexy.runReady(r.key)), false)
  loadLog()
}
// Times in the phone's clock (owner 2026-10-30: «2026-10-30T10:48:01Z» is not read), Arabic column names
const ISO = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/
const cell = (v) => {
  if (v === null || v === undefined) return '—'
  if (v instanceof Date || (typeof v === 'string' && ISO.test(v))) {
    const d = new Date(v)
    const today = new Date().toDateString() === d.toDateString()
    return (today ? '' : d.toLocaleDateString('ar-DZ', { day: '2-digit', month: '2-digit' }) + ' ') + d.toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' })
  }
  return typeof v === 'object' ? JSON.stringify(v) : String(v)
}
const HEADERS = {
  at: 'الوقت', created_at: 'الوقت', updated_at: 'آخر تغيير', applied_at: 'طُبّق', task: 'المهمة', target: 'الهدف', reason: 'السبب',
  status: 'الحالة', phone: 'الرقم', amount: 'المبلغ', sim: 'الشريحة', display_code: 'الشريحة', title: 'العنوان', kind: 'النوع',
  name: 'الاسم', label: 'الاسم', balance: 'الرصيد', balance_amount: 'الرصيد', checked_at: 'قُرئ', last_seen_at: 'آخر ظهور',
  operation_key: 'العملية', code: 'الرمز', error: 'الخطأ', rows: 'الأسطر', id: 'رقم', last_visit: 'آخر دخول'
}
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '—')
const hourOf = (t) => new Date(t).toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' })
// The owner's limit (0085, «المفاتيح»): the dashed line, and red bars above it
const callsLimit = ref(0)
const hourBars = computed(() => [
  ...(hours.value?.hours || []).map((h) => ({
    value: Number(h.per_minute), text: h.per_minute + '/دقيقة', label: (h.from ? hourOf(h.from) + ' ← ' : '') + hourOf(h.at), short: hourOf(h.at).slice(0, 2)
  })),
  ...(hours.value?.current ? [{
    value: Number(hours.value.current.per_minute), partial: true, text: hours.value.current.per_minute + '/دقيقة',
    label: 'الآن: ' + hours.value.current.minutes + ' دقيقة منذ ' + hourOf(hours.value.current.from), short: 'الآن'
  }] : [])
])
const loadForClaude = () => ({ last_at: hours.value?.last_at, limit_per_hour: callsLimit.value,
  hours: (hours.value?.hours || []).map((h) => `${h.from}→${h.at} ${h.per_minute}/min writes=${h.writes}`).join(' ; '),
  current: hours.value?.current ? `${hours.value.current.per_minute}/min for ${hours.value.current.minutes} min` : null,
  top: (hours.value?.last_hour || []).slice(0, 6).map((r) => `${r.what} ${r.per_minute}/min w=${r.writes}`).join(' ; ') })
registerForClaude('ضغط القاعدة', loadForClaude)
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
.pending { border: 2px solid var(--q-primary); border-color: #283593; }
.sql-view { font-size: 12px; max-height: 260px; overflow: auto; background: rgba(0, 0, 0, 0.04); padding: 8px; border-radius: 6px; margin: 0; }
.gap-xs { gap: 4px; }
.gap-sm { gap: 8px; }
.gap-md { gap: 16px; }
.row.gap-xs, .row.gap-sm, .row.gap-md { flex-wrap: wrap; }
.row.no-wrap.gap-xs, .row.no-wrap.gap-sm, .row.no-wrap.gap-md { flex-wrap: nowrap; }
/* long names (tables, migrations) break instead of widening the card */
.col, .card > * { min-width: 0; }
.ltr, .text-weight-bold, .sql-view { overflow-wrap: anywhere; }
.sql-view { max-width: 100%; }
.table-wrap { display: block; width: 100%; max-width: 100%; overflow-x: auto; }
.tables-list { max-height: 320px; overflow-y: auto; border: 1px solid rgba(0, 0, 0, 0.08); border-radius: 8px; }
.table-row { display: flex; justify-content: space-between; align-items: center; gap: 8px; width: 100%; padding: 8px 10px;
  border: 0; border-bottom: 1px solid rgba(0, 0, 0, 0.06); background: none; font: inherit; color: inherit; cursor: pointer; text-align: left; }
.card { min-width: 0; max-width: 100%; overflow-x: hidden; }
.grid { border-collapse: collapse; font-size: 12px; direction: ltr; }
.grid th, .grid td { border: 1px solid rgba(0, 0, 0, 0.1); padding: 3px 6px; white-space: nowrap; max-width: 260px; overflow: hidden; text-overflow: ellipsis; }
</style>
