<template>
  <q-page class="page">
    <div class="card small">
      اختبار الاتصال بنواة Flexy. <b>قراءة فقط</b>: لا يُرسل أي رصيد ولا أي USSD، والرقم لا يُحفظ.
    </div>
    <div class="card">
      <q-btn unelevated rounded no-caps color="primary" icon="bolt" label="القدرات" :loading="busy === 'cap'" @click="runCapabilities" />
    </div>
    <div class="card grid-2">
      <q-input v-model="phone" dense outlined label="رقم موبيليس" inputmode="tel" autocomplete="off" />
      <q-input v-model.number="amount" dense outlined type="number" label="المبلغ (دج)" />
      <q-select v-model="account" :options="accounts" emit-value map-options dense outlined label="حساب الموزع" />
      <q-btn unelevated rounded no-caps color="primary" icon="fact_check" label="تحقق" :loading="busy === 'val'" @click="runValidate" />
    </div>
    <div v-if="result" class="card">
      <div class="small">
        النتيجة: <b :class="result.status === 200 ? 'text-positive' : 'text-negative'">{{ result.status }}</b>
        · {{ verdict }}
      </div>
      <pre dir="ltr" class="small q-mt-sm" style="white-space:pre-wrap;word-break:break-all">{{ pretty }}</pre>
    </div>
    <!-- Owner settings (v1.32): site links instead of constants in the code -->
    <q-expansion-item class="card q-pa-none" icon="settings" label="روابط الموقع" @show="loadLinks">
      <div class="column q-gutter-sm q-pa-md">
        <div class="text-weight-bold">الرابط الرسمي</div>
        <div class="small muted">يُرسل لهاتف آخر من صفحة إيدوم (رابط الموقع ورابط تطبيق Rech-Doom). فارغ = <bdi dir="ltr">{{ defaultSite }}</bdi></div>
        <q-input v-model="officialUrl" dense outlined label="https://…/" input-class="ltr text-left" />
        <q-btn unelevated color="primary" label="حفظ الرابط الرسمي" :loading="saving" @click="saveOfficial" />
        <q-separator />
        <div class="text-weight-bold">مواقع إضافية مسموحة</div>
        <div class="small muted">
          نسخ أخرى من المتجر يُسمح لها باختبار Flexy، مثل نسخة Cloudflare. <bdi dir="ltr">amordz72.github.io</bdi> مسموح دائمًا.
          سطر لكل موقع، مثل <bdi dir="ltr">https://card-store-eej.pages.dev</bdi>. الحد 3. يسري التغيير خلال دقيقة.
        </div>
        <q-input v-model="originsText" type="textarea" autogrow dense outlined input-class="ltr text-left" />
        <div class="small text-negative">⚠ احذف الموقع من هنا قبل حذف موقعه: الاسم المحذوف قد يأخذه غيرك.</div>
        <q-btn unelevated color="primary" label="حفظ المواقع" :loading="saving" @click="saveOrigins" />
      </div>
    </q-expansion-item>
  </q-page>
</template>

<script setup>
import { computed, ref } from 'vue'
import * as flexy from 'src/api/flexy'
import * as admin from 'src/api/admin'
import { useRun } from 'src/composables/useRun'

const accounts = [
  { value: '01', label: '01 POSTE' }, { value: '02', label: '02 ASSILOU' }, { value: '03', label: '03 DATA' },
  { value: '04', label: '04 GTS' }, { value: '05', label: '05 MOBILIS' }
]
const phone = ref('')
const amount = ref(100)
const account = ref('05')
const busy = ref('')
const result = ref(null)

const VERDICTS = {
  200: 'الاتصال بالنواة يعمل والمفتاح صحيح',
  401: 'النواة رفضت مفتاح المتجر: قيمة FLEXY_CARD_STORE_KEY لا تطابق',
  403: 'هذا الحساب ليس مديرًا، أو انتهت الجلسة',
  422: 'الاتصال يعمل، والنواة رفضت الطلب (انظر الخطأ)',
  500: 'المفتاح غير موجود في الخادم، أو خطأ داخلي',
  502: 'تعذّر الوصول إلى النواة'
}
const verdict = computed(() => VERDICTS[result.value?.status] || 'رد غير متوقع')
const pretty = computed(() => JSON.stringify(result.value?.body, null, 2))

async function go (kind, fn) {
  busy.value = kind
  try { result.value = await fn() } finally { busy.value = '' }
}
const runCapabilities = () => go('cap', () => flexy.capabilities())
const runValidate = () => go('val', () => flexy.validate(phone.value, Number(amount.value), account.value))

// Site links
const { busy: saving, run } = useRun()
const defaultSite = admin.DEFAULT_OFFICIAL_SITE
const officialUrl = ref('')
const originsText = ref('')
async function loadLinks () {
  const l = await run(() => admin.siteLinks())
  if (!l) return
  officialUrl.value = l.officialUrl
  originsText.value = l.extraOrigins.join('\n')
}
async function saveOfficial () {
  if (await run(() => admin.setOfficialUrl(officialUrl.value.trim()).then(() => true), { success: 'حُفظ الرابط الرسمي.' })) loadLinks()
}
async function saveOrigins () {
  const list = originsText.value.split(/\s+/).filter(Boolean)
  if (await run(() => admin.setExtraOrigins(list).then(() => true), { success: 'حُفظت المواقع.' })) loadLinks()
}
</script>
