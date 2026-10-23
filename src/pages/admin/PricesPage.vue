<template>
  <q-page class="page">
    <div class="small muted">
      لكل بطاقة: <b>الربح الكلي = سعر البيع − سعر الشراء</b>. تكتب <b>نسبة الزبون من الربح</b> والباقي لك، فإن غلا الشراء نقص ربحكما معًا
      (مثال: بطاقة 1000 وشراء 960 والزبون 50% ← يدفع 980). أو تكتب <b>سعرًا ثابتًا</b> لا يتغيّر مع الشراء.
    </div>
    <q-select v-model="who" :options="whoOptions" emit-value map-options dense outlined label="أسعار مَن؟" />
    <div class="q-pa-sm rounded-borders text-weight-medium" :class="who === DEFAULT ? 'banner-default' : 'banner-own'">
      <template v-if="who === DEFAULT">تعدّل الآن: <b>السعر الافتراضي لكل الزبائن</b> (كل من ليس له سعر خاص)</template>
      <template v-else>تعدّل الآن: <b>سعر خاص بـ {{ whoName }}</b> — لا يؤثر على غيره</template>
    </div>
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" />

    <!-- Overview: one line per card; tap a line to edit it -->
    <div v-if="activeCards.length" class="card q-pa-none overview">
      <table>
        <thead>
          <tr><th class="name">البطاقة</th><th>الشراء</th><th>يدفع الزبون</th><th>ربح الزبون</th><th>ربحي</th></tr>
        </thead>
        <tbody>
          <template v-for="r in activeCards" :key="r.product_id">
            <tr class="line" :class="{ open: openId === r.product_id }" tabindex="0" @click="toggle(r)" @keydown.enter="toggle(r)">
              <td class="name">
                <div class="text-weight-bold">{{ r.product_name }}</div>
                <div class="small muted">بيع {{ money(r.base_price) }}
                  <span v-if="who !== DEFAULT" class="own-dot" :class="{ on: r.own }">{{ r.own ? 'خاص' : 'افتراضي' }}</span>
                </div>
              </td>
              <td>{{ r.cost == null ? '—' : money(r.cost) }}</td>
              <td class="text-weight-bold">{{ r.price == null ? '—' : money(r.price) }}</td>
              <td :class="custProfit(r) < 0 ? 'neg' : 'cust'">{{ fmtProfit(custProfit(r)) }}<div v-if="r.share != null" class="small">{{ r.share }}%</div></td>
              <td :class="myProfit(r) < 0 ? 'neg' : 'me'">{{ fmtProfit(myProfit(r)) }}<div v-if="r.share != null" class="small">{{ round2(100 - r.share) }}%</div></td>
            </tr>
            <tr v-if="openId === r.product_id" class="edit-row">
              <td colspan="5">
                <div class="column q-gutter-sm q-pa-sm">
                  <!-- Purchase and selling prices are set when a batch is entered in «المخزن»; read-only here -->
                  <div class="small muted">
                    سعر الشراء {{ r.cost == null ? 'غير معروف' : money(r.cost) }}{{ COST_FROM[r.costSource] || '' }} · سعر البيع {{ money(r.base_price) }}
                    — يُعدَّلان عند إدخال دفعة في <router-link to="/stock">المخزن</router-link>
                  </div>
                  <div class="sum-line total">
                    <span>الربح الكلي</span>
                    <b>{{ r.cost == null ? '—' : fmtProfit(r.base_price - r.cost) }}</b>
                    <span v-if="r.cost != null" class="small">{{ pctOfSell(r, r.base_price - r.cost) }}% من سعر البيع</span>
                  </div>

                  <div class="grid-2">
                    <q-input :model-value="r.share" dense outlined type="number" inputmode="decimal" stack-label label="ربح الزبون من الربح"
                      suffix="%" input-class="text-center" :disable="r.cost == null || r.base_price <= r.cost" :class="{ 'rule-field': r.mode === 'share' }"
                      @update:model-value="(v) => edit(r, 'share', v)" />
                    <q-input :model-value="r.price" dense outlined type="number" inputmode="numeric" stack-label label="أو سعر ثابت يدفعه"
                      suffix="دج" input-class="text-center" :class="{ 'rule-field': r.mode === 'fixed' }"
                      @update:model-value="(v) => edit(r, 'price', v)" />
                  </div>

                  <div v-if="r.price != null && r.cost != null" class="column q-gutter-xs">
                    <div class="sum-line cust">
                      <span>ربح الزبون</span><b>{{ fmtProfit(custProfit(r)) }}</b>
                      <span class="small">{{ r.share != null ? r.share + '% من الربح · ' : '' }}{{ pctOfSell(r, custProfit(r)) }}% من سعر البيع</span>
                    </div>
                    <div class="sum-line me">
                      <span>ربحي المتبقي</span><b>{{ fmtProfit(myProfit(r)) }}</b>
                      <span class="small">{{ r.share != null ? round2(100 - r.share) + '% من الربح · ' : '' }}{{ pctOfSell(r, myProfit(r)) }}% من سعر البيع</span>
                    </div>
                  </div>
                  <div class="small" style="color:#4338CA">القاعدة: {{ RULE_TEXT[r.mode](r) }}</div>
                  <div v-if="r.cost == null" class="small text-warning">لا يوجد سعر شراء بعد: أدخل دفعة في «المخزن» ليُحسب الربح، أو اكتب سعرًا ثابتًا.</div>
                  <div v-if="r.cost != null && r.price != null && r.price < r.cost" class="small q-pa-sm rounded-borders warn-loss">
                    تنبيه: أقل من سعر الشراء — خسارة {{ money(r.cost - r.price) }} في كل بطاقة (مسموح لك).
                  </div>
                  <div v-else-if="r.price != null && r.price > r.base_price" class="small q-pa-sm rounded-borders warn-high">
                    أعلى من سعر البيع ({{ money(r.base_price) }}) — الزبون يبيع بخسارة.
                  </div>
                  <div v-else-if="r.mode === 'share' && r.cost != null && r.base_price <= r.cost" class="small q-pa-sm rounded-borders warn-high">
                    لا ربح في هذه الدفعة: الزبون يدفع سعر الشراء.
                  </div>

                  <div class="row items-center q-gutter-sm">
                    <q-btn v-if="r.dirty" unelevated color="primary" :label="who === DEFAULT ? 'حفظ للجميع' : `حفظ لـ ${whoName}`" :loading="busy"
                      :disable="!valid(r)" @click="save(r)" />
                    <q-btn v-if="r.dirty" flat label="إلغاء" @click="load" />
                    <q-btn v-if="who !== DEFAULT && r.own && !r.dirty" flat dense no-caps color="primary" label="إرجاع للافتراضي" @click="inherit(r)" />
                    <q-space />
                    <q-btn dense outline size="sm" color="warning" label="إيقاف البطاقة" :ripple="false" @click="toggleActive(r)" />
                  </div>
                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
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
import { useRoute } from 'vue-router'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money } from 'src/api/format'
import CatalogFilter from 'components/CatalogFilter.vue'

const DEFAULT = 'default'
const COST_FROM = { stock: ' (الدفعة الحالية)', usual: ' (المعتاد)', last: ' (آخر دفعة)' }
// Rules typed here: 'share' (customer's % of selling − cost) or 'fixed'. Older 'amount' / 'pct' rules are shown as they are.
const RULE_TEXT = {
  fixed: (r) => `سعر ثابت ${money(r.price)} مهما تغيّر سعر الشراء`,
  share: (r) => `للزبون ${r.share}% من الربح ولي الباقي، ويُعاد الحساب مع كل دفعة`,
  amount: (r) => `قاعدة قديمة: سعر الشراء + ${money(r.value)} — اكتب نسبة الزبون أو سعرًا ثابتًا لتغييرها`,
  pct: (r) => `قاعدة قديمة: ربحي ${r.value}% من سعر البيع — اكتب نسبة الزبون أو سعرًا ثابتًا لتغييرها`
}

const { busy, run } = useRun()
const cat = ref('phone')
const brand = ref('all')
// «أسعار ونسب هذا الزبون» in the customer page opens here with ?who=<id>
const who = ref(String(useRoute().query.who || DEFAULT))
const rows = ref([])
const loaded = ref(false)
const openId = ref(null)

const round2 = (n) => Math.round(n * 100) / 100
const pctOfSell = (r, amount) => round2(amount / r.base_price * 100)
const custProfit = (r) => (r.price == null ? null : r.base_price - r.price)
const myProfit = (r) => (r.price == null || r.cost == null ? null : r.price - r.cost)
const fmtProfit = (n) => (n == null ? '—' : (n < 0 ? '−' : '') + money(n))

const whoOptions = computed(() => {
  const seen = new Map()
  for (const x of rows.value) if (x.customer_id != null && !seen.has(x.customer_id)) seen.set(x.customer_id, x.customer_name)
  return [{ value: DEFAULT, label: 'الافتراضي (لكل زبون ليس له سعر خاص)' },
    ...[...seen].map(([id, name]) => ({ value: String(id), label: name }))]
})
const whoName = computed(() => whoOptions.value.find((o) => o.value === who.value)?.label || '')

const inCat = (x) => cat.value === 'all' || x.category === cat.value
const brandList = computed(() => [...new Set(rows.value.filter((x) => x.customer_id == null && x.active && inCat(x)).map((x) => x.brand))])

// Same formulas as private.store_unit_charge
function priceOf (r) {
  const c = r.cost
  if (r.mode === 'fixed') return r.value
  if (c == null || r.value == null) return null
  if (r.mode === 'amount') return c + Math.round(r.value)
  if (r.mode === 'pct') return c + Math.round(r.base_price * r.value / 100)
  // customer profit first; my profit is what remains
  const margin = Math.max(r.base_price - c, 0)
  return c + margin - Math.round(margin * r.value / 100)
}
// Customer's share of the margin that a given price means (null when there is no margin)
const shareOf = (r) => (r.price != null && r.cost != null && r.base_price > r.cost ? round2((r.base_price - r.price) / (r.base_price - r.cost) * 100) : null)

function derive (r) {
  r.price = priceOf(r)
  r.share = r.mode === 'share' ? r.value : shareOf(r)
}

const cards = ref([])
function buildCards () {
  cards.value = rows.value
    .filter((x) => (who.value === DEFAULT ? x.customer_id == null : String(x.customer_id) === who.value))
    .map((x) => {
      const r = {
        product_id: x.product_id, product_name: x.product_name, brand: x.brand, category: x.category, active: x.active,
        base_price: Number(x.base_price), cost: x.current_cost == null ? null : Number(x.current_cost),
        costSource: x.cost_source,
        own: x.source === 'customer', mode: x.mode, value: Number(x.value), dirty: false, price: null, share: null
      }
      derive(r)
      return r
    })
}
const shown = (r) => inCat(r) && (brand.value === 'all' || r.brand === brand.value)
const activeCards = computed(() => cards.value.filter((r) => r.active && shown(r)))
const stoppedCards = computed(() => cards.value.filter((r) => !r.active && inCat(r)))

const toggle = (r) => { openId.value = openId.value === r.product_id ? null : r.product_id }

async function load () {
  const data = await run(() => api.priceList(null))
  if (!data) return
  rows.value = data
  loaded.value = true
  if (!whoOptions.value.some((o) => o.value === who.value)) who.value = DEFAULT
  buildCards()
}

// Typing the customer's share makes a 'share' rule; typing a price makes a 'fixed' rule
function edit (r, key, raw) {
  const v = raw === '' || raw == null ? null : Number(raw)
  r.dirty = true
  r.mode = key === 'share' ? 'share' : 'fixed'
  r.value = v
  derive(r)
}

function valid (r) {
  if (r.mode === 'fixed') return r.value > 0
  if (r.mode === 'share') return r.value != null && r.value >= 0 && r.value <= 100
  return false
}

const customerId = () => (who.value === DEFAULT ? null : Number(who.value))

async function save (r) {
  const ok = await run(() => api.setPrice(customerId(), r.product_id, r.mode, r.value).then(() => true), { success: 'حُفظ السعر.' })
  if (ok) load()
}

async function inherit (r) {
  const ok = await run(() => api.setPrice(customerId(), r.product_id, 'inherit', null).then(() => true), { success: 'عاد إلى السعر الافتراضي.' })
  if (ok) load()
}

// Same switch as «إيقاف / تفعيل» in «المخزن»
async function toggleActive (r) {
  const ok = await run(() => api.saveProduct({ id: r.product_id, active: !r.active }).then(() => true),
    { success: r.active ? `أُوقفت «${r.product_name}» ولن تظهر للزبائن.` : `فُعّلت «${r.product_name}» وعادت للمتجر.` })
  if (ok) load()
}

watch(who, () => { openId.value = null; buildCards() })
onMounted(load)
</script>

<style scoped>
.overview { overflow-x: auto; }
.overview table { width: 100%; border-collapse: collapse; font-size: 13px; font-variant-numeric: tabular-nums; }
.overview th { font-weight: 500; color: #5B6170; font-size: 12px; padding: 8px 4px; border-bottom: 1px solid #EEF0F5; white-space: nowrap; }
.overview td { padding: 8px 4px; text-align: center; border-bottom: 1px solid #EEF0F5; white-space: nowrap; }
.overview .name { text-align: right; padding-right: 12px; white-space: normal; }
.overview tr.line { cursor: pointer; }
.overview tr.line:hover, .overview tr.line.open { background: #F7F8FB; }
.overview tr.line:focus-visible { outline: 2px solid #4F46E5; outline-offset: -2px; }
.overview .edit-row td { text-align: right; white-space: normal; background: #FBFBFE; }
.cust { color: #15803D; }
.me { color: #0E7490; }
.neg { color: #B91C1C; }
.own-dot { margin-right: 4px; padding: 0 6px; border-radius: 99px; background: #E5E7EB; color: #4B5563; font-size: 11px; }
.own-dot.on { background: #4F46E5; color: #fff; }
.sum-line { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; padding: 8px 12px; border-radius: 10px; }
.sum-line b { font-size: 16px; }
.sum-line.total { background: #EEF0FF; color: #3730A3; }
.sum-line.cust { background: #EAF7EE; }
.sum-line.me { background: #E6F6F9; }
.rule-field :deep(.q-field__control) { background: #EEF0FF; }
.rule-field :deep(.q-field__control:before) { border: 2px solid #4F46E5; }
.warn-loss { background: #FEF2F2; color: #B91C1C; border: 1px solid #FCA5A5; }
.warn-high { background: #FFFBEB; color: #92400E; border: 1px solid #FCD34D; }
.banner-default { background: #EEF0FF; color: #3730A3; border: 1px solid #C7D2FE; }
.banner-own { background: #FFFBEB; color: #92400E; border: 1px solid #FCD34D; }
</style>
