<template>
  <q-page class="page">
    <OpsFilters v-model="f" />
    <div class="card q-pa-none" style="overflow:hidden">
      <OperationRow v-for="op in rows" :key="op.order_id" :op="op" :hide="customer.hideAmounts" @open="openCodes(op)" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>
    <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="rows.length" />
    <q-inner-loading :showing="busy" />
    <CodesDialog v-model="codesOpen" :title="codesTitle" :subtitle="codesSub" :codes="codes" />
  </q-page>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/customer'
import OpsFilters from 'components/OpsFilters.vue'
import OperationRow from 'components/OperationRow.vue'
import PagerBar from 'components/PagerBar.vue'
import CodesDialog from 'components/CodesDialog.vue'

const customer = useCustomerStore()
const { busy, run } = useRun()

const f = ref({ category: null, from: '', to: '', query: '' })
const page = ref(1)
const size = ref(10)   // latest 10 by default
const rows = ref([])
const total = ref(0)

async function load () {
  const data = await run(() => api.orders(customer.token, { ...f.value, limit: size.value, offset: (page.value - 1) * size.value }))
  if (!data) return
  rows.value = data
  total.value = data.length ? Number(data[0].total_count) : 0
}

watch(f, () => { page.value === 1 ? load() : (page.value = 1) }, { deep: true })
watch(size, () => { page.value === 1 ? load() : (page.value = 1) })
watch(page, load)
onMounted(load)

const codesOpen = ref(false)
const codes = ref([])
const codesTitle = ref('')
const codesSub = ref('')

async function openCodes (op) {
  const data = await run(() => api.orderCodes(customer.token, op.order_id))
  if (!data) return
  const refunded = op.status !== 'done'
  codesTitle.value = refunded ? 'عملية مسترجعة' : 'أكواد العملية'
  codesSub.value = `${op.product_name} × ${op.qty} · رقم ${op.order_id}` + (refunded ? ' — هذه الأكواد أُلغيت ولا تُستعمل' : '')
  codes.value = data.map((c) => ({ ...c, actionLabel: 'نسخ', action: refunded ? null : () => copyText(c.code) }))
  codesOpen.value = true
}
</script>
