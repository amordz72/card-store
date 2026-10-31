<template>
  <q-page class="page">
    <!-- Owner: review queue -->
    <template v-if="session.isAdmin">
      <div class="row q-gutter-sm">
        <q-btn v-for="s in FILTERS" :key="s.id" rounded no-caps :ripple="false" :unelevated="filter === s.id" :outline="filter !== s.id"
          :color="filter === s.id ? 'primary' : 'grey-8'" :label="s.label" @click="filter = s.id" />
      </div>
      <div v-for="r in rows" :key="r.report_id" class="card column q-gutter-xs">
        <div class="row items-center justify-between">
          <span class="text-weight-bold">{{ r.product_name }}</span>
          <q-badge :color="REPORT_STATUS[r.status].color" :label="REPORT_STATUS[r.status].label" />
        </div>
        <div class="text-weight-medium" style="color:#B91C1C">{{ REPORT_REASONS[r.reason] }}</div>
        <div v-if="r.note" class="small" style="white-space:pre-line">«{{ r.note }}»</div>
        <div class="small muted ltr text-left">{{ r.masked_code }}<span v-if="r.serial"> · SN {{ r.serial }}</span></div>
        <div class="small muted">
          {{ r.customer_name }} · دفعة #{{ r.batch_id }} ({{ r.supplier }}) · بيعت {{ dateTime(r.sold_at) }} · أُبلغ {{ dateTime(r.created_at) }}
        </div>
        <div class="small" :class="Number(r.customer_reports) > 2 ? 'text-warning text-weight-bold' : 'muted'">
          سجل الزبون: {{ r.customer_reports }} بلاغ، منها {{ r.customer_accepted }} مقبول
        </div>
        <div v-if="r.admin_note" class="small">ردّك: {{ r.admin_note }}</div>
        <div v-if="r.status === 'open'" class="row q-gutter-sm q-mt-xs">
          <q-btn unelevated color="positive" label="قبول" @click="resolve(r, 'accepted')" />
          <q-btn outline color="negative" label="رفض" @click="resolve(r, 'rejected')" />
          <q-btn flat dense no-caps color="primary" icon="visibility" label="عرض الكود" @click="reveal(r)" />
        </div>
      </div>
      <div v-if="loaded && !rows.length" class="text-center muted q-pa-lg">{{ filter === 'open' ? 'لا توجد بلاغات مفتوحة' : 'لا توجد بلاغات' }}</div>
    </template>

    <!-- Customer: my reports -->
    <template v-else>
      <div class="small muted">للإبلاغ عن بطاقة لم تعمل: «العمليات» ← افتح العملية ← «مساعدة» بجانب البطاقة (خلال 7 أيام من الشراء).</div>
      <div v-for="r in rows" :key="r.report_id" class="card column q-gutter-xs">
        <div class="row items-center justify-between">
          <span class="text-weight-bold">{{ r.product_name }}</span>
          <q-badge :color="REPORT_STATUS[r.status].color" :label="REPORT_STATUS[r.status].label" />
        </div>
        <div class="ltr text-left text-weight-medium">{{ r.code }}<span v-if="r.serial" class="small muted"> · {{ r.serial }}</span></div>
        <div class="small">{{ REPORT_REASONS[r.reason] }}<span v-if="r.note"> — {{ r.note }}</span></div>
        <div class="small muted">أُبلغ {{ dateTime(r.created_at) }}<span v-if="r.resolved_at"> · رُدّ {{ dateTime(r.resolved_at) }}</span></div>
        <div v-if="r.admin_note" class="small text-weight-medium" style="color:var(--brand-deep, #9A3412)">رد المتجر: {{ r.admin_note }}</div>
      </div>
      <div v-if="loaded && !rows.length" class="text-center muted q-pa-lg">لا توجد بلاغات</div>
    </template>
    <q-inner-loading :showing="!loaded" />
  </q-page>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import { dateTime, REPORT_REASONS, REPORT_STATUS } from 'src/api/format'
import { useBell } from 'src/composables/useBell'

// «البلاغات»: the owner reviews customer reports; a customer follows his own («بلاغاتي»)
const session = useSessionStore()
const customer = useCustomerStore()
const { run } = useRun()
const { refreshBell } = useBell()
const FILTERS = [{ id: 'open', label: 'المفتوحة' }, { id: null, label: 'الكل' }]
const filter = ref('open')
const rows = ref([])
const loaded = ref(false)

async function load () {
  const data = await run(() => (session.isAdmin ? adminApi.reports(filter.value) : customerApi.myReports(customer.token)))
  if (data) rows.value = data
  loaded.value = true
}
watch(filter, load)
onMounted(load)

// No automatic compensation (owner decision): refund or replace by hand from «التحويلات» if needed
function resolve (r, status) {
  const accept = status === 'accepted'
  Dialog.create({
    title: accept ? 'قبول البلاغ' : 'رفض البلاغ',
    message: (accept ? 'لا يوجد تعويض تلقائي: أرجع الثمن أو أعطِ بطاقة بديلة يدويًا إن لزم. ' : '') + 'ردّك يظهر للزبون (اختياري):',
    prompt: { model: '', type: 'text' },
    cancel: 'رجوع', ok: { label: accept ? 'قبول' : 'رفض', color: accept ? 'positive' : 'negative' }
  }).onOk(async (note) => {
    const ok = await run(() => adminApi.resolveReport(r.report_id, status, note).then(() => true),
      { success: accept ? 'قُبل البلاغ.' : 'رُفض البلاغ.' })
    if (ok) { load(); refreshBell() }
  })
}

async function reveal (r) {
  const code = await run(() => adminApi.revealCode(r.code_id))
  if (code) Dialog.create({ title: 'الكود', message: code, class: 'ltr', ok: 'إغلاق' })
}
</script>
