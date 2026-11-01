<template>
  <q-page class="page">
    <q-form class="card column q-gutter-sm" @submit.prevent="add">
      <div class="text-weight-bold">إضافة زبون</div>
      <div class="help small muted">تضيفه يدويًا وتعطيه رقم هاتفه وكلمة السر ليدخل بهما.</div>
      <div class="grid-2">
        <q-input v-model="form.name" dense outlined label="الاسم" />
        <q-input v-model="form.phone" dense outlined label="رقم الهاتف" inputmode="tel" placeholder="05xxxxxxxx" input-class="ltr text-right" />
      </div>
      <q-input v-model="form.password" dense outlined label="كلمة السر الأولى (8 أحرف على الأقل)" input-class="ltr text-right">
        <template #append><q-btn flat round dense icon="casino" aria-label="كلمة سر جديدة" @click="form.password = easyPassword()" /></template>
      </q-input>
      <div class="help small muted">بعد الإضافة تظهر لك رسالة جاهزة (الرابط والهاتف وكلمة السر) لتنسخها له في الواتساب.</div>
      <q-btn type="submit" unelevated color="primary" label="إضافة الزبون" :loading="busy"
        :disable="!form.name.trim() || !form.phone || form.password.length < 8" />
    </q-form>

    <q-input v-model="query" dense outlined clearable label="بحث بالاسم أو الهاتف" bg-color="white" />
    <!-- s169: hidden customers (e.g. DEMO) only on demand -->
    <q-btn v-if="hiddenIds.size" flat dense no-caps class="self-start" color="grey-8" :icon="showHidden ? 'visibility_off' : 'visibility'"
      :label="(showHidden ? 'أخفِ المخفيين' : 'أظهر المخفيين') + ' (' + hiddenIds.size + ')'" @click="showHidden = !showHidden" />
    <q-list class="card q-pa-none">
      <q-item v-for="c in shown" :key="c.customer_id" clickable :to="'/customers/' + c.customer_id" style="border-top:1px solid #EEF0F5">
        <q-item-section>
          <q-item-label class="text-weight-bold">{{ c.name }}<q-badge v-if="!c.active" color="grey" class="q-ml-sm">موقوف</q-badge><q-badge v-if="hiddenIds.has(Number(c.customer_id))" color="grey-7" class="q-ml-sm">مخفي</q-badge></q-item-label>
          <q-item-label caption class="ltr text-right">{{ c.phone }}</q-item-label>
          <!-- Its settings at a glance (owner 2026-10-31), without opening it -->
          <q-item-label caption>{{ summary(c) }}</q-item-label>
        </q-item-section>
        <q-item-section side class="items-end">
          <span class="text-weight-bold amount-pos">رصيد {{ money(c.balance) }}</span>
          <span class="small" :class="debtView(c.debt).cls">{{ debtView(c.debt).label }} {{ debtView(c.debt).text }}</span>
        </q-item-section>
      </q-item>
      <div v-if="loaded && !shown.length" class="text-center muted q-pa-lg">لا يوجد زبائن</div>
    </q-list>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money, debtView } from 'src/api/format'
import { easyPassword, showLoginCopy } from 'src/api/loginCopy'

const router = useRouter()
const { busy, run } = useRun()
const list = ref([])
const loaded = ref(false)
const query = ref('')
const blankForm = () => ({ name: '', phone: '', password: easyPassword() })
const form = ref(blankForm())

const hiddenIds = ref(new Set())
const showHidden = ref(false)
const shown = computed(() => {
  const q = (query.value || '').trim()
  const base = showHidden.value ? list.value : list.value.filter((c) => !hiddenIds.value.has(Number(c.customer_id)))
  return q ? base.filter((c) => c.name.includes(q) || c.phone.includes(q.replace(/\s/g, ''))) : base
})

// Flexy of each account (the same list as «فليكسي المحلات»), by customer id
const flexyOf = ref({})
async function load () {
  const [data, hidden] = await Promise.all([run(() => api.customersAll()), api.hiddenCustomers()])
  if (data) list.value = data
  hiddenIds.value = new Set((hidden || []).map(Number))
  loaded.value = true
  const rows = await api.flexyCustomers().catch(() => null)
  flexyOf.value = Object.fromEntries((rows || []).map((r) => [Number(r.customer_id), r]))
}
function summary (c) {
  const f = flexyOf.value[Number(c.customer_id)]
  const flexyText = !f ? '' : f.enabled ? 'فليكسي مفعّل' + (f.max_amount != null ? ' · أكبر مبلغ ' + money(f.max_amount) : '') : 'فليكسي غير مفعّل'
  return [flexyText, 'حد الدين ' + money(c.debt_limit), c.self_topup ? 'شحن ذاتي' : ''].filter(Boolean).join(' · ')
}

async function add () {
  const id = await run(() => api.createCustomer(form.value.name, form.value.phone, form.value.password),
    { success: 'أُضيف الزبون. رصيده ودينه وحد دينه 0، ونسبه = النسب الافتراضية.' })
  if (!id) return
  const { name, phone, password } = form.value
  form.value = blankForm()
  router.push('/customers/' + id)
  showLoginCopy(name.trim(), phone.trim(), password)
}

onMounted(load)
</script>
