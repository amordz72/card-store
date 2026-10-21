<template>
  <q-dialog v-model="open">
    <q-card style="width:100%;max-width:420px">
      <q-card-section class="column q-gutter-sm">
        <div class="text-weight-bold">{{ session.isAdmin ? 'شحن رصيد المحل' : 'شحن رصيدي (بالدين)' }}</div>
        <div class="small muted">
          <template v-if="session.isAdmin">مبلغ تضعه لنفسك لتتابع استهلاكك وأرباحك.</template>
          <template v-else>يضاف المبلغ إلى رصيدك وإلى دينك. المتاح لك الآن: <b>{{ money(available) }}</b></template>
        </div>
        <q-input v-model.number="amount" dense outlined autofocus type="number" inputmode="numeric" label="المبلغ (دج)"
          :error="!session.isAdmin && amount > available" error-message="أكثر من المتاح لك" />
        <q-input v-if="session.isAdmin" v-model="note" dense outlined label="ملاحظة (اختيارية)" />
      </q-card-section>
      <q-card-actions align="right">
        <q-btn flat label="إلغاء" v-close-popup />
        <q-btn unelevated color="primary" label="شحن" :loading="busy"
          :disable="!(amount > 0) || (!session.isAdmin && amount > available)" @click="submit" />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import { newRequestId } from 'src/api/rpc'
import { money } from 'src/api/format'

// The «+» on the balance card: owner tops up his shop balance; a trusted customer tops up on debt (self top-up)
const open = defineModel({ type: Boolean, default: false })
const emit = defineEmits(['done'])
const session = useSessionStore()
const customer = useCustomerStore()
const { busy, run } = useRun()
const amount = ref(null)
const note = ref('')
let requestId = null
watch([amount, note], () => { requestId = null })
watch(open, (v) => { if (v) { amount.value = null; note.value = '' } })

const available = computed(() => Math.max(0, Number(customer.profile?.debt_limit || 0) - Number(customer.profile?.debt || 0)))

async function submit () {
  requestId = requestId || newRequestId()
  const res = await run(() => (session.isAdmin
    ? adminApi.shopTopup(amount.value, note.value, requestId)
    : customerApi.selfTopup(customer.token, amount.value, requestId)),
  { success: session.isAdmin ? 'تم شحن رصيد المحل.' : 'تم الشحن وأضيف المبلغ إلى دينك.' })
  if (!res) return
  requestId = null
  open.value = false
  emit('done')
}
</script>
