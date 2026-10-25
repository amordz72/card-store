<template>
  <q-page class="page">
    <div class="card small">
      إرسال Mobilis حقيقي من حسابك أنت فقط: رصيد عادي عبر أرسلي <b>630</b>، أو عرض عبر Sama <b>665</b>. كل ضغطة «أرسل» = عملية واحدة، ولا إعادة محاولة تلقائية.
    </div>

    <div class="card row items-center q-gutter-sm">
      <q-toggle :model-value="switchOn" :disable="switchOn === null || switchBusy || forcedOff" color="negative"
        :label="forcedOff ? 'الإرسال موقوف من الخادم (طوارئ)' : switchOn ? 'الإرسال الحقيقي مفتوح' : 'الإرسال الحقيقي مقفل'"
        @update:model-value="flip" />
      <q-spinner v-if="switchBusy" size="16px" />
    </div>

    <q-tabs v-model="tab" dense class="tabs" active-color="primary" indicator-color="primary" no-caps :class="{ 'disabled': locked }">
      <q-tab name="630" label="رصيد عادي" :disable="locked" />
      <q-tab name="offer" label="عروض" :disable="locked" />
    </q-tabs>

    <template v-if="tab === 'offer'">
      <div class="card">
        <q-input v-model="offerPhone" dense outlined label="رقم موبيليس (06…)" inputmode="tel" autocomplete="off" :disable="locked" />
      </div>
      <FlexyOffers v-if="!op" :phone="offerDigits" :phone-ok="offerPhoneOk" :lookup="lookupOffers" :send="sendOffer" @sent="afterOffer" />
    </template>

    <template v-else>
    <div class="card grid-2">
      <q-input v-model="phone" dense outlined label="رقم موبيليس (06…)" inputmode="tel" autocomplete="off" :disable="locked" />
      <q-input v-model.number="amount" dense outlined type="number" label="المبلغ (دج)" :disable="locked" />
      <q-btn unelevated rounded no-caps color="primary" icon="fact_check" label="تحقق" :loading="busy === 'pre'" :disable="locked" @click="check" />
    </div>

    <div v-if="pre && !op" class="card">
      <template v-if="pre.ready">
        <div>سيُرسل <b>{{ pre.request.amount }} دج</b> إلى <bdi dir="ltr"><b>{{ pre.request.phone }}</b></bdi> من حساب الموزع <b>{{ pre.distributor_account }}</b><template v-if="pre.target">، الشريحة <b dir="ltr">{{ pre.target.sim_code || '—' }}</b> على <b dir="ltr">{{ pre.target.station_code || '—' }}</b></template>.</div>
        <div class="row q-gutter-sm q-mt-md">
          <q-btn unelevated rounded no-caps color="negative" icon="send" label="أرسل الآن" :loading="busy === 'send'" @click="send" />
          <q-btn flat rounded no-caps label="إلغاء" :disable="busy === 'send'" @click="reset" />
        </div>
      </template>
      <div v-else-if="refreshing" class="small"><q-spinner size="14px" /> الرصيد قديم: يُحدَّث آليًا (632، استعلام فقط بلا مال)، ثم يُعاد التحقق وحده…</div>
      <div v-else class="text-negative">المحطة غير جاهزة: {{ reasonText(pre.refresh?.reason || pre.reason) }}. لم يُرسل شيء.</div>

      <!-- Flexy Core's choice, SIM by SIM: why each one can or cannot run this send. Never a balance. -->
      <div v-if="sims.length" class="q-mt-md">
        <div class="small text-weight-bold q-mb-xs">اختيار الشريحة (النواة)</div>
        <div v-for="s in sims" :key="s.sim_uuid" class="sim-row" :class="{ chosen: s.chosen }">
          <div class="small">
            <b dir="ltr">{{ s.sim_code || '—' }}</b>
            <span class="muted"> · <span dir="ltr">{{ s.station_code || '—' }}</span> · <span dir="ltr">{{ s.sim_type }}</span></span>
            <q-badge v-if="s.chosen" class="q-ml-xs" color="positive" label="المختارة" />
          </div>
          <div v-if="s.same" class="small" :class="reasonClass(s.lines[0].reason)">{{ reasonText(s.lines[0].reason) }}</div>
          <div v-else class="small">
            <span v-for="l in s.lines" :key="l.account" class="q-mr-sm" :class="reasonClass(l.reason)">
              <b dir="ltr">{{ l.account }}</b>: {{ reasonText(l.reason) }}
            </span>
          </div>
        </div>
      </div>
    </div>

    </template>

    <div v-if="op" class="card">
      <div class="text-weight-bold" :class="LABELS[op.status]?.cls">{{ LABELS[op.status]?.text || op.status }}</div>
      <div class="small q-mt-xs">{{ MONEY[op.money] }}</div>
      <div v-if="op.outcome" class="small muted q-mt-xs" dir="ltr">{{ op.outcome.code }}</div>
      <div v-if="op.outcome?.carrierText" class="small q-mt-xs">رد الشبكة: {{ op.outcome.carrierText }}</div>
      <div v-if="following" class="small muted q-mt-sm"><q-spinner size="14px" /> متابعة النتيجة…</div>
      <q-btn v-if="!following" class="q-mt-md" flat rounded no-caps icon="refresh" label="تحديث" @click="follow" />
      <q-btn v-if="!following && op.status !== 'running'" class="q-mt-md" unelevated rounded no-caps color="primary" label="عملية جديدة" @click="reset" />
    </div>

    <div v-if="error" class="card text-negative small">{{ error }}</div>
  </q-page>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useQuasar } from 'quasar'
import * as flexy from 'src/api/flexy'
import FlexyOffers from 'src/components/FlexyOffers.vue'

const $q = useQuasar()

const LAST_KEY = 'flexy-owner-630-last'
const POLL_MS = 3000
const POLL_MAX = 60 // 3 minutes; after that the owner presses «تحديث»

const LABELS = {
  running: { text: 'قيد التنفيذ…', cls: '' },
  accepted: { text: 'قبلتها الشبكة («prise en charge»). التأكيد النهائي برسالة SMS عند المستلم.', cls: 'text-positive' },
  success: { text: 'نجحت (مؤكدة).', cls: 'text-positive' },
  not_sent: { text: 'لم تُرسل. لم يخرج أي رصيد.', cls: 'text-negative' },
  rejected: { text: 'رفضتها الشبكة.', cls: 'text-negative' },
  failed: { text: 'فشلت بعد القبول.', cls: 'text-negative' },
  review: { text: 'غير معروفة: تحقق بنفسك قبل أي إعادة. لا تُرسل مرة ثانية.', cls: 'text-warning' }
}
const MONEY = { release: 'المال: لم يُخصم.', capture: 'المال: خُصم نهائيًا.', hold: 'المال: محجوز حتى التأكيد.' }
const ERRORS = {
  OWNER_REQUIRED: 'هذا الحساب ليس المالك، أو انتهت الجلسة.',
  OWNER_SESSION_REQUIRED: 'سجّل الدخول أولًا.',
  ORIGIN_NOT_ALLOWED: 'هذا الموقع غير مسموح له بالإرسال (FLEXY_OWNER_ORIGINS).',
  PHONE_NOT_MOBILIS: 'الرقم ليس Mobilis (يجب أن يبدأ بـ 06).',
  PHONE_INVALID: 'رقم غير صحيح.',
  AMOUNT_INVALID: 'المبلغ بين 40 و50000 دج، عدد صحيح.',
  STATION_NOT_READY: 'المحطة غير جاهزة.',
  DISTRIBUTOR_ACCOUNT_CHANGED: 'تغيّر حساب الموزع منذ التحقق. اضغط «تحقق» مرة أخرى.',
  TARGET_CHANGED: 'تغيّرت الشريحة المختارة منذ التحقق. اضغط «تحقق» مرة أخرى.',
  IDEMPOTENCY_CONFLICT: 'نفس العملية بطلب مختلف. ابدأ عملية جديدة.',
  STATION_CONNECT_UNREACHABLE: 'تعذّر الوصول إلى Station Connect. لم يُرسل شيء.',
  SEND_DISABLED: 'الإرسال الحقيقي مقفل. افتحه من الزر أعلى الصفحة.',
  APP_SEND_DISABLED: 'الإرسال الحقيقي مقفل. افتحه من الزر أعلى الصفحة.',
  OFFER_NOT_ON_SAMA: 'هذا العرض لا يُنفَّذ من Sama.',
  '665_NO_SAMA_READY': 'لا توجد شريحة Sama متصلة وفارغة الآن.'
}

// Why a SIM/account can or cannot run the send (Flexy Core, core/selection.ts REASONS).
const REASONS = {
  ELIGIBLE: 'صالحة',
  READY: 'جاهزة',
  OFFER_NOT_SUPPORTED_ON_SIM_TYPE: 'نوعها لا يدعم هذه العملية',
  STATION_NOT_APPROVED: 'المحطة غير معتمدة',
  STATION_OFFLINE: 'المحطة غير متصلة',
  MODEM_OFFLINE: 'المودم غير متصل',
  SIM_OFFLINE: 'الشريحة غير متصلة',
  SIM_NOT_APPROVED: 'الشريحة غير معتمدة',
  PIN_MISSING: 'بلا PIN',
  NO_ACCOUNT_BALANCE: 'لا رصيد مقروء لحساباتها',
  ACCOUNT_DISABLED: 'الحساب معطّل',
  UNATTRIBUTED_OR_ASSUMED_FINANCIAL_JOB: 'عملية مالية غير محسومة عليها',
  BALANCE_STALE: 'الرصيد قديم (يُحدَّث بـ632)',
  INSUFFICIENT_BALANCE: 'الرصيد لا يكفي',
  SIM_BUSY: 'مشغولة الآن',
  NO_EXECUTOR: 'لا توجد شريحة'
}
const reasonText = (r) => (r ? REASONS[r] || r : '—')
const reasonClass = (r) => (r === 'ELIGIBLE' ? 'text-positive' : r === 'OFFER_NOT_SUPPORTED_ON_SIM_TYPE' ? 'muted' : 'text-negative')

const tab = ref('630')
const phone = ref('')
const amount = ref(100)
const busy = ref('')
const pre = ref(null)
const op = ref(null)
const key = ref('')
const error = ref('')
const following = ref(false)
let timer = null

// Money switch: read from Flexy Core, flipped here, applies to the next «أرسل».
const switchOn = ref(null)
const forcedOff = ref(false)
const switchBusy = ref(false)
function showSwitch (res) {
  if (res.status === 200) { switchOn.value = res.body.send_enabled; forcedOff.value = res.body.forced_off }
  else show(res)
}
async function loadSwitch () {
  switchBusy.value = true
  try { showSwitch(await flexy.ownerSwitch()) } finally { switchBusy.value = false }
}
function flip (on) {
  const apply = async () => {
    switchBusy.value = true
    try { showSwitch(await flexy.setOwnerSwitch(on)) } finally { switchBusy.value = false }
  }
  if (!on) return apply()
  $q.dialog({ title: 'فتح الإرسال الحقيقي', message: 'كل «أرسل» بعدها يُخرج رصيدًا حقيقيًا من الشريحة. متأكد؟', cancel: 'لا', ok: 'نعم، افتح' }).onOk(apply)
}

// Candidates grouped by SIM: the chosen one first, then the ones of a supported type.
const sims = computed(() => {
  const sel = pre.value?.selection
  if (!sel?.candidates?.length) return []
  const bySim = new Map()
  for (const c of sel.candidates) {
    if (!bySim.has(c.sim_uuid)) bySim.set(c.sim_uuid, { ...c, lines: [] })
    bySim.get(c.sim_uuid).lines.push({ account: c.distributor_account || '—', reason: c.reason })
  }
  const chosen = sel.selected?.sim_uuid
  const rank = (s) => (s.sim_uuid === chosen ? 0 : s.lines.every((l) => l.reason === 'OFFER_NOT_SUPPORTED_ON_SIM_TYPE') ? 2 : 1)
  return [...bySim.values()]
    .map((s) => ({ ...s, chosen: s.sim_uuid === chosen, same: s.lines.every((l) => l.reason === s.lines[0].reason) }))
    .sort((a, b) => rank(a) - rank(b) || String(a.sim_code).localeCompare(String(b.sim_code)))
})

const locked = computed(() => !!op.value || busy.value === 'send')

function remember (k) {
  try { k ? localStorage.setItem(LAST_KEY, k) : localStorage.removeItem(LAST_KEY) } catch { /* private mode */ }
}

function show (res) {
  if (res.body?.operation) op.value = res.body.operation
  error.value = res.body?.ok === false && res.body?.error ? (ERRORS[res.body.error] || res.body.error) : ''
}

// A stale balance is refreshed by the server on each check (one 632 at most, reused while
// it runs). The page just checks again until ready or blocked, for up to 3 minutes.
const REFRESH_MS = 5000
const REFRESH_MAX = 36
const refreshing = ref(false)
async function check () {
  error.value = ''
  pre.value = null
  busy.value = 'pre'
  try {
    for (let i = 0; i < REFRESH_MAX; i++) {
      const res = await flexy.ownerPreflight(phone.value, Number(amount.value))
      if (res.status !== 200) { show(res); break }
      pre.value = res.body
      refreshing.value = !res.body.ready && res.body.refresh?.state === 'waiting'
      if (!refreshing.value) break
      await new Promise((resolve) => { timer = setTimeout(resolve, REFRESH_MS) })
    }
  } finally { busy.value = ''; refreshing.value = false }
}

async function send () {
  if (!pre.value?.ready) return
  // One key per confirmed form: a double click or a retry of this same click can never send twice.
  if (!key.value) key.value = 'owner_' + crypto.randomUUID().replace(/-/g, '')
  remember(key.value)
  busy.value = 'send'
  try {
    // The SIM the owner saw: Flexy Core refuses (TARGET_CHANGED) if its choice moved since.
    show(await flexy.ownerSend(pre.value.request.phone, pre.value.request.amount, pre.value.distributor_account, key.value, pre.value.target?.sim_uuid))
  } finally { busy.value = '' }
  if (op.value?.status === 'running') follow()
}

// Offers: the shared component asks Flexy Core through the owner's routes.
const offerPhone = ref('')
const offerDigits = computed(() => {
  let d = offerPhone.value.replace(/\D/g, '')
  if (/^213\d{9}$/.test(d)) d = '0' + d.slice(3)
  return d
})
const offerPhoneOk = computed(() => /^06\d{8}$/.test(offerDigits.value))
async function lookupOffers (p) {
  const res = await flexy.ownerOffers(p)
  if (res.status !== 200) throw new Error(ERRORS[res.body?.error] || res.body?.error || 'تعذّر جلب العروض.')
  return res.body
}
async function sendOffer (p, label) {
  // One key per confirmed offer, kept so a reload goes on following it
  key.value = 'own665_' + crypto.randomUUID().replace(/-/g, '')
  remember(key.value)
  const res = await flexy.ownerOfferSend(p, label, key.value)
  show(res)
  if (res.status >= 400) throw new Error(error.value || 'لم يُقبل الطلب.')
  return res.body
}
function afterOffer () {
  if (op.value?.status === 'running') follow()
}

// 630 and offers are followed the same way; the key says which one it is.
const statusOf = (k) => (k.startsWith('own665_') ? flexy.ownerOfferStatus(k) : flexy.ownerStatus(k))

async function follow () {
  if (!key.value || following.value) return
  following.value = true
  try {
    for (let i = 0; i < POLL_MAX; i++) {
      const res = await statusOf(key.value)
      show(res)
      if (res.status !== 200 || op.value?.status !== 'running') break
      await new Promise((resolve) => { timer = setTimeout(resolve, POLL_MS) })
    }
  } finally { following.value = false }
}

function reset () {
  clearTimeout(timer)
  pre.value = null
  op.value = null
  key.value = ''
  error.value = ''
  remember('')
}

onMounted(() => {
  loadSwitch()
  // Back after a reload: keep following the last operation instead of losing it.
  let last = ''
  try { last = localStorage.getItem(LAST_KEY) || '' } catch { last = '' }
  if (last) { key.value = last; if (last.startsWith('own665_')) tab.value = 'offer'; follow() }
})
onBeforeUnmount(() => clearTimeout(timer))
</script>

<style scoped>
.tabs { background: #E4E6EC; border-radius: 12px; }
.sim-row { border-top: 1px solid #ECEEF2; padding: 6px 0; }
.sim-row.chosen { background: #F1FAF3; border-radius: 6px; padding: 6px; }
</style>
