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
  </q-page>
</template>

<script setup>
import { computed, ref } from 'vue'
import * as flexy from 'src/api/flexy'

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
</script>
