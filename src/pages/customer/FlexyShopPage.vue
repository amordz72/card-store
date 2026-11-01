<template>
  <q-page class="page">
    <!-- «هل وصل للزبون؟» (owner 2026-10-30): the shop knows its customer; asked before the owner, its answer moves no money -->
    <div v-for="q in questions" :key="q.job_id" class="card column q-gutter-xs question" style="border: 2px solid #e64a19">
      <div class="text-weight-bold">هل وصل للزبون؟</div>
      <div class="small"><span class="ltr">{{ q.phone }}</span> · {{ q.kind === 'offer' ? offerTitle(q.offer_label) : money(q.amount) }} · {{ when(q.created_at) }}</div>
      <div class="small muted">لم يصلنا دليل من الشبكة. اسأل الزبون وأجبنا.</div>
      <div class="row q-gutter-xs">
        <q-btn unelevated dense no-caps color="positive" label="نعم، وصل" :loading="answering === q.job_id + 'arrived'" @click="answer(q, 'arrived')" />
        <q-btn unelevated dense no-caps color="negative" label="لا، لم يصل" :loading="answering === q.job_id + 'not_arrived'" @click="answer(q, 'not_arrived')" />
        <q-btn flat dense no-caps color="grey-8" label="لا أعرف" :loading="answering === q.job_id + 'unknown'" @click="answer(q, 'unknown')" />
      </div>
    </div>
    <div v-if="!access.enabled.value" class="card text-center column q-gutter-sm q-pa-lg">
      <q-icon name="send_to_mobile" size="40px" color="grey-6" class="self-center" />
      <div class="text-weight-bold">الفليكسي غير مفعّل لحسابك</div>
      <div class="small muted">اطلب من المحل تفعيله.</div>
    </div>
    <FlexySend v-else remember="shop" :automix="automix" :open="access.open.value" :max-amount="access.maxAmount.value" :offers="access.offers.value"
      :credit-prefixes="access.creditPrefixes.value" :offer-prefixes="access.offerPrefixes.value" note="إن فشل الإرسال يرجع المبلغ إلى رصيدك تلقائيًا." :send="send" :lookup="lookupOffers" :send-offer="sendOffer" :available-offers="availableOffers"
      :rows="allOps" :has-more="hasMore" :loading-more="loadingMore" :refreshing="refreshing"
      @sent="afterSend" @refresh="refreshNow" @more="more">
      <template #other="{ raw }"><IdoomCards :raw="raw" :running-lines="idoomBusy" @sent="afterIdoom" /></template>
      <!-- What can be sent now, by the ready SIMs (s185, owner 2026-11-01): a missing one says «قريبًا» -->
      <div v-if="access.operators.value.length && access.supply.value" class="row q-gutter-xs supply">
        <span v-for="o in access.operators.value" :key="o.key" class="op" :class="o.on ? 'on' : 'off'">
          {{ o.on ? '✓' : '⏳' }} {{ o.name }}<template v-if="!o.on"> — غير متوفر حاليًا، قريبًا</template></span>
      </div>
      <!-- Only when stopped (owner 2026-11-01: «إزالة كلمة متاح») -->
      <q-badge v-if="!access.open.value" color="negative" class="q-pa-sm self-start">الخدمة متوقفة الآن — حاول بعد قليل</q-badge>
    </FlexySend>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useFlexyAccess } from 'src/composables/useFlexyAccess'
import * as api from 'src/api/customer'
import { money } from 'src/api/format'
import { offerTitle } from 'src/api/flexyExplain'
import FlexySend from 'src/components/FlexySend.vue'
import IdoomCards from 'src/components/IdoomCards.vue'
import { idoomView } from 'src/api/idoomView'
import { useIdoomAccess } from 'src/composables/useIdoomAccess'
import { when } from 'src/api/when'
import { Notify } from 'quasar'

// The shop's side of the shared send screen (FlexySend): its balance pays through store-flexy.
// Light on purpose (owner rule: fast on weak networks): one request to send, small pages of
// operations, the last ones kept on the phone, and a refresh only while something is running.
const customer = useCustomerStore()
const buyer = useBuyer()
const access = useFlexyAccess()
// The owner's «اللوحة التلقائية» switch (s166); unknown = on
const automix = ref(true)
api.flexyUi(customer.token).then((r) => { automix.value = r?.automix !== false }).catch(() => {})

const PAGE = 10

// Short and general: the shop sees what happened, the money side is automatic
function view (j) {
  if (j.status === 'success') return { label: 'ناجحة', color: 'positive' }
  if (j.status === 'failed') return { label: 'فاشلة · أُعيد المبلغ', color: 'negative' }
  if (j.status === 'not_sent') return { label: 'لم تُرسل · أُعيد المبلغ', color: 'grey-7' }
  if (j.status === 'review') return { label: 'قيد المراجعة', color: 'deep-orange' }
  return { label: 'جارٍ', color: 'info' }
}

// The last page stays on the phone and shows at once; the server copy replaces it when it arrives
const cacheKey = computed(() => 'flexy-ops:' + (customer.profile?.phone || ''))
function readCache () {
  try { return JSON.parse(localStorage.getItem(cacheKey.value) || '[]') } catch { return [] }
}
function writeCache (list) {
  try { localStorage.setItem(cacheKey.value, JSON.stringify(list.slice(0, PAGE))) } catch { /* private mode */ }
}
const rows = ref(readCache())
const ops = computed(() => rows.value.map((j) => ({
  id: j.job_id, title: j.kind === 'offer' ? offerTitle(j.offer_label) : money(j.amount), phone: j.phone,
  kind: j.kind === 'offer' ? 'offer' : '630', amount: j.amount, offer: j.offer_label,
  badge: view(j), at: j.created_at, reply: j.network_reply,
  running: ['queued', 'sent'].includes(j.status), stopped: j.status === 'not_sent'
})))
// «تعبئة» (owner 2026-11-01): the Idoom top-ups in the same list, by time, like «العمليات»
const idoomAccess = useIdoomAccess()
const idoomRows = ref([])
const loadIdoom = () => (idoomAccess.enabled.value
  ? api.idoomJobs(customer.token, PAGE, 0).then((l) => { idoomRows.value = l || [] }).catch(() => null)
  : Promise.resolve())
const idoomRunning = computed(() => idoomRows.value.some((j) => ['queued', 'claimed'].includes(j.status)))
const idoomBusy = computed(() => idoomRows.value.filter((j) => ['queued', 'claimed'].includes(j.status)).map((j) => ({ line: j.line, at: j.created_at })))
const allOps = computed(() => [...ops.value, ...idoomRows.value.map((j) => ({
  id: 'idoom:' + j.job_id, title: j.product_name, phone: j.line, kind: 'idoom', amount: j.charged_amount,
  badge: idoomView(j), at: j.created_at, reply: null, running: ['queued', 'claimed'].includes(j.status)
}))].sort((a, b) => String(b.at).localeCompare(String(a.at))))
const hasMore = ref(false)
const loadingMore = ref(false)
const refreshing = ref(false)
const running = computed(() => rows.value.some((j) => ['queued', 'sent'].includes(j.status)))

async function loadFirst () {
  const list = await api.flexyJobs(customer.token, PAGE, null)
  rows.value = list
  hasMore.value = list.length === PAGE
  writeCache(list)
}
async function more () {
  loadingMore.value = true
  try {
    const list = await api.flexyJobs(customer.token, PAGE, rows.value[rows.value.length - 1]?.job_id)
    rows.value = rows.value.concat(list)
    hasMore.value = list.length === PAGE
  } catch { /* the button stays; try again */ } finally { loadingMore.value = false }
}

// Ask the server to follow up running requests with Flexy Core, then reload the first page
async function refreshNow () {
  refreshing.value = true
  const wasRunning = running.value
  try {
    if (wasRunning) await api.flexyRefresh(customer.token).catch(() => null)
    const idoomWas = idoomRunning.value
    await Promise.all([loadFirst(), loadIdoom()])
    if ((wasRunning && !running.value) || (idoomWas && !idoomRunning.value)) buyer.refresh()
  } catch { /* offline: keep what is shown */ } finally { refreshing.value = false }
}

// While something runs: 3 s, then a little longer each time, up to 30 s. Nothing runs: no requests.
let timer = null
let delay = 3000
function schedule () {
  clearTimeout(timer)
  if (!running.value && !idoomRunning.value) { delay = 3000; return }
  timer = setTimeout(async () => {
    await refreshNow()
    delay = Math.min(Math.round(delay * 1.6), 30000)
    schedule()
  }, delay)
}

// The key comes from FlexySend: one per press, kept while the answer is lost (no answer, or no
// body from the server), so pressing again re-asks the same request and the shop is charged once.
const lostAnswer = (e) => {
  if (['NETWORK', 'UNKNOWN'].includes(e?.code)) e.lost = true
  throw e
}
const send = (p, v, { key }) => api.flexySend(customer.token, p, v, key).catch(lostAnswer)
const lookupOffers = (p, o = {}) => api.flexyOffers(customer.token, p, o.debtPaid === true)
const availableOffers = (names) => api.flexyAvailable(customer.token, names)
const sendOffer = (p, label, key) => api.flexyOffer(customer.token, p, label, key).catch(lostAnswer)

// Something went out (credit or offer): the balance changed, follow it in «آخر العمليات»
async function afterSend () {
  buyer.refresh()
  await loadFirst().catch(() => null)
  delay = 3000
  schedule()
}

async function afterIdoom () {
  await loadIdoom()
  delay = 3000
  schedule()
}

// The shop's questions (v1.47; before it, none)
const questions = ref([])
const answering = ref('')
const loadQuestions = () => api.flexyQuestions(customer.token).then((l) => { questions.value = l || [] }).catch(() => null)
async function answer (q, a) {
  answering.value = q.job_id + a
  try {
    const r = await api.flexyAnswer(customer.token, q.job_id, a)
    if (r !== 'OK') throw new Error(r)
    questions.value = questions.value.filter((x) => x.job_id !== q.job_id)
    Notify.create({ type: 'positive', message: 'شكرًا، وصل جوابك', position: 'top', timeout: 1500 })
  } catch {
    Notify.create({ type: 'negative', message: 'لم يُحفظ، حاول مرة أخرى', position: 'top' })
  } finally {
    answering.value = ''
  }
}

onMounted(async () => {
  await access.refresh()
  if (!access.enabled.value) return
  loadQuestions()
  await idoomAccess.refresh()
  await Promise.all([loadFirst().catch(() => null), loadIdoom()])
  schedule()
})
onUnmounted(() => clearTimeout(timer))
</script>

<style scoped>
.supply .op { font-size: 12px; padding: 3px 10px; border-radius: 999px; }
.supply .on { background: #ECFDF5; color: #047857; }
.supply .off { background: #F3F4F6; color: #6B7280; }
</style>
