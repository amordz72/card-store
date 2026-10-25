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
      <template v-else>
        <!-- The line's group (kept, or discovered without money), then its offers: name and price -->
        <div v-if="!phoneOk" class="card text-center muted q-pa-lg">اكتب رقم الزبون لتظهر عروضه.</div>
        <div v-else-if="loading" class="card column items-center q-gutter-sm q-pa-lg">
          <q-spinner color="primary" size="32px" />
          <div class="small muted">جارٍ معرفة نوع خط الزبون… قد يأخذ حتى دقيقة.</div>
        </div>
        <div v-else-if="offersError" class="card column items-center q-gutter-sm q-pa-lg">
          <div class="small text-negative text-center">{{ offersError }}</div>
          <q-btn flat no-caps color="primary" icon="refresh" label="أعد المحاولة" @click="loadOffers" />
        </div>
        <div v-else-if="families.length" class="card q-pa-none">
          <q-expansion-item v-for="f in families" :key="f.name" :label="f.name" :default-opened="families.length === 1"
            group="families" header-class="family" expand-separator>
            <div v-for="o in f.offers" :key="o.label" class="offer-row" role="button" tabindex="0"
              @click="confirmOffer(o)" @keyup.enter="confirmOffer(o)">
              <span class="text-weight-bold">{{ o.label }}</span>
              <span class="row items-center no-wrap q-gutter-xs">
                <q-btn v-if="DETAILS[o.label]" flat round dense size="sm" icon="info_outline" aria-label="التفاصيل"
                  @click.stop="showDetails(o)" />
                <span class="price">{{ money(o.amount) }}</span>
              </span>
            </div>
          </q-expansion-item>
        </div>
        <div v-else-if="looked" class="card text-center muted q-pa-lg">لا توجد عروض متاحة لهذا الرقم الآن.</div>
      </template>

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
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { useFlexyAccess } from 'src/composables/useFlexyAccess'
import * as api from 'src/api/customer'
import { money } from 'src/api/format'

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

// What the customer gets for each offer (shown from «i»). The price is the number in the name.
const DETAILS = {
  'Sama Mix 50': '', 'Sama Mix 100': '500Mo — يوم واحد', 'Sama Mix 500': '5Go — 15 يومًا', 'Sama Mix 1000': '15Go — 30 يومًا',
  'Sama Mix 1500': '30Go — 30 يومًا', 'Sama Mix 2000': '50Go — 30 يومًا',
  'Sama Talk 500': '500Mo — 15 يومًا', 'Sama Talk 1000': '2Go — 30 يومًا', 'Sama Talk 1500': '3Go — 30 يومًا',
  'Sama Talk 2000': '4Go — 30 يومًا',
  'Sama Net 500': '10Go — 15 يومًا', 'Sama Net 1000': '30Go — 30 يومًا', 'Sama Net 1500': '60Go — 30 يومًا',
  'Sama Net 2000': '90Go — 30 يومًا',
  'PixX 50': '500Mo — يوم واحد', 'PixX 100': '1Go — يوم واحد', 'PixX 500': '5Go — 15 يومًا',
  'PixX 1000': '13Go — 30 يومًا', 'PixX 2000': '30Go'
}
const loading = ref(false)
const looked = ref(false)
const offersError = ref('')
const offers = ref([])
let offersFor = ''
let lookupRun = 0
// Families in the catalog's order (Mix, Talk, Net…), prices rising inside each one
const families = computed(() => {
  const out = []
  for (const o of offers.value.filter((x) => x.amount <= access.maxAmount.value)) {
    let f = out.find((x) => x.name === o.family)
    if (!f) out.push(f = { name: o.family, offers: [] })
    f.offers.push(o)
  }
  for (const f of out) f.offers.sort((a, b) => a.amount - b.amount)
  return out
})

// One request; while the core discovers the line, ask again every 3 s (at most 90 s)
async function loadOffers () {
  const p = digits.value
  const mine = ++lookupRun
  offers.value = []
  offersError.value = ''
  looked.value = false
  loading.value = true
  try {
    let r = await api.flexyOffers(customer.token, p)
    for (let i = 0; r.status === 'discovering' && i < 30 && mine === lookupRun; i++) {
      await new Promise((resolve) => setTimeout(resolve, 3000))
      r = await api.flexyOffers(customer.token, p)
    }
    if (mine !== lookupRun) return
    if (r.status === 'ready') {
      offersFor = p
      offers.value = r.offers
      looked.value = true
    } else {
      offersError.value = r.status === 'discovering' ? 'لم تردّ الشبكة. أعد المحاولة.' : 'تعذّر معرفة نوع خط الزبون الآن.'
    }
  } catch (e) {
    if (mine === lookupRun) offersError.value = e?.message || 'تعذّر جلب العروض الآن.'
  } finally {
    if (mine === lookupRun) loading.value = false
  }
}
// «عروض» opens the offers of the number written; a new number loads its own
watch([tab, digits], () => {
  if (tab.value !== 'offer' || !access.offers.value) return
  if (!phoneOk.value) { lookupRun++; loading.value = false; offers.value = []; looked.value = false; return }
  if (digits.value !== offersFor || !looked.value) loadOffers()
})

function showDetails (o) {
  Dialog.create({ title: o.label, message: DETAILS[o.label], ok: 'حسنًا', position: 'bottom' })
}

function confirmOffer (o) {
  const p = digits.value
  if (p !== offersFor) { loadOffers(); return }
  Dialog.create({
    title: 'تأكيد العرض',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      <div style="text-align:center"><b>${o.label}</b>${DETAILS[o.label] ? ' — ' + DETAILS[o.label] : ''}</div>
      <div style="text-align:center">السعر: <b>${money(o.amount)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>`,
    cancel: 'رجوع',
    ok: 'نعم، أرسل'
  }).onOk(async () => {
    const r = await run(() => api.flexyOffer(customer.token, p, o.label, crypto.randomUUID()))
    if (!r) return
    buyer.refresh()
    phone.value = ''
    await loadFirst().catch(() => null)
    delay = 3000
    schedule()
  })
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
.offer-row { border-top: 1px solid #ECEEF3; padding: 10px 14px;
  cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; text-align: right; }
:deep(.family) { font-weight: 700; }
.price { font-weight: 700; white-space: nowrap; }
:deep(.phone) { font-size: 1.4rem; letter-spacing: 1px; }
</style>
