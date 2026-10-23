<template>
  <q-page class="page">
    <!-- Owner: the store settings page comes later (plan item 9); for now the signed-in e-mail -->
    <div v-if="session.isAdmin" class="card column q-gutter-xs">
      <div class="muted small">حساب المدير</div>
      <div class="text-weight-bold ltr text-right">{{ admin.email }}</div>
      <div class="small muted">كلمة سر المدير وحمايته الثنائية تُدار من Supabase.</div>
    </div>
    <div class="card column q-gutter-xs">
      <div class="text-weight-bold">ولاية {{ session.isAdmin ? 'محلي' : 'المحل' }}</div>
      <WilayaSelect :model-value="wilaya" @update:model-value="setWilaya" />
    </div>

    <template v-if="!session.isAdmin">
    <div v-if="p" class="card grid-3">
      <div class="column"><span class="small muted">رصيدي</span><b class="amount-pos">{{ shown(p.balance) }}</b></div>
      <div class="column"><span class="small muted">{{ debt.label }}</span><b :class="debt.cls">{{ customer.hideAmounts ? '••••••' : debt.text }}</b></div>
      <div class="column"><span class="small muted">حد الدين</span><b>{{ money(p.debt_limit) }}</b></div>
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
import WilayaSelect from 'components/WilayaSelect.vue'
import * as adminApi from 'src/api/admin'
import { useLockStore } from 'stores/lock'

const router = useRouter()
const customer = useCustomerStore()
const { busy, run } = useRun()
const p = computed(() => customer.profile)
const debt = computed(() => debtView(p.value?.debt || 0, true))
const shown = (n) => (customer.hideAmounts ? '••••••' : money(n))

const session = useSessionStore()
const admin = useAdminStore()

// Province of this shop (the owner's own shop account, or the signed-in customer)
const wilaya = ref(null)
let shopId = null
async function loadWilaya () {
  if (session.isAdmin) {
    const ws = await run(() => adminApi.customerWilayas())
    const shop = ws?.find((w) => w.is_shop)
    shopId = shop?.customer_id ?? null
    wilaya.value = shop?.wilaya_code ?? null
  } else {
    wilaya.value = (await run(() => api.myWilaya(customer.token))) ?? null
  }
}
async function setWilaya (code) {
  const ok = await run(() => (session.isAdmin ? adminApi.setCustomerWilaya(shopId, code) : api.setMyWilaya(customer.token, code))
    .then(() => true), { success: 'حُفظت الولاية.' })
  if (ok) wilaya.value = code
}

onMounted(async () => {
  loadWilaya()
  if (session.isAdmin) return
  await run(() => customer.refresh())
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
