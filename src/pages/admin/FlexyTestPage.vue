<template>
  <q-page class="page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
    <!-- «المختبر» (owner 2026-10-29): one real try of a Mobilis offer, its source forced, its steps shown.
         Real money: the owner confirms each try. Kept as his own operation like any other. -->
    <div class="card column q-gutter-sm lab">
      <div class="text-weight-bold">المختبر · إرسال تجريبي حقيقي</div>
      <div class="small text-deep-orange-9">مال حقيقي: كل تجربة ترسل العرض فعلًا إلى الرقم.</div>
      <q-input v-model="labPhone" dense outlined label="رقم موبيليس" inputmode="tel" autocomplete="off" />
      <q-input v-model="labOffer" dense outlined label="العرض (كما في الكتالوج)" />
      <div class="row q-gutter-xs">
        <q-btn v-for="o in LAB_OFFERS" :key="o" dense no-caps rounded size="sm" outline color="primary" :label="o" @click="labOffer = o" />
      </div>
      <div class="row items-center q-gutter-sm">
        <span class="small muted">المصدر</span>
        <q-btn-toggle v-model="labRoute" dense no-caps unelevated toggle-color="primary"
          :options="[{ label: 'تلقائي', value: '' }, { label: 'أرسلي', value: 'arsselli' }, { label: 'سما', value: 'sama' }]" />
      </div>
      <q-btn unelevated no-caps color="deep-orange" icon="science" label="جرّب" :loading="labBusy"
        :disable="!/^0[67]\d{8}$/.test(labPhone.replace(/\s/g, '')) || !labOffer.trim()" @click="labTry" />
      <div v-if="lab" class="column q-gutter-xs">
        <div class="text-weight-bold" :class="LAB_CLASS[lab.status] || ''">{{ LAB_STATUS[lab.status] || lab.status }}<template v-if="lab.code"> · {{ lab.code }}</template></div>
        <div v-if="lab.sim" class="small muted">من {{ lab.sim }}<template v-if="lab.station"> · {{ lab.station }}</template> · {{ lab.kind }}</div>
        <div v-for="(st, i) in lab.steps" :key="i" class="step small">
          <span class="muted">{{ i + 1 }}. {{ STEP[st.action] || st.action }}<template v-if="st.status !== 'success'"> · {{ st.status === 'unknown' ? 'بلا رد' : 'لم يُرسل' }}</template></span>
          <div v-if="st.raw" class="ltr raw">{{ st.raw }}</div>
        </div>
        <div v-if="lab.error" class="small text-negative">{{ lab.error }}</div>
      </div>
    </div>
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
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import { computed, ref } from 'vue'
import { Dialog } from 'quasar'
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

// «المختبر»
const LAB_OFFERS = ['Sama Mix 50', 'Mixed 100', 'PixX 50', 'Revolution 100', 'Sama Mix 500']
const LAB_STATUS = { queued: 'في الطابور', running: 'جارية…', accepted: 'قبلتها الشبكة (تنتظر الحسم)', success: 'نجحت', failed: 'فشلت', not_sent: 'لم تُرسل (لم يُخصم شيء)', review: 'قيد المراجعة' }
const LAB_CLASS = { success: 'text-positive', failed: 'text-negative', not_sent: 'text-deep-orange-9', review: 'text-deep-orange-9' }
const STEP = { ussd_start: 'بدء الجلسة', ussd_reply: 'رد', ussd_release: 'إنهاء الجلسة' }
const LAB_ERRORS = { ROUTE_NOT_POSSIBLE: 'هذا العرض لا يمر من هذا المصدر.', OFFER_UNKNOWN: 'عرض غير معروف: اكتب اسمه كما في الكتالوج.', APP_SEND_DISABLED: 'الإرسال الحقيقي مقفل (المفاتيح).' }
const labPhone = ref('')
const labOffer = ref('Sama Mix 50')
const labRoute = ref('arsselli')
const labBusy = ref(false)
const lab = ref(null)
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
function labTry () {
  const phone = labPhone.value.replace(/\s/g, '')
  const offer = labOffer.value.trim()
  const src = labRoute.value === 'arsselli' ? 'أرسلي' : labRoute.value === 'sama' ? 'سما' : 'المصدر التلقائي'
  Dialog.create({ title: 'تجربة حقيقية', message: 'يُرسل «' + offer + '» إلى …' + phone.slice(-2) + ' من ' + src + '. مال حقيقي. متأكد؟', cancel: 'لا', ok: 'جرّب' })
    .onOk(() => labRun(phone, offer, labRoute.value))
}
async function labRun (phone, offer, route) {
  labBusy.value = true
  const key = 'own665_' + crypto.randomUUID().replace(/-/g, '')
  lab.value = { status: 'queued', steps: [], kind: route === 'arsselli' ? 'أرسلي' : route === 'sama' ? 'سما' : 'تلقائي' }
  try {
    let r = await flexy.ownerLabSend(phone, offer, key, route || null)
    // A busy source keeps the request's place: asked again with the same key (2 minutes at most)
    for (const end = Date.now() + 120_000; r.status === 409 && r.body?.error === 'SOURCE_BUSY' && Date.now() < end;) {
      await wait(1000 * (r.body.retry_after_seconds || 3))
      r = await flexy.ownerLabSend(phone, offer, key, route || null)
    }
    if (r.status >= 400 && !r.body?.operation) throw new Error(LAB_ERRORS[r.body?.error] || r.body?.error || 'تعذّر الإرسال.')
    for (const end = Date.now() + 180_000; Date.now() < end;) {
      const s = await flexy.ownerLabStatus(key)
      if (s.status === 200 && s.body?.ok) {
        const op = s.body.operation
        lab.value = { ...lab.value, status: op.status, code: op.outcome?.code || '', steps: s.body.steps || [], sim: s.body.sim_code, station: s.body.station_code,
          kind: s.body.operation_key?.includes('630') ? 'أرسلي' : 'سما' }
        if (['success', 'failed', 'not_sent', 'review'].includes(op.status)) break
      }
      await wait(2000)
    }
  } catch (e) {
    lab.value = { ...lab.value, error: e.message }
  } finally {
    labBusy.value = false
  }
}

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

<style scoped>
.lab .raw { white-space: pre-wrap; background: #F6F7FB; border-radius: 8px; padding: 6px 8px; margin-top: 2px; }
.lab .step { border-top: 1px solid #ECEEF3; padding-top: 4px; }
</style>
