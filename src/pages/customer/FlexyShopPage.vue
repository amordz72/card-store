<template>
  <q-page class="page">
    <div v-if="!access.enabled.value" class="card text-center column q-gutter-sm q-pa-lg">
      <q-icon name="send_to_mobile" size="40px" color="grey-6" class="self-center" />
      <div class="text-weight-bold">الفليكسي غير مفعّل لحسابك</div>
      <div class="small muted">اطلب من المحل تفعيله.</div>
    </div>
    <FlexySend v-else remember="shop" :open="access.open.value" :max-amount="access.maxAmount.value" :offers="access.offers.value"
      note="إن فشل الإرسال يرجع المبلغ إلى رصيدك تلقائيًا." :send="send" :lookup="lookupOffers" :send-offer="sendOffer"
      :rows="ops" :has-more="hasMore" :loading-more="loadingMore" :refreshing="refreshing"
      @sent="afterSend" @refresh="refreshNow" @more="more">
      <q-badge :color="access.open.value ? 'positive' : 'negative'" class="q-pa-sm self-start">
        {{ access.open.value ? 'الخدمة متاحة الآن' : 'الخدمة متوقفة الآن — حاول بعد قليل' }}
      </q-badge>
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
import FlexySend from 'src/components/FlexySend.vue'

// The shop's side of the shared send screen (FlexySend): its balance pays through store-flexy.
// Light on purpose (owner rule: fast on weak networks): one request to send, small pages of
// operations, the last ones kept on the phone, and a refresh only while something is running.
const customer = useCustomerStore()
const buyer = useBuyer()
const access = useFlexyAccess()

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
  id: j.job_id, title: j.kind === 'offer' ? j.offer_label : money(j.amount), phone: j.phone,
  kind: j.kind === 'offer' ? 'offer' : '630', amount: j.amount, offer: j.offer_label,
  badge: view(j), at: j.created_at, reply: j.network_reply
})))
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
    await loadFirst()
    if (wasRunning && !running.value) buyer.refresh()
  } catch { /* offline: keep what is shown */ } finally { refreshing.value = false }
}

// While something runs: 3 s, then a little longer each time, up to 30 s. Nothing runs: no requests.
let timer = null
let delay = 3000
function schedule () {
  clearTimeout(timer)
  if (!running.value) { delay = 3000; return }
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
const lookupOffers = (p) => api.flexyOffers(customer.token, p)
const sendOffer = (p, label, key) => api.flexyOffer(customer.token, p, label, key).catch(lostAnswer)

// Something went out (credit or offer): the balance changed, follow it in «آخر العمليات»
async function afterSend () {
  buyer.refresh()
  await loadFirst().catch(() => null)
  delay = 3000
  schedule()
}

onMounted(async () => {
  await access.refresh()
  if (!access.enabled.value) return
  await loadFirst().catch(() => null)
  schedule()
})
onUnmounted(() => clearTimeout(timer))
</script>
