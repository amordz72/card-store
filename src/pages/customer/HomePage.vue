<template>
  <q-page class="page">
    <template v-if="p">
      <div v-if="p.announcement" class="card" style="background:#EEF0FF;border-color:#C7CAF5">
        <div class="small text-weight-bold" style="color:#3730A3">إعلان</div>
        <div class="text-subtitle1 text-weight-medium" style="white-space:pre-line">{{ p.announcement }}</div>
      </div>
      <div class="card">
        <div class="muted text-weight-medium">رصيدي</div>
        <div class="big-number amount-pos">{{ shown(p.balance) }}</div>
      </div>
      <div class="card">
        <div class="muted text-weight-medium">{{ debt.label }}</div>
        <div class="big-number" :class="debt.cls">{{ customer.hideAmounts ? '••••••' : debt.text }}</div>
        <div class="small muted">حد الدين: {{ money(p.debt_limit) }}</div>
      </div>
      <div class="card">
        <div class="muted text-weight-medium">أرباحي</div>
        <div class="big-number amount-info">{{ shown(p.profit) }}</div>
        <div class="small muted">الفرق بين سعر البيع وما اقتُطع من رصيدك</div>
      </div>
      <div class="grid-2">
        <q-btn color="primary" unelevated size="lg" label="شراء بطاقة" to="/store" />
        <q-btn outline color="primary" size="lg" label="كشف حسابي" to="/account" />
      </div>
    </template>
    <q-inner-loading :showing="!p" />
  </q-page>
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'
import { money, debtView } from 'src/api/format'

const customer = useCustomerStore()
const { run } = useRun()
const p = computed(() => customer.profile)
const debt = computed(() => debtView(p.value?.debt || 0, true))
const shown = (n) => (customer.hideAmounts ? '••••••' : money(n))

onMounted(() => run(() => customer.refresh()))
</script>
