<template>
  <q-page class="page">
    <!-- One request to Flexy Core; refreshed every 30 seconds while this page is open and visible -->
    <div class="card column q-gutter-sm">
      <div class="row items-center q-gutter-sm">
        <div class="col section-title">الحالة الآن</div>
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
      </div>
      <!-- What is connected now, counted for the owner (owner 2026-10-25): zero shows red -->
      <!-- A type's tile filters the SIMs table (funnel icon); the computers tile only counts -->
      <div v-if="tree" class="sum">
        <component :is="t.type ? 'button' : 'div'" v-for="t in summary" :key="t.label" :type="t.type ? 'button' : undefined" class="tile"
          :class="{ zero: !t.n, picked: t.type && typeFilter === t.type }" @click="t.type && pickType(t.type)">
          <q-icon v-if="t.type" name="filter_alt" size="14px" class="funnel" />
          <div class="n">{{ t.n }}</div><div class="small">{{ t.label }}</div>
        </component>
      </div>
      <div v-if="tree" class="small muted">المتصل الآن<template v-if="typeFilter"> · <button type="button" class="link" @click="typeFilter = null">مفلتر: {{ typeName(typeFilter) }} ✕</button></template> · آخر تحديث {{ clock(tree.checked_at) }} · غائب بعد {{ tree.limits.absentMinutes }} دقيقة · معطّل بعد {{ tree.limits.ussdTimeouts }} مهل USSD</div>
      <div v-if="error" class="small text-negative">{{ error }}</div>
    </div>

    <!-- SIMs (owner 2026-10-25, agreed on a picture): the computer first, then active or not inside it.
         Active = its computer present and its modem connected. Gone 7+ days = «قديمة» at the end. -->
    <div v-if="tree" class="card q-pa-none">
      <div class="section-title q-pa-sm">الشرائح</div>
      <div class="row q-gutter-xs q-px-sm">
        <q-btn v-for="c in stationChips" :key="c.value" dense unelevated rounded no-caps size="md" :label="c.label"
          :color="simStation === c.value ? 'primary' : 'white'" :text-color="simStation === c.value ? 'white' : c.muted ? 'grey-6' : 'dark'"
          class="chip" @click="simStation = c.value" />
      </div>
      <div class="sub">
        <q-btn-toggle v-model="simActive" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: `النشطة (${simRows.active.length})`, value: true }, { label: `غير النشطة (${simRows.inactive.length})`, value: false }]" />
      </div>
      <div class="table-wrap">
        <table class="sims">
          <thead><tr><th>الشريحة</th><th>الرقم</th><th>الجهاز</th><th>الرصيد</th><th>الحالة</th></tr></thead>
          <tbody>
            <tr v-for="r in shownSims" :key="r.m.sim.sim_uuid" @click="open(r.st, r.m)">
              <td><span class="text-weight-bold">{{ r.m.sim.code || 'جديدة' }}</span><div class="small muted">{{ r.m.sim.label || r.m.sim.sim_type_name }}</div></td>
              <td><bdi class="ltr">{{ r.m.sim.msisdn || (r.m.sim.msisdn_tail ? '…' + r.m.sim.msisdn_tail : '—') }}</bdi></td>
              <td>{{ r.st.code || '—' }}</td>
              <td :class="r.m.sim.balance == null ? 'text-deep-orange' : r.m.sim.balance <= 0 ? 'text-negative' : ''">{{ r.m.sim.balance == null ? 'غير مقروء' : money(r.m.sim.balance) }}</td>
              <td><q-badge :color="r.old ? 'grey-6' : LEVEL[r.m.level].color" :label="r.old ? 'قديمة' : LEVEL[r.m.level].label" />
                <div v-if="statusText(r)" class="small" :class="statusClass(r)">{{ statusText(r) }}</div></td>
            </tr>
            <tr v-if="!shownSims.length">
              <td colspan="5" class="text-center muted">لا شرائح بهذا الفلتر
                <q-btn v-if="typeFilter || simStation !== 'all'" flat dense no-caps size="sm" color="primary" label="إلغاء الفلاتر" @click="clearFilters" /></td>
            </tr>
            <tr v-if="!simActive && simRows.old.length" class="static">
              <td colspan="5"><button type="button" class="link" @click="showOldSims = !showOldSims">قديمة ({{ simRows.old.length }}) {{ showOldSims ? '▴' : '▾' }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Computers: connected first, one row each, the Agent's update and gateway buttons in the row -->
    <div v-if="tree" class="card q-pa-none">
      <div class="section-title q-pa-sm">الكمبيوترات</div>
      <div class="sub">
        <q-btn-toggle v-model="stationActive" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: `النشطة (${presentCount})`, value: true }, { label: `غير النشطة (${current.length - presentCount})`, value: false }]" />
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
            <tr v-if="!stationActive && gone.length" class="static">
              <td colspan="5"><button type="button" class="link" @click="showOldStations = !showOldStations">قديمة ({{ gone.length }}) {{ showOldStations ? '▴' : '▾' }}</button></td>
            </tr>
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
            <div v-if="reading.text" class="small" :class="reading.ok ? 'text-positive' : 'text-negative'">{{ reading.text }}</div>
          </q-card-section>
        </template>
        <template v-if="picked.m.sim">
          <q-separator />
          <q-card-section class="q-pt-sm"><ModemPanel :sim-uuid="picked.m.sim.sim_uuid" /></q-card-section>
        </template>
        <q-card-actions align="right">
          <q-btn v-if="picked.m.sim?.approved || canRetryFirstBalance(picked.m.sim)" outline no-caps color="primary" label="اقرأ الرصيد" :loading="reading.busy" @click="readBalance" />
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
import ModemPanel from 'src/components/ModemPanel.vue'

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
// Connected = the modem answers and holds a SIM (ready or with a warning); otherwise not.
const isConnected = (m) => !!m.sim && m.level !== 'down'
// Computers table: active (present) first; «غير النشطة» = absent; gone 7+ days only under «قديمة».
const stationActive = ref(true)
const showOldStations = ref(false)
const stationRows = computed(() => stationActive.value
  ? current.value.filter((st) => !isAbsent(st))
  : [...current.value.filter(isAbsent), ...(showOldStations.value ? gone.value : [])])

// SIMs: the computer first, then active or not inside it; a type tile narrows it further.
// Filters stay as chosen across the 30-second refresh.
const SUMMARY_TYPES = [['mobilis-arsselli', 'أرسلي'], ['mobilis-sama', 'Sama'], ['djezzy-flexy', 'جيزي'], ['ooredoo-flexy', 'أوريدو']]
const typeName = (type) => SUMMARY_TYPES.find(([t]) => t === type)?.[1] || type
const typeFilter = ref(null)
const simStation = ref('all')
const simActive = ref(true)
const showOldSims = ref(false)
const pickType = (type) => { typeFilter.value = typeFilter.value === type ? null : type }
function clearFilters () { typeFilter.value = null; simStation.value = 'all' }
const stationChips = computed(() => [
  { value: 'all', label: 'الكل' },
  ...current.value.filter((st) => !isAbsent(st)).map((st) => ({ value: st.station_uuid, label: st.code || 'كمبيوتر' })),
  ...current.value.filter(isAbsent).map((st) => ({ value: st.station_uuid, label: (st.code || 'كمبيوتر') + ' (غائب)', muted: true }))
])
// Every SIM with its computer; old = its modem or its computer gone for longer than old_days.
const everySim = computed(() => [...current.value, ...gone.value].flatMap((st) =>
  st.modems.filter((m) => m.sim).map((m) => ({ st, m, old: st.level === 'old' || m.level === 'old' }))))
const isActive = (r) => !r.old && !isAbsent(r.st) && isConnected(r.m)
const simRows = computed(() => {
  const rows = everySim.value.filter((r) =>
    (simStation.value === 'all' || r.st.station_uuid === simStation.value) && (!typeFilter.value || r.m.sim.sim_type === typeFilter.value))
  return { active: rows.filter(isActive), inactive: rows.filter((r) => !r.old && !isActive(r)), old: rows.filter((r) => r.old) }
})
const shownSims = computed(() => simActive.value
  ? simRows.value.active
  : [...simRows.value.inactive, ...(showOldSims.value ? simRows.value.old : [])])
// The summary counts every active SIM of each type, whatever the filters (owner 2026-10-25).
const summary = computed(() => [
  { label: 'كمبيوتر', n: presentCount.value },
  ...SUMMARY_TYPES.map(([type, label]) => ({ type, label, n: everySim.value.filter((r) => isActive(r) && r.m.sim.sim_type === type).length }))
])
const statusText = (r) => onboardingText(r.m.sim) || (r.old ? '' : isAbsent(r.st) ? 'الكمبيوتر غائب' : r.m.reasons[0]?.text) || ''
const statusClass = (r) => onboardingText(r.m.sim) ? onboardingClass(r.m.sim) : r.m.level === 'down' ? 'text-negative' : 'text-deep-orange'
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
  BALANCE_NOT_CONFIRMED: 'لم يُؤكَّد أول رصيد: اضغط «اقرأ الرصيد» أو احفظ الـPIN من جديد',
  BALANCE_READ_FAILED: 'تعذّرت قراءة الرصيد: افحص الموديم ثم اضغط «اقرأ الرصيد»',
  LAST_632_UNCONFIRMED: 'آخر طلب رصيد (632) لم يتأكد: تحقق من الـPIN واحفظه من جديد قبل طلب آخر'
}
const onboardingOf = (sim) => (tree.value?.onboarding || []).find((o) => o.sim_uuid === sim.sim_uuid) || null
// A SIM not approved yet that stopped on its first balance: the button asks once more (flexy-core 0028).
// A PIN refused is not among them: a new PIN does that.
const RETRY_ALERTS = ['BALANCE_NOT_CONFIRMED', 'TYPE_NOT_CONFIRMED', 'LAST_632_UNCONFIRMED']
const canRetryFirstBalance = (sim) => {
  const o = sim && onboardingOf(sim)
  return !!o && o.stage === 'alert' && RETRY_ALERTS.includes(o.alert_code)
}
const noteOf = (sim) => onboardingOf(sim)?.note || ''
function onboardingText (sim) {
  const o = onboardingOf(sim)
  if (!o?.stage) return ''
  if (o.stage === 'number') return `يُكتشف الرقم (محاولة ${o.number_tries || 1} من 3)`
  if (o.stage === 'pin_wait') return 'ينتظر PIN منك قبل سؤال الرصيد'
  if (o.stage === 'balance') return 'يُسأل أول رصيد'
  if (o.stage === 'read') return 'يُقرأ الرصيد'
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
const reading = ref({ busy: false, ok: false, text: '' })
function open (st, m) {
  picked.value = { st, m }
  form.value = { label: m.sim?.label || '', note: m.sim ? noteOf(m.sim) : '', pin: '', busy: false, error: '', saved: false }
  reading.value = { busy: false, ok: false, text: '' }
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

// One balance code for an approved SIM, at once if it is connected and its modem free.
const READ_ERRORS = {
  SIM_NOT_APPROVED: 'الشريحة غير معتمدة',
  PROBE_RUNNING: 'كود آخر يعمل على الموديم الآن',
  // The 632 guard (one at a time, never again with a PIN refused or unconfirmed)
  PIN_REJECTED: 'الشبكة رفضت الـPIN: أدخل الـPIN الصحيح واحفظه أولًا',
  LAST_632_UNCONFIRMED: 'آخر طلب رصيد لم يتأكد: تحقق من الـPIN واحفظه من جديد أولًا',
  RUNNING: 'طلب رصيد آخر يعمل الآن',
  LAST_QUERY_RECENT: 'قُرئ الرصيد قبل قليل',
  NOTHING_CHANGED: 'الرصيد لم يتغير منذ آخر قراءة',
  MODEM_BUSY: 'الموديم مشغول الآن',
  SIM_NOT_FOUND: 'الشريحة غير موجودة'
}
async function readBalance () {
  const sim = picked.value?.m.sim
  if (!sim || reading.value.busy) return
  reading.value = { busy: true, ok: false, text: '' }
  try {
    const res = await flexy.readSimBalance(sim.sim_uuid)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    reading.value.ok = true
    reading.value.text = res.body.sent ? 'أُرسل كود الرصيد، والرد يظهر هنا خلال دقيقة' : 'سيُرسل كود الرصيد عند اتصال الشريحة'
    await load()
  } catch (e) {
    reading.value.text = 'لم يُرسل: ' + (READ_ERRORS[e.message] || e.message || 'FLEXY_CORE')
  } finally {
    reading.value.busy = false
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
button.tile { border: 0; font: inherit; cursor: pointer; }
.tile { position: relative; }
.tile .funnel { position: absolute; top: 5px; left: 5px; color: #9AA0AC; }
.tile.picked { outline: 2px solid var(--q-primary); }
.tile.picked .funnel { color: var(--q-primary); }
.sub { margin: 8px; padding: 8px; background: #F4F6FA; border-radius: 8px; }
.chip { border: 1px solid #D5D9E0; }
.link { border: 0; background: transparent; padding: 0; font: inherit; color: var(--q-primary); cursor: pointer; }
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
