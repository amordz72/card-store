<template>
  <q-dialog v-model="open" position="bottom">
    <q-card style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
      <q-card-section class="column q-gutter-sm">
        <div class="text-h6 text-weight-bold">مساعدة — البطاقة لم تعمل</div>
        <div v-if="card" class="ltr text-left text-weight-bold">{{ card.code }}<span v-if="card.serial" class="small muted"> · {{ card.serial }}</span></div>
        <div class="small muted">ما المشكلة؟</div>
        <q-option-group v-model="reason" :options="options" color="primary" />
        <q-input v-model="note" type="textarea" autogrow outlined dense stack-label maxlength="500" label="ملاحظة (اختيارية): ما ظهر لك عند الشحن" />
        <div class="small muted">يصل البلاغ إلى المتجر للتحقق. القرار بعد المراجعة يظهر في «بلاغاتي».</div>
      </q-card-section>
      <q-card-actions class="q-pa-md q-gutter-sm">
        <q-btn class="col-grow" unelevated color="negative" size="lg" label="إرسال البلاغ" :loading="busy" :disable="!reason" @click="send" />
        <q-btn flat size="lg" label="إلغاء" v-close-popup :disable="busy" />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useCustomerStore } from 'stores/customer'
import * as customerApi from 'src/api/customer'
import { REPORT_REASONS } from 'src/api/format'

// card: { code_id, code, serial }; emits 'sent' after the report is saved
const props = defineProps({ card: { type: Object, default: null } })
const emit = defineEmits(['sent'])
const open = defineModel({ type: Boolean, default: false })
const customer = useCustomerStore()
const { busy, run } = useRun()

const options = Object.entries(REPORT_REASONS).map(([value, label]) => ({ value, label }))
const reason = ref(null)
const note = ref('')
watch(open, (v) => { if (v) { reason.value = null; note.value = '' } })

async function send () {
  const id = await run(() => customerApi.reportCode(customer.token, props.card.code_id, reason.value, note.value),
    { success: 'أُرسل البلاغ. سنراجعه ونرد عليك.' })
  if (!id) return
  open.value = false
  emit('sent')
}
</script>
