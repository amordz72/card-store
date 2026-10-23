<template>
  <q-page class="page">
    <OpsFilters v-model="f" />
    <div class="card q-pa-none" style="overflow:hidden">
      <OperationRow v-for="op in rows" :key="op.order_id" :op="op" :shop="buyer.isShop.value" :hide="buyer.hide.value" @open="openCodes(op)" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>
    <LoadMoreBar :total="total" :shown="rows.length" :size="size" :loading="loadingMore" @more="more" />
    <q-inner-loading :showing="busy && !loadingMore" />
    <CodesDialog v-model="codesOpen" :title="codesTitle" :subtitle="codesSub" :codes="codes" :order-id="lastOrderId"
      :mark-copied="buyer.markCopied" />
    <ReportDialog v-model="reportOpen" :card="reportCard" @sent="openCodes(lastOp)" />
  </q-page>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useLoadMore } from 'src/composables/useLoadMore'
import { useBuyer } from 'src/composables/useBuyer'
import { copyText } from 'src/composables/useCopy'
import { askCardFailed } from 'src/composables/useCardFailed'
import OpsFilters from 'components/OpsFilters.vue'
import OperationRow from 'components/OperationRow.vue'
import LoadMoreBar from 'components/LoadMoreBar.vue'
import CodesDialog from 'components/CodesDialog.vue'
import ReportDialog from 'components/ReportDialog.vue'
import { REPORT_STATUS } from 'src/api/format'

const buyer = useBuyer()
const { busy, run } = useRun()

const f = ref({ category: null, from: '', to: '', query: '' })
const { rows, total, loadingMore, reset, more, size } =
  useLoadMore((limit, offset) => run(() => buyer.orders({ ...f.value, limit, offset })), { key: 'order_id' })

watch(f, () => reset(), { deep: true })
onMounted(() => reset())

const lastOrderId = ref(null)
const codesOpen = ref(false)
const codes = ref([])
const codesTitle = ref('')
const codesSub = ref('')

// «مساعدة» on each card: customers only (the shop account is the owner himself)
const reportOpen = ref(false)
const reportCard = ref(null)
let lastOp = null

async function openCodes (op) {
  lastOp = op
  lastOrderId.value = op.order_id
  // copy hints are optional: without them the cards still open (device hints only)
  const [data, copies] = await Promise.all([
    run(() => buyer.orderCodes(op.order_id)),
    buyer.orderCopies(op.order_id).catch(() => [])
  ])
  if (!data) return
  const copiedAt = new Map(copies.map((x) => [x.code_id, x.copied_at]))
  const refunded = op.status !== 'done'
  codesTitle.value = refunded ? 'عملية مسترجعة' : 'أكواد العملية'
  codesSub.value = `${op.product_name} × ${op.qty} · رقم ${op.order_id}` + (refunded ? ' — هذه الأكواد أُلغيت ولا تُستعمل' : '')
  codes.value = data.map((c) => ({
    id: c.code_id,
    ...c,
    copiedAt: copiedAt.get(c.code_id) || null,
    actionLabel: 'نسخ',
    action: refunded ? null : () => copyText(c.code),
    // customers report a card; the shop (the owner himself) records «لم تعمل» on his own card
    help: buyer.isShop.value
      ? (!refunded && c.status === 'sold' ? () => askCardFailed(run, { id: c.code_id, code: c.code }, () => openCodes(op)) : null)
      : (c.can_report ? () => { reportCard.value = c; reportOpen.value = true } : null),
    helpLabel: buyer.isShop.value ? 'لم تعمل' : null,
    badge: c.report_status ? { label: 'بلاغ: ' + REPORT_STATUS[c.report_status].label, color: REPORT_STATUS[c.report_status].color } : null
  }))
  codesOpen.value = true
}
</script>
