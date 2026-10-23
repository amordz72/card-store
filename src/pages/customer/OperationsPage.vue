<template>
  <q-page class="page">
    <OpsFilters v-model="f" />
    <div class="card q-pa-none" style="overflow:hidden">
      <OperationRow v-for="op in rows" :key="op.order_id" :op="op" :shop="buyer.isShop.value" :hide="buyer.hide.value" @open="openCodes(op)" />
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>
    <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="rows.length" />
    <q-inner-loading :showing="busy" />
    <CodesDialog v-model="codesOpen" :title="codesTitle" :subtitle="codesSub" :codes="codes" />
    <ReportDialog v-model="reportOpen" :card="reportCard" @sent="openCodes(lastOp)" />
  </q-page>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useBuyer } from 'src/composables/useBuyer'
import { copyText } from 'src/composables/useCopy'
import OpsFilters from 'components/OpsFilters.vue'
import OperationRow from 'components/OperationRow.vue'
import PagerBar from 'components/PagerBar.vue'
import CodesDialog from 'components/CodesDialog.vue'
import ReportDialog from 'components/ReportDialog.vue'
import { REPORT_STATUS } from 'src/api/format'

const buyer = useBuyer()
const { busy, run } = useRun()

const f = ref({ category: null, from: '', to: '', query: '' })
const page = ref(1)
const size = ref(10)   // latest 10 by default
const rows = ref([])
const total = ref(0)

async function load () {
  const data = await run(() => buyer.orders({ ...f.value, limit: size.value, offset: (page.value - 1) * size.value }))
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

// «مساعدة» on each card: customers only (the shop account is the owner himself)
const reportOpen = ref(false)
const reportCard = ref(null)
let lastOp = null

async function openCodes (op) {
  lastOp = op
  const data = await run(() => buyer.orderCodes(op.order_id))
  if (!data) return
  const refunded = op.status !== 'done'
  codesTitle.value = refunded ? 'عملية مسترجعة' : 'أكواد العملية'
  codesSub.value = `${op.product_name} × ${op.qty} · رقم ${op.order_id}` + (refunded ? ' — هذه الأكواد أُلغيت ولا تُستعمل' : '')
  codes.value = data.map((c) => ({
    ...c,
    actionLabel: 'نسخ',
    action: refunded ? null : () => copyText(c.code),
    help: !buyer.isShop.value && c.can_report ? () => { reportCard.value = c; reportOpen.value = true } : null,
    badge: c.report_status ? { label: 'بلاغ: ' + REPORT_STATUS[c.report_status].label, color: REPORT_STATUS[c.report_status].color } : null
  }))
  codesOpen.value = true
}
</script>
