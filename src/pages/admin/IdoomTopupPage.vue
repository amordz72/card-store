<template>
  <q-page class="page">
    <div class="row items-center q-gutter-sm">
      <q-badge :color="phone.online ? 'positive' : 'negative'" class="q-pa-sm">{{ phone.label }}</q-badge>
    </div>

    <div class="card column q-gutter-sm">
      <div class="idoom-line text-center" dir="ltr">{{ pretty || '0XX XXX XXX' }}</div>
      <div v-if="check" class="text-center">
        <q-badge v-if="check.status === 'looked_up'" color="primary" class="q-pa-sm text-subtitle2 ltr">idoom · {{ check.offer }}</q-badge>
        <q-badge v-else-if="check.status === 'failed'" color="negative" class="q-pa-sm ltr">{{ check.reply || 'فشل التحقق' }}</q-badge>
        <span v-else class="muted">جارٍ التحقق في My IDOOM…</span>
      </div>
      <q-input v-model="line" dense outlined label="رقم خط IDOOM (9 أرقام)" inputmode="tel" maxlength="12"
        placeholder="0XXXXXXXX" input-class="ltr text-right" />
      <q-btn unelevated color="primary" icon="search" label="تحقق" :loading="busy" :disable="!lineOk" @click="lookup" />
    </div>

    <div v-if="check?.status === 'looked_up'" class="card column q-gutter-sm">
      <div class="text-weight-bold">اختر البطاقة</div>
      <div v-if="cards.length" class="row q-col-gutter-sm">
        <div v-for="c in cards" :key="c.product_id" class="col-6">
          <q-btn unelevated color="primary" class="full-width q-py-md" :disable="busy" @click="confirmCharge(c)">
            <div class="column items-center">
              <span class="text-h6">{{ c.base_price }} دج</span>
              <span class="small">{{ c.name }}</span>
            </div>
          </q-btn>
        </div>
      </div>
      <div v-else class="muted">لا توجد بطاقات إنترنت متوفرة في المخزن</div>
    </div>

    <div class="row items-center justify-between q-mt-md">
      <div class="text-weight-bold">العمليات</div>
      <q-btn flat dense icon="refresh" aria-label="تحديث" @click="load" />
    </div>
    <q-list class="card q-pa-none">
      <q-item v-for="j in jobs" :key="j.id" style="border-top:1px solid #EEF0F5">
        <q-item-section>
          <q-item-label class="text-weight-bold text-right"><span dir="ltr">{{ spaced(j.line) }}</span></q-item-label>
          <q-item-label caption>{{ j.kind === 'lookup' ? 'تحقق' : j.product_name }}<span v-if="j.offer"> · <span class="ltr">{{ j.offer }}</span></span></q-item-label>
          <q-item-label v-if="j.reply && j.status !== 'looked_up'" caption class="ltr text-right">{{ j.reply }}</q-item-label>
          <q-item-label caption>{{ when(j.created_at) }}</q-item-label>
        </q-item-section>
        <q-item-section side class="items-end">
          <q-badge :color="STATUS[j.status]?.color || 'grey'">{{ STATUS[j.status]?.label || j.status }}</q-badge>
          <q-btn v-if="j.status === 'queued'" flat dense size="sm" color="negative" label="إلغاء" @click="cancel(j.id)" />
        </q-item-section>
      </q-item>
      <div v-if="loaded && !jobs.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </q-list>

    <q-expansion-item class="card q-mt-md" icon="smartphone" label="ربط هاتف Rech-Doom" dense>
      <q-form class="column q-gutter-sm q-pt-sm" @submit.prevent="addExecutor">
        <div class="small muted">ينشئ رمزًا يُلصق مرة واحدة في تطبيق Rech-Doom.</div>
        <q-btn outline color="primary" icon="share" label="مشاركة رابط الموقع" @click="share(siteUrl, 'متجر البطاقات')" />
        <q-input v-model="executorName" dense outlined label="اسم الهاتف" />
        <q-btn type="submit" unelevated color="primary" label="إنشاء رمز" :loading="busy" :disable="!executorName.trim()" />
        <template v-if="token">
          <q-input :model-value="token" readonly dense outlined label="الرمز — انسخه الآن" input-class="ltr" />
          <q-btn unelevated color="positive" icon="content_copy" label="نسخ الرمز" @click="copyText(token)" />
          <q-btn outline color="positive" icon="share" label="مشاركة الرمز (بلوتوث، رسالة…)" @click="share(token, 'رمز هاتف Rech-Doom')" />
          <div class="small text-negative">لن يظهر الرمز مرة أخرى بعد تحديث الصفحة. إن ضاع، أنشئ رمزًا جديدًا.</div>
        </template>
      </q-form>
    </q-expansion-item>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/admin'

const STATUS = {
  queued: { label: 'في الانتظار', color: 'grey-7' },
  claimed: { label: 'الهاتف ينفذ', color: 'blue' },
  success: { label: 'ناجح', color: 'positive' },
  likely_success: { label: 'غالبًا ناجح — يحتاج تأكيد', color: 'teal' },
  used_card: { label: 'بطاقة مستعملة', color: 'negative' },
  failed: { label: 'فشل — البطاقة لم تُستعمل', color: 'orange' },
  review: { label: 'مراجعة', color: 'deep-orange' },
  cancelled: { label: 'أُلغي', color: 'grey' },
  looked_up: { label: 'تم التحقق', color: 'primary' }
}
const ONLINE_SECONDS = 60

const { busy, run } = useRun()
const catalog = ref([])
const jobs = ref([])
const phones = ref([])
const loaded = ref(false)
const line = ref('')
const executorName = ref('')
const token = ref('')
let timer = null

const digits = computed(() => line.value.replace(/\D/g, ''))
const lineOk = computed(() => /^0\d{8}$/.test(digits.value))
const spaced = (d) => (d || '').replace(/^(\d{3})(\d{3})(\d{3})$/, '$1 $2 $3')
const pretty = computed(() => spaced(digits.value))

// Latest check of the typed line (a pending one, or the last finished result)
const check = computed(() => lineOk.value
  ? jobs.value.find((j) => j.kind === 'lookup' && j.line === digits.value)
  : null)

const cards = computed(() => catalog.value
  .filter((p) => p.category === 'net' && p.available)
  .sort((a, b) => a.base_price - b.base_price))

const phone = computed(() => {
  const p = phones.value.find((x) => x.active && x.last_seen_at)
  if (!p) return { online: false, label: '🔴 لا يوجد هاتف متصل' }
  const age = Math.round((Date.now() - new Date(p.last_seen_at)) / 1000)
  if (age <= ONLINE_SECONDS) return { online: true, label: `🟢 الهاتف متصل (${p.name})` }
  return { online: false, label: `🔴 الهاتف غير متصل منذ ${age < 3600 ? Math.round(age / 60) + ' د' : Math.round(age / 3600) + ' سا'} (${p.name})` }
})

const siteUrl = window.location.origin + window.location.pathname

// System share sheet (Bluetooth, messages…); falls back to copying where sharing is unavailable.
async function share (text, title) {
  if (navigator.share) {
    try { await navigator.share({ title, text }) } catch { /* closed by the user */ }
  } else copyText(text)
}

const when = (t) => new Date(t).toLocaleString('ar-DZ')

async function load () {
  const [j, p] = await Promise.all([run(() => api.idoomJobs(30)), run(() => api.executors())])
  if (j) jobs.value = j
  if (p) phones.value = p
  loaded.value = true
}

async function lookup () {
  if (await run(() => api.idoomLookup(line.value, crypto.randomUUID()))) load()
}

function confirmCharge (c) {
  Dialog.create({
    title: 'تأكيد الشحن',
    html: true,
    message: `شحن <b dir="ltr">${pretty.value}</b><br>العرض: <span dir="ltr">${check.value.offer}</span><br>البطاقة: <b>${c.base_price} دج</b> (${c.name})`,
    cancel: 'إلغاء',
    ok: 'نعم، اشحن'
  }).onOk(async () => {
    const r = await run(() => api.idoomCreate(c.product_id, digits.value, crypto.randomUUID()),
      { success: 'أُرسل الشحن إلى الهاتف. تُسحب البطاقة بعد أن يتحقق الهاتف من الخط.' })
    if (r) load()
  })
}

async function cancel (id) {
  if (await run(() => api.idoomCancel(id), { success: 'أُلغيت العملية.' })) load()
}

async function addExecutor () {
  const r = await run(() => api.executorCreate(executorName.value))
  if (r) { token.value = r.token; executorName.value = '' }
}

onMounted(async () => {
  const data = await run(() => api.shopCatalog())
  if (data) catalog.value = data
  load()
  timer = setInterval(load, 5000)
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.idoom-line { font-size: 2.2rem; font-weight: 700; letter-spacing: 2px; }
</style>
