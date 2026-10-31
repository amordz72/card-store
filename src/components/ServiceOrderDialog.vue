<template>
  <!-- طلب خدمة (owner 2026-10-31): the count, the service's own fields (* = required), a note; the money is held now,
       and only the count the shop confirms sending is charged in the end -->
  <q-dialog :model-value="modelValue" position="bottom" @update:model-value="(v) => emit('update:modelValue', v)">
    <q-card v-if="service" style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
      <q-card-section class="column q-gutter-sm">
        <div class="text-h6 text-weight-bold">طلب: {{ service.name }}</div>
        <div class="help small muted">يُحجز المبلغ الآن، ويُحسب عليك فقط العدد الذي يؤكد المحل إرساله. تتابع طلبك في «الخدمات».</div>

        <div class="row justify-between items-center">
          <span>العدد</span>
          <div class="row items-center no-wrap q-gutter-sm">
            <q-btn outline round icon="remove" aria-label="إنقاص" :disable="qty <= 1" @click="qty--" />
            <q-input v-model.number="qty" dense outlined type="number" inputmode="numeric" style="width:84px" input-class="text-center"
              :min="1" :max="MAX" @blur="fixQty" />
            <q-btn outline round icon="add" aria-label="زيادة" :disable="qty >= MAX" @click="qty++" />
          </div>
        </div>

        <template v-for="f in fields" :key="f.key">
          <q-select v-if="f.type === 'choice'" v-model="answers[f.key]" dense outlined :options="f.options"
            :label="f.label + (f.required ? ' *' : '')" />
          <q-input v-else v-model="answers[f.key]" dense outlined :autogrow="f.type === 'long'" :type="f.type === 'long' ? 'textarea' : 'text'"
            :inputmode="INPUT_MODE[f.type] || 'text'" :input-class="LTR.includes(f.type) ? 'ltr text-left' : ''"
            :label="f.label + (f.required ? ' *' : '')" :placeholder="PLACEHOLDER[f.type] || ''" />
        </template>
        <q-input v-model="note" dense outlined autogrow type="textarea" label="ملاحظة (اختيارية)" maxlength="1000" />

        <q-separator />
        <div class="row justify-between"><span>المبلغ المحجوز (سعر البيع)</span><span class="text-weight-bold">{{ money(service.base_price * (qty || 0)) }}</span></div>
        <div class="row justify-between small muted"><span>رصيدك الآن</span><span>{{ hide ? '••••••' : money(balance) }}</span></div>
        <div v-if="missing.length" class="small text-deep-orange">ينقص: {{ missing.join('، ') }}</div>
      </q-card-section>
      <q-card-actions class="q-pa-md q-gutter-sm">
        <q-btn class="col-grow" unelevated color="primary" size="lg" label="أرسل الطلب" :loading="busy" :disable="!canSend" @click="send" />
        <q-btn flat size="lg" label="إلغاء" v-close-popup :disable="busy" />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { newRequestId } from 'src/api/rpc'
import { money } from 'src/api/format'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'

const props = defineProps({
  modelValue: Boolean,
  service: { type: Object, default: null },  // a row of store_services
  balance: { type: Number, default: 0 },
  hide: Boolean
})
const emit = defineEmits(['update:modelValue', 'sent'])
const { busy, run } = useRun()
const customer = useCustomerStore()

const MAX = 500
const INPUT_MODE = { number: 'decimal', phone: 'tel', link: 'url' }
const LTR = ['number', 'phone', 'link']
const PLACEHOLDER = { phone: '07xxxxxxxx', link: 'https://…' }

const qty = ref(1)
const note = ref('')
const answers = ref({})
let requestId = null
const fields = computed(() => props.service?.fields || [])

// A fresh form (and a fresh request id) each time the sheet opens on a service
watch(() => [props.modelValue, props.service?.product_id], ([open]) => {
  if (!open) return
  qty.value = 1
  note.value = ''
  answers.value = {}
  requestId = newRequestId()
}, { immediate: true })

function fixQty () { qty.value = Math.min(MAX, Math.max(1, Math.round(Number(qty.value) || 1))) }
const missing = computed(() => fields.value.filter((f) => f.required && !String(answers.value[f.key] ?? '').trim()).map((f) => f.label))
const canSend = computed(() => props.service?.open && qty.value >= 1 && qty.value <= MAX && !missing.value.length)

async function send () {
  fixQty()
  const res = await run(() => customerApi.serviceCreate(customer.token, props.service.product_id, qty.value, answers.value, note.value, requestId),
    { success: 'وصل طلبك: جاري تأكيد الطلبية.' })
  if (!res) return
  emit('update:modelValue', false)
  emit('sent', res)
}
</script>
