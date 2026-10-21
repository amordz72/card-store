<template>
  <q-page class="page">
    <div class="small muted">سعر الزبون = السعر الأساسي − نسبته. النسبة لكل زبون ولكل منتج. صف «افتراضي ★» يُنسخ للزبون الجديد عند إضافته. التعديل يُحفظ فور الخروج من الخانة.</div>
    <div class="row q-gutter-sm">
      <q-btn v-for="c in CATEGORIES" :key="c.id" rounded no-caps :unelevated="cat === c.id" :outline="cat !== c.id"
        :color="cat === c.id ? 'primary' : 'grey-8'" :label="c.label" @click="cat = c.id" />
    </div>

    <div class="card q-pa-none" style="overflow-x:auto">
      <q-markup-table flat dense separator="horizontal">
        <thead>
          <tr>
            <th class="text-right">الزبون</th>
            <th v-for="p in products" :key="p.id" class="text-center" style="min-width:86px">
              <div>{{ p.name }}</div><div class="small muted">{{ money(p.base_price) }}</div>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in matrix" :key="r.key">
            <td class="text-right text-weight-medium">{{ r.name }}</td>
            <td v-for="p in products" :key="p.id" class="text-center">
              <q-input :model-value="r.cells[p.id]" dense outlined type="number" min="0" max="50" step="0.25" suffix="%"
                input-class="text-center" style="width:86px" :aria-label="`نسبة ${r.name} في ${p.name}`"
                @change="(v) => save(r, p, v)" />
            </td>
          </tr>
          <tr v-if="!products.length"><td class="text-center muted q-pa-md">لا توجد بطاقات في هذه الفئة</td></tr>
        </tbody>
      </q-markup-table>
    </div>
  </q-page>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money, CATEGORIES } from 'src/api/format'

const { run } = useRun()
const cat = ref('phone')
const products = ref([])
const matrix = ref([])

async function load () {
  const rows = await run(() => api.rates(cat.value))
  if (!rows) return
  const prods = new Map()
  const people = new Map()
  for (const x of rows) {
    prods.set(x.product_id, { id: x.product_id, name: x.product_name, base_price: x.base_price })
    const key = x.customer_id == null ? 'default' : String(x.customer_id)
    if (!people.has(key)) people.set(key, { key, customerId: x.customer_id, name: x.customer_id == null ? 'افتراضي ★' : x.customer_name, cells: {} })
    people.get(key).cells[x.product_id] = Number(x.pct)
  }
  products.value = [...prods.values()]
  matrix.value = [...people.values()]
}

async function save (row, product, value) {
  const pct = Math.max(0, Math.min(50, Number(value) || 0))
  const ok = await run(() => api.setRate(row.customerId, product.id, pct).then(() => true))
  if (ok) row.cells[product.id] = pct
}

watch(cat, load)
onMounted(load)
</script>
