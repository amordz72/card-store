<template>
  <q-page class="page">
    <div class="row q-gutter-sm">
      <q-btn v-for="s in SCOPES" :key="s.id" rounded no-caps :unelevated="f.scope === s.id" :outline="f.scope !== s.id"
        :color="f.scope === s.id ? 'primary' : 'grey-8'" :label="s.label" @click="f.scope = s.id" />
    </div>
    <OpsFilters v-model="f" :customers="f.scope === 'shop' ? null : customers" />
    <div class="card q-pa-none" style="overflow:hidden">
      <OperationRow v-for="op in rows" :key="op.order_id" :op="op" admin @open="openCodes(op)" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>
    <LoadMoreBar :total="total" :shown="rows.length" :size="size" :loading="loadingMore" @more="more" />
    <q-inner-loading :showing="busy && !loadingMore" />
    <CodesDialog v-model="codesOpen" :title="codesTitle" :subtitle="codesSub" :codes="codes" :order-id="lastOrderId"
      :mark-copied="markCopied" />
  </q-page>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useLoadMore } from 'src/composables/useLoadMore'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/admin'
import OpsFilters from 'components/OpsFilters.vue'
import OperationRow from 'components/OperationRow.vue'
import LoadMoreBar from 'components/LoadMoreBar.vue'
import CodesDialog from 'components/CodesDialog.vue'

const { busy, run } = useRun()
const customers = ref([])
const SCOPES = [{ id: 'shop', label: 'مشترياتي' }, { id: 'customers', label: 'الزبائن' }, { id: null, label: 'الكل' }]
const f = ref({ scope: 'shop', customerId: null, category: null, from: '', to: '', query: '' })
const { rows, total, loadingMore, reset, more, size } =
  useLoadMore((limit, offset) => run(() => api.orders({ ...f.value, limit, offset })), { key: 'order_id' })
// «مشترياتي» are the owner's own purchases, so a customer filter makes no sense there
watch(() => f.value.scope, (s) => { if (s === 'shop') f.value.customerId = null })
watch(f, () => reset(), { deep: true })
onMounted(async () => {
  customers.value = (await run(() => api.customers())) || []
  reset()
})

// Codes are masked for the admin; each reveal is logged in the database
const lastOrderId = ref(null)
const codesOpen = ref(false)
const codes = ref([])
const codesTitle = ref('')
const codesSub = ref('')
// The owner saves copies of the shop's own cards only; a customer's copy is shown, never set, here
const markCopied = ref(null)

function codeItem (c, copiedAt) {
  return {
    badge: copiedAt ? { label: 'نسخها الزبون', color: 'grey-7' } : null,
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
  lastOrderId.value = op.order_id
  const [data, copies] = await Promise.all([
    run(() => api.orderCodes(op.order_id)),
    api.orderCopies(op.order_id).catch(() => [])
  ])
  if (!data) return
  const copiedAt = new Map(copies.map((x) => [x.code_id, x.copied_at]))
  markCopied.value = op.is_shop ? api.markCopied : null
  const refunded = op.status !== 'done'
  codesTitle.value = refunded ? 'عملية مسترجعة' : 'أكواد العملية'
  codesSub.value = `${op.product_name} × ${op.qty} · رقم ${op.order_id}` + (op.is_shop ? ' — من حساب المحل' : ' — الأكواد مخفية؛ «كشف» يُسجَّل')
  // the shop's own codes come back in full; customers' codes are masked with a logged reveal
  codes.value = op.is_shop
    ? data.map((c) => ({ id: c.code_id, code: c.masked_code, serial: c.serial, status: c.status, copiedAt: copiedAt.get(c.code_id) || null, actionLabel: 'نسخ', action: refunded ? null : () => copyText(c.masked_code) }))
    : data.map((c) => codeItem(c, copiedAt.get(c.code_id)))
  codesOpen.value = true
}
</script>
