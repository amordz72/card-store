<template>
  <q-page class="page">
    <!-- Owner: «الواردة» = money he puts into his own shop balance -->
    <q-form v-if="session.isAdmin" class="card column q-gutter-sm" @submit.prevent="topup">
      <div class="text-weight-bold">شحن رصيد المحل</div>
      <div class="small muted">مبلغ تضعه لنفسك لتتابع استهلاكك وأرباحك. لا يُخلط مع دفعات الزبائن.</div>
      <div class="row q-gutter-sm items-start">
        <q-input v-model.number="amount" class="col" dense outlined type="number" inputmode="numeric" stack-label label="المبلغ (دج)" placeholder="مثال: 50000" />
        <q-btn type="submit" unelevated color="primary" label="شحن" :loading="busy" :disable="!(amount > 0)" />
      </div>
      <q-input v-model="note" dense outlined stack-label label="ملاحظة (اختيارية)" />
    </q-form>

    <!-- Customer: what he received from the shop or paid to it -->
    <div v-else class="row q-gutter-sm">
      <q-btn v-for="k in KINDS_FILTER" :key="k.label" rounded no-caps :ripple="false" :unelevated="kind === k.id" :outline="kind !== k.id"
        :color="kind === k.id ? 'primary' : 'grey-8'" :label="k.label" @click="kind = k.id" />
    </div>

    <div class="card grid-2 small">
      <div>عدد التحويلات: <b>{{ total }}</b></div>
      <div>المجموع: <b>{{ hide ? '••••' : money(sum) }}</b></div>
    </div>
    <div class="card q-pa-none" style="overflow:hidden">
      <EntryRow v-for="e in rows" :key="e.entry_id" :e="e" :admin="session.isAdmin" :hide="hide" @reverse="reverse(e)" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد تحويلات</div>
    </div>
    <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="rows.length" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import { newRequestId } from 'src/api/rpc'
import { money } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import PagerBar from 'components/PagerBar.vue'

const session = useSessionStore()
const customer = useCustomerStore()
const buyer = useBuyer()
const { busy, run } = useRun()
const hide = computed(() => buyer.hide.value)

const KINDS_FILTER = [
  { id: null, label: 'الكل' }, { id: 'debt', label: 'دَين' }, { id: 'cash', label: 'نقد' },
  { id: 'pay', label: 'دفع' }, { id: 'self', label: 'شحن ذاتي' }
]
const kind = ref(null)
const page = ref(1)
const size = ref(10)
const rows = ref([])
const total = ref(0)
const sum = ref(0)

async function load () {
  const f = { kind: kind.value, limit: size.value, offset: (page.value - 1) * size.value }
  const data = await run(() => (session.isAdmin
    ? adminApi.entries({ ...f, kind: 'transfers', scope: 'shop' })
    : customerApi.transfers(customer.token, f)))
  if (!data) return
  rows.value = data
  total.value = data.length ? Number(data[0].total_count) : 0
  sum.value = data.length ? Number(data[0].total_amount) : 0
}
watch([kind, size], () => { page.value === 1 ? load() : (page.value = 1) })
watch(page, load)
onMounted(load)

// --- owner: top up the shop balance
const amount = ref(null)
const note = ref('')
let requestId = null
watch([amount, note], () => { requestId = null })
async function topup () {
  requestId = requestId || newRequestId()
  const res = await run(() => adminApi.shopTopup(amount.value, note.value, requestId), { success: (r) => `تم الشحن. رصيد المحل: ${money(r.balance_after)}` })
  if (!res) return
  amount.value = null
  note.value = ''
  requestId = null
  buyer.refresh()
  page.value === 1 ? load() : (page.value = 1)
}

function reverse (e) {
  Dialog.create({ title: 'استرداد شحن المحل', message: `استرداد ${money(e.amount)}؟ لا تُحذف الحركة الأصلية.`, cancel: 'إلغاء', ok: 'تأكيد' })
    .onOk(async () => {
      const ok = await run(() => adminApi.reverse(e.entry_id, null, newRequestId()).then(() => true), { success: 'تم الاسترداد.' })
      if (ok) { buyer.refresh(); load() }
    })
}
</script>
