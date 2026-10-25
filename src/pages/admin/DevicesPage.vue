<template>
  <q-page class="page">
    <!-- One request to Flexy Core; refreshed every 30 seconds while this page is open and visible -->
    <div class="card column q-gutter-sm">
      <div class="row items-center q-gutter-sm">
        <div class="col section-title">الحالة الآن</div>
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
      </div>
      <!-- What is connected now, counted for the owner (owner 2026-10-25): zero shows red -->
      <div v-if="tree" class="sum">
        <div v-for="t in summary" :key="t.label" class="tile" :class="{ zero: !t.n }"><div class="n">{{ t.n }}</div><div class="small">{{ t.label }}</div></div>
      </div>
      <div v-if="tree" class="small muted">متصلة الآن · آخر تحديث {{ clock(tree.checked_at) }} · غائب بعد {{ tree.limits.absentMinutes }} دقيقة · معطّل بعد {{ tree.limits.ussdTimeouts }} مهل USSD</div>
      <div v-if="error" class="small text-negative">{{ error }}</div>
    </div>

    <!-- Every SIM in one table, one row each, nothing to open to read it (owner 2026-10-25).
         Connected first; a row opens the SIM's settings only, and closing keeps your place. -->
    <div v-if="tree" class="card q-pa-none">
      <div class="row items-center q-gutter-sm q-pa-sm">
        <q-btn-toggle v-model="tableFilter" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: 'المتصلة', value: 'connected' }, { label: 'الكل', value: 'all' }]" />
        <span class="small muted">{{ connectedRows.length }} متصلة · {{ allRows.length }} في الكل</span>
      </div>
      <div class="table-wrap">
        <table class="sims">
          <thead><tr><th>الشريحة</th><th>الرقم</th><th>الكمبيوتر</th><th>الرصيد</th><th>الحالة</th></tr></thead>
          <tbody>
            <tr v-for="r in tableRows" :key="r.m.sim.sim_uuid" @click="open(r.st, r.m)">
              <td><span class="text-weight-bold">{{ r.m.sim.code || 'جديدة' }}</span><div v-if="r.m.sim.label" class="small muted">{{ r.m.sim.label }}</div><div class="small muted">{{ r.m.sim.sim_type_name }}</div></td>
              <td><bdi class="ltr">{{ r.m.sim.msisdn || (r.m.sim.msisdn_tail ? '…' + r.m.sim.msisdn_tail : '—') }}</bdi></td>
              <td>{{ r.st.code || '—' }}<div class="small muted"><bdi class="ltr">{{ r.m.ip || '—' }}</bdi></div></td>
              <td :class="r.m.sim.balance == null ? 'text-deep-orange' : r.m.sim.balance <= 0 ? 'text-negative' : ''">{{ r.m.sim.balance == null ? 'غير مقروء' : money(r.m.sim.balance) }}</td>
              <td><q-badge :color="LEVEL[r.m.level].color" :label="LEVEL[r.m.level].label" /><div class="small" :class="statusClass(r)">{{ statusText(r) }}</div></td>
            </tr>
            <tr v-if="!tableRows.length"><td colspan="5" class="text-center muted">لا شرائح بهذا الفلتر</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Computers: connected first, one row each, the Agent's update and gateway buttons in the row -->
    <div v-if="tree" class="card q-pa-none">
      <div class="section-title q-pa-sm">الكمبيوترات</div>
      <div class="row items-center q-gutter-sm q-px-sm q-pb-sm">
        <q-btn-toggle v-model="stationFilter" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: 'المتصلة', value: 'present' }, { label: 'الكل', value: 'all' }]" />
        <span class="small muted">{{ presentCount }} متصل · {{ absentCount }} غائب</span>
      </div>
      <div class="table-wrap">
        <table class="sims">
          <thead><tr><th>الجهاز</th><th>الحالة</th><th>الشرائح</th><th>البوابة</th><th>التحديث</th></tr></thead>
          <tbody>
            <tr v-for="st in stationRows" :key="st.station_uuid" class="static">
              <td><span class="text-weight-bold">{{ st.code || 'كمبيوتر' }}</span><span v-if="st.label" class="muted"> · {{ st.label }}</span>
                <div class="small muted">{{ isAbsent(st) ? 'آخر ظهور ' + clock(st.last_seen_at) : 'Agent ' + (st.agent_version || '—') }}</div></td>
              <td><q-badge :color="isAbsent(st) ? 'grey-6' : LEVEL[st.level].color" :label="isAbsent(st) ? 'غائب' : '✅ متصل'" />
                <div v-for="r in isAbsent(st) ? [] : st.reasons" :key="r.code" class="small" :class="r.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ r.text }}</div></td>
              <td>{{ isAbsent(st) ? '—' : simSummary(st) }}</td>
              <td>{{ st.gateway === 'core' ? 'النواة' : st.gateway === 'old' ? 'القديمة' : '—' }}</td>
              <td>
                <template v-if="updates && active(st)">
                  <q-badge color="info" :label="UPDATE_STATUS[active(st).status]" />
                  <div class="small muted">{{ updateLabel(active(st)) }}</div>
                  <q-btn v-if="active(st).status === 'pending'" flat dense no-caps size="sm" color="negative" label="إلغاء" :loading="busy" @click="cancel(active(st))" />
                </template>
                <template v-else-if="updates && !isAbsent(st)">
                  <q-btn v-if="newInMain(st)" outline dense no-caps size="sm" color="primary" :label="'حدّث إلى ' + newInMain(st).main_version" :loading="busy" @click="askRelease(st)" />
                  <span v-else-if="mainOf(st)?.main_error" class="small text-deep-orange">لا يمكن التحديث: {{ MAIN_ERRORS[mainOf(st).main_error] || mainOf(st).main_error }}</span>
                  <span v-else-if="mainOf(st)" class="small muted">على آخر main</span>
                  <div>
                    <q-btn v-if="st.gateway === 'old'" flat dense no-caps size="sm" color="primary" label="انقل إلى بوابة النواة" :loading="busy" @click="askGateway(st, 'flexy-gateway')" />
                    <q-btn v-if="st.gateway === 'core'" flat dense no-caps size="sm" color="grey-8" label="أرجع إلى القديمة" :loading="busy" @click="askGateway(st, 'station-gateway')" />
                  </div>
                </template>
                <span v-else class="small muted">—</span>
                <div v-if="last(st) && !active(st)" class="small" :class="last(st).status === 'succeeded' ? 'text-positive' : last(st).status === 'cancelled' ? 'muted' : 'text-deep-orange'">
                  آخر تحديث: {{ UPDATE_STATUS[last(st).status] }}<span v-if="last(st).error"> ({{ last(st).error }})</span>
                </div>
              </td>
            </tr>
            <tr v-if="!stationRows.length"><td colspan="5" class="text-center muted">لا كمبيوترات بهذا الفلتر</td></tr>
          </tbody>
        </table>
      </div>
    </div>

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
            <span class="muted">الرقم</span><span><bdi class="ltr">{{ picked.m.sim.msisdn || (picked.m.sim.msisdn_tail ? '…' + picked.m.sim.msisdn_tail : '—') }}</bdi> · {{ numberText(picked.m.sim) }}</span>
            <span class="muted">الرصيد</span><span :class="balanceClass(picked.m.sim)">{{ balanceText(picked.m.sim) }}<span v-if="picked.m.sim.balance_checked_at" class="muted"> · قُرئ {{ clock(picked.m.sim.balance_checked_at) }}</span></span>
            <template v-if="onboardingText(picked.m.sim)">
              <span class="muted">الاكتشاف الآلي</span><span :class="onboardingClass(picked.m.sim)">{{ onboardingText(picked.m.sim) }}</span>
            </template>
            <template v-if="noteOf(picked.m.sim)">
              <span class="muted">ملاحظة</span><span>{{ noteOf(picked.m.sim) }}</span>
            </template>
          </template>
          <template v-else>
            <span class="muted">الشريحة</span><span>لا شريحة</span>
          </template>
          <span class="muted">آخر نجاح USSD</span><span>{{ picked.m.ussd.lastSuccessAt ? clock(picked.m.ussd.lastSuccessAt) : 'لا يوجد' }}</span>
          <span class="muted">آخر محاولة</span><span>{{ picked.m.ussd.lastAttemptAt ? clock(picked.m.ussd.lastAttemptAt) : 'لا يوجد' }}</span>
          <span class="muted">مهل متتالية</span><span>{{ picked.m.ussd.timeoutsInRow }}</span>
        </q-card-section>
        <template v-if="picked.m.sim">
          <q-separator />
          <!-- The SIM's settings: a name beside the fixed code, a free note, and the PIN (never shown) -->
          <q-card-section class="column q-gutter-sm">
            <div class="text-weight-bold">إعدادات الشريحة</div>
            <q-input v-model="form.label" dense outlined maxlength="80" label="اسم خاص" :hint="'يظهر بجانب ' + (picked.m.sim.code || 'الاسم الثابت')" />
            <q-input v-model="form.note" dense outlined autogrow maxlength="500" label="ملاحظة" />
            <q-input v-model="form.pin" dense outlined type="password" inputmode="numeric" maxlength="8" autocomplete="off"
              :label="picked.m.sim.pin_present ? 'PIN جديد (اتركه فارغًا لإبقاء المحفوظ)' : 'PIN'" :error="!!form.pin && !/^[0-9]{4,8}$/.test(form.pin)" error-message="4 إلى 8 أرقام" />
            <div v-if="form.error" class="small text-negative">{{ form.error }}</div>
            <div v-if="form.saved" class="small text-positive">حُفظ</div>
          </q-card-section>
        </template>
        <q-card-section class="small muted q-pt-none">الشبكة والإشارة وحالة الشريحة تظهر بعد تحديث الـAgent.</q-card-section>
        <q-card-actions align="right">
          <q-btn v-if="picked.m.sim" unelevated no-caps color="primary" label="حفظ" :loading="form.busy" :disable="!!form.pin && !/^[0-9]{4,8}$/.test(form.pin)" @click="saveSettings" />
          <q-btn flat no-caps label="إغلاق" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Dialog } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
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
const isAbsent = (st) => !!st.absent_minutes
const presentCount = computed(() => current.value.filter((s) => !isAbsent(s)).length)
const absentCount = computed(() => current.value.filter(isAbsent).length + gone.value.length)
// Connected = the modem answers and holds a SIM (ready or with a warning); otherwise not.
const isConnected = (m) => !!m.sim && m.level !== 'down'
// Computers table: connected first; «الكل» adds the absent ones (and those gone for long).
const stationFilter = ref('present')
const stationRows = computed(() => stationFilter.value === 'present'
  ? current.value.filter((st) => !isAbsent(st))
  : [...current.value, ...gone.value])
// The summary: connected computers, and connected SIMs of each type.
const SUMMARY_TYPES = [['mobilis-arsselli', 'أرسلي'], ['mobilis-sama', 'Sama'], ['djezzy-flexy', 'جيزي'], ['ooredoo-flexy', 'أوريدو']]
const summary = computed(() => [
  { label: 'كمبيوتر', n: presentCount.value },
  ...SUMMARY_TYPES.map(([type, label]) => ({ label, n: connectedRows.value.filter((r) => r.m.sim.sim_type === type).length }))
])
// The table: every SIM of a computer still in use; "connected" = its computer present and its modem connected.
const tableFilter = ref('connected')
const allRows = computed(() => current.value.flatMap((st) => st.modems.filter((m) => m.sim && m.level !== 'old').map((m) => ({ st, m }))))
const connectedRows = computed(() => allRows.value.filter((r) => !isAbsent(r.st) && isConnected(r.m)))
const tableRows = computed(() => tableFilter.value === 'connected' ? connectedRows.value : allRows.value)
const statusText = (r) => onboardingText(r.m.sim) || (isAbsent(r.st) ? 'الكمبيوتر غائب' : r.m.reasons[0]?.text) || 'جاهزة'
const statusClass = (r) => onboardingText(r.m.sim) ? onboardingClass(r.m.sim) : r.m.reasons.length || isAbsent(r.st) ? (r.m.level === 'down' ? 'text-negative' : 'text-deep-orange') : 'text-positive'
// Balance: one total the SIM can execute now, with how old the reading is. Old = past the
// core's refresh window (6 h), when a send would first ask for a fresh 632.
const BALANCE_FRESH_MS = 6 * 3600 * 1000
function balanceText (sim) {
  if (sim.balance == null) return 'الرصيد غير مقروء'
  const age = sim.balance_checked_at ? Date.now() - Date.parse(sim.balance_checked_at) : null
  const when = age == null ? '' : age < 3600 * 1000 ? ` · قبل ${Math.max(1, Math.round(age / 60000))} دقيقة` : age < 48 * 3600 * 1000 ? ` · قبل ${Math.round(age / 3600000)} ساعة` : ` · قبل ${Math.round(age / 86400000)} يوم`
  return money(sim.balance) + when
}
function balanceClass (sim) {
  if (sim.balance == null) return 'text-deep-orange'
  const age = sim.balance_checked_at ? Date.now() - Date.parse(sim.balance_checked_at) : Infinity
  return age > BALANCE_FRESH_MS ? 'text-deep-orange' : sim.balance <= 0 ? 'text-negative' : ''
}
const numberText = (sim) => sim.msisdn_source === 'ussd' ? 'الرقم من الشبكة' : sim.msisdn_source === 'manual' ? 'الرقم مكتوب يدويًا' : 'الرقم غير معروف'
function simSummary (st) {
  const ms = live(st)
  const connected = ms.filter(isConnected).length
  const off = ms.length - connected
  if (!ms.length) return 'لا موديمات'
  return `${connected} متصلة` + (off ? ` · ${off} غير متصلة` : '')
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
// What each computer's updater last reported: the version and commit it runs, and main's
const mainOf = (st) => (updates.value?.main || []).find((m) => m.station_uuid === st.station_uuid) || null
// A newer version on main, or the same version at another commit (a fix merged without a bump)
const newInMain = (st) => {
  const m = mainOf(st)
  if (!m || !m.main_version || m.main_error) return null
  return m.main_version !== m.agent_version || (m.main_commit && m.agent_commit && m.main_commit !== m.agent_commit) ? m : null
}
const MAIN_ERRORS = {
  GIT_LOCAL_CHANGES: 'ملفات معدّلة يدويًا على الكمبيوتر',
  GIT_NOT_ON_MAIN: 'الكمبيوتر ليس على فرع main',
  GIT_NOT_AGENT_REPOSITORY: 'المجلد ليس نسخة من المستودع',
  GIT_REMOTE_VERSION_UNREADABLE: 'تعذّرت قراءة الإصدار من main'
}
const last = (st) => (updates.value?.stations || []).find((x) => x.station_uuid === st.station_uuid) || null
const active = (st) => { const u = last(st); return u && (u.status === 'pending' || u.status === 'claimed') ? u : null }
function updateLabel (u) {
  if (u.kind === 'release') return 'إصدار ' + u.release
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
  const m = newInMain(st)
  confirm('تحديث ' + (st.code || 'الكمبيوتر'), `يسحب الكمبيوتر main من GitHub (الإصدار ${m.main_version}) حين لا يكون عليه أي USSD. إن لم يتصل الـAgent الجديد خلال 3 دقائق يرجع وحده إلى السابق.`,
    () => flexy.requestUpdate(st.station_uuid, 'release', m.main_version))
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

// New SIM onboarding (Flexy Core, owner decision 2026-10-25): number → type → first balance → approved.
const ALERTS = {
  NUMBER_NOT_FOUND: 'لم يُكتشف الرقم بعد 3 محاولات',
  PIN_REJECTED: 'الشبكة رفضت الـPIN: أدخل PIN جديدًا',
  TYPE_NOT_CONFIRMED: 'رد الشبكة لا يطابق النوع: حدّد النوع بنفسك',
  BALANCE_NOT_CONFIRMED: 'لم يُؤكَّد أول رصيد'
}
const onboardingOf = (sim) => (tree.value?.onboarding || []).find((o) => o.sim_uuid === sim.sim_uuid) || null
const noteOf = (sim) => onboardingOf(sim)?.note || ''
function onboardingText (sim) {
  const o = onboardingOf(sim)
  if (!o?.stage) return ''
  if (o.stage === 'number') return `يُكتشف الرقم (محاولة ${o.number_tries || 1} من 3)`
  if (o.stage === 'pin_wait') return 'ينتظر PIN منك قبل سؤال الرصيد'
  if (o.stage === 'balance') return 'يُسأل أول رصيد'
  if (o.stage === 'approved') return 'اعتُمدت آليًا بعد أول رصيد'
  if (o.stage === 'balance_only') return 'الرصيد ' + (o.probe_amount != null ? money(o.probe_amount) : 'مقروء') + ' (بلا اعتماد)'
  if (o.stage === 'alert') return '⚠️ ' + (ALERTS[o.alert_code] || o.alert_code)
  return ''
}
const onboardingClass = (sim) => {
  const stage = onboardingOf(sim)?.stage
  return stage === 'alert' ? 'text-negative' : stage === 'approved' ? 'text-positive' : 'text-deep-orange'
}

const details = ref(false)
const picked = ref(null)
const form = ref({ label: '', note: '', pin: '', busy: false, error: '', saved: false })
function open (st, m) {
  picked.value = { st, m }
  form.value = { label: m.sim?.label || '', note: m.sim ? noteOf(m.sim) : '', pin: '', busy: false, error: '', saved: false }
  details.value = true
}
async function saveSettings () {
  const sim = picked.value?.m.sim
  if (!sim || form.value.busy) return
  form.value.busy = true
  form.value.error = ''
  form.value.saved = false
  try {
    const fields = { label: form.value.label, note: form.value.note }
    if (form.value.pin) fields.pin = form.value.pin
    const res = await flexy.saveSimSettings(sim.sim_uuid, fields)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    form.value.pin = ''
    form.value.saved = true
    await load()
  } catch (e) {
    form.value.error = 'لم يُحفظ (' + (e.message || 'FLEXY_CORE') + ')'
  } finally {
    form.value.busy = false
  }
}

// Only while the page is open, and not in a hidden tab
const timer = setInterval(() => { if (document.visibilityState === 'visible') load() }, 30000)
onBeforeUnmount(() => clearInterval(timer))
onMounted(load)
</script>

<style scoped>
.station-row { width: 100%; border: 0; background: transparent; padding: 12px 14px; text-align: right; font: inherit; color: inherit; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.station-row:disabled { cursor: default; opacity: 0.7; }
.station-open { border-bottom: 1px solid #EEF0F4; }
.station { padding: 12px 14px; display: flex; flex-direction: column; gap: 4px; }
.modem { width: 100%; border: 0; border-top: 1px solid #EEF0F4; background: transparent; padding: 10px 14px; text-align: right; font: inherit; color: inherit; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.op-row { padding: 10px 14px; border-top: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
.kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 12px; }
.table-wrap { overflow-x: auto; }
.sims td { white-space: nowrap; }
.sims tbody tr.static { cursor: default; }
.sum { display: flex; gap: 6px; }
.tile { flex: 1 1 0; min-width: 0; background: #F1F8F3; border-radius: 10px; padding: 8px 4px; text-align: center; color: #5B6170; }
.tile .n { font-size: 22px; font-weight: 700; color: #1E8E3E; }
.tile.zero { background: #FDECEA; color: #C62828; }
.tile.zero .n { color: #C62828; }
.sims { width: 100%; border-collapse: collapse; font-size: 14px; }
.sims th { text-align: right; font-weight: 600; color: #5B6170; padding: 8px 10px; border-bottom: 1px solid #E3E6EC; white-space: nowrap; }
.sims td { padding: 8px 10px; border-top: 1px solid #EEF0F4; vertical-align: top; }
.sims tbody tr { cursor: pointer; }
.sims tbody tr:hover { background: #F6F7F9; }
</style>
