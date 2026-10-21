<template>
  <q-dialog v-model="open">
    <q-card style="width:100%;max-width:420px">
      <q-card-section class="column q-gutter-sm">
        <div class="text-weight-bold">{{ session.isAdmin ? 'شحن رصيد المحل' : 'شحن رصيدي (بالدين)' }}</div>
        <div class="small muted">
          <template v-if="session.isAdmin">مبلغ تضعه لنفسك لتتابع استهلاكك وأرباحك.</template>
          <template v-else>يضاف المبلغ إلى رصيدك وإلى دينك. المتاح لك الآن: <b>{{ money(available) }}</b></template>
        </div>
        <!-- customer: quick amounts in steps of 500 (no awkward debt figures) -->
        <div v-if="!session.isAdmin" class="row q-gutter-sm">
          <q-btn v-for="v in quick" :key="v" rounded no-caps :ripple="false" :unelevated="amount === v" :outline="amount !== v"
            :color="amount === v ? 'primary' : 'grey-8'" :label="money(v)" @click="amount = v" />
        </div>
        <q-input v-model.number="amount" dense outlined :autofocus="session.isAdmin" type="number" inputmode="numeric" label="المبلغ (دج)"
          :step="session.isAdmin ? 1 : STEP" :error="!!customerError" :error-message="customerError"
          :hint="session.isAdmin ? '' : 'بمضاعفات 500 دج: 500، 1000، 1500…'" />
        <q-input v-if="session.isAdmin" v-model="note" dense outlined label="ملاحظة (اختيارية)" />
      </q-card-section>
      <q-card-actions align="right">
        <q-btn flat label="إلغاء" v-close-popup />
        <q-btn unelevated color="primary" label="شحن" :loading="busy"
          :disable="!(amount > 0) || !!customerError" @click="submit" />
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

const STEP = 500
// room under the debt limit, rounded down to a whole step
const available = computed(() => {
  const room = Math.max(0, Number(customer.profile?.debt_limit || 0) - Number(customer.profile?.debt || 0))
  return Math.floor(room / STEP) * STEP
})
const quick = computed(() => [500, 1000, 2000, 5000].filter((v) => v <= available.value))
const customerError = computed(() => {
  if (session.isAdmin || !(amount.value > 0)) return ''
  if (amount.value % STEP !== 0) return 'المبلغ بمضاعفات 500 دج فقط'
  if (amount.value > available.value) return 'أكثر من المتاح لك'
  return ''
})

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
