<template>
  <q-page class="page">
    <q-input v-model="query" outlined dense clearable label="بحث" placeholder="مثال: موبيليس 1000" bg-color="white" />
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" />
    <q-btn rounded no-caps class="self-start" :unelevated="availOnly" :outline="!availOnly" color="positive"
      :label="availOnly ? '✓ المتوفر فقط' : 'المتوفر فقط'" :aria-pressed="availOnly" @click="availOnly = !availOnly" />

    <!-- One section per category (titled when showing «الكل»), each brand on its own rows -->
    <template v-for="g in groups" :key="g.id">
      <div v-if="cat === 'all'" class="cat-title">{{ g.label }}</div>
      <template v-for="b in g.brands" :key="b.name">
        <div class="brand-title">{{ b.name }}</div>
        <div class="grid-2">
          <div v-for="p in b.items" :key="p.product_id" class="card column q-gutter-xs" :class="{ 'out-of-stock': !p.available }">
            <CardImage :item="p" />
            <!-- A game card (owner 2026-10-30): its amount big, the price under it, never confused -->
            <template v-if="p.category === 'game' && gameAmount(p.name)">
              <span class="price-badge game-badge self-start">💎 {{ gameAmount(p.name) }}</span>
              <q-separator />
              <div class="text-weight-medium">السعر: <b>{{ money(p.base_price) }}</b></div>
              <div class="small muted">{{ p.name }}</div>
            </template>
            <template v-else>
              <span class="price-badge self-start">{{ money(p.base_price) }}</span>
              <q-separator />
              <div class="text-weight-medium">{{ p.name }}</div>
            </template>
            <div v-if="!p.available && splits[p.product_id]" class="small text-weight-medium text-deep-orange">متوفر من {{ partsText(splits[p.product_id]) }}</div>
            <div v-else class="small text-weight-medium" :class="p.available ? 'amount-pos' : 'muted'">{{ p.available ? 'متوفر' : 'غير متوفر' }}</div>
            <q-btn unelevated :color="canBuy(p) ? 'primary' : 'grey-4'" :text-color="canBuy(p) ? 'white' : 'grey-8'"
              :label="canBuy(p) ? 'شراء' : 'نفد'" :disable="!canBuy(p)" @click="openBuy(p)" />
          </div>
        </div>
      </template>
    </template>
    <div v-if="loaded && !shownProducts.length" class="text-center muted q-pa-lg">لا توجد بطاقات مطابقة</div>
    <q-inner-loading :showing="!loaded" />

    <!-- Buy sheet: only the default selling price is shown (owner decision) -->
    <q-dialog v-model="buyOpen" position="bottom">
      <q-card v-if="sel" style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
        <q-card-section class="column q-gutter-sm">
          <div class="text-h6 text-weight-bold">تأكيد الشراء</div>
          <div class="row justify-between"><span>{{ sel.name }}</span><span class="text-weight-medium">{{ money(unitPrice) }}</span></div>
          <!-- v1.52 (owner: «مع التنبيه»): said before buying -->
          <div v-if="selSplit" class="split-note">ستستلم {{ selSplit.parts.length === 2 ? 'كودين' : selSplit.parts.length + ' أكواد' }}: {{ selSplit.parts.join(' + ') }} = {{ selSplit.parts.reduce((a, b) => a + b, 0) }}. أدخلها كلها لنفس اللاعب.</div>
          <div class="row justify-between items-center">
            <span>الكمية</span>
            <div class="row items-center q-gutter-sm">
              <q-btn outline round icon="remove" aria-label="إنقاص" :disable="qty <= 1" @click="qty--" />
              <span class="text-weight-bold" style="min-width:24px;text-align:center;font-size:17px">{{ qty }}</span>
              <q-btn outline round icon="add" aria-label="زيادة" :disable="qty >= (selSplit ? 5 : 20)" @click="qty++" />
            </div>
          </div>
          <q-separator />
          <div class="row justify-between"><span>المجموع (سعر البيع)</span><span class="text-weight-bold">{{ money(unitPrice * qty) }}</span></div>
          <div class="row justify-between small muted"><span>{{ buyer.isShop.value ? 'رصيد المحل الآن' : 'رصيدك الآن' }}</span><span>{{ buyer.hide.value ? '••••••' : money(buyer.balance.value) }}</span></div>
        </q-card-section>
        <q-card-actions class="q-pa-md q-gutter-sm">
          <q-btn class="col-grow" unelevated color="primary" size="lg" label="تأكيد الشراء" :loading="busy" @click="confirmBuy" />
          <q-btn flat size="lg" label="إلغاء" v-close-popup :disable="busy" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <CodesDialog v-model="codesOpen" title="تم الشراء بنجاح" :subtitle="bought.subtitle" :codes="bought.codes" :order-id="bought.orderId"
      :mark-copied="buyer.markCopied" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { LocalStorage } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { useBuyer } from 'src/composables/useBuyer'
import { copyText } from 'src/composables/useCopy'
import { newRequestId } from 'src/api/rpc'
import { money, gameAmount, CATEGORIES } from 'src/api/format'
import CodesDialog from 'components/CodesDialog.vue'
import CatalogFilter from 'components/CatalogFilter.vue'
import CardImage from 'components/CardImage.vue'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'

const buyer = useBuyer()
const { busy, run } = useRun()

const products = ref([])
const loaded = ref(false)
const query = ref('')
const cat = ref('all')
// «المتوفر فقط» is on by default; the viewer's choice is remembered on this device
const AVAIL_KEY = 'cs_avail_only'
const readAvail = () => { try { return LocalStorage.getItem(AVAIL_KEY) !== false } catch { return true } }
const availOnly = ref(readAvail())
watch(availOnly, (v) => { try { LocalStorage.set(AVAIL_KEY, v) } catch { /* storage blocked: default next time */ } })
const brand = ref('all')
// What the shop looks at without buying (owner 2026-10-30, v1.46): the brand it opens, the card whose sheet it opens,
// what it searches. Its own name only, never a number; the same light rule as the pages (once per 10 minutes).
const customer = useCustomerStore()
const interest = (what) => { if (!buyer.isShop.value && customer.token) customerApi.pageSeen(customer.token, ('/store/' + what).slice(0, 60)).catch(() => {}) }
watch(brand, (b) => { if (b && b !== 'all') interest('brand:' + b) })
let searchTimer = null
watch(query, (q) => {
  clearTimeout(searchTimer)
  const t = (q || '').trim()
  if (t.length >= 2) searchTimer = setTimeout(() => interest('search:' + t), 1500)
})
const inCat = (p) => cat.value === 'all' || p.category === cat.value
const brandList = computed(() => [...new Set(products.value.filter(inCat).map((p) => p.brand))])

const shownProducts = computed(() => {
  const q = (query.value || '').trim().toLowerCase()
  return products.value
    .filter((p) => inCat(p) && (brand.value === 'all' || p.brand === brand.value))
    .filter((p) => !q || p.name.toLowerCase().includes(q) || p.brand.toLowerCase().includes(q))
    .filter((p) => !availOnly.value || p.available)
})

// Rows arrive ordered by category, brand, card. Keep that order; inside a brand
// out-of-stock cards stay visible, at the end.
const groups = computed(() => CATEGORIES.map((c) => {
  const brands = []
  for (const p of shownProducts.value.filter((x) => x.category === c.id)) {
    let b = brands.find((x) => x.name === p.brand)
    if (!b) brands.push(b = { name: p.brand, items: [] })
    b.items.push(p)
  }
  for (const b of brands) b.items.sort((x, y) => Number(y.available) - Number(x.available))
  return { ...c, brands }
}).filter((g) => g.brands.length))

// v1.52: game cards out of stock that the cards in stock make up, with their price (the sum of the cards)
const splits = ref({})
const canBuy = (p) => p.available || !!splits.value[p.product_id]
const partsText = (s) => (s.parts.length === 2 ? 'بطاقتين' : s.parts.length + ' بطاقات') + ' (' + s.parts.join(' + ') + ')'
async function load () {
  const [rows, sp] = await Promise.all([run(() => buyer.catalog()), buyer.splitOffers()])
  if (rows) products.value = rows
  splits.value = sp || {}
  loaded.value = true
  openBrand()
}

// «/store?brand=PUBG» (a home banner link) opens on that brand
const route = useRoute()
function openBrand () {
  const p = products.value.find((x) => x.brand === route.query.brand)
  if (!p) return
  cat.value = p.category
  brand.value = p.brand
}
watch(() => route.query.brand, openBrand)

const buyOpen = ref(false)
const sel = ref(null)
const qty = ref(1)
let requestId = null
const selSplit = computed(() => (sel.value && !sel.value.available ? splits.value[sel.value.product_id] || null : null))
const unitPrice = computed(() => (selSplit.value ? Number(selSplit.value.total) : sel.value?.base_price || 0))

function openBuy (p) {
  interest('buy:' + p.name)
  sel.value = p
  qty.value = 1
  requestId = newRequestId()   // one id per purchase attempt; a retry reuses it
  buyOpen.value = true
}

const codesOpen = ref(false)
const bought = ref({ subtitle: '', codes: [], orderId: null })

async function confirmBuy () {
  const res = await run(() => (selSplit.value ? buyer.buySplit(sel.value.product_id, qty.value, requestId) : buyer.buy(sel.value.product_id, qty.value, requestId)))
  if (!res) {
    await load()
    return
  }
  buyOpen.value = false
  // The purchase answer has no card ids; take them from the order so a copy can be saved on the server.
  // Without them the copy is still remembered on this device.
  const rows = await buyer.orderCodes(res.order_id).catch(() => [])
  const idOf = new Map(rows.map((r) => [r.code, r.code_id]))
  bought.value = {
    subtitle: `${res.product_name} × ${res.qty} — احتفظ بالكود أو انسخه`,
    orderId: res.order_id,
    codes: res.codes.map((c) => ({ ...c, id: idOf.get(c.code) ?? null, actionLabel: 'نسخ', action: () => copyText(c.code),
      ...(c.name ? { badge: { color: 'deep-orange', label: c.name } } : {}) }))
  }
  codesOpen.value = true
  run(() => buyer.refresh())
  load()
}

onMounted(load)
</script>

<style scoped>
.split-note { background: #FFF7ED; color: #9A3412; border-radius: 10px; padding: 8px 10px; font-weight: 600; }
.cat-title { font-size: 17px; font-weight: 700; margin-top: 8px; }
.brand-title { font-size: 13px; font-weight: 600; color: #5B6170; margin-top: 2px; }
.price-badge { background: #111827; color: #fff; font-size: 15px; font-weight: 700; padding: 2px 12px; border-radius: 999px; }
.game-badge { background: #6D28D9; }
</style>
