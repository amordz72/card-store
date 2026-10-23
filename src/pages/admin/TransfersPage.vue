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
    <LoadMoreBar :total="total" :shown="rows.length" :size="size" :loading="loadingMore" @more="more" />
    <q-inner-loading :showing="busy && !loadingMore" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useLoadMore } from 'src/composables/useLoadMore'
import * as api from 'src/api/admin'
import { money } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import DateField from 'components/DateField.vue'
import LoadMoreBar from 'components/LoadMoreBar.vue'

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
const customers = ref([])
const customerOptions = computed(() => [{ value: null, label: 'كل الزبائن' }, ...customers.value.map((c) => ({ value: c.customer_id, label: c.name }))])

const { rows, total, sum, loadingMore, reset, more, size } = useLoadMore((limit, offset) => run(() => api.entries({
  customerId: customerId.value, kind: kind.value, from: from.value, to: to.value, scope, limit, offset
})), { key: 'entry_id' })
watch([kind, customerId, from, to], () => reset())
onMounted(async () => {
  customers.value = (await run(() => api.customers())) || []
  reset()
})
</script>
