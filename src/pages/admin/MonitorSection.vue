<template>
  <div class="column gap-sm">
    <!-- «المراقبة» (owner 2026-10-29, Flexy Core 0068): what needs the owner now, then the balances.
         One request to Flexy Core; refreshed every 30 seconds while this page is open and visible. -->
    <!-- The three tiles filter what is below (owner 2026-10-29): critical or orange alerts only, or the ready SIMs
         with their details. A second press, or ✕, shows everything again. -->
    <div class="counts">
      <button v-for="t in TILES" :key="t.key" type="button" class="count" :class="[t.key, { picked: filter === t.key, dim: filter && filter !== t.key }]"
        :aria-pressed="filter === t.key" @click="pick(t.key)">
        <q-icon name="filter_alt" size="14px" class="funnel" />
        <div class="n">{{ view ? tileCount(t.key) : '—' }}</div><div class="small">{{ t.label }}</div>
      </button>
    </div>
    <div class="row items-center q-mt-sm">
      <div class="col small muted">آخر تحديث {{ view ? clock(view.checked_at) : '—' }}<template v-if="filter"> · <button type="button" class="link text-primary" @click="filter = null">مفلتر: {{ TILES.find((t) => t.key === filter).label }} ✕</button></template></div>
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
    </div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <template v-if="!SIM_FILTERS.has(filter)">
    <!-- «حدث أثناء غيابك» (Flexy Core 0079): what solved itself stays until «رأيته» -->
    <template v-if="unseenIncidents.length">
      <div class="row items-center q-mt-sm">
        <div class="section-title col">حدث أثناء غيابك</div>
        <q-btn flat dense no-caps size="sm" color="primary" label="رأيتها كلها" :loading="seeing === 'all'" @click="seeIncident('all')" />
      </div>
      <div v-for="i in unseenIncidents" :key="i.id" class="card row items-center no-wrap q-gutter-sm">
        <q-icon :name="i.kind === 'sim_back' || i.kind === 'station_restart_back' ? 'sim_card' : i.kind === 'update_failed' ? 'system_update' : i.kind === 'station_restart' ? 'restart_alt' : i.kind === 'station_restart_failed' ? 'usb_off' : i.kind === 'db_load' ? 'storage' : 'power_off'" :color="i.kind === 'site_outage' || i.kind === 'station_restart_failed' ? 'negative' : i.kind === 'station_restart_back' ? 'positive' : 'deep-orange'" size="20px" />
        <div class="col column">
          <span class="text-weight-bold small">{{ i.title }}</span>
          <span class="tiny muted">{{ i.started_at ? when(i.started_at) + (i.ended_at ? ' – ' + when(i.ended_at) : '') : (i.ended_at ? when(i.ended_at) : '') }}</span>
        </div>
        <q-btn flat dense no-caps size="sm" color="primary" label="رأيته" :loading="seeing === i.id" @click="seeIncident(i.id)" />
      </div>
    </template>
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
        <q-btn v-if="['sim_gone', 'no_reply', 'none_ready', 'difference', 'fail_streak', 'station_off', 'all_off'].includes(a.kind)" outline no-caps color="primary"
          :label="a.sim_code ? 'افتح ' + a.sim_code : a.kind === 'station_off' ? 'افتح ' + a.title.replace(' مطفأ', '') : 'المحطات والشرائح'" :to="devicesLink(a)" class="col" />
        <q-btn v-if="a.kind === 'overdue'" outline no-caps color="primary" label="آخر العمليات" to="/flexy/send" class="col" />
        <q-btn v-if="a.kind === 'tick'" outline no-caps color="primary" label="المهام الآلية" to="/flexy/switches" class="col" />
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
      <div class="help small muted q-mt-sm">«تبيع الآن» = متصلة الآن، معتمدة، الـPIN محفوظ، ترد على الشبكة، ورصيدها 100 دج فما فوق. المتصلة التي لا تبيع يظهر سببها في عمود الحالة.</div>
      <!-- Owner 2026-10-29: never one «غير متاح» mixing connected and disconnected SIMs; the online/offline
           filter applies to these cards and their window too (built here from the SIM rows). -->
      <div class="ops q-mt-sm">
        <div v-for="o in cards" :key="o.operator" class="card op" :class="{ bad: o.level === 'down' }">
          <div class="small muted">{{ o.name }} · متاح الآن</div>
          <!-- Owner 2026-10-29: «which SIM holds this?» — pressing it lists the SIMs that sell, each with its reading -->
          <button v-if="filter !== 'offline' && o.selling.length" type="button" class="link big" :class="{ 'text-negative': o.ready === 0 }" @click="openUnavailable(o, 'selling')">{{ money(o.available) }} ‹</button>
          <div v-else class="big" :class="{ 'text-negative': o.ready === 0 && filter !== 'offline' }">{{ filter === 'offline' ? '—' : money(o.available) }}</div>
          <div v-if="o.staleSum" class="small text-negative">منها {{ money(o.staleSum) }} من قراءة قديمة</div>
          <div v-if="o.unknown" class="small text-deep-orange-9">{{ o.unknown }} شريحة تبيع بلا رصيد مقروء</div>
          <div v-if="o.reserved" class="small muted">محجوز {{ money(o.reserved) }}</div>
          <button v-if="o.stuck.length" type="button" class="link small text-deep-orange-9" @click="openUnavailable(o, 'stuck')">
            متصلة لا تبيع {{ money(o.stuckSum) }} · {{ o.stuck.length }} ‹
          </button>
          <button v-if="o.off.length" type="button" class="link small text-negative" @click="openUnavailable(o, 'off')">
            غير متصلة {{ money(o.offSum) }} · {{ o.off.length }} ‹
          </button>
          <div v-if="!o.stuck.length && !o.off.length" class="small text-positive">كل شرائحها تبيع ({{ o.ready }})</div>
          <div class="tiny muted">المجموع {{ money(o.total) }}</div>
          <div v-if="o.ready === 0 && filter !== 'offline'" class="small text-negative text-weight-bold">حرج: لا شريحة تبيع</div>
        </div>
      </div>
      <div class="small muted q-mt-xs"><span class="dot ok" /> متصلة الآن · <span class="dot down" /> غير متصلة (منزوعة أو الكمبيوتر مطفأ). «متاح الآن» = شرائح معتمدة ومتصلة وترد، ناقص المحجوز في عمليات جارية. الحرج أقل من {{ money(view?.limits.critical || 2000) }}، وقبل الحرج أقل من {{ money(view?.limits.beforeCritical || 4000) }}.</div>

      <div class="card q-mt-sm q-pa-none sims">
        <div class="sim head small"><span>الشريحة</span><span>الرصيد</span><span>المتاح</span><span>الحالة</span></div>
        <div v-for="s in sortedSims" :key="s.sim_uuid" class="sim small">
          <span class="column"><span class="text-weight-bold"><span class="dot" :class="s.online ? 'ok' : 'down'" :title="s.online ? 'متصلة الآن' : 'غير متصلة'" /> {{ s.code || 'شريحة' }}</span>
            <span v-if="!s.online" class="tiny text-negative">غير متصلة<template v-if="s.last_seen_at"> منذ {{ ago(s.last_seen_at).replace('منذ ', '') }}</template></span>
            <span class="tiny muted">{{ [s.station_code, s.usb != null ? 'USB ' + s.usb : null].filter(Boolean).join(' · ') }}<template v-if="s.reserved"> · محجوز {{ money(s.reserved) }}</template></span>
            <!-- The connection log (Flexy Core 0070) -->
            <span v-if="s.outages_7d" class="tiny" :class="s.unstable ? 'text-negative text-weight-bold' : 'text-deep-orange-9'">
              <template v-if="s.unstable">غير مستقرة · </template>انقطعت {{ s.outages_24h }} اليوم · {{ s.outages_7d }} في 7 أيام ({{ s.offline_minutes_7d }} د)</span></span>
          <span class="column"><span>{{ s.balance == null ? '—' : money(s.balance) }}</span>
            <span v-if="s.balance_checked_at" class="tiny" :class="s.stale ? 'text-negative' : 'muted'">قُرئ {{ ago(s.balance_checked_at) }}</span>
            <!-- «الفرق» (Flexy Core 0076): the last reading against what the program sold before it -->
            <span v-if="s.difference" class="tiny" :class="diffClass(s.difference)">{{ diffText(s.difference) }}</span></span>
          <span>{{ s.available == null ? '؟' : money(s.available) }}</span>
          <span :class="s.ready ? 'text-positive' : 'text-negative'">{{ s.ready ? 'تبيع' : !s.online ? 'غير متصلة' : SHORT[s.reason] || 'لا تبيع' }}</span>
        </div>
      </div>
      <!-- The admin phone's SIMs (owner 2026-10-29): the owner's own, never counted with the shops' -->
      <template v-if="view?.admin_sims?.length">
        <div class="section-title q-mt-md">هاتف الإدارة · لا يدخل في أرصدة المحلات</div>
        <div class="card q-pa-none sims">
          <div v-for="s in view.admin_sims" :key="s.sim_uuid" class="sim small">
            <span class="column"><span class="text-weight-bold"><span class="dot" :class="s.online ? 'ok' : 'down'" /> <q-icon name="smartphone" size="14px" /> {{ s.name || s.code || 'شريحة' }}</span>
              <span class="tiny muted">{{ s.operator_name }} · هاتف الإدارة<template v-if="s.name && s.code"> · {{ s.code }}</template></span></span>
            <span class="column"><span>{{ s.balance == null ? '—' : money(s.balance) }}</span>
              <span v-if="s.balance_checked_at" class="tiny muted">قُرئ {{ ago(s.balance_checked_at) }}</span></span>
            <span />
            <span class="muted">للإدارة فقط</span>
          </div>
        </div>
      </template>
    </template>
    <div v-else class="card q-mt-sm small muted">
      {{ tab === 'stock' ? 'المخزون (أيام التغطية لكل منتج وبطاقات التعبئة)' : 'الأكثر استهلاكًا (اليوم، 7 أيام، 30 يومًا)' }}: المرحلة التالية، بعد الأرصدة.
    </div>

    <q-dialog v-model="unavailableOpen">
      <q-card v-if="picked" style="min-width: 300px">
        <q-card-section class="column q-gutter-xs">
          <div class="text-weight-bold">{{ picked.name }} · {{ picked.which === 'off' ? 'غير متصلة' : picked.which === 'selling' ? 'متاح الآن' : 'متصلة لا تبيع' }}</div>
          <!-- Owner 2026-10-29: the amount is money still inside a SIM that cannot send now, not money available -->
          <div v-if="picked.which === 'selling'" class="help small muted">الشرائح التي تبيع الآن ورصيد كل واحدة: آخر قراءة ناقص ما باعه البرنامج منها بعدها.</div>
          <div v-else class="small muted">{{ picked.which === 'off' ? 'رصيد في شرائح لا يراها الكمبيوتر الآن (منزوعة، أو المودم أو الكمبيوتر مطفأ).' : 'رصيد في شرائح متصلة لكنها لا تبيع، والسبب تحت كل واحدة.' }} لا يدخل في «متاح الآن».</div>
        </q-card-section>
        <q-card-section class="column q-gutter-sm q-pt-none">
          <div v-for="s in pickedSims" :key="s.sim_uuid" class="column">
            <div class="row"><b class="col"><span class="dot" :class="s.online ? 'ok' : 'down'" /> {{ s.code || 'شريحة' }}<span class="small" :class="s.online ? 'text-positive' : 'text-negative'"> · {{ s.online ? 'متصلة' : 'غير متصلة' }}</span></b><span class="column items-end"><span>{{ s.balance == null ? '—' : money(s.balance) }}</span>
              <span class="tiny" :class="s.stale ? 'text-negative' : 'muted'">{{ picked.which === 'selling' ? 'رصيدها' : 'رصيدها المحفوظ' }}<template v-if="s.balance_checked_at">، قُرئ {{ ago(s.balance_checked_at) }}</template><template v-else>، لم يُقرأ</template><template v-if="s.stale"> · قراءة قديمة</template></span></span></div>
            <div class="tiny muted">{{ [s.station_code, s.usb != null ? 'USB ' + s.usb : null].filter(Boolean).join(' · ') }}<template v-if="s.spent_since_read || s.topup_since_read"> · آخر قراءة {{ money(s.balance_read) }}<template v-if="s.spent_since_read">، بيع بعدها {{ money(s.spent_since_read) }}</template><template v-if="s.topup_since_read">، شحن +{{ money(s.topup_since_read) }} (من رسالته)</template></template><template v-if="s.reserved"> · محجوز {{ money(s.reserved) }}</template></div>
            <div v-if="s.reason_text" class="small text-negative">السبب: {{ s.reason_text }}</div>
          </div>
        </q-card-section>
        <q-card-actions align="left">
          <q-btn flat no-caps color="primary" label="المحطات والشرائح" to="/flexy/devices" />
          <q-btn flat no-caps color="primary" label="إغلاق" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import { useBell } from 'src/composables/useBell'

const KIND = { station_off: 'كمبيوتر', all_off: 'كمبيوتر', sim_gone: 'أجهزة', no_reply: 'أجهزة', none_ready: 'أجهزة', low_balance: 'رصيد', unavailable: 'المحلات', difference: 'مال', overdue: 'مال', tick: 'البرنامج', fail_streak: 'أجهزة' }
const SHORT = {
  NOT_APPROVED: 'غير معتمدة', NO_PIN: 'بلا PIN', STATION_OFF: 'الكمبيوتر مطفأ', STATION_NOT_APPROVED: 'كمبيوتر غير معتمد',
  MODEM_MISSING: 'المودم غائب', SIM_MISSING: 'غائبة', NO_REPLY: 'لا ترد', EMPTY: 'الرصيد نفد'
}

const { refreshBell } = useBell()
// The alert's SIM or computer opened on the devices page (owner 2026-10-30)
const devicesLink = (a) => a.sim_code ? { path: '/flexy/devices', query: { sim: a.sim_code } } : a.kind === 'station_off' ? { path: '/flexy/devices', query: { station: a.title.replace(' مطفأ', '') } } : '/flexy/devices'
const view = ref(null)
const busy = ref(false)
const error = ref('')
const acking = ref('')
const tab = ref('balances')
const picked = ref(null)
const unavailableOpen = ref(false)

// «متصلة» / «غير متصلة» (owner 2026-10-29): what is really connected now, whatever its other state
const TILES = [{ key: 'down', label: 'حرج' }, { key: 'warn', label: 'قبل الحرج' }, { key: 'ok', label: 'تبيع الآن' },
  { key: 'online', label: 'متصلة' }, { key: 'offline', label: 'غير متصلة' }]
const SIM_FILTERS = new Set(['ok', 'online', 'offline'])
function tileCount (key) {
  const sims = view.value?.sims || []
  if (key === 'online') return sims.filter((s) => s.online).length
  if (key === 'offline') return sims.filter((s) => !s.online).length
  return view.value?.counts[key] ?? 0
}
const filter = ref(null)
function pick (key) {
  filter.value = filter.value === key ? null : key
  if (SIM_FILTERS.has(key) && filter.value) tab.value = 'balances'
}
const unseenIncidents = computed(() => (view.value?.incidents || []).filter((i) => !i.seen))
const seeing = ref(null)
const when = (t) => new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' })
async function seeIncident (id) {
  seeing.value = id
  try {
    const res = await flexy.ownerIncidentSeen(id)
    if (res.status === 200 && res.body?.ok) view.value = res.body
  } finally { seeing.value = null }
}
const shownAlerts = computed(() => (view.value?.alerts || []).filter((a) => !filter.value || SIM_FILTERS.has(filter.value) || a.level === filter.value))
const sortedSims = computed(() => [...(view.value?.sims || [])].filter((s) => (filter.value === 'ok' ? s.ready : filter.value === 'online' ? s.online : filter.value === 'offline' ? !s.online : true)).sort((a, b) =>
  (a.ready === b.ready ? 0 : a.ready ? 1 : -1) || (a.approved === b.approved ? 0 : a.approved ? -1 : 1) || String(a.code).localeCompare(String(b.code))))
// The SIMs the filter keeps (online / offline), the cards and the window are built from them
const filteredSims = computed(() => (view.value?.sims || []).filter((s) => filter.value === 'online' ? s.online : filter.value === 'offline' ? !s.online : true))
const sum = (xs, f) => xs.reduce((a, x) => a + (Number(f(x)) || 0), 0)
const cards = computed(() => (view.value?.operators || []).map((o) => {
  const mine = filteredSims.value.filter((s) => s.operator === o.operator)
  const selling = mine.filter((s) => s.ready)
  const stuck = mine.filter((s) => !s.ready && s.online)
  const off = mine.filter((s) => !s.online)
  return {
    operator: o.operator, name: o.name, level: o.level, ready: selling.length,
    available: sum(selling, (s) => s.available), reserved: sum(selling, (s) => s.reserved), unknown: selling.filter((s) => s.available == null).length,
    stuck, stuckSum: sum(stuck, (s) => s.balance), off, offSum: sum(off, (s) => s.balance), total: sum(mine, (s) => s.balance),
    selling, staleSum: sum(selling.filter((s) => s.stale), (s) => s.available)
  }
}).filter((c) => c.stuck.length + c.off.length + c.ready > 0))
const pickedSims = computed(() => (picked.value ? picked.value.list : []))

const clock = (t) => new Date(t).toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
// The SIM ledger's last close: 0 = what was sold explains the reading; an amount = what it does not
function diffText (d) {
  if (d.state === 'matched') return 'الفرق: 0 ✓'
  if (d.state === 'difference' && d.amount != null) return 'الفرق: ' + (d.amount > 0 ? 'نقص ' : 'زاد ') + money(Math.abs(d.amount))
  if (d.state === 'first') return 'أول قراءة'
  return d.state === 'unreadable' ? 'الفرق: قراءة غير مقروءة' : 'الفرق: غير محسوم'
}
const diffClass = (d) => (d.state === 'matched' || d.state === 'first' ? 'text-positive' : d.state === 'difference' ? 'text-negative text-weight-bold' : 'text-deep-orange-9')
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
function openUnavailable (o, which) {
  picked.value = { ...o, which, list: which === 'off' ? o.off : which === 'selling' ? o.selling : o.stuck }
  unavailableOpen.value = true
}

let timer = null
// A tab of «المراقبة والإحصائيات»: asks every 30 s only while its tab is the one shown
const props = defineProps({ active: { type: Boolean, default: true } })
watch(() => props.active, (a) => { if (a) load() })
onMounted(() => {
  load()
  timer = setInterval(() => { if (document.visibilityState === 'visible' && props.active) load() }, 30000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<style scoped>
.counts { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 8px; }
.counts .count { grid-column: span 2; }
.counts .count.online, .counts .count.offline { grid-column: span 3; }
.count.online { background: #DCFCE7; color: #166534; }
.count.offline { background: #FEE2E2; color: #991B1B; }
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
