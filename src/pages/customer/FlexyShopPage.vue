<template>
  <q-page class="page">
    <div v-if="!access.enabled.value" class="card text-center column q-gutter-sm q-pa-lg">
      <q-icon name="send_to_mobile" size="40px" color="grey-6" class="self-center" />
      <div class="text-weight-bold">الفليكسي غير مفعّل لحسابك</div>
      <div class="small muted">اطلب من المحل تفعيله.</div>
    </div>
    <template v-else>
      <q-badge :color="access.open.value ? 'positive' : 'negative'" class="q-pa-sm self-start">
        {{ access.open.value ? 'الخدمة متاحة الآن' : 'الخدمة متوقفة الآن — حاول بعد قليل' }}
      </q-badge>

      <q-tabs v-model="tab" dense class="tabs" active-color="primary" indicator-color="primary" no-caps>
        <q-tab name="630" label="رصيد عادي" />
        <q-tab name="offer" label="عروض" />
      </q-tabs>

      <div class="card column q-gutter-sm">
        <q-input v-model="phone" dense outlined label="رقم الزبون (موبيليس)" inputmode="tel" maxlength="16"
          placeholder="06XX XX XX XX" input-class="ltr text-center phone" />
        <div v-if="phone && !phoneOk" class="small text-negative">رقم موبيليس يبدأ بـ 06 (10 أرقام).</div>
      </div>

      <template v-if="tab === '630'">
        <div class="card column q-gutter-sm">
          <div class="amounts">
            <q-btn v-for="a in amounts" :key="a" dense unelevated no-caps class="chip"
              :outline="amount !== a" :color="amount === a ? 'primary' : 'grey-7'" :label="money(a)" @click="pick(a)" />
          </div>
          <q-input v-model.number="other" dense outlined type="number" inputmode="numeric"
            :label="`أو اكتب مبلغًا (40 إلى ${money(access.maxAmount.value)})`" @update:model-value="amount = null" />
        </div>
        <div class="small muted">إن فشل الإرسال يرجع المبلغ إلى رصيدك تلقائيًا.</div>
        <q-btn unelevated color="primary" size="lg" icon="send" label="إرسال" :loading="busy"
          :disable="!canSend" @click="confirmSend" />
      </template>
      <div v-else-if="!access.offers.value" class="card text-center muted q-pa-lg">العروض غير مفعّلة لحسابك.</div>
      <FlexyOffers v-else :phone="digits" :phone-ok="phoneOk" :active="tab === 'offer'" :max-amount="access.maxAmount.value"
        :lookup="lookupOffers" :send="sendOffer" @sent="afterOffer" />

      <div class="row items-center justify-between q-mt-md">
        <div class="text-weight-bold">آخر العمليات</div>
        <q-btn flat dense icon="refresh" aria-label="تحديث" :loading="refreshing" @click="refreshNow" />
      </div>
      <div class="card q-pa-none">
        <button v-for="j in rows" :key="j.job_id" type="button" class="op-row" :aria-expanded="opened === j.job_id"
          @click="opened = opened === j.job_id ? null : j.job_id">
          <div class="row items-center no-wrap q-gutter-sm">
            <span class="col text-weight-bold">{{ j.kind === 'offer' ? j.offer_label : money(j.amount) }}</span>
            <q-badge :color="view(j).color" class="q-pa-xs">{{ view(j).label }}</q-badge>
          </div>
          <div class="small muted ltr text-right">{{ spaced(j.phone) }}</div>
          <div v-if="opened === j.job_id" class="details column q-gutter-xs">
            <div class="small">التاريخ: <bdi dir="ltr">{{ when(j.created_at) }}</bdi></div>
            <div class="small">رد الشبكة:</div>
            <div class="small muted ltr text-right reply">{{ j.network_reply || '—' }}</div>
          </div>
        </button>
        <div v-if="!rows.length" class="text-center muted q-pa-lg">لا توجد عمليات بعد</div>
      </div>
      <q-btn v-if="hasMore" flat no-caps color="primary" label="عرض المزيد" :loading="loadingMore" @click="more" />
    </template>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { Dialog } from 'quasar'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { useFlexyAccess } from 'src/composables/useFlexyAccess'
import * as api from 'src/api/customer'
import { money } from 'src/api/format'
import FlexyOffers from 'src/components/FlexyOffers.vue'

// Light on purpose (owner rule: fast on weak networks): one request to send, small pages of
// operations, the last ones kept on the phone, and a refresh only while something is running.
const customer = useCustomerStore()
const buyer = useBuyer()
const access = useFlexyAccess()
const { busy, run } = useRun()

const PAGE = 10
const tab = ref('630')
const phone = ref('')
const amount = ref(1000)
const other = ref(null)
const opened = ref(null)

const digits = computed(() => {
  let d = phone.value.replace(/\D/g, '')
  if (/^213\d{9}$/.test(d)) d = '0' + d.slice(3)
  return d
})
const phoneOk = computed(() => /^06\d{8}$/.test(digits.value))
const amounts = computed(() => [100, 200, 500, 1000, 2000, 5000].filter((a) => a <= access.maxAmount.value))
const value = computed(() => amount.value || Number(other.value) || 0)
const canSend = computed(() => access.open.value && phoneOk.value && value.value >= 40 && value.value <= access.maxAmount.value)
const spaced = (d) => (d || '').replace(/^(\d{4})(\d{2})(\d{2})(\d{2})$/, '$1 $2 $3 $4')
const when = (t) => new Date(t).toLocaleString('ar-DZ')
function pick (a) { amount.value = a; other.value = null }

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

function confirmSend () {
  const v = value.value
  const p = digits.value
  Dialog.create({
    title: 'تأكيد الإرسال',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      <div style="text-align:center">يصل للزبون: <b>${money(v)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>`,
    cancel: 'رجوع',
    ok: 'نعم، أرسل'
  }).onOk(async () => {
    // One id per press: a retry after a lost answer is the same request, never a second send
    const r = await run(() => api.flexySend(customer.token, p, v, crypto.randomUUID()))
    if (!r) return
    buyer.refresh()
    phone.value = ''
    await loadFirst().catch(() => null)
    delay = 3000
    schedule()
  })
}

const lookupOffers = (p) => api.flexyOffers(customer.token, p)
// One id per press: a retry after a lost answer is the same request, never a second send
const sendOffer = (p, label) => api.flexyOffer(customer.token, p, label, crypto.randomUUID())
// An offer went out: same follow-up as ordinary credit
async function afterOffer () {
  buyer.refresh()
  phone.value = ''
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

<style scoped>
.tabs { background: #E4E6EC; border-radius: 12px; }
.amounts { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
.chip { min-height: 40px; font-weight: 700; border-radius: 10px; }
.op-row { width: 100%; border: 0; background: transparent; text-align: right; padding: 10px 14px; border-bottom: 1px solid #ECEEF3;
  display: flex; flex-direction: column; gap: 4px; font: inherit; color: inherit; cursor: pointer; }
.op-row:last-child { border-bottom: 0; }
.details { margin-top: 6px; padding: 8px; border: 1px solid #E4E6EC; border-radius: 8px; background: #F8F9FB; }
.reply { white-space: normal; word-break: break-word; }
:deep(.phone) { font-size: 1.4rem; letter-spacing: 1px; }
</style>
