<template>
  <q-page class="page">
    <div class="small muted">
      اكتب في أي خانة وتُحسب الأخريان. <b>آخر خانة تكتب فيها هي القاعدة</b>: السعر يبقى ثابتًا، أو الربح بالدينار يُضاف على سعر الشراء، أو النسبة تُحسب <b>من سعر البيع</b> (مثال: بطاقة 1000 وشراء 910 وربحي 1% ← 10 دج، فيدفع الزبون 920).
    </div>
    <q-select v-model="who" :options="whoOptions" emit-value map-options dense outlined label="أسعار مَن؟" />
    <div class="q-pa-sm rounded-borders text-weight-medium" :class="who === DEFAULT ? 'banner-default' : 'banner-own'">
      <template v-if="who === DEFAULT">تعدّل الآن: <b>السعر الافتراضي لكل الزبائن</b> (كل من ليس له سعر خاص)</template>
      <template v-else>تعدّل الآن: <b>سعر خاص بـ {{ whoName }}</b> — لا يؤثر على غيره</template>
    </div>
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" />

    <div v-for="r in activeCards" :key="r.product_id" class="card column q-gutter-sm">
      <div class="row justify-between items-start no-wrap">
        <div>
          <div class="text-weight-bold">{{ r.product_name }}</div>
          <div class="small muted">سعر البيع للزبون النهائي {{ money(r.base_price) }}</div>
        </div>
        <q-btn dense outline size="sm" color="warning" label="إيقاف" :ripple="false" @click="toggleActive(r)" />
      </div>

      <!-- Purchase cost: from stock when codes exist, otherwise the usual cost typed here -->
      <div class="row items-center q-gutter-sm no-wrap">
        <template v-if="r.costSource === 'stock'">
          <span class="small muted">سعر الشراء (من المخزن)</span><b>{{ money(r.cost) }}</b>
        </template>
        <template v-else>
          <q-input :model-value="r.usualDraft" class="col" dense outlined type="number" inputmode="numeric" stack-label
            label="سعر الشراء المعتاد (دج)" :hint="r.costSource === 'last' && r.usual == null ? `آخر دفعة: ${money(r.cost)}` : 'يُستعمل حتى تصل أكواد بسعرها'"
            :class="{ 'need-cost': r.cost == null }" @update:model-value="(v) => (r.usualDraft = v === '' ? null : Number(v))" />
          <q-btn v-if="r.usualDraft !== r.usual" unelevated dense color="primary" label="حفظ" :disable="r.usualDraft != null && !(r.usualDraft > 0)"
            @click="saveUsual(r)" />
        </template>
      </div>

      <div v-if="who !== DEFAULT" class="row items-center q-gutter-sm">
        <span class="badge" :style="{ background: r.own ? '#4F46E5' : '#9CA3AF' }">{{ r.own ? 'سعر خاص به' : 'يتبع الافتراضي' }}</span>
        <q-btn v-if="r.own && !r.dirty" flat dense no-caps color="primary" label="إرجاع للافتراضي" @click="inherit(r)" />
      </div>

      <div class="grid-3">
        <q-input v-for="f in FIELDS" :key="f.key" :model-value="r[f.key]" dense outlined type="number" inputmode="decimal"
          stack-label :label="f.label" :suffix="f.suffix" :disable="f.key !== 'price' && r.cost == null"
          :class="{ 'rule-field': r.mode === f.mode }" input-class="text-center"
          @update:model-value="(v) => edit(r, f.key, v)" />
      </div>
      <div class="small" style="color:#4338CA">القاعدة: {{ RULE_TEXT[r.mode](r) }}</div>
      <div v-if="r.cost == null" class="small text-warning">اكتب سعر الشراء المعتاد أعلاه ليُحسب ربحك.</div>

      <div v-if="r.cost != null && r.price != null && r.price < r.cost" class="small q-pa-sm rounded-borders warn-loss">
        تنبيه: أقل من سعر الشراء — خسارة {{ money(r.cost - r.price) }} في كل بطاقة (مسموح لك).
      </div>
      <div v-else-if="r.price != null && r.price > r.base_price" class="small q-pa-sm rounded-borders warn-high">
        أعلى من سعر البيع ({{ money(r.base_price) }}) — الزبون يبيع بخسارة.
      </div>
      <div v-else-if="r.price != null" class="small muted">ربح الزبون حين يبيع بـ {{ money(r.base_price) }}: {{ money(r.base_price - r.price) }}</div>

      <div v-if="r.dirty" class="row q-gutter-sm">
        <q-btn unelevated color="primary" :label="who === DEFAULT ? 'حفظ للجميع' : `حفظ لـ ${whoName}`" :loading="busy" :disable="!valid(r)" @click="save(r)" />
        <q-btn flat label="إلغاء" @click="load" />
      </div>
    </div>
    <div v-if="loaded && !activeCards.length" class="text-center muted q-pa-lg">لا توجد بطاقات مفعّلة هنا</div>

    <q-expansion-item v-if="stoppedCards.length" class="card q-pa-none" dense-toggle
      :label="`البطاقات الموقوفة (${stoppedCards.length})`" caption="لا تظهر للزبائن">
      <div v-for="r in stoppedCards" :key="r.product_id" class="row items-center justify-between q-px-md q-py-sm" style="border-top:1px solid #EEF0F5">
        <span class="muted" style="text-decoration:line-through">{{ r.product_name }}</span>
        <q-btn dense outline size="sm" color="positive" label="تفعيل" @click="toggleActive(r)" />
      </div>
    </q-expansion-item>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money } from 'src/api/format'
import CatalogFilter from 'components/CatalogFilter.vue'

const DEFAULT = 'default'
const FIELDS = [
  { key: 'price', mode: 'fixed', label: 'يدفع الزبون', suffix: 'دج' },
  { key: 'dzd', mode: 'amount', label: 'ربحي', suffix: 'دج' },
  { key: 'pct', mode: 'pct', label: 'ربحي', suffix: '%' }
]
const RULE_TEXT = {
  fixed: (r) => `سعر ثابت ${money(r.price)} مهما تغيّر سعر الشراء`,
  amount: (r) => `سعر الشراء + ${money(r.dzd)} (يتغيّر مع كل دفعة)`,
  pct: (r) => `ربح ${r.pct}% من سعر البيع = ${money(Math.round(r.base_price * r.pct / 100))} فوق سعر الشراء (يتغيّر مع كل دفعة)`
}

const { busy, run } = useRun()
const cat = ref('phone')
const brand = ref('all')
const who = ref(DEFAULT)
const rows = ref([])
const loaded = ref(false)

const round2 = (n) => Math.round(n * 100) / 100
// profit % is a share of the SELLING price (owner decision): 10 DZD on a 1000 card = 1%
const pctOf = (r, price) => (price != null && r.cost != null && r.base_price > 0 ? round2((price - r.cost) / r.base_price * 100) : null)

const whoOptions = computed(() => {
  const seen = new Map()
  for (const x of rows.value) if (x.customer_id != null && !seen.has(x.customer_id)) seen.set(x.customer_id, x.customer_name)
  return [{ value: DEFAULT, label: 'الافتراضي (لكل زبون ليس له سعر خاص)' },
    ...[...seen].map(([id, name]) => ({ value: String(id), label: name }))]
})
const whoName = computed(() => whoOptions.value.find((o) => o.value === who.value)?.label || '')

const inCat = (x) => cat.value === 'all' || x.category === cat.value
const brandList = computed(() => [...new Set(rows.value.filter((x) => x.customer_id == null && x.active && inCat(x)).map((x) => x.brand))])

// Re-derive the two other fields from the rule field and the cost (no dirty flag)
function derive (r) {
  const c = r.cost
  if (r.mode === 'fixed') {
    r.dzd = r.price != null && c != null ? r.price - c : null
    r.pct = pctOf(r, r.price)
  } else if (r.mode === 'amount') {
    r.price = r.dzd != null && c != null ? c + r.dzd : null
    r.pct = pctOf(r, r.price)
  } else {
    r.price = r.pct != null && c != null ? c + Math.round(r.base_price * r.pct / 100) : null
    r.dzd = r.price != null ? r.price - c : null
  }
}

// One editable card per product for the selected person
const cards = ref([])
function buildCards () {
  cards.value = rows.value
    .filter((x) => (who.value === DEFAULT ? x.customer_id == null : String(x.customer_id) === who.value))
    .map((x) => {
      const usual = x.default_cost == null ? null : Number(x.default_cost)
      const r = {
        product_id: x.product_id, product_name: x.product_name, brand: x.brand, category: x.category, active: x.active,
        base_price: Number(x.base_price), cost: x.current_cost == null ? null : Number(x.current_cost),
        costSource: x.cost_source, usual, usualDraft: usual,
        own: x.source === 'customer', mode: x.mode, dirty: false, price: null, dzd: null, pct: null
      }
      // the stored rule is shown exactly as typed
      r[{ fixed: 'price', amount: 'dzd', pct: 'pct' }[x.mode]] = Number(x.value)
      derive(r)
      return r
    })
}
const shown = (r) => inCat(r) && (brand.value === 'all' || r.brand === brand.value)
const activeCards = computed(() => cards.value.filter((r) => r.active && shown(r)))
const stoppedCards = computed(() => cards.value.filter((r) => !r.active && inCat(r)))

async function load () {
  const data = await run(() => api.priceList(null))
  if (!data) return
  rows.value = data
  loaded.value = true
  if (!whoOptions.value.some((o) => o.value === who.value)) who.value = DEFAULT
  buildCards()
}

// Typing in one field recomputes the other two; that field becomes the rule
function edit (r, key, raw) {
  r.dirty = true
  r.mode = { price: 'fixed', dzd: 'amount', pct: 'pct' }[key]
  r[key] = raw === '' || raw == null ? null : Number(raw)
  derive(r)
}

function valid (r) {
  if (r.mode === 'fixed') return r.price > 0
  if (r.mode === 'amount') return r.dzd != null && r.dzd >= 0
  return r.pct != null && r.pct >= 0 && r.pct < 100
}

const ruleValue = (r) => (r.mode === 'fixed' ? r.price : r.mode === 'amount' ? r.dzd : r.pct)
const customerId = () => (who.value === DEFAULT ? null : Number(who.value))

async function save (r) {
  const ok = await run(() => api.setPrice(customerId(), r.product_id, r.mode, ruleValue(r)).then(() => true), { success: 'حُفظ السعر.' })
  if (ok) load()
}

async function inherit (r) {
  const ok = await run(() => api.setPrice(customerId(), r.product_id, 'inherit', null).then(() => true), { success: 'عاد إلى السعر الافتراضي.' })
  if (ok) load()
}

// The usual cost belongs to the card (same for everyone); keep unsaved price drafts of other cards
async function saveUsual (r) {
  const ok = await run(() => api.setDefaultCost(r.product_id, r.usualDraft).then(() => true), { success: 'حُفظ سعر الشراء المعتاد.' })
  if (!ok) return
  if (r.usualDraft == null) return load()   // cleared: the server knows the fallback (last batch)
  for (const x of rows.value.filter((x) => x.product_id === r.product_id)) {
    x.default_cost = r.usualDraft
    if (x.cost_source !== 'stock') { x.current_cost = r.usualDraft; x.cost_source = 'usual' }
  }
  for (const c of cards.value.filter((x) => x.product_id === r.product_id)) {
    c.usual = c.usualDraft = r.usualDraft
    if (c.costSource !== 'stock') {
      c.cost = r.usualDraft
      c.costSource = 'usual'
      derive(c)
    }
  }
}

// Same switch as «إيقاف / تفعيل» in «المخزن»
async function toggleActive (r) {
  const ok = await run(() => api.saveProduct({ id: r.product_id, active: !r.active }).then(() => true),
    { success: r.active ? `أُوقفت «${r.product_name}» ولن تظهر للزبائن.` : `فُعّلت «${r.product_name}» وعادت للمتجر.` })
  if (ok) load()
}

watch(who, buildCards)
onMounted(load)
</script>

<style scoped>
.rule-field :deep(.q-field__control) { background: #EEF0FF; }
.rule-field :deep(.q-field__control:before) { border: 2px solid #4F46E5; }
.need-cost :deep(.q-field__control:before) { border: 2px solid #F59E0B; }
.warn-loss { background: #FEF2F2; color: #B91C1C; border: 1px solid #FCA5A5; }
.warn-high { background: #FFFBEB; color: #92400E; border: 1px solid #FCD34D; }
.banner-default { background: #EEF0FF; color: #3730A3; border: 1px solid #C7D2FE; }
.banner-own { background: #FFFBEB; color: #92400E; border: 1px solid #FCD34D; }
</style>
