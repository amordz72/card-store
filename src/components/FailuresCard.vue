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
      <q-btn v-for="s in sims" :key="s" rounded dense no-caps size="sm" :unelevated="sim === s" :outline="sim !== s"
        :color="sim === s ? 'primary' : 'grey-8'" :label="s" @click="sim = sim === s ? null : s" />
    </div>
    <div class="chips">
      <q-btn v-for="r in reasons" :key="r" rounded dense no-caps size="sm" :unelevated="reason === r" :outline="reason !== r"
        :color="reason === r ? 'primary' : 'grey-8'" :label="reasonOf(r)" @click="reason = reason === r ? null : r" />
    </div>
    <q-input v-model="search" dense outlined clearable inputmode="tel" placeholder="ابحث برقم" />

    <div class="tiles">
      <div class="tile"><div class="n">{{ shown.length }}</div><div class="small">فشلت ({{ periodLabel }})</div></div>
      <div class="tile"><div class="n">{{ countDay(0) }} · {{ countDay(1) }}</div><div class="small">اليوم · أمس</div></div>
      <div class="tile"><div class="n small-n">{{ top(shown, (x) => reasonOf(x.code)) || '—' }}</div><div class="small">أكثر سبب</div></div>
      <div class="tile"><div class="n small-n">{{ top(shown, (x) => x.sim) || '—' }}</div><div class="small">أكثر شريحة</div></div>
    </div>

    <div v-if="state !== 'busy' && !shown.length" class="small muted">لا فشل بهذه الفلاتر.</div>
    <div v-for="(x, i) in shown.slice(0, limit)" :key="i" class="op">
      <div class="row items-center no-wrap gap-sm">
        <span class="small muted">{{ when(x.at) }}</span>
        <span class="col text-weight-bold ltr phone">{{ x.phone || '—' }}</span>
        <q-btn v-if="x.phone" flat round dense size="sm" icon="content_copy" aria-label="نسخ الرقم" @click="copy(x.phone)" />
      </div>
      <div class="small">
        {{ OPERATORS[x.operator] || x.operator }} · {{ x.offer || (x.amount ? x.amount + ' دج' : '') }}
        <span v-if="x.sim"> · {{ x.sim }}</span>
      </div>
      <div class="small text-negative">{{ STATUS[x.status] || x.status }} · {{ reasonOf(x.code) }}</div>
    </div>
    <q-btn v-if="shown.length > limit" flat dense no-caps color="primary" :label="`أظهر المزيد (${shown.length - limit})`" @click="limit += 30" />

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
import * as flexy from 'src/api/flexy'

const PERIODS = [{ id: 'today', label: 'اليوم' }, { id: 'yesterday', label: 'أمس' }, { id: 7, label: '7 أيام' }, { id: 30, label: '30 يومًا' }]
const OPERATORS = { mobilis: 'موبيليس', djezzy: 'جيزي', ooredoo: 'أوريدو' }
const STATUS = { failed: 'فشلت', rejected: 'رُفضت', not_sent: 'لم تُرسل' }
const REASONS = {
  STUCK_CLOSED_NO_MONEY: 'عالقة، أُغلقت بلا مال',
  AGENT_MODEM_BUSY: 'المودم مشغول',
  HiLinkUssdError: 'المودم لا يرد',
  AGENT_UPDATING: 'الكمبيوتر يتحدّث',
  PROBE_NOT_DELIVERED: 'لم تصل للشريحة',
  NO_SIM_READY: 'لا شريحة جاهزة',
  INSUFFICIENT_BALANCE: 'رصيد الشريحة غير كافٍ',
  NETWORK_REJECTED: 'رفض الشبكة',
  PIN_REJECTED: 'الرمز مرفوض'
}
const reasonOf = (c) => (c ? REASONS[c] || c : 'بلا سبب')

const ops = ref([])
const reads = ref([])
const state = ref('')
const period = ref('today')
const operator = ref(null)
const sim = ref(null)
const reason = ref(null)
const search = ref('')
const limit = ref(30)

// Days by the phone's calendar (Algeria): 0 = today, 1 = yesterday
const dayIndex = (t) => { const d = new Date(t); const now = new Date(); d.setHours(0, 0, 0, 0); now.setHours(0, 0, 0, 0); return Math.round((now - d) / 86400000) }
const inPeriod = (t) => { const i = dayIndex(t); return period.value === 'today' ? i === 0 : period.value === 'yesterday' ? i === 1 : i < period.value }
const periodLabel = computed(() => PERIODS.find((p) => p.id === period.value)?.label)
const inScope = computed(() => ops.value.filter((x) => inPeriod(x.at)))
const shown = computed(() => {
  const q = (search.value || '').replace(/\D/g, '')
  return inScope.value.filter((x) => (!operator.value || x.operator === operator.value) && (!sim.value || x.sim === sim.value) &&
    (!reason.value || x.code === reason.value) && (!q || String(x.phone || '').replace(/\D/g, '').includes(q)))
})
const operators = computed(() => [...new Set(inScope.value.map((x) => x.operator).filter(Boolean))])
const sims = computed(() => [...new Set(inScope.value.map((x) => x.sim).filter(Boolean))].sort())
const reasons = computed(() => [...new Set(inScope.value.map((x) => x.code).filter(Boolean))])
const readsShown = computed(() => reads.value.filter((x) => inPeriod(x.at) && (!sim.value || x.sim === sim.value)))
const countDay = (i) => ops.value.filter((x) => dayIndex(x.at) === i).length
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
.ltr { direction: ltr; text-align: right; }
.phone { font-size: 16px; letter-spacing: 0.5px; }
body.body--dark .tile { background: rgba(255, 255, 255, 0.06); }
</style>
