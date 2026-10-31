<template>
  <!-- «الخدمات» for a customer (owner 2026-10-31): each order, its state, what the shop wrote, every price change with its
       reason, and «إلغاء» while the shop has not started -->
  <q-page class="page column q-gutter-sm">
    <div class="row items-center">
      <div class="col text-h6 text-weight-bold">طلباتي من الخدمات</div>
      <q-btn flat no-caps color="primary" icon="storefront" label="اطلب خدمة" to="/store?cat=other" />
    </div>
    <div v-if="loaded && !orders.length" class="card muted text-center q-pa-lg">لا طلبات بعد. الخدمات في المتجر، قسم «منتجات أخرى» أو عليها «خدمة».</div>

    <div v-for="o in orders" :key="o.id" class="card column q-gutter-xs">
      <div class="row items-center no-wrap">
        <div class="col text-weight-bold">{{ o.product_name }} <span class="muted small">× {{ o.qty_done ?? o.qty }}</span></div>
        <q-badge :color="STATUS[o.status].color" :label="STATUS[o.status].label" />
      </div>
      <div class="small muted">طلب رقم {{ o.id }} · {{ when(o.created_at) }}<template v-if="o.finished_at"> · انتهى {{ when(o.finished_at) }}</template></div>
      <div v-if="o.status === 'done' && o.qty_done !== o.qty" class="small">أُرسل {{ o.qty_done }} من {{ o.qty }}، ويُحسب عليك المرسَل فقط.</div>
      <div v-for="f in o.fields" :key="f.key" class="small"><span class="muted">{{ f.label }}:</span> <bdi>{{ f.value }}</bdi></div>
      <div v-if="o.note" class="small"><span class="muted">ملاحظتك:</span> {{ o.note }}</div>
      <div v-if="o.reply" class="reply small">{{ o.status === 'failed' ? 'السبب' : 'رد المحل' }}: {{ o.reply }}</div>
      <div v-for="(c, i) in o.changes.filter((x) => x.what === 'price')" :key="i" class="small text-deep-orange">
        تغيّر السعر {{ when(c.at) }}: {{ money(c.old_total) }} ← {{ money(c.new_total) }} · السبب: {{ c.reason }}
      </div>
      <div class="row justify-between">
        <span class="muted">{{ o.status === 'queued' || o.status === 'claimed' ? 'المبلغ المحجوز' : 'المحسوب عليك' }}</span>
        <span class="text-weight-bold">{{ money(o.total) }}</span>
      </div>
      <div v-if="o.debt > 0" class="small text-negative">منه {{ money(o.debt) }} أُضيف إلى دينك (لم يكفِ رصيدك عند تغيير السعر).</div>
      <q-btn v-if="o.status === 'queued'" outline color="negative" class="self-start" label="إلغاء الطلب" :loading="busy && cancelling === o.id"
        @click="cancel(o)" />
    </div>
    <LoadMoreBar v-if="orders.length" :total="null" :shown="orders.length" :size="PAGE" :has-more="more" :loading="busy" @more="load(true)" />
    <q-inner-loading :showing="!loaded" />
  </q-page>
</template>

<script setup>
import { onMounted, onUnmounted, ref } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import { when } from 'src/api/when'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'
import LoadMoreBar from 'components/LoadMoreBar.vue'

const STATUS = {
  queued: { label: 'جاري تأكيد الطلبية', color: 'orange-8' },
  claimed: { label: 'قيد التنفيذ', color: 'primary' },
  done: { label: 'تمت الطلبية', color: 'positive' },
  failed: { label: 'لم تتم · أُرجع المبلغ', color: 'negative' },
  cancelled: { label: 'ألغيته · أُرجع المبلغ', color: 'grey-7' }
}
const PAGE = 20
const customer = useCustomerStore()
const { busy, run } = useRun()
const orders = ref([])
const loaded = ref(false)
const more = ref(false)
const cancelling = ref(null)

async function load (append = false) {
  const rows = await run(() => customerApi.serviceOrders(customer.token, PAGE, append ? orders.value.length : 0))
  if (rows) {
    orders.value = append ? [...orders.value, ...rows] : rows
    more.value = rows.length === PAGE
  }
  loaded.value = true
}

function cancel (o) {
  Dialog.create({ title: 'إلغاء الطلب', message: `إلغاء «${o.product_name}» وإرجاع ${money(o.total)} إلى رصيدك؟`, cancel: 'لا', ok: 'نعم، ألغِ' })
    .onOk(async () => {
      cancelling.value = o.id
      const res = await run(() => customerApi.serviceCancel(customer.token, o.id), { success: 'أُلغي الطلب وأُرجع المبلغ.' })
      cancelling.value = null
      if (res) { customer.refresh(); load() } else load()
    })
}

// The order moves on the shop's side: read again every 30 s while the page is shown
let timer = null
onMounted(() => {
  load()
  timer = setInterval(() => { if (!document.hidden && orders.value.some((o) => o.status === 'queued' || o.status === 'claimed')) load() }, 30000)
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.reply { background: #EFF6FF; color: #1E3A8A; border-radius: 10px; padding: 6px 10px; }
</style>
