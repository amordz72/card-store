<template>
  <q-page class="page">
    <!-- One request to Flexy Core; refreshed every 30 seconds while this page is open and visible -->
    <div class="card column q-gutter-sm">
      <div class="row items-center q-gutter-sm">
        <div class="col section-title">الحالة الآن</div>
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
      </div>
      <div v-if="tree" class="grid-3">
        <div v-for="l in ['down', 'warn', 'ok']" :key="l" class="count" :class="'count-' + l">
          <span class="big">{{ tree.summary[l] }}</span>
          <span class="small">{{ LEVEL[l].label }}</span>
        </div>
      </div>
      <div v-if="tree" class="small muted">آخر تحديث {{ clock(tree.checked_at) }} · غائب بعد {{ tree.limits.absentMinutes }} دقيقة · معطّل بعد {{ tree.limits.ussdTimeouts }} مهل USSD</div>
      <div v-if="error" class="small text-negative">{{ error }}</div>
    </div>

    <div v-for="st in current" :key="st.station_uuid" class="card q-pa-none">
      <div class="station">
        <div class="row items-center no-wrap q-gutter-sm">
          <q-icon name="computer" size="20px" />
          <span class="col text-weight-bold">{{ st.code || 'كمبيوتر' }}<span v-if="st.label" class="muted"> · {{ st.label }}</span></span>
          <q-badge :color="LEVEL[st.level].color" :label="LEVEL[st.level].label" />
        </div>
        <div class="small muted">{{ st.computer_name }} · Agent {{ st.agent_version || '—' }} · {{ st.absent_minutes ? 'آخر ظهور ' + clock(st.last_seen_at) : 'متصل' }}</div>
        <!-- Moving station by station to the core's gateway (step 2) -->
        <div v-if="st.gateway" class="small">البوابة: <q-badge :color="st.gateway === 'core' ? 'primary' : 'grey-6'" :label="st.gateway === 'core' ? 'النواة' : 'القديمة'" /></div>
        <div v-for="r in st.reasons" :key="r.code" class="small" :class="r.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ r.text }}</div>
        <!-- Agent updates: the computer's updater applies them and rolls back by itself -->
        <div v-if="updates" class="row items-center q-gutter-xs q-mt-xs">
          <template v-if="active(st)">
            <q-badge color="info" :label="UPDATE_STATUS[active(st).status]" />
            <span class="small muted">{{ updateLabel(active(st)) }}</span>
            <q-btn v-if="active(st).status === 'pending'" flat dense no-caps size="sm" color="negative" label="إلغاء" :loading="busy" @click="cancel(active(st))" />
          </template>
          <template v-else-if="!st.absent_minutes">
            <q-btn v-if="latest && latest.agent_version !== st.agent_version" outline dense no-caps size="sm" color="primary" :label="'حدّث إلى ' + latest.agent_version" :loading="busy" @click="askRelease(st)" />
            <q-btn v-if="st.gateway === 'old'" outline dense no-caps size="sm" color="primary" label="انقل إلى بوابة النواة" :loading="busy" @click="askGateway(st, 'flexy-gateway')" />
            <q-btn v-if="st.gateway === 'core'" flat dense no-caps size="sm" color="grey-8" label="أرجع إلى البوابة القديمة" :loading="busy" @click="askGateway(st, 'station-gateway')" />
          </template>
        </div>
        <div v-if="last(st) && !active(st)" class="small" :class="last(st).status === 'succeeded' ? 'text-positive' : last(st).status === 'cancelled' ? 'muted' : 'text-deep-orange'">
          آخر تحديث: {{ updateLabel(last(st)) }} · {{ UPDATE_STATUS[last(st).status] }}<span v-if="last(st).error"> ({{ last(st).error }})</span>
        </div>
      </div>

      <button v-for="m in live(st)" :key="m.modem_uuid || m.ip" type="button" class="modem" @click="open(st, m)">
        <span class="column items-start">
          <span class="row items-center q-gutter-xs">
            <bdi class="ltr text-weight-bold">{{ m.ip || '—' }}</bdi>
            <span v-if="m.usb != null" class="small muted">· USB {{ m.usb }}</span>
          </span>
          <span class="small">{{ simLine(m) }}</span>
          <span v-if="m.reasons.length" class="small" :class="m.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ m.reasons[0].text }}<bdi v-if="m.reasons.length > 1" class="ltr q-ml-xs"> (+{{ m.reasons.length - 1 }})</bdi></span>
        </span>
        <q-badge :color="LEVEL[m.level].color" :label="LEVEL[m.level].label" />
      </button>
      <div v-if="!live(st).length" class="small muted q-pa-md">لا موديمات حديثة</div>

      <q-expansion-item v-if="old(st).length" dense switch-toggle-side :label="`قديمة (${old(st).length})`" header-class="small muted">
        <button v-for="m in old(st)" :key="m.modem_uuid || m.ip" type="button" class="modem" @click="open(st, m)">
          <span class="column items-start">
            <bdi class="ltr">{{ m.ip || '—' }}</bdi>
            <span class="small muted">{{ simLine(m) }} · آخر ظهور {{ clock(m.last_seen_at) }}</span>
          </span>
          <q-badge :color="LEVEL.old.color" :label="LEVEL.old.label" />
        </button>
      </q-expansion-item>
    </div>

    <q-expansion-item v-if="gone.length" class="card q-pa-none" dense switch-toggle-side :label="`كمبيوترات غائبة منذ مدة (${gone.length})`" header-class="small muted">
      <div v-for="st in gone" :key="st.station_uuid" class="op-row">
        <span class="text-weight-bold">{{ st.code || 'كمبيوتر' }}</span>
        <span class="small muted">{{ st.computer_name }} · آخر ظهور {{ clock(st.last_seen_at) }}</span>
      </div>
    </q-expansion-item>

    <div v-if="tree && !tree.stations.length" class="card text-center muted">لا كمبيوترات مسجّلة</div>

    <q-dialog v-model="details">
      <q-card v-if="picked" style="min-width: 300px; max-width: 420px">
        <q-card-section class="row items-center q-gutter-sm">
          <span class="col text-weight-bold"><bdi class="ltr">{{ picked.m.ip || '—' }}</bdi> · {{ picked.st.code }}</span>
          <q-badge :color="LEVEL[picked.m.level].color" :label="LEVEL[picked.m.level].label" />
        </q-card-section>
        <q-card-section class="column q-gutter-xs q-pt-none">
          <div v-for="r in picked.m.reasons" :key="r.code" :class="r.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ r.text }}</div>
          <div v-if="!picked.m.reasons.length" class="text-positive">جاهز</div>
        </q-card-section>
        <q-separator />
        <q-card-section class="kv">
          <span class="muted">الموديم</span><span>{{ picked.m.model || '—' }} · USB {{ picked.m.usb ?? '—' }}</span>
          <span class="muted">آخر ظهور</span><span>{{ picked.m.last_seen_at ? clock(picked.m.last_seen_at) : '—' }}</span>
          <template v-if="picked.m.sim">
            <span class="muted">الشريحة</span><span>{{ picked.m.sim.code || 'بلا اسم' }}<span v-if="picked.m.sim.label"> · {{ picked.m.sim.label }}</span></span>
            <span class="muted">النوع</span><span>{{ picked.m.sim.sim_type_name }} · {{ picked.m.sim.approved ? 'معتمدة' : 'غير معتمدة' }}</span>
            <span class="muted">PIN</span><span>{{ picked.m.sim.pin_present ? 'محفوظ' : 'غير محفوظ' }}</span>
            <span class="muted">ICCID</span><bdi class="ltr">…{{ picked.m.sim.iccid_tail || '—' }}</bdi>
            <span class="muted">الرقم</span><bdi class="ltr">…{{ picked.m.sim.msisdn_tail || '—' }}</bdi>
          </template>
          <template v-else>
            <span class="muted">الشريحة</span><span>لا شريحة</span>
          </template>
          <span class="muted">آخر نجاح USSD</span><span>{{ picked.m.ussd.lastSuccessAt ? clock(picked.m.ussd.lastSuccessAt) : 'لا يوجد' }}</span>
          <span class="muted">آخر محاولة</span><span>{{ picked.m.ussd.lastAttemptAt ? clock(picked.m.ussd.lastAttemptAt) : 'لا يوجد' }}</span>
          <span class="muted">مهل متتالية</span><span>{{ picked.m.ussd.timeoutsInRow }}</span>
        </q-card-section>
        <q-card-section class="small muted q-pt-none">الشبكة والإشارة وحالة الشريحة تظهر بعد تحديث الـAgent.</q-card-section>
        <q-card-actions align="right"><q-btn flat no-caps label="إغلاق" v-close-popup /></q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Dialog } from 'quasar'
import * as flexy from 'src/api/flexy'
import { useBell } from 'src/composables/useBell'

// Read only: Flexy Core answers from what the stations already report. No USSD, no money.
const LEVEL = {
  down: { label: '⛔ معطّل', color: 'negative' },
  warn: { label: '⚠️ تحذير', color: 'orange-8' },
  ok: { label: '✅ جاهز', color: 'positive' },
  old: { label: 'قديم', color: 'grey-6' }
}
// The bell's count follows this page without a second request
const { devicesDown } = useBell()
const tree = ref(null)
const error = ref('')
const busy = ref(false)
const clock = (t) => new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' })

const current = computed(() => (tree.value?.stations || []).filter((s) => s.level !== 'old'))
const gone = computed(() => (tree.value?.stations || []).filter((s) => s.level === 'old'))
const live = (st) => st.modems.filter((m) => m.level !== 'old')
const old = (st) => st.modems.filter((m) => m.level === 'old')
function simLine (m) {
  if (m.unreachable && !m.sim) return 'لا ترد صفحته'
  if (!m.sim) return 'لا شريحة'
  return (m.sim.code || 'شريحة بلا اسم') + ' · ' + m.sim.sim_type_name
}

// Agent updates (owner 2026-10-25): one request per computer at a time
const UPDATE_STATUS = {
  pending: 'في الانتظار',
  claimed: 'جارٍ على الكمبيوتر',
  succeeded: 'تم',
  failed: 'فشل، لم يتغيّر شيء',
  rolled_back: 'رجع وحده إلى السابق',
  cancelled: 'أُلغي'
}
const GATEWAYS = { 'flexy-gateway': 'بوابة النواة', 'station-gateway': 'البوابة القديمة' }
const FUNCTIONS = 'https://wqyebqzbbpohbnznqdjj.supabase.co/functions/v1/'
const updates = ref(null)
const latest = computed(() => updates.value?.releases?.[0] || null)
const last = (st) => (updates.value?.stations || []).find((x) => x.station_uuid === st.station_uuid) || null
const active = (st) => { const u = last(st); return u && (u.status === 'pending' || u.status === 'claimed') ? u : null }
function updateLabel (u) {
  if (u.kind === 'release') return 'إصدار ' + String(u.release).split('+')[0]
  const url = u.config?.SERVER_URL || ''
  return 'نقل إلى ' + (GATEWAYS[url.slice(FUNCTIONS.length)] || 'عنوان آخر')
}
async function loadUpdates () {
  const res = await flexy.ownerUpdates()
  if (res.status === 200 && res.body?.ok) updates.value = res.body
}
async function send (fn) {
  busy.value = true
  try {
    const res = await fn()
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    await loadUpdates()
  } catch (e) {
    error.value = 'لم يُقبل الطلب (' + (e.message || 'FLEXY_CORE') + ').'
  } finally {
    busy.value = false
  }
}
const confirm = (title, message, fn) => Dialog.create({ title, message, cancel: 'لا', ok: 'نعم' }).onOk(() => send(fn))
function askRelease (st) {
  const r = latest.value
  confirm('تحديث ' + (st.code || 'الكمبيوتر'), `يُثبَّت الإصدار ${r.agent_version} حين لا يكون على الكمبيوتر أي USSD. إن لم يتصل الـAgent الجديد خلال 3 دقائق يرجع وحده إلى السابق.`,
    () => flexy.requestUpdate(st.station_uuid, 'release', r.release))
}
function askGateway (st, gateway) {
  confirm('نقل ' + (st.code || 'الكمبيوتر'), `يكلّم الـAgent ${GATEWAYS[gateway]} بعد إعادة تشغيله. إن لم يتصل خلال 3 دقائق يرجع وحده إلى العنوان السابق.`,
    () => flexy.requestUpdate(st.station_uuid, 'config', { SERVER_URL: FUNCTIONS + gateway }))
}
const cancel = (u) => send(() => flexy.cancelUpdate(u.deployment_id))

async function load () {
  if (busy.value) return
  busy.value = true
  try {
    const res = await flexy.ownerDevices()
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    tree.value = res.body
    await loadUpdates().catch(() => {})
    error.value = ''
    devicesDown.value = Number(res.body.summary?.down) || 0
  } catch (e) {
    error.value = 'تعذّرت القراءة من Flexy Core (' + (e.message || 'FLEXY_CORE') + '). تُعرض آخر حالة مقروءة.'
  } finally {
    busy.value = false
  }
}

const details = ref(false)
const picked = ref(null)
function open (st, m) {
  picked.value = { st, m }
  details.value = true
}

// Only while the page is open, and not in a hidden tab
const timer = setInterval(() => { if (document.visibilityState === 'visible') load() }, 30000)
onBeforeUnmount(() => clearInterval(timer))
onMounted(load)
</script>

<style scoped>
.count { border-radius: 12px; padding: 8px; display: flex; flex-direction: column; align-items: center; }
.count .big { font-size: 24px; font-weight: 700; }
.count-down { background: #FEF2F2; color: #B91C1C; }
.count-warn { background: #FFF7ED; color: #C2410C; }
.count-ok { background: #ECFDF3; color: #15803D; }
.station { padding: 12px 14px; display: flex; flex-direction: column; gap: 4px; }
.modem { width: 100%; border: 0; border-top: 1px solid #EEF0F4; background: transparent; padding: 10px 14px; text-align: right; font: inherit; color: inherit; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.op-row { padding: 10px 14px; border-top: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
.kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 12px; }
</style>
