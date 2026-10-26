<template>
  <q-page class="page">
    <div class="row items-center q-gutter-sm">
      <q-badge :color="phone.online ? 'positive' : 'negative'" class="q-pa-sm">{{ phone.label }}</q-badge>
    </div>

    <div class="card column q-gutter-sm">
      <div class="idoom-line text-center" dir="ltr">{{ pretty || '0XX XXX XXX' }}</div>
      <div v-if="lineOk" class="text-center"><q-badge :color="is4g ? 'indigo' : 'purple'">{{ is4g ? '4G LTE' : 'ADSL / FTTH' }}</q-badge></div>
      <div v-if="check && check.status !== 'looked_up'" class="text-center">
        <template v-if="check.status === 'failed'">
          <q-badge color="negative" class="q-pa-sm">فشل التحقق — لم تُستعمل أي بطاقة</q-badge>
          <div v-if="check.reply" class="small muted ltr text-left q-mt-xs wrap-any">{{ check.reply }}</div>
        </template>
        <span v-else class="muted">جارٍ التحقق في My IDOOM…</span>
      </div>
      <div v-if="lineOk && known" class="text-center">
        <q-badge color="primary" class="q-pa-sm text-subtitle2 ltr">idoom · {{ known.offer }}</q-badge>
        <div class="small muted q-mt-xs">آخر تحقق {{ ago(known.checked_at) }}<span v-if="!fresh"> — سيُتحقق من الخط عند الشحن</span></div>
      </div>
      <div v-else-if="lineOk && infoLoaded && !check" class="small muted text-center">لم يُتحقق من هذا الخط بعد — الهاتف يتحقق منه تلقائيًا قبل استعمال البطاقة</div>
      <q-input v-model="line" dense outlined label="رقم الخط: ثابت 9 أرقام أو 4G يبدأ بـ 213" inputmode="tel" maxlength="16"
        placeholder="0XXXXXXXX" input-class="ltr text-right" />
      <q-btn outline color="primary" icon="search" label="تحقق (اختياري)" :loading="busy" :disable="!lineOk" @click="lookup" />
    </div>

    <!-- Cards show at once: every top-up checks the line on the phone before a card is taken -->
    <div v-if="lineOk" class="card column q-gutter-sm">
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
      <div v-else class="muted">لا توجد بطاقات {{ is4g ? 'Idoom 4G' : 'Idoom ADSL' }} متوفرة في المخزن</div>
    </div>

    <div class="row items-center justify-between q-mt-md">
      <div class="text-weight-bold">العمليات</div>
      <q-btn flat dense icon="refresh" aria-label="تحديث" @click="load" />
    </div>
    <!-- Operations as a compact table (owner reference: Hani Rohek): number · status · type, details stacked below -->
    <div class="card q-pa-none">
      <div v-for="j in jobs" :key="j.id" class="op-row">
        <div class="op-cells">
          <div class="op-line">
            <span dir="ltr" class="text-weight-bold">{{ spaced(j.line) }}</span>
            <q-btn flat dense round size="sm" icon="content_copy" aria-label="نسخ الرقم" @click="copyText(j.line)" />
          </div>
          <q-badge class="op-status" :color="STATUS[j.status]?.color || 'grey'">{{ STATUS[j.status]?.label || j.status }}</q-badge>
          <div class="op-type">
            <span class="op-chip" :class="j.kind === 'lookup' ? 'chip-check' : (isLte(j.line) ? 'chip-4g' : 'chip-adsl')">
              {{ j.kind === 'lookup' ? 'تحقق' : (isLte(j.line) ? '4G' : 'ADSL') }}
            </span>
            <span v-if="j.kind !== 'lookup' && amount(j.product_name)" class="op-amount">{{ amount(j.product_name) }}</span>
          </div>
        </div>
        <div class="op-details small muted">
          <span>{{ when(j.created_at) }}</span>
          <span v-if="j.customer_name"> · <b>{{ j.customer_name }}</b><span v-if="j.attempt > 1"> (محاولة {{ j.attempt }})</span></span>
          <span v-if="j.offer"> · <span class="ltr">{{ j.offer }}</span></span>
          <div v-if="j.reply && j.status !== 'looked_up'" class="ltr text-left wrap-any">{{ j.reply }}</div>
          <q-btn v-if="j.status === 'queued'" flat dense size="sm" color="negative" label="إلغاء" @click="cancel(j.id)" />
          <div v-if="j.status === 'review' && j.customer_name" class="row q-gutter-sm q-mt-xs">
            <q-btn unelevated dense size="sm" color="positive" label="تمت" @click="resolve(j, true)" />
            <q-btn outline dense size="sm" color="negative" label="لم تتم — استرداد للزبون" @click="resolve(j, false)" />
          </div>
        </div>
      </div>
      <div v-if="loaded && !jobs.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>

    <q-expansion-item class="card q-mt-md" icon="smartphone" label="ربط هاتف Rech-Doom" dense>
      <q-form class="column q-gutter-sm q-pt-sm" @submit.prevent="addExecutor">
        <div class="small muted">ثبّت تطبيق Rech-Doom على الهاتف، ثم أنشئ رمزًا يُلصق فيه مرة واحدة.</div>
        <q-btn unelevated color="primary" icon="download" label="تنزيل تطبيق Rech-Doom" :href="apkUrl" download="rech-doom.apk" />
        <!-- Android browsers refuse to share .apk files, so the other phone gets the link or scans it -->
        <q-btn outline color="primary" icon="share" label="إرسال رابط التطبيق لهاتف آخر" @click="share(OFFICIAL_APK, 'تطبيق Rech-Doom')" />
        <div class="row items-center no-wrap q-gutter-sm">
          <img v-if="apkQr" :src="apkQr" alt="رمز QR لتنزيل التطبيق" width="132" height="132" class="qr">
          <div class="small muted">أو امسح هذا الرمز بكاميرا الهاتف الآخر لتنزيل التطبيق مباشرة.</div>
        </div>
        <div v-if="apk" class="small muted">النسخة <bdi dir="ltr">{{ apk.version }}</bdi> · <bdi>{{ when(apk.built_at) }}</bdi></div>
        <!-- 0.8.0 is signed with a new key (the 0.7.x key was lost): older installs must be removed once -->
        <div class="small muted">من النسخة 0.8.0 تغيّر مفتاح التوقيع: احذف Rech-Doom القديم مرة واحدة قبل التثبيت.</div>
        <q-btn outline color="primary" icon="share" label="مشاركة رابط الموقع" @click="share(OFFICIAL_SITE, 'متجر البطاقات')" />
        <template v-if="phones.length">
          <div class="text-weight-bold q-mt-sm">الهواتف المربوطة</div>
          <div class="small muted">المهمة يأخذها أول هاتف مفعّل يستقبل. عطّل الهاتف الذي لا تريده أن ينفذ.</div>
          <div v-for="p in phones" :key="p.id" class="row items-center no-wrap q-gutter-sm">
            <div class="col">
              <div :class="{ muted: !p.active }">{{ p.name }}</div>
              <div class="small muted">{{ p.last_seen_at ? 'آخر اتصال ' + ago(p.last_seen_at) : 'لم يتصل بعد' }}</div>
            </div>
            <q-btn flat dense size="sm" color="primary" icon="key" label="رمز جديد" :disable="busy" @click="newToken(p)" />
            <q-toggle :model-value="p.active" :label="p.active ? 'مفعّل' : 'معطّل'" color="positive" :disable="busy"
              @update:model-value="(v) => setActive(p, v)" />
            <q-btn v-if="!p.active" flat dense round size="sm" color="negative" icon="delete" :disable="busy"
              aria-label="حذف الهاتف" @click="removePhone(p)" />
          </div>
        </template>
        <q-input v-model="executorName" dense outlined label="اسم الهاتف" />
        <q-btn type="submit" unelevated color="primary" label="إنشاء رمز" :loading="busy" :disable="!executorName.trim()" />
        <template v-if="token">
          <q-input :model-value="token" readonly dense outlined :label="`رمز ${tokenFor} — انسخه الآن`" input-class="ltr" />
          <q-btn unelevated color="positive" icon="content_copy" label="نسخ الرمز" @click="copyText(token)" />
          <q-btn outline color="positive" icon="share" label="مشاركة الرمز (بلوتوث، رسالة…)" @click="shareToken" />
          <div class="small text-negative">لن يظهر الرمز مرة أخرى بعد تحديث الصفحة. إن ضاع، اضغط «رمز جديد» بجانب الهاتف.</div>
        </template>
      </q-form>
    </q-expansion-item>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/admin'
import QRCode from 'qrcode'
import { useBell } from 'src/composables/useBell'

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
const { refreshBell } = useBell()
const catalog = ref([])
const jobs = ref([])
const phones = ref([])
const loaded = ref(false)
const line = ref('')
const executorName = ref('')
const token = ref('')
const tokenFor = ref('')
let timer = null

const digits = computed(() => line.value.replace(/\D/g, ''))
const lineOk = computed(() => /^(0\d{8}|213\d{9})$/.test(digits.value))
// 4G LTE lines are 12 digits starting with 213; fixed lines (ADSL/FTTH) are 9 digits
const is4g = computed(() => /^213\d{9}$/.test(digits.value))
const spaced = (d) => (d || '').replace(/^(\d{3})(\d{3})(\d{3})(\d{3})?$/, (m, a, b, c, e) => [a, b, c, e].filter(Boolean).join(' '))
const pretty = computed(() => spaced(digits.value))
const isLte = (line) => /^213\d{9}$/.test(line || '')
// Card value from the product name, e.g. "Idoom 4G 1000 · 40GO / شهر" → 1000
const amount = (name) => (name || '').match(/\b(\d{3,5})\b/)?.[1] || ''


// Last known offer of the typed line (from any check or top-up); display only
const FRESH_DAYS = 30
const known = ref(null)
const infoLoaded = ref(false)
const fresh = computed(() => known.value && Date.now() - new Date(known.value.checked_at) < FRESH_DAYS * 864e5)
const ago = (t) => {
  const m = Math.round((Date.now() - new Date(t)) / 60000)
  if (m < 60) return `منذ ${m} د`
  if (m < 1440) return `منذ ${Math.round(m / 60)} سا`
  return `منذ ${Math.round(m / 1440)} يوم`
}
async function loadInfo () {
  known.value = null
  infoLoaded.value = false
  if (!lineOk.value) return
  const want = digits.value
  const r = await run(() => api.idoomLineInfo(want))
  if (want === digits.value) { known.value = r || null; infoLoaded.value = true }
}

// Latest check of the typed line (a pending one, or the last finished result)
const check = computed(() => lineOk.value
  ? jobs.value.find((j) => j.kind === 'lookup' && j.line === digits.value)
  : null)

const cards = computed(() => catalog.value
  .filter((p) => p.category === 'net' && p.available && /4g|lte/i.test(p.brand + ' ' + p.name) === is4g.value)
  .sort((a, b) => a.base_price - b.base_price))

const phone = computed(() => {
  const p = phones.value.find((x) => x.active && x.last_seen_at)
  if (!p) return { online: false, label: '🔴 لا يوجد هاتف متصل' }
  const age = Math.round((Date.now() - new Date(p.last_seen_at)) / 1000)
  if (age <= ONLINE_SECONDS) return { online: true, label: `🟢 الهاتف متصل (${p.name})` }
  return { online: false, label: `🔴 الهاتف غير متصل منذ ${age < 3600 ? Math.round(age / 60) + ' د' : Math.round(age / 3600) + ' سا'} (${p.name})` }
})

const siteUrl = window.location.origin + window.location.pathname
// Published here by the Rech-Doom build (same key every version, so it installs over the old one)
const apkUrl = new URL('apps/rech-doom.apk', siteUrl).href
const apk = ref(null)
// Shared links always point at the one official site, whichever host this page was opened from.
// The owner setting «الرابط الرسمي» (v1.32) wins over the built-in link.
const OFFICIAL_SITE = ref(api.DEFAULT_OFFICIAL_SITE)
const OFFICIAL_APK = computed(() => OFFICIAL_SITE.value + 'apps/rech-doom.apk')
const apkQr = ref('')
watch(OFFICIAL_APK, (link) => {
  QRCode.toDataURL(link, { margin: 1, width: 264 }).then((url) => { apkQr.value = url }).catch(() => {})
}, { immediate: true })

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
    message: `شحن <b dir="ltr">${pretty.value}</b><br>العرض: ${known.value ? `<span dir="ltr">${known.value.offer}</span>` : 'يُقرأ عند الشحن'}<br>البطاقة: <b>${c.base_price} دج</b> (${c.name})`,
    cancel: 'إلغاء',
    ok: 'نعم، اشحن'
  }).onOk(async () => {
    const r = await run(() => api.idoomCreate(c.product_id, digits.value, crypto.randomUUID()),
      { success: 'أُرسل الشحن إلى الهاتف. تُسحب البطاقة بعد أن يتحقق الهاتف من الخط.' })
    if (r) load()
  })
}

// A customer's top-up in review: the owner decides; «لم تتم» refunds the customer in full
function resolve (j, done) {
  Dialog.create({
    title: done ? 'تأكيد: تمت التعبئة' : 'تأكيد: لم تتم التعبئة',
    message: done ? `تُسجّل تعبئة ${j.line} لـ${j.customer_name} ناجحة.` : `يُعاد المبلغ كاملًا إلى ${j.customer_name}. البطاقة لا تعود إلى المخزن.`,
    cancel: 'رجوع',
    ok: 'تأكيد'
  }).onOk(async () => {
    if (await run(() => api.idoomResolve(j.id, done).then(() => true), { success: 'سُجّل القرار.' })) { load(); refreshBell() }
  })
}

async function cancel (id) {
  if (await run(() => api.idoomCancel(id), { success: 'أُلغيت العملية.' })) load()
}

async function addExecutor () {
  const r = await run(() => api.executorCreate(executorName.value))
  if (r) { token.value = r.token; tokenFor.value = executorName.value; executorName.value = ''; load() }
}

// Shown once, so a lost token is replaced: the phone's old token stops working at once
function newToken (p) {
  Dialog.create({
    title: `رمز جديد لـ${p.name}`,
    message: 'الرمز القديم لهذا الهاتف يتوقف فورًا، والصق الجديد في تطبيق Rech-Doom.',
    cancel: 'رجوع',
    ok: 'إنشاء رمز جديد'
  }).onOk(async () => {
    const t = await run(() => api.executorNewToken(p.id))
    if (t) { token.value = t; tokenFor.value = p.name }
  })
}

// Bluetooth turns shared text into an .html page with no copy button: send a plain .txt file instead
async function shareToken () {
  const file = new File([token.value], 'rech-doom-token.txt', { type: 'text/plain' })
  if (navigator.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file], title: 'رمز هاتف Rech-Doom' }) } catch { /* closed by the user */ }
  } else share(token.value, 'رمز هاتف Rech-Doom')
}

async function setActive (p, active) {
  if (await run(() => api.executorSetActive(p.id, active).then(() => true),
    { success: active ? `فُعّل ${p.name}.` : `عُطّل ${p.name}. أوقف الاستقبال فيه أيضًا.` })) load()
}

// Only a disabled phone; the old phone's token stops for good and its past jobs stay as they are
function removePhone (p) {
  Dialog.create({
    title: `حذف ${p.name}؟`,
    message: 'يختفي من القائمة ولا يستقبل أي مهمة بعد اليوم، ولا يمكن إرجاعه. العمليات السابقة تبقى كما هي.',
    cancel: 'رجوع',
    ok: { label: 'حذف', color: 'negative' }
  }).onOk(async () => {
    if (await run(() => api.executorDelete(p.id).then(() => true), { success: `حُذف ${p.name}.` })) load()
  })
}

onMounted(async () => {
  const data = await run(() => api.shopCatalog())
  if (data) catalog.value = data
  api.siteLinks().then((l) => { if (l.officialUrl) OFFICIAL_SITE.value = l.officialUrl }).catch(() => {})
  fetch(new URL('apps/rech-doom.json', siteUrl), { cache: 'no-store' })
    .then((r) => (r.ok ? r.json() : null)).then((j) => { apk.value = j }).catch(() => {})
  load()
  timer = setInterval(load, 5000)
})
onUnmounted(() => clearInterval(timer))
watch(digits, loadInfo)
// a check that just finished updates the known offer
watch(() => check.value?.status, (s) => { if (s === 'looked_up') loadInfo() })
</script>

<style scoped>
.idoom-line { font-size: 2.2rem; font-weight: 700; letter-spacing: 2px; }
/* raw My IDOOM replies can be long: wrap inside the card, never widen the page */
.wrap-any { white-space: normal; overflow-wrap: anywhere; }
.qr { border: 1px solid #ECEEF3; border-radius: 8px; background: #fff; flex-shrink: 0; }
.op-row { padding: 10px 12px; border-top: 1px solid #EEF0F5; }
.op-row:first-child { border-top: 0; }
.op-cells { display: grid; grid-template-columns: auto minmax(0, 1fr) auto; align-items: center; gap: 8px; }
.op-line { display: flex; align-items: center; gap: 2px; white-space: nowrap; font-size: 1.05rem; }
.op-status { justify-self: center; white-space: normal; text-align: center; line-height: 1.3; }
.op-type { display: flex; align-items: center; justify-content: flex-end; gap: 6px; }
.op-chip { font-size: .75rem; font-weight: 700; padding: 2px 8px; border-radius: 6px; color: #fff; }
.chip-adsl { background: #76509B; }
.chip-4g { background: #2452A4; }
.chip-check { background: #9CA3AF; }
.op-amount { background: #1F2937; color: #fff; font-weight: 700; padding: 2px 10px; border-radius: 8px; }
.op-details { margin-top: 4px; }
</style>
