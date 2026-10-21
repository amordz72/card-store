<template>
  <q-page class="page">
    <q-form class="card column q-gutter-sm" @submit.prevent="topup">
      <div class="text-weight-bold">شحن رصيد المحل</div>
      <div class="small muted">مبلغ تضعه لنفسك لتتابع استهلاكك وأرباحك. لا يُخلط مع دفعات الزبائن.</div>
      <div class="row q-gutter-sm items-start">
        <q-input v-model.number="amount" class="col" dense outlined type="number" inputmode="numeric" stack-label label="المبلغ (دج)" placeholder="مثال: 50000" />
        <q-btn type="submit" unelevated color="primary" label="شحن" :loading="busy" :disable="!(amount > 0)" />
      </div>
      <q-input v-model="note" dense outlined stack-label label="ملاحظة (اختيارية)" />
    </q-form>

    <div class="row q-gutter-sm">
      <q-btn v-for="s in scopes" :key="s.id" rounded no-caps :unelevated="scope === s.id" :outline="scope !== s.id"
        :color="scope === s.id ? 'primary' : 'grey-8'" :label="s.label" @click="scope = s.id" />
    </div>
    <div v-if="scope === 'range'" class="card grid-2">
      <DateField v-model="from" label="من تاريخ" />
      <DateField v-model="to" label="حتى تاريخ" />
    </div>

    <div v-if="row" class="card column q-gutter-sm">
      <div class="small muted">{{ scopeHint }}</div>
      <div class="grid-2">
        <div class="column"><span class="small muted">مجموع ما شحنته</span><b style="font-size:18px">{{ m(row.topups) }}</b></div>
        <div class="column"><span class="small muted">ما استهلكته (سعر الشراء)</span><b style="font-size:18px;color:#B45309">{{ m(row.consumed) }}</b></div>
        <div class="column"><span class="small muted">الرصيد الحالي</span><b class="amount-pos" style="font-size:18px">{{ m(row.balance) }}</b></div>
        <div class="column"><span class="small muted">عدد العمليات</span><b style="font-size:18px">{{ row.orders_count }}</b></div>
      </div>
      <q-separator />
      <div class="column">
        <span class="small muted">أرباحي (سعر البيع − سعر الشراء)</span><b class="big-number amount-info">{{ m(row.real_profit) }}</b>
        <span v-if="Number(row.unknown_cost_orders)" class="small text-warning">{{ row.unknown_cost_orders }} عملية قديمة بلا سعر شراء (غير محسوبة)</span>
      </div>
    </div>

    <div class="section-title">آخر الشحنات</div>
    <div class="card q-pa-none" style="overflow:hidden">
      <EntryRow v-for="e in topups" :key="e.entry_id" :e="e" admin :hide="shop.hideAmounts" @reverse="reverse(e)" />
      <div v-if="!topups.length" class="text-center muted q-pa-lg">لا توجد شحنات بعد</div>
    </div>
    <div class="grid-2">
      <q-btn unelevated color="primary" size="lg" label="شراء بطاقة" to="/admin/shop/store" />
      <q-btn outline color="primary" size="lg" label="عمليات المحل" to="/admin/shop/operations" />
    </div>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useShopStore } from 'stores/shop'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { newRequestId } from 'src/api/rpc'
import { money, dateTime } from 'src/api/format'
import DateField from 'components/DateField.vue'
import EntryRow from 'components/EntryRow.vue'

const shop = useShopStore()
const { busy, run } = useRun()
const m = (n) => (shop.hideAmounts ? '••••••' : money(n))

const scopes = [
  { id: 'since_last', label: 'منذ آخر شحن' },
  { id: 'all', label: 'الكل' },
  { id: 'range', label: 'بالتاريخ' }
]
const scope = ref('since_last')
const from = ref('')
const to = ref('')
const row = computed(() => shop.summary?.[scope.value] || null)
const scopeHint = computed(() => {
  const s = shop.summary?.since_last
  if (scope.value === 'since_last') {
    return s?.last_topup_at ? `منذ آخر شحن: ${m(s.last_topup_amount)} في ${dateTime(s.last_topup_at)}` : 'لا شحن بعد — تُعرض كل العمليات'
  }
  if (scope.value === 'range') return from.value || to.value ? `من ${from.value || 'البداية'} حتى ${to.value || 'اليوم'}` : 'اختر التاريخ'
  return 'منذ البداية'
})

const topups = ref([])
async function load () {
  await run(() => shop.refresh(from.value, to.value))
  const rows = await run(() => api.entries({ scope: 'shop', kind: 'shop_topup', limit: 10, offset: 0 }))
  if (rows) topups.value = rows
}
watch([from, to], () => run(() => shop.refresh(from.value, to.value)))
onMounted(load)

const amount = ref(null)
const note = ref('')
let requestId = null
watch([amount, note], () => { requestId = null })
async function topup () {
  requestId = requestId || newRequestId()
  const res = await run(() => api.shopTopup(amount.value, note.value, requestId), { success: (r) => `تم الشحن. رصيد المحل: ${money(r.balance_after)}` })
  if (!res) return
  amount.value = null
  note.value = ''
  requestId = null
  load()
}

function reverse (e) {
  Dialog.create({ title: 'استرداد شحن المحل', message: `استرداد ${money(e.amount)}؟ لا تُحذف الحركة الأصلية.`, cancel: 'إلغاء', ok: 'تأكيد' })
    .onOk(async () => {
      const ok = await run(() => api.reverse(e.entry_id, null, newRequestId()), { success: 'تم الاسترداد.' })
      if (ok) load()
    })
}
</script>
