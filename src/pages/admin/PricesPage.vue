<template>
  <q-page class="page">
    <div class="small muted">
      اكتب في أي خانة وتُحسب الأخريان. <b>آخر خانة تكتب فيها هي القاعدة</b>: السعر يبقى ثابتًا، أو الربح بالدينار يُضاف على سعر الشراء، أو النسبة تُحسب من المبلغ الذي يدفعه الزبون (مثال: شراء 910 ونسبة 9% ← 1000).
    </div>
    <div class="row q-gutter-sm">
      <q-btn v-for="c in CATEGORIES" :key="c.id" rounded no-caps :unelevated="cat === c.id" :outline="cat !== c.id"
        :color="cat === c.id ? 'primary' : 'grey-8'" :label="c.label" @click="cat = c.id" />
    </div>
    <q-select v-model="who" :options="whoOptions" emit-value map-options dense outlined label="أسعار مَن؟" />

    <div v-for="r in cards" :key="r.product_id" class="card column q-gutter-sm">
      <div class="row justify-between items-start no-wrap">
        <div>
          <div class="text-weight-bold">{{ r.product_name }}</div>
          <div class="small muted">سعر البيع للزبون النهائي {{ money(r.base_price) }}</div>
        </div>
        <div class="column items-end">
          <span class="small muted">سعر الشراء الحالي</span>
          <b :class="r.cost == null ? 'text-warning' : ''">{{ r.cost == null ? 'غير مسجّل' : money(r.cost) }}</b>
        </div>
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
      <div class="small" :style="{ color: '#4338CA' }">القاعدة: {{ RULE_TEXT[r.mode](r) }}</div>

      <div v-if="r.cost != null && r.price != null && r.price < r.cost" class="small q-pa-sm rounded-borders warn-loss">
        تنبيه: أقل من سعر الشراء — خسارة {{ money(r.cost - r.price) }} في كل بطاقة (مسموح لك).
      </div>
      <div v-else-if="r.price != null && r.price > r.base_price" class="small q-pa-sm rounded-borders warn-high">
        أعلى من سعر البيع ({{ money(r.base_price) }}) — الزبون يبيع بخسارة.
      </div>
      <div v-else-if="r.price != null" class="small muted">ربح الزبون حين يبيع بـ {{ money(r.base_price) }}: {{ money(r.base_price - r.price) }}</div>

      <div v-if="r.dirty" class="row q-gutter-sm">
        <q-btn unelevated color="primary" label="حفظ" :loading="busy" :disable="!valid(r)" @click="save(r)" />
        <q-btn flat label="إلغاء" @click="load" />
      </div>
    </div>
    <div v-if="loaded && !cards.length" class="text-center muted q-pa-lg">لا توجد بطاقات في هذه الفئة</div>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money, CATEGORIES } from 'src/api/format'

const DEFAULT = 'default'
const FIELDS = [
  { key: 'price', mode: 'fixed', label: 'يدفع الزبون', suffix: 'دج' },
  { key: 'dzd', mode: 'amount', label: 'ربحي', suffix: 'دج' },
  { key: 'pct', mode: 'pct', label: 'ربحي', suffix: '%' }
]
const RULE_TEXT = {
  fixed: (r) => `سعر ثابت ${money(r.price)} مهما تغيّر سعر الشراء`,
  amount: (r) => `سعر الشراء + ${money(r.dzd)} (يتغيّر مع كل دفعة)`,
  pct: (r) => `ربح ${r.pct}% من المبلغ المدفوع (يتغيّر مع كل دفعة)`
}

const { busy, run } = useRun()
const cat = ref('phone')
const who = ref(DEFAULT)
const rows = ref([])
const loaded = ref(false)

const round2 = (n) => Math.round(n * 100) / 100
const pctOf = (price, cost) => (price > 0 && cost != null ? round2((price - cost) / price * 100) : null)

const whoOptions = computed(() => {
  const seen = new Map()
  for (const x of rows.value) if (x.customer_id != null && !seen.has(x.customer_id)) seen.set(x.customer_id, x.customer_name)
  return [{ value: DEFAULT, label: 'الافتراضي (لكل زبون ليس له سعر خاص)' },
    ...[...seen].map(([id, name]) => ({ value: String(id), label: name }))]
})

// One editable card per product for the selected person
const cards = ref([])
function buildCards () {
  cards.value = rows.value
    .filter((x) => (who.value === DEFAULT ? x.customer_id == null : String(x.customer_id) === who.value))
    .map((x) => {
      const cost = x.current_cost == null ? null : Number(x.current_cost)
      const price = x.charge_now == null ? null : Number(x.charge_now)
      const r = {
        product_id: x.product_id, product_name: x.product_name, base_price: Number(x.base_price), cost,
        customer_id: x.customer_id, own: x.source === 'customer', mode: x.mode, dirty: false,
        price, dzd: price != null && cost != null ? price - cost : null, pct: pctOf(price, cost)
      }
      // the stored rule is shown exactly as typed
      if (x.mode === 'fixed') r.price = Number(x.value)
      if (x.mode === 'amount') r.dzd = Number(x.value)
      if (x.mode === 'pct') r.pct = Number(x.value)
      return r
    })
}

async function load () {
  const data = await run(() => api.prices(cat.value))
  if (!data) return
  rows.value = data
  loaded.value = true
  if (!whoOptions.value.some((o) => o.value === who.value)) who.value = DEFAULT
  buildCards()
}

// Typing in one field recomputes the other two; that field becomes the rule
function edit (r, key, raw) {
  const v = raw === '' || raw == null ? null : Number(raw)
  const c = r.cost
  r.dirty = true
  if (key === 'price') {
    r.mode = 'fixed'
    r.price = v
    r.dzd = v != null && c != null ? v - c : null
    r.pct = v != null ? pctOf(v, c) : null
  } else if (key === 'dzd') {
    r.mode = 'amount'
    r.dzd = v
    r.price = v != null ? c + v : null
    r.pct = v != null ? pctOf(r.price, c) : null
  } else {
    r.mode = 'pct'
    r.pct = v
    r.price = v != null && v < 100 ? Math.round(c / (1 - v / 100)) : null
    r.dzd = r.price != null ? r.price - c : null
  }
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

watch(cat, load)
watch(who, buildCards)
onMounted(load)
</script>

<style scoped>
.rule-field :deep(.q-field__control) { background: #EEF0FF; }
.rule-field :deep(.q-field__control:before) { border: 2px solid #4F46E5; }
.warn-loss { background: #FEF2F2; color: #B91C1C; border: 1px solid #FCA5A5; }
.warn-high { background: #FFFBEB; color: #92400E; border: 1px solid #FCD34D; }
</style>
