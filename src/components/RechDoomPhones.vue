<template>
  <!-- «ربط هاتف Rech-Doom» (owner 2026-11-01): moved here from «تعبئة إيدوم», beside the phones 📱 -->
    <q-expansion-item class="card q-pa-none" icon="smartphone" label="ربط هاتف Rech-Doom" dense>
      <q-form class="column q-gutter-sm q-pt-sm" @submit.prevent="addExecutor">
        <div class="small muted">ثبّت تطبيق Rech-Doom على الهاتف، ثم أنشئ رمزًا يُلصق فيه مرة واحدة.</div>
        <q-btn unelevated color="primary" icon="download" label="تنزيل تطبيق Rech-Doom" :href="apkUrl" :download="apkName" />
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
          <div class="help small muted">المهمة يأخذها أول هاتف مفعّل يستقبل. عطّل الهاتف الذي لا تريده أن ينفذ.</div>
          <div v-for="p in phones" :key="p.id" class="row items-center no-wrap q-gutter-sm">
            <div class="col">
              <div :class="{ muted: !p.active }">{{ p.name }}</div>
              <div class="small muted">{{ p.last_seen_at ? 'آخر اتصال ' + ago(p.last_seen_at) : 'لم يتصل بعد' }}</div>
            </div>
            <q-btn flat dense size="sm" color="primary" icon="key" label="رمز جديد" :disable="busy" @click="newToken(p)" />
            <q-toggle :model-value="p.active" :label="p.active ? 'مفعّل' : 'معطّل'" color="positive" :disable="busy"
              @update:model-value="(v) => setActive(p, v)" />
            <!-- s164: this phone also takes Free Fire orders (Shop2game, Rech-Doom 0.9.1); off by default -->
            <q-toggle v-if="p.active && gameKnown" :model-value="Boolean(gameOn[p.id])" label="Free Fire" color="deep-orange" :disable="busy"
              @update:model-value="(v) => setGame(p, v)" />
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
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/admin'
import QRCode from 'qrcode'

const { busy, run } = useRun()
const phones = ref([])
const executorName = ref('')
const token = ref('')
const tokenFor = ref('')
const ago = (t) => {
  const m = Math.round((Date.now() - new Date(t)) / 60000)
  if (m < 60) return `منذ ${m} د`
  if (m < 1440) return `منذ ${Math.round(m / 60)} سا`
  return `منذ ${Math.round(m / 1440)} يوم`
}
const when = (t) => new Date(t).toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers' })

const siteUrl = window.location.origin + window.location.pathname
// Published here by the Rech-Doom build (same key every version, so it installs over the old one)
const apk = ref(null)
// The saved file carries its version (owner 2026-10-31: «always the same name, I can't tell them apart»),
// and ?v= stops the browser from handing back the old cached file.
const apkVer = computed(() => apk.value?.version || '')
const apkUrl = computed(() => new URL('apps/rech-doom.apk' + (apkVer.value ? `?v=${apkVer.value}` : ''), siteUrl).href)
const apkName = computed(() => `Rech-Doom-${apkVer.value || 'latest'}.apk`)
// Shared links always point at the one official site, whichever host this page was opened from.
// The owner setting «الرابط الرسمي» (v1.32) wins over the built-in link.
const OFFICIAL_SITE = ref(api.DEFAULT_OFFICIAL_SITE)
const OFFICIAL_APK = computed(() => OFFICIAL_SITE.value + 'apps/rech-doom.apk' + (apkVer.value ? `?v=${apkVer.value}` : ''))
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

async function load () {
  const p = await run(() => api.executors())
  if (p) phones.value = p
  // Before s164 is applied the view is missing: the switch simply does not show
  api.gamePhoneView().then((v) => { gameOn.value = Object.fromEntries((v?.phones || []).map((x) => [x.id, x.game_on])); gameKnown.value = true })
    .catch(() => { gameKnown.value = false })
}
const gameOn = ref({})
const gameKnown = ref(false)
async function setGame (p, on) {
  if (await run(() => api.executorGame(p.id, on).then(() => true), { success: on ? `${p.name} يأخذ طلبات Free Fire الآن.` : `${p.name} لم يعد يأخذ Free Fire.` })) load()
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

onMounted(() => {
  api.siteLinks().then((l) => { if (l.officialUrl) OFFICIAL_SITE.value = l.officialUrl }).catch(() => {})
  fetch(new URL('apps/rech-doom.json', siteUrl), { cache: 'no-store' })
    .then((r) => (r.ok ? r.json() : null)).then((j) => { apk.value = j }).catch(() => {})
  load()
})
</script>

<style scoped>
.qr { border: 1px solid #ECEEF3; border-radius: 8px; background: #fff; flex-shrink: 0; }
.help { line-height: 1.5; }
</style>
