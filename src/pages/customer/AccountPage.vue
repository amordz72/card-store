<template>
  <q-page class="page">
    <div v-if="p" class="card grid-3">
      <div class="column"><span class="small muted">رصيدي</span><b class="amount-pos">{{ shown(p.balance) }}</b></div>
      <div class="column"><span class="small muted">{{ debt.label }}</span><b :class="debt.cls">{{ customer.hideAmounts ? '••••••' : debt.text }}</b></div>
      <div class="column"><span class="small muted">حد الدين</span><b>{{ money(p.debt_limit) }}</b></div>
    </div>

    <div v-if="p && p.self_topup" class="card column q-gutter-sm" style="background:#FFFBEB;border-color:#F59E0B">
      <div class="text-weight-bold" style="color:#92400E">شحن ذاتي (بالدين)</div>
      <div class="small" style="color:#78350F">يضاف المبلغ إلى رصيدك وإلى دينك. المتاح لك الآن: {{ money(Math.max(0, p.debt_limit - p.debt)) }}</div>
      <div class="row q-gutter-sm items-start">
        <q-input v-model.number="topup" class="col" dense outlined type="number" inputmode="numeric" label="المبلغ (دج)" bg-color="white" />
        <q-btn unelevated color="warning" label="شحن" :loading="busy" :disable="!(topup > 0)" @click="doTopup" />
      </div>
    </div>

    <div class="section-title">أسعاري</div>
    <div class="card q-pa-none" style="overflow:hidden">
      <div class="row q-px-md q-py-xs small muted" style="background:#F7F8FB">
        <span class="col">البطاقة</span><span class="col-3 text-center">سعر البيع</span><span class="col-3 text-center">أدفع</span><span class="col-2 text-center">ربحي</span>
      </div>
      <div v-for="r in myPrices" :key="r.product_id" class="row items-center q-px-md q-py-sm" style="border-top:1px solid #EEF0F5">
        <span class="col">{{ r.name }}</span>
        <span class="col-3 text-center">{{ money(r.base_price) }}</span>
        <b class="col-3 text-center" style="color:#B45309">{{ r.pay_now == null ? '—' : shown(r.pay_now) }}</b>
        <b class="col-2 text-center amount-info">{{ r.pay_now == null ? '—' : shown(r.base_price - r.pay_now) }}</b>
      </div>
      <div v-if="!myPrices.length" class="muted small q-pa-md">لا توجد بطاقات بعد</div>
    </div>

    <div class="section-title">كشف الحساب</div>
    <div class="card q-pa-none" style="overflow:hidden">
      <EntryRow v-for="e in entries" :key="e.entry_id" :e="e" :hide="customer.hideAmounts" />
      <div v-if="!entries.length" class="text-center muted q-pa-lg">لا توجد حركات</div>
    </div>
    <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="entries.length" />

    <div class="section-title">تغيير كلمة السر</div>
    <q-form class="card column q-gutter-sm" @submit.prevent="changePassword">
      <q-input v-model="oldPw" type="password" dense outlined label="كلمة السر الحالية" autocomplete="current-password" />
      <q-input v-model="newPw" type="password" dense outlined label="كلمة السر الجديدة (8 أحرف على الأقل)" autocomplete="new-password" />
      <q-btn type="submit" outline color="primary" label="حفظ" :disable="!oldPw || newPw.length < 8" :loading="busy" />
    </q-form>

    <q-btn flat color="negative" icon="logout" label="خروج" @click="logout" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/customer'
import { newRequestId } from 'src/api/rpc'
import { money, debtView } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import PagerBar from 'components/PagerBar.vue'

const router = useRouter()
const customer = useCustomerStore()
const { busy, run } = useRun()
const p = computed(() => customer.profile)
const debt = computed(() => debtView(p.value?.debt || 0, true))
const shown = (n) => (customer.hideAmounts ? '••••••' : money(n))

const myPrices = ref([])
const entries = ref([])
const total = ref(0)
const page = ref(1)
const size = ref(10)

async function loadEntries () {
  const data = await run(() => api.entries(customer.token, size.value, (page.value - 1) * size.value))
  if (!data) return
  entries.value = data
  total.value = data.length ? Number(data[0].total_count) : 0
}
watch(page, loadEntries)
watch(size, () => { page.value === 1 ? loadEntries() : (page.value = 1) })

onMounted(async () => {
  await run(() => customer.refresh())
  const r = await run(() => api.myPrices(customer.token))
  if (r) myPrices.value = r
  loadEntries()
})

const topup = ref(null)
let topupRequest = null
watch(topup, () => { topupRequest = null })
async function doTopup () {
  topupRequest = topupRequest || newRequestId()
  const res = await run(() => api.selfTopup(customer.token, topup.value, topupRequest),
    { success: 'تم الشحن وأضيف المبلغ إلى دينك.' })
  if (!res) return
  topup.value = null
  topupRequest = null
  await run(() => customer.refresh())
  loadEntries()
}

const oldPw = ref('')
const newPw = ref('')
async function changePassword () {
  const ok = await run(() => api.changePassword(customer.token, oldPw.value, newPw.value).then(() => true),
    { success: 'تم تغيير كلمة السر. خرجت أجهزتك الأخرى.' })
  if (ok) { oldPw.value = ''; newPw.value = '' }
}

async function logout () {
  await customer.logout()
  router.replace('/login')
}
</script>
