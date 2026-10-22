<template>
  <q-page class="page">
    <q-form class="card column q-gutter-sm" @submit.prevent="create">
      <div class="text-weight-bold">تعبئة إيدوم مباشرة</div>
      <div class="small muted">1) افحص عرض الخط. 2) اختر البطاقة المناسبة واشحن: يشتري المحل بطاقة واحدة ويشحنها هاتف Rech-Doom عبر My IDOOM.</div>
      <q-input v-model="line" dense outlined label="رقم خط IDOOM" inputmode="tel" placeholder="0XXXXXXXX" input-class="ltr text-right" />
      <q-btn outline color="primary" label="1) فحص العرض (بدون بطاقة)" :loading="busy" :disable="!lineOk" @click="lookup" />
      <div v-if="lastOffer" class="text-weight-bold">العرض: <span class="ltr">{{ lastOffer }}</span></div>
      <q-select v-model="productId" dense outlined emit-value map-options label="البطاقة" :options="productOptions"
        :hint="productOptions.length ? '' : 'لا توجد بطاقات إنترنت متوفرة في المخزن'" />
      <q-btn type="submit" unelevated color="primary" label="2) شحن" :loading="busy" :disable="!productId || !lineOk" />
    </q-form>

    <div class="row items-center justify-between q-mt-md">
      <div class="text-weight-bold">العمليات</div>
      <q-btn flat dense icon="refresh" aria-label="تحديث" @click="load" />
    </div>
    <q-list class="card q-pa-none">
      <q-item v-for="j in jobs" :key="j.id" style="border-top:1px solid #EEF0F5">
        <q-item-section>
          <q-item-label class="text-weight-bold ltr text-right">{{ j.line }}</q-item-label>
          <q-item-label caption>{{ j.kind === 'lookup' ? 'فحص العرض' : j.product_name }}<span v-if="j.offer"> · {{ j.offer }}</span><span v-if="j.executor_name"> · {{ j.executor_name }}</span></q-item-label>
          <q-item-label v-if="j.reply" caption class="ltr text-right">{{ j.reply }}</q-item-label>
          <q-item-label caption>{{ when(j.created_at) }}</q-item-label>
        </q-item-section>
        <q-item-section side class="items-end">
          <q-badge :color="STATUS[j.status]?.color || 'grey'">{{ STATUS[j.status]?.label || j.status }}</q-badge>
          <q-btn v-if="j.status === 'queued'" flat dense size="sm" color="negative" label="إلغاء" @click="cancel(j.id)" />
        </q-item-section>
      </q-item>
      <div v-if="loaded && !jobs.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </q-list>

    <q-form class="card column q-gutter-sm q-mt-md" @submit.prevent="addExecutor">
      <div class="text-weight-bold">ربط هاتف Rech-Doom</div>
      <div class="small muted">ينشئ رمزًا يُلصق مرة واحدة في تطبيق Rech-Doom. يظهر الرمز هنا مرة واحدة فقط.</div>
      <q-input v-model="executorName" dense outlined label="اسم الهاتف" />
      <q-btn type="submit" unelevated color="primary" label="إنشاء رمز" :loading="busy" :disable="!executorName.trim()" />
      <template v-if="token">
        <q-input :model-value="token" readonly dense outlined label="الرمز — انسخه الآن" input-class="ltr" />
        <q-btn unelevated color="positive" icon="content_copy" label="نسخ الرمز" @click="copyText(token)" />
        <div class="small text-negative">لن يظهر الرمز مرة أخرى بعد تحديث الصفحة. إن ضاع، أنشئ رمزًا جديدًا.</div>
      </template>
    </q-form>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { copyText } from 'src/composables/useCopy'

const STATUS = {
  queued: { label: 'في الانتظار', color: 'grey-7' },
  claimed: { label: 'الهاتف ينفذ', color: 'blue' },
  success: { label: 'ناجح', color: 'positive' },
  likely_success: { label: 'غالبًا ناجح — يحتاج تأكيد', color: 'teal' },
  used_card: { label: 'بطاقة مستعملة', color: 'negative' },
  failed: { label: 'فشل قبل الإرسال', color: 'orange' },
  review: { label: 'مراجعة', color: 'deep-orange' },
  cancelled: { label: 'أُلغي', color: 'grey' },
  looked_up: { label: 'تم الفحص', color: 'primary' }
}

const { busy, run } = useRun()
const catalog = ref([])
const jobs = ref([])
const loaded = ref(false)
const productId = ref(null)
const line = ref('')
const executorName = ref('')
const token = ref('')
let timer = null

const productOptions = computed(() => catalog.value
  .filter((p) => p.category === 'net' && p.available)
  .map((p) => ({ label: `${p.brand} — ${p.name}`, value: p.product_id })))

const digits = computed(() => line.value.replace(/\D/g, ''))
const lineOk = computed(() => /^0\d{8,9}$/.test(digits.value))
// Latest finished lookup for the line being typed
const lastOffer = computed(() => jobs.value.find((j) => j.kind === 'lookup' && j.line === digits.value && j.offer)?.offer)

const when = (t) => new Date(t).toLocaleString('ar-DZ')

async function load () {
  const data = await run(() => api.idoomJobs(30))
  if (data) jobs.value = data
  loaded.value = true
}

async function create () {
  const r = await run(() => api.idoomCreate(productId.value, line.value, crypto.randomUUID()),
    { success: 'أُرسلت العملية إلى الهاتف.' })
  if (!r) return
  line.value = ''
  load()
}

async function lookup () {
  if (await run(() => api.idoomLookup(line.value, crypto.randomUUID()), { success: 'أُرسل الفحص إلى الهاتف.' })) load()
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
