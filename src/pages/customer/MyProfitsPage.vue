<template>
  <q-page class="page">
    <div class="small muted">البطاقات التي تربح فيها: تشتريها بسعر أقل من سعر البيع، والفرق ربحك.</div>
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" :only="catsWithProfit" />

    <div v-for="g in groups" :key="g.brand" class="card q-pa-none" style="overflow:hidden">
      <div class="row items-center q-gutter-sm q-pa-sm" style="background:#F7F8FB">
        <div class="brand-tile" style="width:40px;height:28px;font-size:10px" :style="{ background: brandColor(g.brand) }">{{ g.brand }}</div>
        <b>{{ g.brand }}</b>
      </div>
      <div class="row q-px-md q-pt-xs small muted">
        <span class="col">الفئة</span><span class="col-3 text-center">سعر البيع</span><span class="col-3 text-center">تدفع</span><span class="col-2 text-center">ربحك</span>
      </div>
      <div v-for="r in g.items" :key="r.product_id" class="row items-center q-px-md q-py-sm" style="border-top:1px solid #EEF0F5">
        <span class="col">{{ r.short }}</span>
        <span class="col-3 text-center">{{ money(r.base_price) }}</span>
        <b class="col-3 text-center" style="color:#B45309">{{ shown(r.pay_now) }}</b>
        <b class="col-2 text-center amount-info">{{ shown(r.profit) }}</b>
      </div>
    </div>
    <div v-if="loaded && !groups.length" class="text-center muted q-pa-lg">لا توجد بطاقات هنا</div>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { LocalStorage } from 'quasar'
import { useBuyer } from 'src/composables/useBuyer'
import { useMyProfits } from 'src/composables/useMyProfits'
import { useRun } from 'src/composables/useRun'
import { money, brandColor } from 'src/api/format'
import CatalogFilter from 'components/CatalogFilter.vue'

const buyer = useBuyer()
const { run } = useRun()
const { rows, loaded, load } = useMyProfits()
const shown = (n) => (buyer.hide.value ? '••••' : money(n))

const FILTER_KEY = 'cs_profits_filter'   // the last filter is remembered on this device
const saved = LocalStorage.getItem(FILTER_KEY) || {}
const cat = ref(saved.cat || 'all')
const brand = ref(saved.brand || 'all')

const catsWithProfit = computed(() => [...new Set(rows.value.map((r) => r.category).filter(Boolean))])
const inCat = (r) => cat.value === 'all' || r.category === cat.value
const brandList = computed(() => [...new Set(rows.value.filter(inCat).map((r) => r.brand))])
const groups = computed(() => {
  LocalStorage.set(FILTER_KEY, { cat: cat.value, brand: brand.value })
  const map = new Map()
  for (const r of rows.value.filter((x) => inCat(x) && (brand.value === 'all' || x.brand === brand.value))) {
    if (!map.has(r.brand)) map.set(r.brand, { brand: r.brand, items: [] })
    map.get(r.brand).items.push(r)
  }
  return [...map.values()]
})

onMounted(async () => {
  await run(load)
  // a remembered filter that no longer has profitable cards falls back to «الكل»
  if (cat.value !== 'all' && !catsWithProfit.value.includes(cat.value)) { cat.value = 'all'; brand.value = 'all' }
})
</script>
