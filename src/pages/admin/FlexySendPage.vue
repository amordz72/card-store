<template>
  <q-page class="page">
    <!-- «من هاتفي» (owner 2026-10-29): one send page; this button switches to the admin phone and back.
         The owner's page only: shops never see it. The last choice is kept on this device. -->
    <div class="card row items-center q-gutter-sm q-mb-sm" :class="phoneMode ? 'via-phone' : ''">
      <div class="col small" :class="phoneMode ? 'text-weight-bold text-primary' : 'muted'">الإرسال الآن: {{ phoneMode ? 'من هاتفك' : 'من الكمبيوترات' }}</div>
      <q-btn round unelevated :color="phoneMode ? 'primary' : 'grey-4'" :text-color="phoneMode ? 'white' : 'grey-8'" icon="smartphone"
        :aria-label="phoneMode ? 'إيقاف الإرسال من الهاتف' : 'الإرسال من هاتفي'" :aria-pressed="phoneMode" @click="switchVia" />
    </div>
    <FlexySend remember="owner" :open="(switchOn === true || djezzyOn === true || ooredooOn === true) && !forcedOff" :max-amount="MAX_AMOUNT" :send="send" :lookup="lookupOffers"
      :credit-prefixes="phoneMode ? ['06'] : ['06', '07', '05']"
      :offer-prefixes="phoneMode ? ['06'] : ['06', '07', '05']"
      :send-offer="sendOffer" :probe-offer="probeOffer" :decide-offer="decideOffer" :explore-offer="exploreOffer" :rows="ops" :has-more="hasMore" :loading-more="loadingMore" :refreshing="refreshing" :settle="settleRow" :presence="presenceAt"
      @sent="afterSend" @refresh="refreshNow" @more="more">
      <!-- What the network said that no path knows yet (Flexy Core 0056): the owner reads it, then marks it seen -->
      <div v-if="newReplies.length" class="card column q-gutter-xs">
        <div class="row items-center">
          <span class="col text-weight-bold">ردود وعروض جديدة من الشبكة ({{ newReplies.length }})</span>
          <q-btn flat dense no-caps size="sm" color="primary" label="رأيتها كلها" @click="seenReplies('all')" />
        </div>
        <div v-for="n in newReplies" :key="n.id" class="new-reply">
          <div class="small text-weight-bold">{{ STEPS[n.step] || 'رد جديد قبل التأكيد' }} · {{ OPERATORS[n.operator] || n.operator }}<span class="muted"> · {{ n.seenCount }} مرة · {{ new Date(n.lastAt).toLocaleString('ar-DZ') }}</span></div>
          <div class="small ltr reply">{{ n.text }}</div>
          <q-btn flat dense no-caps size="sm" color="primary" label="رأيته" @click="seenReplies([n.id])" />
        </div>
      </div>
      <!-- The switches live in «الإدارة ← المفاتيح» (owner 2026-10-29: the send page starts at the number).
           One line here, only when something is closed, or the server's emergency stop. -->
      <router-link v-if="closedLine" to="/flexy/switches" class="card row items-center q-gutter-sm closed-line"
        :class="forcedOff ? 'bg-red-1 text-negative' : 'text-deep-orange-9'">
        <span class="col text-weight-bold">{{ closedLine }}</span>
        <span class="small text-underline">المفاتيح ←</span>
      </router-link>
      <!-- Offers sent from their second source, and why (Flexy Core 0036): what to fix, one line per reason -->
      <div v-if="offerAlerts.length" class="card q-gutter-xs">
        <div class="row items-center">
          <div class="text-weight-bold text-deep-orange col">عروض خرجت من المصدر الآخر</div>
          <q-btn flat dense color="primary" label="تم" :loading="alertsBusy" @click="alertsSeen" />
        </div>
        <div v-for="a in offerAlerts" :key="a.preferred + a.reason" class="small">
          {{ alertText(a) }} — {{ a.count }} {{ a.count > 1 ? 'عروض' : 'عرض' }}، آخرها {{ a.last_offer }}.
        </div>
      </div>
      <!-- «أرسل من هاتفي» (owner 2026-10-26): offers and discovery on the admin phone, his choice only -->
      <div v-if="phoneMode" class="column items-center q-gutter-xs q-py-sm">
        <q-icon name="smartphone" size="44px" color="primary" />
        <div class="text-weight-bold">فليكسي الهاتف</div>
      </div>
      <div v-if="phoneMode && phoneSim" class="card row items-center q-gutter-sm">
        <span class="name">شريحة الهاتف</span>
        <q-badge :color="phoneSim.live ? 'positive' : 'negative'" class="q-pa-xs">
          {{ phoneSim.live ? 'متصل' : 'غير متصل: لن يُرسل شيء' }}</q-badge>
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
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useQuasar } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import FlexySend from 'src/components/FlexySend.vue'
import { explain, offerTitle } from 'src/api/flexyExplain'
import { useBell } from 'src/composables/useBell'

// The owner's side of the shared send screen (FlexySend): real Mobilis from his own SIMs through
// Flexy Core, under his money switch, no wallet. Flexy Core checks and chooses the SIM itself at
// send time (no «تحقق», owner 2026-10-25); its choice per SIM is on «المحطات والشرائح».
const $q = useQuasar()

const PAGE = 10
const MAX_AMOUNT = 50000
const OFFER_KEY = 'mobilis.sama.offer.665'
// An offer the Sama menu never shows (Revolution 100 and 500; Sama Mix 50 dropped 2026-10-29) goes from an Arsselli SIM
// by its amount (*696*1*, Flexy Core 0032): an offer for the page, followed like a 630 (owner 2026-10-26)
const ARSSELLI_OFFER_KEY = 'mobilis.arsselli.offer.696'
const DJEZZY_KEY = 'djezzy.flexy.ordinary.760'
const OOREDOO_KEY = 'ooredoo.flexy.ordinary.590'
const DJEZZY_OFFER_KEY = 'djezzy.flexy.offer.760'
const OOREDOO_OFFER_KEY = 'ooredoo.flexy.offer.585'

const ERRORS = {
  OWNER_REQUIRED: 'هذا الحساب ليس المالك، أو انتهت الجلسة.',
  OWNER_SESSION_REQUIRED: 'سجّل الدخول أولًا.',
  ORIGIN_NOT_ALLOWED: 'هذا الموقع غير مسموح له بالإرسال (FLEXY_OWNER_ORIGINS).',
  PHONE_NOT_MOBILIS: 'الرقم ليس Mobilis (يجب أن يبدأ بـ 06).',
  PHONE_NOT_DJEZZY: 'الرقم ليس Djezzy (يجب أن يبدأ بـ 07).',
  PHONE_NOT_OOREDOO: 'الرقم ليس Ooredoo (يجب أن يبدأ بـ 05).',
  OFFER_IN_DOUBT: 'هذا العرض موضع شك حتى تراجعه. لم يُرسل شيء.',
  OFFER_CLOSED: 'هذا العرض مغلق في شاشة العروض. لم يُرسل شيء.',
  '585_START_NO_RESPONSE': 'المودم لم يردّ على قراءة قائمة الرقم. أعد المحاولة.',
  '585_NEW_REPLY_BEFORE_PIN': 'الشبكة ردّت بغير قائمة العروض (أُبلغت الإدارة). لم يُخصم شيء.',
  '760O_PREVIOUS_OFFER_UNSETTLED_OR_TOO_RECENT': 'لهذا الرقم عرض جيزي غير محسوم أو نفس العرض قبل أقل من دقيقة. لم يُرسل شيء.',
  OOREDOO_SEND_DISABLED: 'إرسال أوريدو مقفل: افتحه من زرّه أعلاه. لم يُرسل شيء.',
  '590_NO_OOREDOO_READY': 'لا شريحة أوريدو معتمدة ومتصلة ولها PIN على مودم حر. لم يُرسل شيء.',
  '590_PREVIOUS_TRANSFER_UNSETTLED_OR_TOO_RECENT': 'لهذا الرقم عملية أوريدو غير محسومة أو نفس المبلغ قبل أقل من دقيقة. لم يُرسل شيء.',
  DJEZZY_SEND_DISABLED: 'إرسال جيزي مقفل: افتحه من زرّه أعلاه. لم يُرسل شيء.',
  '760_NO_DJEZZY_READY': 'لا شريحة جيزي معتمدة ومتصلة ولها PIN على مودم حر. لم يُرسل شيء.',
  // Reading a Djezzy line's offers ended without the network's menu (owner 2026-10-28): never «no offers»
  '760O_START_NO_RESPONSE': 'لم تردّ شبكة جيزي على طلب العروض. أعد المحاولة.',
  '760O_START_NOT_DISPATCHED': 'لم يصل طلب العروض إلى المودم. أعد المحاولة.',
  '760O_MENU_UNRECOGNIZED': 'ردّت جيزي بنص غير قائمة العروض. أعد المحاولة.',
  '760O_NOT_DISCOVERED': 'لم تُقرأ عروض هذا الرقم. أعد المحاولة.',
  '760_PREVIOUS_TRANSFER_UNSETTLED_OR_TOO_RECENT': 'لهذا الرقم عملية جيزي غير محسومة أو نفس المبلغ قبل أقل من دقيقة. لم يُرسل شيء.',
  PHONE_INVALID: 'رقم غير صحيح.',
  AMOUNT_INVALID: 'المبلغ بين 40 و50000 دج، عدد صحيح.',
  IDEMPOTENCY_CONFLICT: 'نفس العملية بطلب مختلف. ابدأ عملية جديدة.',
  STATION_CONNECT_UNREACHABLE: 'تعذّر الوصول إلى الخادم. لم يُرسل شيء.',
  SEND_DISABLED: 'الإرسال الحقيقي مقفل. افتحه من الزر أعلى الصفحة.',
  APP_SEND_DISABLED: 'الإرسال الحقيقي مقفل. افتحه من الزر أعلى الصفحة.',
  OFFER_NOT_ON_SAMA: 'هذا العرض لا يُنفَّذ من Sama (ولا من هاتف الإدارة).',
  SOURCE_BUSY: 'كل الشرائح مشغولة الآن ولم تتحرر في الوقت. لم يُرسل شيء، أعد المحاولة.',
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
  if (res.status === 200) {
    switchOn.value = res.body.send_enabled
    forcedOff.value = res.body.forced_off
    samaOn.value = res.body.sama_offers_enabled !== false
    djezzyOn.value = res.body.djezzy_send_enabled === true
    ooredooOn.value = res.body.ooredoo_send_enabled === true
  } else $q.notify({ type: 'negative', message: errorText(res.body) })
}
async function loadSwitch () {
  switchBusy.value = true
  try { showSwitch(await flexy.ownerSwitch()) } finally { switchBusy.value = false }
}
// Offers that left their first source: the reason says what to do (owner 2026-10-27).
const SOURCE = { sama: 'سما', arsselli: 'أرسلي' }
const offerAlerts = ref([])
const { refreshBell } = useBell()
const alertsBusy = ref(false)
function alertText (a) {
  const p = SOURCE[a.preferred] || a.preferred
  const u = SOURCE[a.used] || a.used
  if (a.reason === 'busy') return `طابور ${p} أطول من الحد فخرجت من ${u}: زد شرائح ${p}`
  if (a.reason === 'no_balance') return `${p} بلا رصيد يكفي فخرجت من ${u}: غذِّ رصيد ${p}`
  return `${p} معطّلة فخرجت من ${u}: افحص «المحطات والشرائح»`
}
async function loadAlerts () {
  const res = await flexy.ownerOfferAlerts()
  if (res.status === 200) offerAlerts.value = res.body.alerts || []
}
async function alertsSeen () {
  alertsBusy.value = true
  try {
    const res = await flexy.ownerOfferAlertsSeen()
    if (res.status === 200) { offerAlerts.value = res.body.alerts || []; refreshBell() }
  } finally { alertsBusy.value = false }
}

// Read only here: flipped in «المفاتيح» (SwitchesPage.vue)
const djezzyOn = ref(null)
const ooredooOn = ref(null)
const samaOn = ref(null)
const closedLine = computed(() => {
  if (forcedOff.value) return '🔴 الإرسال موقوف من الخادم (طوارئ)'
  const off = []
  if (switchOn.value === false) off.push('الإرسال الحقيقي')
  if (!phoneMode && djezzyOn.value === false) off.push('جيزي')
  if (!phoneMode && ooredooOn.value === false) off.push('أوريدو')
  if (!phoneMode && samaOn.value === false) off.push('عروض سما')
  return off.length ? '🔴 مقفل: ' + off.join('، ') : ''
})

// A stale balance is refreshed by the server (one 632, no money) and nothing is created meanwhile,
// so the same press is asked again with the same key until a SIM is ready: one operation at most.
const REFRESH_MS = 5000
const REFRESH_MAX = 36
// A number just served is a question, an open operation the owner's choice (Flexy Core 0057, owner 2026-10-28).
// Asked again with a new key: the refused one stays «لم تُرسل» in the list with its reason.
const askYes = (message, ok, danger = false) => new Promise((resolve) => {
  $q.dialog({ title: 'هذا الرقم', message, cancel: 'لا', ok: { label: ok, color: danger ? 'negative' : 'primary' }, persistent: true })
    .onOk(() => resolve(true)).onCancel(() => resolve(false))
})
async function guarded (call, key) {
  let res = await call(key, {})
  const code = () => res.body?.operation?.outcome?.code || res.body?.error || ''
  if (/_SAME_NUMBER_RECENT$/.test(code()) && await askYes('لهذا الرقم عملية قبل أقل من دقيقتين. هل ترسل عملية أخرى؟', 'نعم، أرسل')) {
    res = await call(key + '_r', { confirm_repeat: true })
  }
  if (/_PREVIOUS_UNSETTLED$/.test(code()) && await askYes('لهذا الرقم عملية لم تُحسم بعد، وقد يكون وصله مبلغها. الإرسال الآن قد يدفع مرتين. أرسل رغم ذلك؟', 'أرسل رغم ذلك', true)) {
    res = await call(key + '_f', { force: true })
  }
  return res
}
async function send (p, v, { wait, key: pressKey }) {
  const key = 'owner_' + pressKey.replace(/-/g, '')
  // 07 = Djezzy (*760*): its own route and switch; no balance refresh exists for it, one request decides.
  if (p.startsWith('07')) {
    const res = await guarded((k, extra) => flexy.ownerSend760(p, v, k, extra), key)
    if (res.body?.operation) return res.body
    throw refused(res)
  }
  // 05 = Ooredoo (*590*): its own route and switch, never Djezzy's.
  if (p.startsWith('05')) {
    const res = await guarded((k, extra) => flexy.ownerSend590(p, v, k, extra), key)
    if (res.body?.operation) return res.body
    throw refused(res)
  }
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
// The phone screen (route flexy/phone, owner only) sends every offer from the phone; the send screen never does.
const phoneMode = useRoute().meta.phone === true
// The switch alone decides. It used to also require the phone to look «live» here, and when it did not
// (2026-10-26 21:51 UTC) a Revolution 1200 went out from sama-4 instead: the owner's choice fell back to a
// modem in silence. Now «from my phone» is always sent as is; the core refuses when the phone is offline
// (665_PHONE_OFFLINE) and nothing is sent. Never a fallback.
const via = () => (phoneMode ? 'phone' : null)
// The phone button: /flexy/send ⇄ /flexy/phone (the same page, remounted in the other mode), remembered here
const router = useRouter()
const VIA_KEY = 'flexy.send.via'
function remember (v) { try { localStorage.setItem(VIA_KEY, v) } catch { /* private window: not kept */ } }
function switchVia () {
  remember(phoneMode ? 'computers' : 'phone')
  router.replace(phoneMode ? '/flexy/send' : '/flexy/phone')
}
function recall () { try { return localStorage.getItem(VIA_KEY) } catch { return null } }
if (!phoneMode && recall() === 'phone') router.replace('/flexy/phone')
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
  // 07 = Djezzy offers: their own route (Flexy Core 0051); the line's family then its catalog
  if (p.startsWith('07')) {
    const r7 = await flexy.ownerOffers760(p, retry)
    if (r7.status !== 200) throw new Error(errorText(r7.body))
    return r7.body
  }
  // 05 = Ooredoo offers (*585*, Flexy Core 0059): no discovery session, the sale itself reads the menu
  if (p.startsWith('05')) {
    const r5 = await flexy.ownerOffers585(p, retry)
    if (r5.status !== 200) throw new Error(errorText(r5.body))
    return r5.body
  }
  const res = await flexy.ownerOffers(p, retry, via())
  // A paid offer waits for a Sama SIM: the discovery comes after it (owner 2026-10-27), the page keeps asking.
  if (res.status === 409 && res.body?.error === 'DISCOVERY_DEFERRED') return { status: 'discovering' }
  if (res.status !== 200) throw new Error(errorText(res.body))
  return res.body
}
// «اكشف» (Flexy Core 0065): Ooredoo only; {status: 'probing'} while it runs, then the price and the offers holding the code
// «صيغ» (Flexy Core 0067): confirm this variant, a change in it, or a new variant of the label
async function decideOffer (p, decision, group = null) {
  const r = await flexy.ownerOfferDecide585(p, decision, group)
  if (r.status !== 200) throw new Error(errorText(r.body))
  return r.body
}
// «اقرأ عروض الإنترنت» (Flexy Core 0075): Djezzy only, the line's «Offres Internet» pages, no money
async function exploreOffer (p) {
  if (!p.startsWith('07')) return null
  const r = await flexy.ownerOfferExplore760(p)
  if (r.status !== 200) throw new Error(errorText(r.body))
  return r.body
}
async function probeOffer (p, code, again = false) {
  const r = await flexy.ownerOfferProbe585(p, code, again)
  if (r.status !== 200) throw new Error(errorText(r.body))
  return r.body
}
async function sendOffer (p, label, key) {
  // SOURCE_BUSY: the SIM frees within the queue limit (owner 2026-10-27); nothing was created, the same key
  // keeps its place. Asked again until the core sends it or the request expires (2 minutes, then 410).
  if (p.startsWith('07')) {
    const r7 = await guarded((k, extra) => flexy.ownerOfferSend760(p, label, k, extra), 'own760o_' + key.replace(/-/g, ''))
    if ((r7.status === 0 || r7.status >= 400) && !r7.body?.operation) throw refused(r7)
    return r7.body
  }
  if (p.startsWith('05')) {
    const r5 = await guarded((k, extra) => flexy.ownerOfferSend585(p, label, k, extra), 'own585_' + key.replace(/-/g, ''))
    if ((r5.status === 0 || r5.status >= 400) && !r5.body?.operation) throw refused(r5)
    return r5.body
  }
  const id = 'own665_' + key.replace(/-/g, '')
  let res = await flexy.ownerOfferSend(p, label, id, via())
  for (const end = Date.now() + 120_000; res.status === 409 && res.body?.error === 'SOURCE_BUSY' && Date.now() < end;) {
    await new Promise((resolve) => setTimeout(resolve, 1000 * (res.body.retry_after_seconds || 3)))
    res = await flexy.ownerOfferSend(p, label, id, via())
  }
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
  id: o.idempotency_key, title: o.offer ? offerTitle(o.offer) : money(o.amount), phone: o.phone,
  kind: [OFFER_KEY, ARSSELLI_OFFER_KEY, DJEZZY_OFFER_KEY, OOREDOO_OFFER_KEY].includes(o.operation_key) ? 'offer' : '630', amount: o.amount, offer: o.offer,
  badge: BADGES[o.status] || { label: 'جارٍ', color: 'info' }, at: o.created_at, reply: o.network_reply,
  running: ['queued', 'running'].includes(o.status), explain: explain(o.outcome_code, o.status),
  stopped: o.status === 'not_sent', lineChanged: o.outcome_code === '665_LINE_GROUP_CHANGED',
  doneAt: o.updated_at, sims: o.sims || [],
  // Open = may have moved money and not settled: the owner can settle it here (Flexy Core 0057)
  open: ['accepted', 'review'].includes(o.status), operationId: o.operation_id
})))
const OPERATORS = { mobilis: 'موبيليس', djezzy: 'جيزي', ooredoo: 'أوريدو' }
const STEPS = { before_confirm: 'رد جديد قبل التأكيد', new_offer: 'عرض جديد في قائمة', background_paused: 'توقف الاستكشاف الخلفي' }
const newReplies = ref([])
async function loadNewReplies () {
  const res = await flexy.ownerNewReplies().catch(() => null)
  if (res?.status === 200) newReplies.value = (res.body.items || []).filter((x) => !x.seenAt)
}
async function seenReplies (seen) {
  await flexy.ownerNewRepliesSeen(seen).catch(() => null)
  await loadNewReplies()
  refreshBell()
}
// A complaint (owner 2026-10-29): what was offline at the minute this operation ran (Flexy Core 0070)
async function presenceAt (at) {
  const res = await flexy.ownerPresence(at)
  if (res.status === 200 && res.body?.ok) return res.body
  throw new Error(res.body?.error === 'PRESENCE_LOG_NOT_READY' ? 'سجل الانقطاعات لم يبدأ بعد (migration 0070).' : 'تعذّرت القراءة.')
}
async function settleRow (j, to) {
  const words = { success: 'نجحت', failed: 'فشلت', not_sent: 'لم تُرسل' }
  $q.dialog({
    title: 'حسم العملية: ' + words[to],
    message: 'اكتب دليلك (مثلًا: سطر *762# أو كلام الزبون). يُحفظ مع العملية.',
    prompt: { model: '', type: 'text' }, cancel: 'رجوع', ok: 'احسم'
  }).onOk(async (note) => {
    const res = await flexy.ownerSettle(j.operationId, to, note)
    if (res.status === 200 && res.body?.ok) { $q.notify({ type: 'positive', message: 'حُسمت: ' + words[to] }); await refreshNow() } else {
      $q.notify({ type: 'negative', message: 'لم تُحسم: ' + (res.body?.error || res.status) })
    }
  })
}
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
      (o.operation_key === OFFER_KEY ? flexy.ownerOfferStatus(o.idempotency_key)
        : o.operation_key === DJEZZY_KEY ? flexy.ownerStatus760(o.idempotency_key)
          : o.operation_key === OOREDOO_KEY ? flexy.ownerStatus590(o.idempotency_key)
            : o.operation_key === DJEZZY_OFFER_KEY ? flexy.ownerOfferStatus760(o.idempotency_key)
              : o.operation_key === OOREDOO_OFFER_KEY ? flexy.ownerOfferStatus585(o.idempotency_key)
                : flexy.ownerStatus(o.idempotency_key)).catch(() => null)))
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
  loadAlerts().catch(() => null)
  loadNewReplies().catch(() => null)
  if (phoneMode) {
    loadPhone().catch(() => null)
    phoneTimer = setInterval(() => { if (document.visibilityState === 'visible') loadPhone().catch(() => null) }, 10_000)
  }
  await loadFirst().catch(() => null)
  schedule()
})
onUnmounted(() => { clearTimeout(timer); clearInterval(phoneTimer) })
</script>

<style scoped>
.new-reply { border-top: 1px solid #ECEEF3; padding-top: 6px; }
.reply { white-space: pre-wrap; direction: ltr; text-align: left; color: #4B5563; }
.via-phone { border: 2px solid var(--q-primary); }
.closed-line { text-decoration: none; }
</style>
