<template>
  <q-page class="page">
    <q-input v-model="query" outlined dense clearable label="بحث" placeholder="مثال: موبيليس 1000" bg-color="white" />
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" />
    <q-btn rounded no-caps class="self-start" :unelevated="availOnly" :outline="!availOnly" color="positive"
      :label="availOnly ? '✓ المتوفر فقط' : 'المتوفر فقط'" :aria-pressed="availOnly" @click="availOnly = !availOnly" />

    <div class="grid-2">
      <div v-for="p in shownProducts" :key="p.product_id" class="card column q-gutter-xs" :class="{ 'out-of-stock': !p.available }">
        <div class="brand-tile" style="height:56px" :style="{ background: brandColor(p.brand) }">{{ p.brand }}</div>
        <div class="text-weight-medium">{{ p.name }}</div>
        <div class="text-weight-bold" style="font-size:17px">{{ money(p.base_price) }}</div>
        <div class="small text-weight-medium" :class="p.available ? 'amount-pos' : 'muted'">{{ p.available ? 'متوفر' : 'غير متوفر' }}</div>
        <q-btn unelevated :color="p.available ? 'primary' : 'grey-4'" :text-color="p.available ? 'white' : 'grey-8'"
          :label="p.available ? 'شراء' : 'نفد'" :disable="!p.available" @click="openBuy(p)" />
      </div>
    </div>
    <div v-if="loaded && !shownProducts.length" class="text-center muted q-pa-lg">لا توجد بطاقات مطابقة</div>
    <q-inner-loading :showing="!loaded" />

    <!-- Buy sheet: only the default selling price is shown (owner decision) -->
    <q-dialog v-model="buyOpen" position="bottom">
      <q-card v-if="sel" style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
        <q-card-section class="column q-gutter-sm">
          <div class="text-h6 text-weight-bold">تأكيد الشراء</div>
          <div class="row justify-between"><span>{{ sel.name }}</span><span class="text-weight-medium">{{ money(sel.base_price) }}</span></div>
          <div class="row justify-between items-center">
            <span>الكمية</span>
            <div class="row items-center q-gutter-sm">
              <q-btn outline round icon="remove" aria-label="إنقاص" :disable="qty <= 1" @click="qty--" />
              <span class="text-weight-bold" style="min-width:24px;text-align:center;font-size:17px">{{ qty }}</span>
              <q-btn outline round icon="add" aria-label="زيادة" :disable="qty >= 20" @click="qty++" />
            </div>
          </div>
          <q-separator />
          <div class="row justify-between"><span>المجموع (سعر البيع)</span><span class="text-weight-bold">{{ money(sel.base_price * qty) }}</span></div>
          <div class="row justify-between small muted"><span>{{ buyer.isShop.value ? 'رصيد المحل الآن' : 'رصيدك الآن' }}</span><span>{{ buyer.hide.value ? '••••••' : money(buyer.balance.value) }}</span></div>
        </q-card-section>
        <q-card-actions class="q-pa-md q-gutter-sm">
          <q-btn class="col-grow" unelevated color="primary" size="lg" label="تأكيد الشراء" :loading="busy" @click="confirmBuy" />
          <q-btn flat size="lg" label="إلغاء" v-close-popup :disable="busy" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <CodesDialog v-model="codesOpen" title="تم الشراء بنجاح" :subtitle="bought.subtitle" :codes="bought.codes" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useBuyer } from 'src/composables/useBuyer'
import { copyText } from 'src/composables/useCopy'
import { newRequestId } from 'src/api/rpc'
import { money, brandColor } from 'src/api/format'
import CodesDialog from 'components/CodesDialog.vue'
import CatalogFilter from 'components/CatalogFilter.vue'

const buyer = useBuyer()
const { busy, run } = useRun()

const products = ref([])
const loaded = ref(false)
const query = ref('')
const cat = ref('all')
const availOnly = ref(false)
const brand = ref('all')
const inCat = (p) => cat.value === 'all' || p.category === cat.value
const brandList = computed(() => [...new Set(products.value.filter(inCat).map((p) => p.brand))])

const shownProducts = computed(() => {
  const q = (query.value || '').trim().toLowerCase()
  return products.value
    .filter((p) => inCat(p) && (brand.value === 'all' || p.brand === brand.value))
    .filter((p) => !q || p.name.toLowerCase().includes(q) || p.brand.toLowerCase().includes(q))
    .filter((p) => !availOnly.value || p.available)
    // out-of-stock cards stay visible, at the end
    .sort((a, b) => Number(b.available) - Number(a.available))
})

async function load () {
  const rows = await run(() => buyer.catalog())
  if (rows) products.value = rows
  loaded.value = true
}

const buyOpen = ref(false)
const sel = ref(null)
const qty = ref(1)
let requestId = null

function openBuy (p) {
  sel.value = p
  qty.value = 1
  requestId = newRequestId()   // one id per purchase attempt; a retry reuses it
  buyOpen.value = true
}

const codesOpen = ref(false)
const bought = ref({ subtitle: '', codes: [] })

async function confirmBuy () {
  const res = await run(() => buyer.buy(sel.value.product_id, qty.value, requestId))
  if (!res) {
    await load()
    return
  }
  buyOpen.value = false
  bought.value = {
    subtitle: `${res.product_name} × ${res.qty} — احتفظ بالكود أو انسخه`,
    codes: res.codes.map((c) => ({ ...c, actionLabel: 'نسخ', action: () => copyText(c.code) }))
  }
  codesOpen.value = true
  run(() => buyer.refresh())
  load()
}

onMounted(load)
</script>
