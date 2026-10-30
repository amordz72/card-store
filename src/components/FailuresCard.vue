<template>
  <!-- «العمليات الفاشلة» (owner 2026-10-30, Flexy Core 0091): every failure in one place, filtered here; the number in
       full to try it in the lab. One request for 30 days, then filters on the phone (no request per filter). -->
  <div class="card column gap-sm">
    <div class="row items-center">
      <div class="col text-weight-bold">العمليات الفاشلة</div>
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="state === 'busy'" @click="load" />
    </div>
    <div v-if="state === 'failed'" class="small text-negative">لم تصل · <a href="#" @click.prevent="load">أعد المحاولة</a> (طبّق 0091 إن لم تفعل)</div>

    <div class="chips">
      <q-btn v-for="p in PERIODS" :key="p.id" rounded dense no-caps size="sm" :unelevated="period === p.id" :outline="period !== p.id"
        :color="period === p.id ? 'primary' : 'grey-8'" :label="p.label" @click="period = p.id" />
    </div>
    <div class="chips">
      <q-btn v-for="o in operators" :key="o" rounded dense no-caps size="sm" :unelevated="operator === o" :outline="operator !== o"
        :color="operator === o ? 'primary' : 'grey-8'" :label="OPERATORS[o] || o" @click="operator = operator === o ? null : o" />
    </div>
    <!-- Owner 2026-10-30: two short lists instead of twenty buttons -->
    <div class="row no-wrap gap-sm">
      <q-select v-model="reason" class="col" dense outlined clearable emit-value map-options :options="reasonOptions" label="السبب" />
      <q-select v-model="sim" class="col" dense outlined clearable :options="sims" label="الشريحة" />
    </div>
    <q-toggle v-model="withDiscovery" dense size="sm" label="أظهر الاستكشاف أيضًا (بلا مال، ينتهي «لم تُرسل» عمدًا)" class="small" />
    <q-input v-model="search" dense outlined clearable inputmode="tel" placeholder="ابحث برقم" />

    <div class="tiles">
      <div class="tile"><div class="n">{{ shown.length }}</div><div class="small">فشلت ({{ periodLabel }})</div></div>
      <div class="tile"><div class="n">{{ countDay(0) }} · {{ countDay(1) }}</div><div class="small">اليوم · أمس</div></div>
      <div class="tile"><div class="n small-n">{{ top(shown, (x) => familyOf(x.code).label) || '—' }}</div><div class="small">أكثر سبب</div></div>
      <div class="tile"><div class="n small-n">{{ top(shown, (x) => x.sim) || '—' }}</div><div class="small">أكثر شريحة</div></div>
    </div>

    <div v-if="state !== 'busy' && !open.length" class="small muted">لا فشل بلا حل بهذه الفلاتر ✓</div>
    <!-- Unsolved first (owner 2026-10-30: «ما بقي بلا حل في مكان مرتفع»), each with its next step -->
    <div v-for="(x, i) in open.slice(0, limit)" :key="i" class="op">
      <div class="row items-center no-wrap gap-sm">
        <span class="small muted">{{ when(x.at) }}</span>
        <span class="col text-weight-bold ltr phone">{{ x.phone || '—' }}</span>
        <q-btn v-if="x.phone" flat round dense size="sm" icon="content_copy" aria-label="نسخ الرقم" @click="copy(x.phone)" />
      </div>
      <div class="small">
        {{ OPERATORS[x.operator] || x.operator }} · {{ x.offer || (x.amount ? x.amount + ' دج' : '') }}
        <span v-if="x.sim"> · {{ x.sim }}</span>
      </div>
      <div class="small text-negative">{{ STATUS[x.status] || x.status }} · {{ familyOf(x.code).label }}</div>
      <div v-if="x.code" class="tiny muted ltr">{{ x.code }}</div>
      <div class="small next">➜ {{ nextOf(x).text }}</div>
      <div class="row gap-sm">
        <q-btn v-if="x.phone && nextOf(x).lab" outline dense no-caps size="sm" color="deep-orange" icon="science" label="جرّب في المختبر" @click="toLab(x)" />
        <q-btn v-if="x.phone && nextOf(x).rediscover" outline dense no-caps size="sm" color="primary" icon="travel_explore" label="أعد استكشاف الخط"
          :loading="forgetting === x.phone" @click="rediscover(x)" />
        <q-btn v-if="nextOf(x).to" outline dense no-caps size="sm" color="primary" icon="open_in_new" :label="nextOf(x).toLabel" :to="nextOf(x).to" />
      </div>
    </div>
    <q-btn v-if="open.length > limit" flat dense no-caps color="primary" :label="`أظهر المزيد (${open.length - limit})`" @click="limit += 30" />

    <!-- Solved: by what, folded -->
    <q-expansion-item v-if="solved.length" dense icon="task_alt" :label="`حُلّت (${solved.length})`" header-class="text-weight-medium q-px-none">
      <div v-for="(x, i) in solved.slice(0, 60)" :key="i" class="op small">
        <span class="muted">{{ when(x.at) }}</span> · <span class="ltr">{{ x.phone }}</span> · {{ familyOf(x.code).label }}
        <div class="text-positive">✓ {{ SOLVED[x.solved] || x.solved }}</div>
      </div>
    </q-expansion-item>

    <q-expansion-item dense icon="sim_card_alert" :label="`القراءات الآلية الفاشلة لشرائحنا (${readsShown.length})`" header-class="text-weight-medium q-px-none">
      <div v-for="(x, i) in readsShown.slice(0, 40)" :key="i" class="row no-wrap gap-sm small op">
        <span class="muted">{{ when(x.at) }}</span><span class="col text-weight-bold">{{ x.sim }}</span><span>{{ x.reason }}</span>
      </div>
    </q-expansion-item>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { copyToClipboard, Notify } from 'quasar'
import { useRouter } from 'vue-router'
import * as flexy from 'src/api/flexy'

const PERIODS = [{ id: 'today', label: 'اليوم' }, { id: 'yesterday', label: 'أمس' }, { id: 7, label: '7 أيام' }, { id: 30, label: '30 يومًا' }]
const OPERATORS = { mobilis: 'موبيليس', djezzy: 'جيزي', ooredoo: 'أوريدو' }
const STATUS = { failed: 'فشلت', rejected: 'رُفضت', not_sent: 'لم تُرسل' }
// The network's and the program's codes in seven Arabic families (owner 2026-10-30: «رموز إنجليزية لا تُقرأ»);
// the code itself stays small under each operation
const FAMILIES = [
  { id: 'no_response', label: 'الشبكة لم ترد', test: /NO_RESPONSE|HiLinkUssdError|PROBE_NOT_DELIVERED/ },
  { id: 'no_sim', label: 'لا شريحة جاهزة', test: /^NO_.*READY|NO_SIM_READY|AGENT_MODEM_BUSY|AGENT_UPDATING/ },
  { id: 'previous', label: 'تحويل سابق للرقم لم يُحسم أو قريب جدًا', test: /PREVIOUS_TRANSFER/ },
  { id: 'pin', label: 'مشكلة الرمز PIN', test: /PIN_PROMPT|PIN_UNCONFIRMED|PIN_REJECTED/ },
  { id: 'unexpected', label: 'رد غير متوقع من الشبكة', test: /NEW_REPLY|LOAN_QUESTION|SIM_LANGUAGE/ },
  { id: 'busy', label: 'الرقم مشغول أو صعوبات الشبكة', test: /PHONE_BUSY|TECHNICAL_DIFFICULTIES|NETWORK_REJECTED/ },
  { id: 'stuck', label: 'عالقة، أُغلقت بلا مال', test: /STUCK_CLOSED/ }
]
const OTHER = { id: 'other', label: 'أخرى' }
const familyOf = (code) => (code ? FAMILIES.find((f) => f.test.test(code)) || OTHER : OTHER)
// Discoveries and probes end «not sent» on purpose: not failures unless asked
const isDiscovery = (x) => /\.(discover|probe)\./.test(x.op || '') || /DISCOVERED|PROBED|LINE_GROUP_CHANGED/.test(x.code || '')

const ops = ref([])
const reads = ref([])
const state = ref('')
const period = ref('today')
const operator = ref(null)
const sim = ref(null)
const reason = ref(null)
const router = useRouter()
// How a failure was solved (Flexy Core 0093)
const SOLVED = {
  later_success: 'نجحت عملية لاحقة للرقم نفسه',
  learned: 'تعلّم البرنامج أن هذا الخط لا يقبل العرض: يحذّر في الإرسال القادم',
  judged: 'حكمتَ عليها',
  sim_back: 'الشريحة رجعت تنجح بعدها'
}
const open = computed(() => shown.value.filter((x) => !x.solved))
const solved = computed(() => shown.value.filter((x) => x.solved))
// The next step of each family (owner 2026-10-30: «يقترح لي: اذهب إلى المختبر وجرّب»)
function nextOf (x) {
  const f = familyOf(x.code).id
  if (/TRANSACTION_FAILED|FAILURE_SMS/.test(x.code || '')) return { text: 'الخط لا يقبل هذا العرض على الأرجح: جرّبه في المختبر، أو أعد استكشاف الخط، أو جرّب عرضًا آخر', lab: true, rediscover: true }
  if (f === 'no_response') return { text: 'الشبكة لم ترد: أعد المحاولة بعد دقائق', lab: true }
  if (f === 'no_sim') return { text: 'لا شريحة جاهزة: انظر الشرائح', to: '/flexy/devices', toLabel: 'الأجهزة' }
  if (f === 'pin') return { text: 'افحص رمز PIN الشريحة', to: '/flexy/devices', toLabel: 'الأجهزة' }
  if (f === 'previous') return { text: 'احكم على العملية السابقة للرقم أولًا («تحتاج حكمك»)' }
  if (f === 'unexpected') return { text: 'رد لا يعرفه البرنامج: علّمه إياه', to: '/flexy/send', toLabel: 'الردود الجديدة', lab: true }
  if (f === 'busy') return { text: 'الرقم مشغول أو الشبكة متعبة: أعد بعد قليل', lab: true }
  return { text: 'جرّبه في المختبر لترى رد الشبكة', lab: true }
}
function toLab (x) {
  router.push({ path: '/flexy', query: { lab_phone: x.phone, lab_offer: x.offer || '', lab_route: /arsselli/.test(x.op || '') ? 'arsselli' : /sama/.test(x.op || '') ? 'sama' : '' } })
}
const forgetting = ref('')
async function rediscover (x) {
  forgetting.value = x.phone
  try {
    const r = await flexy.numberForget(x.phone)
    if (r.status !== 200 || r.body?.ok === false) throw new Error(r.body?.error || 'FLEXY_CORE')
    Notify.create({ type: 'positive', message: 'نُسي الخط: يُستكشف من جديد في الإرسال القادم', position: 'top' })
  } catch (e) {
    Notify.create({ type: 'negative', message: 'لم يُنسَ: ' + (e.message || ''), position: 'top' })
  } finally {
    forgetting.value = ''
  }
}
const withDiscovery = ref(false)
const search = ref('')
const limit = ref(30)

// Days by the phone's calendar (Algeria): 0 = today, 1 = yesterday
const dayIndex = (t) => { const d = new Date(t); const now = new Date(); d.setHours(0, 0, 0, 0); now.setHours(0, 0, 0, 0); return Math.round((now - d) / 86400000) }
const inPeriod = (t) => { const i = dayIndex(t); return period.value === 'today' ? i === 0 : period.value === 'yesterday' ? i === 1 : i < period.value }
const periodLabel = computed(() => PERIODS.find((p) => p.id === period.value)?.label)
const inScope = computed(() => ops.value.filter((x) => inPeriod(x.at) && (withDiscovery.value || !isDiscovery(x))))
const shown = computed(() => {
  const q = (search.value || '').replace(/\D/g, '')
  return inScope.value.filter((x) => (!operator.value || x.operator === operator.value) && (!sim.value || x.sim === sim.value) &&
    (!reason.value || familyOf(x.code).id === reason.value) && (!q || String(x.phone || '').replace(/\D/g, '').includes(q)))
})
const operators = computed(() => [...new Set(inScope.value.map((x) => x.operator).filter(Boolean))])
const sims = computed(() => [...new Set(inScope.value.map((x) => x.sim).filter(Boolean))].sort())
const reasonOptions = computed(() => [...FAMILIES, OTHER]
  .map((f) => ({ value: f.id, label: `${f.label} (${inScope.value.filter((x) => familyOf(x.code).id === f.id).length})` }))
  .filter((o) => !o.label.endsWith('(0)')))
const readsShown = computed(() => reads.value.filter((x) => inPeriod(x.at) && (!sim.value || x.sim === sim.value)))
const countDay = (i) => ops.value.filter((x) => dayIndex(x.at) === i && (withDiscovery.value || !isDiscovery(x))).length
function top (list, key) {
  const n = {}
  for (const x of list) { const k = key(x); if (k) n[k] = (n[k] || 0) + 1 }
  return Object.entries(n).sort((a, b) => b[1] - a[1])[0]?.[0] || ''
}
const when = (t) => { const d = new Date(t); const i = dayIndex(t); const hm = d.toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' }); return i === 0 ? hm : i === 1 ? 'أمس ' + hm : d.toLocaleDateString('ar-DZ', { day: '2-digit', month: '2-digit' }) + ' ' + hm }
async function copy (p) { await copyToClipboard(p); Notify.create({ message: 'نُسخ الرقم', color: 'positive', position: 'top', timeout: 1000 }) }

const withLimit = (p, ms = 15000) => Promise.race([p, new Promise((resolve) => setTimeout(() => resolve(null), ms))])
async function load () {
  if (state.value === 'busy') return
  state.value = 'busy'
  const [a, b] = await Promise.all([withLimit(flexy.runReady('failed_ops')).catch(() => null), withLimit(flexy.runReady('failed_reads')).catch(() => null)])
  if (a?.status === 200 && a.body?.ok) { ops.value = a.body.rows?.[0]?.rows || []; state.value = '' } else state.value = 'failed'
  if (b?.status === 200 && b.body?.ok) reads.value = b.body.rows?.[0]?.rows || []
}
watch(period, () => { operator.value = null; sim.value = null; reason.value = null; limit.value = 30 })
onMounted(load)
</script>

<style scoped>
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.gap-sm { gap: 8px; }
.tiles { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.tile { background: rgba(0, 0, 0, 0.04); border-radius: 12px; padding: 8px 10px; min-width: 0; }
.tile .n { font-size: 20px; font-weight: 700; overflow-wrap: anywhere; }
.tile .small-n { font-size: 14px; }
.op { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 6px 0; min-width: 0; }
.next { color: #1565c0; }
.tiny { font-size: 10px; }
.ltr { direction: ltr; text-align: right; }
.phone { font-size: 16px; letter-spacing: 0.5px; }
body.body--dark .tile { background: rgba(255, 255, 255, 0.06); }
</style>
