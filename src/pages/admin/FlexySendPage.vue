<template>
  <q-page class="page">
    <FlexySend remember="owner" :open="switchOn === true && !forcedOff" :max-amount="MAX_AMOUNT" :send="send" :lookup="lookupOffers"
      :send-offer="sendOffer" :rows="ops" :has-more="hasMore" :loading-more="loadingMore" :refreshing="refreshing"
      @sent="afterSend" @refresh="refreshNow" @more="more">
      <div class="card row items-center q-gutter-sm">
        <q-toggle :model-value="switchOn" :disable="switchOn === null || switchBusy || forcedOff" color="positive"
          :label="forcedOff ? 'الإرسال موقوف من الخادم (طوارئ)' : switchOn ? 'الإرسال الحقيقي مفتوح' : 'الإرسال الحقيقي مقفل'"
          @update:model-value="flip" />
        <q-spinner v-if="switchBusy" size="16px" />
      </div>
      <!-- «عروض سما» (owner 2026-10-27): kept in Flexy Core for every send, his and the shops'.
           Under 500 DA Arsselli goes first, from 500 Sama; off = Arsselli only. -->
      <div class="card row items-center q-gutter-sm">
        <q-toggle :model-value="samaOn" :disable="samaOn === null || samaBusy" color="primary"
          :label="samaOn ? 'عروض سما مفعّلة' : 'عروض سما ملغاة: العروض من أرسلي فقط'" @update:model-value="flipSama" />
        <q-spinner v-if="samaBusy" size="16px" />
        <div class="col-12 small muted">أقل من 500 دج: أرسلي أولًا وسما عند الضرورة. 500 فما فوق: سما أولًا وأرسلي عند الضرورة.</div>
      </div>
      <!-- «أرسل من هاتفي» (owner 2026-10-26): offers and discovery on the admin phone, his choice only -->
      <div v-if="phoneSim" class="card row items-center q-gutter-sm">
        <q-toggle v-model="viaPhone" color="primary" label="العروض من هاتفي" />
        <q-badge :color="phoneSim.live ? 'positive' : (viaPhone ? 'negative' : 'grey-6')" class="q-pa-xs">
          {{ phoneSim.live ? 'متصل' : (viaPhone ? 'غير متصل: لن يُرسل شيء' : 'غير متصل') }}</q-badge>
        <span class="small muted">آخر اتصال منذ {{ phoneAgo }}</span>
        <!-- Rech-Doom 0.8.2 reports its protection; without it Android freezes the app behind the browser -->
        <div v-if="phoneSim.health && phoneSim.health.protected === false" class="col-12 small text-negative">
          🔴 تطبيق Rech-Doom يعمل بلا حماية من التجميد: افتحه مرة ووافق على «تجاهل تحسين البطارية».</div>
        <span class="small muted" dir="ltr">{{ phoneSim.msisdn || '' }}</span>
        <span v-if="phoneSim.balance_amount != null" class="small">{{ money(phoneSim.balance_amount) }}</span>
      </div>
    </FlexySend>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useQuasar } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import FlexySend from 'src/components/FlexySend.vue'
import { explain } from 'src/api/flexyExplain'

// The owner's side of the shared send screen (FlexySend): real Mobilis from his own SIMs through
// Flexy Core, under his money switch, no wallet. Flexy Core checks and chooses the SIM itself at
// send time (no «تحقق», owner 2026-10-25); its choice per SIM is on «المحطات والشرائح».
const $q = useQuasar()

const PAGE = 10
const MAX_AMOUNT = 50000
const OFFER_KEY = 'mobilis.sama.offer.665'
// An offer the Sama menu never shows (Sama Mix 50, Revolution 100 and 500) goes from an Arsselli SIM
// by its amount (*696*1*, Flexy Core 0032): an offer for the page, followed like a 630 (owner 2026-10-26)
const ARSSELLI_OFFER_KEY = 'mobilis.arsselli.offer.696'

const ERRORS = {
  OWNER_REQUIRED: 'هذا الحساب ليس المالك، أو انتهت الجلسة.',
  OWNER_SESSION_REQUIRED: 'سجّل الدخول أولًا.',
  ORIGIN_NOT_ALLOWED: 'هذا الموقع غير مسموح له بالإرسال (FLEXY_OWNER_ORIGINS).',
  PHONE_NOT_MOBILIS: 'الرقم ليس Mobilis (يجب أن يبدأ بـ 06).',
  PHONE_INVALID: 'رقم غير صحيح.',
  AMOUNT_INVALID: 'المبلغ بين 40 و50000 دج، عدد صحيح.',
  IDEMPOTENCY_CONFLICT: 'نفس العملية بطلب مختلف. ابدأ عملية جديدة.',
  STATION_CONNECT_UNREACHABLE: 'تعذّر الوصول إلى الخادم. لم يُرسل شيء.',
  SEND_DISABLED: 'الإرسال الحقيقي مقفل. افتحه من الزر أعلى الصفحة.',
  APP_SEND_DISABLED: 'الإرسال الحقيقي مقفل. افتحه من الزر أعلى الصفحة.',
  OFFER_NOT_ON_SAMA: 'هذا العرض لا يُنفَّذ من Sama (ولا من هاتف الإدارة).',
  OFFER_SAMA_DISABLED: 'عروض سما ملغاة، وهذا العرض لا يُرسل إلا من سما. فعّلها من الزر أعلى الصفحة.',
  '665_NO_SAMA_READY': 'لا توجد شريحة Sama متصلة وفارغة الآن.',
  '665_SAMA_PIN_UNCONFIRMED': 'شريحة Sama لم تقبل الـPIN في آخر محاولة: تحقق من الـPIN واحفظه من جديد في «المحطات والشرائح».',
  '665_PHONE_NOT_LINKED': 'هاتف الإدارة غير مربوط بعد.',
  '665_PHONE_OFFLINE': 'هاتف الإدارة غير متصل الآن. لم يُرسل شيء.',
  '665_PHONE_NO_PIN': 'احفظ PIN شريحة الهاتف في «المحطات والشرائح».',
  '665_PHONE_BUSY': 'هاتف الإدارة مشغول بعملية أخرى. لم يُرسل شيء.',
  '665_PHONE_BALANCE_SHORT': 'رصيد شريحة الهاتف لا يكفي لهذا العرض.'
}
// Why no SIM can run the send now (Flexy Core, core/selection.ts REASONS)
const REASONS = {
  OFFER_NOT_SUPPORTED_ON_SIM_TYPE: 'لا شريحة من النوع المطلوب',
  STATION_NOT_APPROVED: 'المحطة غير معتمدة',
  STATION_OFFLINE: 'المحطة غير متصلة',
  MODEM_OFFLINE: 'المودم غير متصل',
  SIM_OFFLINE: 'الشريحة غير متصلة',
  SIM_NOT_APPROVED: 'الشريحة غير معتمدة',
  PIN_MISSING: 'بلا PIN',
  NO_ACCOUNT_BALANCE: 'لا رصيد مقروء',
  ACCOUNT_DISABLED: 'الحساب معطّل',
  UNATTRIBUTED_OR_ASSUMED_FINANCIAL_JOB: 'عملية مالية غير محسومة على الشريحة',
  BALANCE_STALE: 'الرصيد قديم',
  INSUFFICIENT_BALANCE: 'الرصيد لا يكفي',
  SIM_BUSY: 'الشريحة مشغولة الآن',
  NO_EXECUTOR: 'لا توجد شريحة'
}
// No answer (network, or a gateway error without a body): the request may have been taken. FlexySend
// keeps its key, so pressing again re-asks the same operation instead of sending a second one.
function refused (res) {
  const e = new Error(errorText(res.body))
  if (res.status === 0 || (res.status >= 500 && !res.body?.error)) {
    e.lost = true
    e.message = 'لم يصل الرد. اضغط «إرسال» مرة ثانية لتعرف ما حدث: لن يُرسل مرتين.'
  }
  return e
}
const errorText = (b) => b?.error === 'STATION_NOT_READY'
  ? 'لا شريحة جاهزة الآن: ' + (REASONS[b.refresh?.reason || b.reason] || b.reason || '—') + '. لم يُرسل شيء.'
  : ERRORS[b?.error] || b?.error || 'لم يُقبل الطلب.'

// Money switch: read from Flexy Core, flipped here, applies to the next «إرسال».
const switchOn = ref(null)
const forcedOff = ref(false)
const switchBusy = ref(false)
function showSwitch (res) {
  if (res.status === 200) { switchOn.value = res.body.send_enabled; forcedOff.value = res.body.forced_off; samaOn.value = res.body.sama_offers_enabled !== false } else $q.notify({ type: 'negative', message: errorText(res.body) })
}
async function loadSwitch () {
  switchBusy.value = true
  try { showSwitch(await flexy.ownerSwitch()) } finally { switchBusy.value = false }
}
// «عروض سما»: read with the money switch, flipped alone.
const samaOn = ref(null)
const samaBusy = ref(false)
async function flipSama (on) {
  samaBusy.value = true
  try { showSwitch(await flexy.setSamaOffersSwitch(on)) } finally { samaBusy.value = false }
}
function flip (on) {
  const apply = async () => {
    switchBusy.value = true
    try { showSwitch(await flexy.setOwnerSwitch(on)) } finally { switchBusy.value = false }
  }
  if (!on) return apply()
  $q.dialog({ title: 'فتح الإرسال الحقيقي', message: 'كل «إرسال» بعدها يُخرج رصيدًا حقيقيًا من الشريحة. متأكد؟', cancel: 'لا', ok: 'نعم، افتح' }).onOk(apply)
}

// A stale balance is refreshed by the server (one 632, no money) and nothing is created meanwhile,
// so the same press is asked again with the same key until a SIM is ready: one operation at most.
const REFRESH_MS = 5000
const REFRESH_MAX = 36
async function send (p, v, { wait, key: pressKey }) {
  const key = 'owner_' + pressKey.replace(/-/g, '')
  for (let i = 0; i < REFRESH_MAX; i++) {
    const res = await flexy.ownerSend(p, v, key)
    // Sent, or refused after it was recorded (it shows in «آخر العمليات» with its status)
    if (res.body?.operation) return res.body
    if (res.status !== 409 || res.body?.error !== 'STATION_NOT_READY' || res.body?.refresh?.state !== 'waiting') throw refused(res)
    wait('الرصيد قديم: يُحدَّث الآن (632، استعلام بلا مال)، ثم يُرسل وحده…')
    await new Promise((resolve) => setTimeout(resolve, REFRESH_MS))
  }
  throw new Error('لم يُحدَّث الرصيد في 3 دقائق. لم يُرسل شيء.')
}

// The admin phone, when one is linked: its SIM, and whether offers go to it (kept on this phone)
const phoneSim = ref(null)
const VIA_KEY = 'flexy-via-phone'
const viaPhone = ref((() => { try { return localStorage.getItem(VIA_KEY) === '1' } catch { return false } })())
watch(viaPhone, (v) => { try { localStorage.setItem(VIA_KEY, v ? '1' : '0') } catch { /* private mode */ } })
// The switch alone decides. It used to also require the phone to look «live» here, and when it did not
// (2026-10-26 21:51 UTC) a Revolution 1200 went out from sama-4 instead: the owner's choice fell back to a
// modem in silence. Now «from my phone» is always sent as is; the core refuses when the phone is offline
// (665_PHONE_OFFLINE) and nothing is sent. Never a fallback.
const via = () => (viaPhone.value ? 'phone' : null)
async function loadPhone () {
  const res = await flexy.ownerPhone()
  const p = res.status === 200 ? (res.body.phones || [])[0] : null
  const sim = p?.sims?.[0]
  phoneSim.value = sim ? { ...sim, live: Boolean(p.live && sim.live), last_seen_at: p.last_seen_at, health: p.health || null } : null
  phoneTick.value = Date.now()
}
// Read once at open, the state went stale and a send fell back to a modem (2026-10-26): now every 10 s
const phoneTick = ref(Date.now())
const phoneAgo = computed(() => {
  const t = phoneSim.value?.last_seen_at ? new Date(phoneSim.value.last_seen_at).getTime() : null
  if (!t) return '—'
  const s = Math.max(0, Math.round((phoneTick.value - t) / 1000))
  return s < 60 ? `${s} ث` : `${Math.round(s / 60)} د`
})
let phoneTimer = null

async function lookupOffers (p, { retry = false } = {}) {
  const res = await flexy.ownerOffers(p, retry, via())
  if (res.status !== 200) throw new Error(errorText(res.body))
  return res.body
}
async function sendOffer (p, label, key) {
  const res = await flexy.ownerOfferSend(p, label, 'own665_' + key.replace(/-/g, ''), via())
  if ((res.status === 0 || res.status >= 400) && !res.body?.operation) throw refused(res)
  return res.body
}

// «آخر العمليات»: the owner's own operations in Flexy Core
const BADGES = {
  success: { label: 'ناجحة', color: 'positive' },
  accepted: { label: 'قبلتها الشبكة', color: 'positive' },
  not_sent: { label: 'لم تُرسل', color: 'grey-7' },
  rejected: { label: 'رفضتها الشبكة', color: 'negative' },
  failed: { label: 'فاشلة', color: 'negative' },
  review: { label: 'قيد المراجعة', color: 'deep-orange' }
}
const rows = ref([])
const ops = computed(() => rows.value.map((o) => ({
  id: o.idempotency_key, title: o.offer || money(o.amount), phone: o.phone,
  kind: [OFFER_KEY, ARSSELLI_OFFER_KEY].includes(o.operation_key) ? 'offer' : '630', amount: o.amount, offer: o.offer,
  badge: BADGES[o.status] || { label: 'جارٍ', color: 'info' }, at: o.created_at, reply: o.network_reply,
  running: ['queued', 'running'].includes(o.status), explain: explain(o.outcome_code, o.status),
  stopped: o.status === 'not_sent', lineChanged: o.outcome_code === '665_LINE_GROUP_CHANGED',
  doneAt: o.updated_at, sims: o.sims || []
})))
const hasMore = ref(false)
const loadingMore = ref(false)
const refreshing = ref(false)
const running = computed(() => rows.value.some((o) => ['queued', 'running'].includes(o.status)))

async function page (before) {
  const res = await flexy.ownerOperations(PAGE, before)
  if (res.status !== 200) throw new Error(errorText(res.body))
  return res.body.operations || []
}
async function loadFirst () {
  const list = await page(null)
  rows.value = list
  hasMore.value = list.length === PAGE
}
async function more () {
  loadingMore.value = true
  try {
    const list = await page(rows.value[rows.value.length - 1]?.created_at)
    rows.value = rows.value.concat(list)
    hasMore.value = list.length === PAGE
  } catch { /* the button stays; try again */ } finally { loadingMore.value = false }
}

// Reading a running operation nudges Flexy Core along; then the first page is read again
async function refreshNow () {
  refreshing.value = true
  try {
    await Promise.all(rows.value.filter((o) => o.status === 'running').map((o) =>
      (o.operation_key === OFFER_KEY ? flexy.ownerOfferStatus(o.idempotency_key) : flexy.ownerStatus(o.idempotency_key)).catch(() => null)))
    await loadFirst()
  } catch { /* offline: keep what is shown */ } finally { refreshing.value = false }
}

// While something runs: every 2 s for 3 minutes (the row turns into its result in place, owner
// 2026-10-26), then a little longer each time, up to 30 s. Nothing runs: no requests.
const FAST_MS = 2000
const FAST_FOR_MS = 180000
let timer = null
let delay = FAST_MS
let since = Date.now()
function schedule () {
  clearTimeout(timer)
  if (!running.value) { delay = FAST_MS; since = Date.now(); return }
  timer = setTimeout(async () => {
    await refreshNow()
    if (Date.now() - since > FAST_FOR_MS) delay = Math.min(Math.round(delay * 1.6), 30000)
    schedule()
  }, delay)
}

async function afterSend () {
  await loadFirst().catch(() => null)
  delay = FAST_MS
  since = Date.now()
  schedule()
}

onMounted(async () => {
  loadSwitch()
  loadPhone().catch(() => null)
  phoneTimer = setInterval(() => { if (document.visibilityState === 'visible') loadPhone().catch(() => null) }, 10_000)
  await loadFirst().catch(() => null)
  schedule()
})
onUnmounted(() => { clearTimeout(timer); clearInterval(phoneTimer) })
</script>
