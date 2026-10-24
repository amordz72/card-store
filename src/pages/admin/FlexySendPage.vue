<template>
  <q-page class="page">
    <div class="card small">
      إرسال رصيد Mobilis حقيقي عبر أرسلي <b>630</b>، من حسابك أنت فقط. كل ضغطة «أرسل» = عملية واحدة، ولا إعادة محاولة تلقائية.
    </div>

    <div class="card grid-2">
      <q-input v-model="phone" dense outlined label="رقم موبيليس (06…)" inputmode="tel" autocomplete="off" :disable="locked" />
      <q-input v-model.number="amount" dense outlined type="number" label="المبلغ (دج)" :disable="locked" />
      <q-btn unelevated rounded no-caps color="primary" icon="fact_check" label="تحقق" :loading="busy === 'pre'" :disable="locked" @click="check" />
    </div>

    <div v-if="pre && !op" class="card">
      <template v-if="pre.ready">
        <div>سيُرسل <b>{{ pre.request.amount }} دج</b> إلى <bdi dir="ltr"><b>{{ pre.request.phone }}</b></bdi> من حساب الموزع <b>{{ pre.distributor_account }}</b>.</div>
        <div class="row q-gutter-sm q-mt-md">
          <q-btn unelevated rounded no-caps color="negative" icon="send" label="أرسل الآن" :loading="busy === 'send'" @click="send" />
          <q-btn flat rounded no-caps label="إلغاء" :disable="busy === 'send'" @click="reset" />
        </div>
      </template>
      <div v-else class="text-negative">المحطة غير جاهزة: <bdi dir="ltr">{{ pre.reason || '—' }}</bdi>. لم يُرسل شيء.</div>
    </div>

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
import * as flexy from 'src/api/flexy'

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
  IDEMPOTENCY_CONFLICT: 'نفس العملية بطلب مختلف. ابدأ عملية جديدة.',
  STATION_CONNECT_UNREACHABLE: 'تعذّر الوصول إلى Station Connect. لم يُرسل شيء.'
}

const phone = ref('')
const amount = ref(100)
const busy = ref('')
const pre = ref(null)
const op = ref(null)
const key = ref('')
const error = ref('')
const following = ref(false)
let timer = null

const locked = computed(() => !!op.value || busy.value === 'send')

function remember (k) {
  try { k ? localStorage.setItem(LAST_KEY, k) : localStorage.removeItem(LAST_KEY) } catch { /* private mode */ }
}

function show (res) {
  if (res.body?.operation) op.value = res.body.operation
  error.value = res.body?.ok === false && res.body?.error ? (ERRORS[res.body.error] || res.body.error) : ''
}

async function check () {
  error.value = ''
  pre.value = null
  busy.value = 'pre'
  try {
    const res = await flexy.ownerPreflight(phone.value, Number(amount.value))
    if (res.status === 200) pre.value = res.body
    else show(res)
  } finally { busy.value = '' }
}

async function send () {
  if (!pre.value?.ready) return
  // One key per confirmed form: a double click or a retry of this same click can never send twice.
  if (!key.value) key.value = 'owner_' + crypto.randomUUID().replace(/-/g, '')
  remember(key.value)
  busy.value = 'send'
  try {
    show(await flexy.ownerSend(pre.value.request.phone, pre.value.request.amount, pre.value.distributor_account, key.value))
  } finally { busy.value = '' }
  if (op.value?.status === 'running') follow()
}

async function follow () {
  if (!key.value || following.value) return
  following.value = true
  try {
    for (let i = 0; i < POLL_MAX; i++) {
      const res = await flexy.ownerStatus(key.value)
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
  // Back after a reload: keep following the last operation instead of losing it.
  let last = ''
  try { last = localStorage.getItem(LAST_KEY) || '' } catch { last = '' }
  if (last) { key.value = last; follow() }
})
onBeforeUnmount(() => clearTimeout(timer))
</script>
