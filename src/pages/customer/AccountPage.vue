<template>
  <q-page class="page">
    <!-- Owner: the store settings page comes later (plan item 9); for now the signed-in e-mail -->
    <div v-if="session.isAdmin" class="card column q-gutter-xs">
      <div class="muted small">حساب المدير</div>
      <div class="text-weight-bold ltr text-right">{{ admin.email }}</div>
      <div class="small muted">كلمة سر المدير وحمايته الثنائية تُدار من Supabase.</div>
    </div>

    <template v-if="!session.isAdmin">
    <div v-if="p" class="card grid-3">
      <div class="column"><span class="small muted">رصيدي</span><b class="amount-pos">{{ shown(p.balance) }}</b></div>
      <div class="column"><span class="small muted">{{ debt.label }}</span><b :class="debt.cls">{{ customer.hideAmounts ? '••••••' : debt.text }}</b></div>
      <div class="column"><span class="small muted">حد الدين</span><b>{{ money(p.debt_limit) }}</b></div>
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

    <q-btn outline color="primary" icon="swap_horiz" label="تحويلاتي (الدين، الدفع، النقد…)" to="/transfers" />

    <div class="section-title">تغيير كلمة السر</div>
    <q-form class="card column q-gutter-sm" @submit.prevent="changePassword">
      <q-input v-model="oldPw" type="password" dense outlined label="كلمة السر الحالية" autocomplete="current-password" />
      <q-input v-model="newPw" type="password" dense outlined label="كلمة السر الجديدة (8 أحرف على الأقل)" autocomplete="new-password" />
      <q-btn type="submit" outline color="primary" label="حفظ" :disable="!oldPw || newPw.length < 8" :loading="busy" />
    </q-form>

    </template>

    <LockSettings />

    <q-btn flat color="negative" icon="logout" label="خروج" @click="logout" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/customer'
import { money, debtView } from 'src/api/format'
import { useSessionStore } from 'stores/session'
import { useAdminStore } from 'stores/admin'
import LockSettings from 'components/LockSettings.vue'
import { useLockStore } from 'stores/lock'

const router = useRouter()
const customer = useCustomerStore()
const { busy, run } = useRun()
const p = computed(() => customer.profile)
const debt = computed(() => debtView(p.value?.debt || 0, true))
const shown = (n) => (customer.hideAmounts ? '••••••' : money(n))

const session = useSessionStore()
const admin = useAdminStore()
const myPrices = ref([])

onMounted(async () => {
  if (session.isAdmin) return
  await run(() => customer.refresh())
  const r = await run(() => api.myPrices(customer.token))
  if (r) myPrices.value = r
})

const oldPw = ref('')
const newPw = ref('')
async function changePassword () {
  const ok = await run(() => api.changePassword(customer.token, oldPw.value, newPw.value).then(() => true),
    { success: 'تم تغيير كلمة السر. خرجت أجهزتك الأخرى.' })
  if (ok) { oldPw.value = ''; newPw.value = '' }
}

async function logout () {
  await session.logout()
  useLockStore().reset()
  router.replace('/login')
}
</script>
