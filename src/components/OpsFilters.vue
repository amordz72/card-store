<template>
  <div class="card grid-2">
    <q-select v-if="customers" v-model="f.customerId" :options="customerOptions" emit-value map-options dense outlined label="الزبون" />
    <q-select v-model="f.category" :options="catOptions" emit-value map-options dense outlined label="نوع العمليات" />
    <q-input v-model="f.from" type="date" dense outlined stack-label label="من تاريخ" />
    <q-input v-model="f.to" type="date" dense outlined stack-label label="حتى تاريخ" />
    <q-input v-model="f.query" dense outlined clearable debounce="400" label="بحث" placeholder="بطاقة، رقم" />
    <q-btn flat no-caps color="grey-8" icon="filter_alt_off" label="مسح الفلاتر" @click="clear" />
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { CATEGORIES } from 'src/api/format'

const props = defineProps({ customers: { type: Array, default: null } })
const f = defineModel({ type: Object, required: true })

const catOptions = [{ value: null, label: 'الكل' }, ...CATEGORIES.map((c) => ({ value: c.id, label: c.label }))]
const customerOptions = computed(() =>
  [{ value: null, label: 'كل الزبائن' }, ...(props.customers || []).map((c) => ({ value: c.customer_id, label: c.name }))])

function clear () {
  Object.assign(f.value, { customerId: null, category: null, from: '', to: '', query: '' })
}
</script>
