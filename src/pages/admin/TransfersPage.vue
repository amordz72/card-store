<template>
  <q-page class="page">
    <div class="row q-gutter-sm">
      <q-btn v-for="k in filters" :key="k.id" rounded no-caps :unelevated="kind === k.id" :outline="kind !== k.id"
        :color="kind === k.id ? 'primary' : 'grey-8'" :label="k.label" @click="kind = k.id" />
    </div>
    <div class="card grid-2">
      <q-select v-model="customerId" :options="customerOptions" emit-value map-options dense outlined label="الزبون" />
      <div />
      <DateField v-model="from" label="من تاريخ" />
      <DateField v-model="to" label="حتى تاريخ" />
    </div>
    <div class="card grid-2 small">
      <div>عدد التحويلات: <b>{{ total }}</b></div>
      <div>المجموع: <b>{{ money(sum) }}</b></div>
    </div>
    <div class="card q-pa-none" style="overflow:hidden">
      <EntryRow v-for="e in rows" :key="e.entry_id" :e="e" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد تحويلات من هذا النوع</div>
    </div>
    <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="rows.length" />
    <q-inner-loading :showing="busy" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import DateField from 'components/DateField.vue'
import PagerBar from 'components/PagerBar.vue'

const { busy, run } = useRun()
const filters = [
  { id: 'transfers', label: 'الكل' }, { id: 'debt', label: 'دَين' }, { id: 'cash', label: 'نقد' }, { id: 'pay', label: 'دفع' },
  { id: 'self', label: 'شحن ذاتي' }, { id: 'refund', label: 'استرداد' }
]
// «الصادرة»: what the owner sends to his customers (purchases are in «العمليات», the shop's own top-ups in «الواردة»)
const scope = 'customers'
const kind = ref('transfers')
const customerId = ref(null)
const from = ref('')
const to = ref('')
const page = ref(1)
const size = ref(10)
const rows = ref([])
const total = ref(0)
const sum = ref(0)
const customers = ref([])
const customerOptions = computed(() => [{ value: null, label: 'كل الزبائن' }, ...customers.value.map((c) => ({ value: c.customer_id, label: c.name }))])

async function load () {
  const data = await run(() => api.entries({
    customerId: customerId.value, kind: kind.value, from: from.value, to: to.value, scope,
    limit: size.value, offset: (page.value - 1) * size.value
  }))
  if (!data) return
  rows.value = data
  total.value = data.length ? Number(data[0].total_count) : 0
  sum.value = data.length ? Number(data[0].total_amount) : 0
}
watch([kind, customerId, from, to, size], () => { page.value === 1 ? load() : (page.value = 1) })
watch(page, load)
onMounted(async () => {
  customers.value = (await run(() => api.customers())) || []
  load()
})
</script>
