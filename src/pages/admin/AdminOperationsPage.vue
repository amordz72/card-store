<template>
  <q-page class="page">
    <div class="row q-gutter-sm">
      <q-btn v-for="s in SCOPES" :key="s.id" rounded no-caps :unelevated="f.scope === s.id" :outline="f.scope !== s.id"
        :color="f.scope === s.id ? 'primary' : 'grey-8'" :label="s.label" @click="f.scope = s.id" />
    </div>
    <OpsFilters v-model="f" :customers="customers" />
    <div class="card q-pa-none" style="overflow:hidden">
      <OperationRow v-for="op in rows" :key="op.order_id" :op="op" admin @open="openCodes(op)" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>
    <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="rows.length" />
    <q-inner-loading :showing="busy" />
    <CodesDialog v-model="codesOpen" :title="codesTitle" :subtitle="codesSub" :codes="codes" />
  </q-page>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/admin'
import OpsFilters from 'components/OpsFilters.vue'
import OperationRow from 'components/OperationRow.vue'
import PagerBar from 'components/PagerBar.vue'
import CodesDialog from 'components/CodesDialog.vue'

const { busy, run } = useRun()
const customers = ref([])
const SCOPES = [{ id: null, label: 'الكل' }, { id: 'customers', label: 'الزبائن' }, { id: 'shop', label: 'المحل' }]
const f = ref({ scope: null, customerId: null, category: null, from: '', to: '', query: '' })
const page = ref(1)
const size = ref(10)
const rows = ref([])
const total = ref(0)

async function load () {
  const data = await run(() => api.orders({ ...f.value, limit: size.value, offset: (page.value - 1) * size.value }))
  if (!data) return
  rows.value = data
  total.value = data.length ? Number(data[0].total_count) : 0
}
watch(f, () => { page.value === 1 ? load() : (page.value = 1) }, { deep: true })
watch(size, () => { page.value === 1 ? load() : (page.value = 1) })
watch(page, load)
onMounted(async () => {
  customers.value = (await run(() => api.customers())) || []
  load()
})

// Codes are masked for the admin; each reveal is logged in the database
const codesOpen = ref(false)
const codes = ref([])
const codesTitle = ref('')
const codesSub = ref('')

function codeItem (c) {
  return {
    code: c.masked_code,
    serial: c.serial,
    status: c.status,
    actionLabel: 'كشف',
    action: async () => {
      const full = await run(() => api.revealCode(c.code_id))
      if (!full) return
      const i = codes.value.findIndex((x) => x.id === c.code_id)
      codes.value[i] = { ...codes.value[i], code: full, actionLabel: 'نسخ', action: () => copyText(full) }
    },
    id: c.code_id
  }
}

async function openCodes (op) {
  const data = await run(() => api.orderCodes(op.order_id))
  if (!data) return
  codesTitle.value = op.status === 'done' ? 'أكواد العملية' : 'عملية مسترجعة'
  codesSub.value = `${op.product_name} × ${op.qty} · رقم ${op.order_id}` + (op.is_shop ? ' — من حساب المحل' : ' — الأكواد مخفية؛ «كشف» يُسجَّل')
  // the shop's own codes come back in full; customers' codes are masked with a logged reveal
  codes.value = op.is_shop ? data.map((c) => ({ code: c.masked_code, serial: c.serial, status: c.status, actionLabel: 'نسخ', action: () => copyText(c.masked_code) })) : data.map(codeItem)
  codesOpen.value = true
}
</script>
