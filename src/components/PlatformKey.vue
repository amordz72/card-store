<template>
  <!-- «منصة topup-dz» (owner 2026-11-01, s178): the API key typed here, kept encrypted in Vault, never shown again -->
  <div class="column q-gutter-sm q-pa-md">
    <div v-if="missing" class="small text-negative">طبّق s178 من «ينتظر تطبيقك» أولًا.</div>
    <template v-else>
      <div v-if="info" class="row items-center q-gutter-sm">
        <q-badge color="positive" class="q-pa-sm">✓ محفوظ · آخره <bdi dir="ltr" class="q-ml-xs">…{{ info.last4 }}</bdi></q-badge>
        <span class="small muted">{{ dateTime(info.saved_at) }}</span>
        <q-space />
        <q-btn flat dense no-caps color="negative" label="احذفه" :disable="busy" @click="clear" />
      </div>
      <div v-else class="small muted">لا يوجد مفتاح محفوظ.</div>
      <q-input v-model="key" dense outlined :type="show ? 'text' : 'password'" autocomplete="off" input-class="ltr"
        :label="info ? 'استبدل المفتاح (API TOKEN)' : 'المفتاح (API TOKEN)'">
        <template #append><q-icon :name="show ? 'visibility_off' : 'visibility'" class="cursor-pointer" @click="show = !show" /></template>
      </q-input>
      <q-btn unelevated no-caps color="primary" icon="lock" label="احفظ" :loading="busy" :disable="key.trim().length < 8" @click="save" />
      <div class="small muted">يُحفظ مشفّرًا في خزنة Supabase ولا يظهر بعد الحفظ، حتى لك. «السماح لكل الايبيات» يبقى في موقع topup-dz.</div>

      <!-- The dollar as the owner bought it: cost in dinars = platform price × rate -->
      <q-separator class="q-my-sm" />
      <div class="row items-center no-wrap q-gutter-sm">
        <q-input v-model.number="rate" class="col" dense outlined type="number" inputmode="decimal" min="1" step="0.5"
          label="سعر الدولار الذي اشتريت به (دج)" />
        <q-btn unelevated no-caps color="primary" label="احفظ" :loading="busy" :disable="!(rate > 0) || rate === savedRate" @click="saveRate" />
      </div>
      <div v-if="savedRate" class="small muted">المحفوظ: 1$ = {{ savedRate }} دج · {{ dateTime(rateAt) }}</div>

      <div class="row q-gutter-sm">
        <q-btn outline no-caps color="primary" icon="wifi_tethering" label="جرّب الاتصال" :loading="testing" :disable="!info" @click="test" />
        <q-btn outline no-caps color="primary" icon="sync" :label="fetchedAt ? 'حدّث من المنصة' : 'اجلب المنتجات من المنصة'" :loading="loadingProducts" :disable="!info" @click="loadProducts" />
      </div>
      <div v-if="balance !== null" class="text-weight-bold">رصيد المنصة: {{ usd(balance) }}<span v-if="rate > 0" class="muted"> ≈ {{ dzd(balance) }}</span></div>
      <div v-if="platformError" class="small text-negative">{{ platformError }}</div>

      <div v-if="fetchedAt" class="small muted">منتجات المنصة محفوظة: {{ products.length }} · حُدّثت {{ dateTime(fetchedAt) }} (لا طلب للمنصة إلا بزر «حدّث»)</div>

      <template v-if="products.length">
        <!-- Our own game products first (owner 2026-11-01): a tap shows the platform's matching products, cheapest first -->
        <div class="text-weight-bold q-mt-sm">منتجاتنا</div>
        <div v-for="b in ours" :key="b.brand" class="column q-gutter-xs">
          <div class="small text-weight-bold text-grey-8">{{ b.brand }}</div>
          <div class="row q-gutter-xs">
            <q-btn v-for="o in b.items" :key="o.product_id" no-caps dense :unelevated="picked === o.product_id" :outline="picked !== o.product_id"
              color="primary" :label="o.name + ' · ' + money(o.base_price)" @click="picked = picked === o.product_id ? null : o.product_id" />
          </div>
          <div v-if="pickedIn(b)" class="match column q-gutter-xs">
            <div class="small muted">مقابله في المنصة (المتاح، الأقرب أولًا ثم الأرخص) · سعرنا {{ money(pickedProduct?.base_price) }}:</div>
            <div v-for="p in matches" :key="p.id" class="prod row items-center no-wrap q-gutter-sm">
              <div class="col">
                <div class="text-weight-bold">{{ p.name }} <span class="small muted">#{{ p.id }}</span></div>
                <div class="small muted">{{ p.category }}<span v-if="p.params.length"> · {{ p.params.join('، ') }}</span></div>
              </div>
              <div class="text-right">
                <div class="text-weight-bold">{{ rate > 0 ? dzd(p.price) : '—' }}</div>
                <div class="small muted ltr">{{ usd(p.price) }}</div>
                <div v-if="rate > 0 && pickedProduct?.base_price" class="small" :class="gap(p) >= 0 ? 'text-positive' : 'text-negative'">
                  الفرق {{ gap(p) >= 0 ? '+' : '' }}{{ gap(p).toLocaleString('en-US') }} دج</div>
              </div>
            </div>
            <div v-if="!matches.length" class="small muted">لا يوجد مقابل متاح في المنصة.</div>
          </div>
        </div>
        <div v-if="!ours.length" class="small muted">لا توجد منتجات ألعاب في موقعك بعد.</div>

        <!-- The whole platform list, last and closed -->
        <q-expansion-item dense class="cat q-mt-md" header-class="cat-head" :label="'كل منتجات المنصة (' + groups.length + ' فئة)'">
          <div class="column q-gutter-sm q-pa-sm">
            <q-input v-model="search" dense outlined clearable label="ابحث عن فئة أو منتج" />
            <q-toggle v-model="onlyAvailable" label="المتاح فقط" />
            <q-expansion-item v-for="g in groups.slice(0, limit)" :key="g.name" dense class="cat" header-class="cat-head">
              <template #header>
                <q-item-section><span class="text-weight-bold">{{ g.name }}</span></q-item-section>
                <q-item-section side><span class="small muted">{{ g.items.length }} · من {{ rate > 0 ? dzd(g.min) : usd(g.min) }}</span></q-item-section>
              </template>
              <div v-for="p in g.items" :key="p.id" class="prod row items-center no-wrap q-gutter-sm">
                <div class="col">
                  <div class="text-weight-bold">{{ p.name }} <span class="small muted">#{{ p.id }}</span></div>
                  <div class="small muted"><span v-if="p.params.length">{{ p.params.join('، ') }}</span><span v-if="!p.available" class="text-negative"> · غير متاح</span></div>
                </div>
                <div class="text-right">
                  <div class="text-weight-bold">{{ rate > 0 ? dzd(p.price) : '—' }}</div>
                  <div class="small muted ltr">{{ usd(p.price) }}</div>
                </div>
              </div>
            </q-expansion-item>
            <q-btn v-if="groups.length > limit" flat no-caps color="primary" label="المزيد من الفئات" @click="limit += 50" />
          </div>
        </q-expansion-item>
      </template>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { ownerPlatformProducts, ownerPlatformProfile } from 'src/api/flexy'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { dateTime, money } from 'src/api/format'

const PLATFORM = 'topup-dz'
const { busy, run } = useRun()
const key = ref('')
const show = ref(false)
const info = ref(null)
const missing = ref(false)

async function load () {
  try {
    info.value = (await api.platformKeys())?.[PLATFORM] || null
  } catch (e) {
    missing.value = /store_admin_platform_keys/.test(e?.message || '')
  }
}
async function save () {
  const r = await run(() => api.platformKeySet(PLATFORM, key.value.trim()), { success: 'حُفظ المفتاح.' })
  if (r) { key.value = ''; show.value = false; await load() }
}
async function clear () {
  const r = await run(() => api.platformKeyClear(PLATFORM), { success: 'حُذف المفتاح.' })
  if (r !== undefined) await load()
}
const rate = ref(null)
const savedRate = ref(null)
const rateAt = ref(null)
const testing = ref(false)
const loadingProducts = ref(false)
const balance = ref(null)
const platformError = ref('')
const products = ref([])
const search = ref('')
const onlyAvailable = ref(true)
const limit = ref(50)

const ERRORS = {
  NO_KEY: 'لا يوجد مفتاح محفوظ.', MIGRATION_S178: 'طبّق s178 أولًا.', TOKEN_REQUIRED: 'المفتاح مفقود.', TOKEN_ERROR: 'المفتاح خاطئ: الصقه من جديد.',
  API_NOT_ALLOWED: 'حسابك عند المنصة غير مسموح له باستعمال API.', IP_NOT_ALLOWED: 'الـIP غير مسموح: فعّل «السماح لكل الايبيات» في موقع topup-dz.',
  MAINTENANCE: 'المنصة في صيانة الآن.', TIMEOUT: 'المنصة لم ترد في 15 ثانية.', UNREACHABLE: 'تعذّر الوصول إلى المنصة.',
  BAD_REPLY: 'رد غير مفهوم من المنصة.', UNKNOWN: 'خطأ غير معروف من المنصة.', OWNER_REQUIRED: 'للمالك فقط.', ROUTE_NOT_FOUND: 'انشر flexy-api أولًا.'
}
const say = (r) => ERRORS[r?.body?.error] || r?.body?.error || 'خطأ'
const usd = (v) => (v === null || v === undefined ? '—' : Number(v).toLocaleString('en-US', { maximumFractionDigits: 3 }) + ' $')
const dzd = (v) => (v === null || v === undefined || !(rate.value > 0) ? '—' : Math.round(Number(v) * rate.value).toLocaleString('en-US') + ' دج')
const isTest = (p) => /\btest\b/i.test(p.name + ' ' + p.category)
const shown = computed(() => {
  const q = String(search.value || '').trim().toLowerCase()
  return products.value.filter((p) => !isTest(p) && (!onlyAvailable.value || p.available) &&
    (!q || (p.name + ' ' + p.category).toLowerCase().includes(q)))
})
// by category, each by price; the categories by name
const groups = computed(() => {
  const m = new Map()
  for (const p of shown.value) {
    const k = (p.category || 'أخرى').trim()
    if (!m.has(k)) m.set(k, [])
    m.get(k).push(p)
  }
  return [...m.entries()].map(([name, items]) => {
    items.sort((a, b) => (a.price ?? 0) - (b.price ?? 0))
    return { name, items, min: items[0]?.price ?? null }
  }).sort((a, b) => a.name.localeCompare(b.name, 'en', { sensitivity: 'base' }))
})

async function loadRate () {
  try {
    const r = (await api.platformRates())?.[PLATFORM]
    savedRate.value = r ? Number(r.usd_rate) : null
    rateAt.value = r?.set_at || null
    if (rate.value === null && savedRate.value) rate.value = savedRate.value
  } catch { /* before s178 */ }
}
async function saveRate () {
  const r = await run(() => api.platformRateSet(PLATFORM, rate.value), { success: 'حُفظ سعر الدولار.' })
  if (r) await loadRate()
}
async function test () {
  testing.value = true
  platformError.value = ''
  try {
    const r = await ownerPlatformProfile()
    if (r.status === 200 && r.body?.ok) balance.value = r.body.balance
    else { balance.value = null; platformError.value = say(r) }
  } finally { testing.value = false }
}
const fetchedAt = ref(null)
// s179: the saved copy; the platform is asked only on «حدّث من المنصة» (or the first time)
async function loadSaved () {
  try {
    const c = await api.platformCatalog(PLATFORM)
    if (c) { products.value = c.products || []; fetchedAt.value = c.fetched_at }
  } catch { /* before s179 */ }
}
async function loadProducts () {
  loadingProducts.value = true
  platformError.value = ''
  try {
    const r = await ownerPlatformProducts()
    if (r.status === 200 && r.body?.ok) {
      products.value = r.body.products || []
      limit.value = 50
      try {
        const saved = await api.platformCatalogSave(PLATFORM, products.value)
        fetchedAt.value = saved?.fetched_at || new Date().toISOString()
      } catch { platformError.value = 'جُلبت المنتجات، لكن لم تُحفظ: طبّق s179.' }
    } else platformError.value = say(r)
  } finally { loadingProducts.value = false }
}

// Our game products (the stock's «game» category), by brand
const ourProducts = ref([])
const picked = ref(null)
const ours = computed(() => {
  const m = new Map()
  for (const p of ourProducts.value) {
    if (!m.has(p.brand)) m.set(p.brand, [])
    m.get(p.brand).push(p)
  }
  return [...m.entries()].map(([brand, items]) => ({ brand, items: items.sort((a, b) => (a.base_price ?? 0) - (b.base_price ?? 0)) }))
})
const pickedProduct = computed(() => ourProducts.value.find((x) => x.product_id === picked.value) || null)
// our price minus the platform's cost in dinars (viewing only, at the rate typed above)
const gap = (p) => Math.round(Number(pickedProduct.value?.base_price || 0) - Number(p.price || 0) * Number(rate.value || 0))
const pickedIn = (b) => b.items.some((o) => o.product_id === picked.value)
const flat = (t) => String(t || '').toLowerCase().replace(/[^a-z0-9\u0600-\u06ff]+/g, '')
const firstNumber = (t) => (String(t || '').match(/\d+/) || [null])[0]
// The platform's products of the same game (its brand's letters in the name or category), the same number first, then by price
const matches = computed(() => {
  const o = ourProducts.value.find((x) => x.product_id === picked.value)
  if (!o) return []
  const brand = flat(o.brand)
  const n = firstNumber(o.name)
  return products.value
    .filter((p) => p.available && !isTest(p) && brand && flat(p.name + ' ' + p.category).includes(brand))
    .map((p) => ({ p, same: n !== null && new RegExp('(^|\\D)' + n + '(\\D|$)').test(p.name) }))
    .sort((a, b) => (b.same - a.same) || ((a.p.price ?? 0) - (b.p.price ?? 0)))
    .slice(0, 20).map((x) => x.p)
})
async function loadOurs () {
  try {
    const stock = await api.stock()
    ourProducts.value = (stock || []).filter((p) => p.category === 'game' && p.active && p.brand_active)
  } catch { ourProducts.value = [] }
}

onMounted(() => { load(); loadRate(); loadSaved(); loadOurs() })
</script>

<style scoped>
.prod { border-top: 1px solid #EEF0F4; padding: 6px 12px; }
.cat { border: 1px solid #E3E6EC; border-radius: 10px; overflow: hidden; }
.match { background: #F7F8FB; border-radius: 10px; padding: 6px 0; }
</style>
