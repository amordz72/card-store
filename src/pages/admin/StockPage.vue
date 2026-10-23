<template>
  <q-page class="page">
    <!-- Tabs instead of one long page; stays visible under the header while scrolling; last tab remembered -->
    <div class="stock-tabs row no-wrap q-gutter-xs" :style="{ top: headerHeight + 'px' }">
      <q-btn v-for="t in TABS" :key="t.id" class="col" rounded no-caps dense :ripple="false" :unelevated="tab === t.id" :outline="tab !== t.id"
        :color="tab === t.id ? 'primary' : 'grey-8'" :label="t.label" :aria-pressed="tab === t.id" @click="tab = t.id" />
    </div>

    <div v-show="tab === 'settings'" class="tab-pane">
    <div class="card column q-gutter-sm">
      <q-input v-model="announcement" type="textarea" autogrow dense outlined label="إعلان الصفحة الرئيسية للزبائن (اتركه فارغًا لإخفائه)" />
      <q-btn outline color="primary" label="حفظ الإعلان" class="self-start" @click="saveAnnouncement" />
    </div>

    <div class="section-title">شعارات العلامات</div>
    <div class="card grid-2">
      <ImageField v-for="b in brands" :key="b.brand_id" :src="b.image" kind="brand" :id="b.brand_id" :label="b.name" @saved="load" />
    </div>
    </div>

    <div v-show="tab === 'codes'" class="tab-pane">
    <q-form ref="codesFormEl" class="card column q-gutter-sm" @submit.prevent="addCodes">
      <div class="text-weight-bold">إضافة أكواد للمخزن</div>
      <!-- Two taps instead of one long list: brand, then the card of that brand -->
      <div class="small muted">1. العلامة</div>
      <div class="row q-gutter-xs">
        <button v-for="b in pickBrands" :key="b.name" type="button" class="brand-pick" :class="{ on: pickBrand === b.name }"
          :aria-pressed="pickBrand === b.name" @click="choose(b.name, null)">
          <img v-if="b.image" :src="b.image" :alt="b.name">
          <span v-else>{{ b.name }}</span>
        </button>
      </div>
      <template v-if="pickBrand">
        <div class="small muted">2. البطاقة ({{ pickBrand }})</div>
        <div class="row q-gutter-xs">
          <q-btn v-for="p in pickProducts" :key="p.product_id" no-caps dense class="q-px-sm" :ripple="false"
            :unelevated="codeForm.productId === p.product_id" :outline="codeForm.productId !== p.product_id"
            :color="codeForm.productId === p.product_id ? 'primary' : 'grey-8'" @click="choose(p.brand, p.product_id)">
            <div class="column items-center" style="line-height:1.25">
              <span class="text-weight-medium">{{ shortName(p) }}</span>
              <span style="font-size:11px">متوفر {{ p.available }}</span>
            </div>
          </q-btn>
        </div>
      </template>
      <div v-if="pickedProduct" class="small text-weight-medium" style="color:#4338CA">البطاقة المختارة: {{ pickedProduct.name }}</div>
      <!-- Codes only after a card is chosen, so they cannot land on a card picked afterwards -->
      <q-file v-model="file" dense outlined accept=".txt,.csv,text/plain,text/csv" :disable="!codeForm.productId" clearable
        :label="codeForm.productId ? 'رفع ملف أكواد (txt أو csv) — أو الصق في الخانة التالية' : 'اختر العلامة والبطاقة أولًا'">
        <template #prepend><q-icon name="upload_file" /></template>
      </q-file>
      <q-input v-model="codeForm.lines" type="textarea" outlined rows="5" :disable="!codeForm.productId" input-class="ltr text-left"
        :label="codeForm.productId ? 'الأكواد (كود في كل سطر، أو: الكود ; الرقم التسلسلي)' : 'اختر العلامة والبطاقة أولًا'" />
      <div v-if="nameMismatch" class="small q-pa-sm rounded-borders warn-loss text-weight-bold">
        تنبيه: اسم الملف لا يطابق البطاقة المختارة ({{ pickedProduct.name }}). تأكد من البطاقة قبل الإضافة.
      </div>
      <!-- What was read: one card per line (code, then optional serial) -->
      <div v-if="parsed.cards" class="small q-pa-sm rounded-borders" :class="parsed.mismatch ? 'warn-loss' : 'preview-ok'">
        <b>عدد البطاقات: {{ parsed.cards }}</b>
        <span v-if="parsed.withSerial"> · منها {{ parsed.withSerial }} برقم تسلسلي</span>
        <span v-if="parsed.dups"> · {{ parsed.dups }} مكررة في الملف (تُضاف مرة واحدة)</span>
        <div v-if="parsed.expected != null">اسم الملف يذكر <b>{{ parsed.expected }}</b> بطاقة —
          {{ parsed.mismatch ? 'العدد مختلف! راجع الملف قبل الإضافة.' : 'العدد مطابق ✓' }}</div>
        <div class="ltr text-left muted">أول بطاقة: {{ parsed.first.code }}<span v-if="parsed.first.serial"> | SN {{ parsed.first.serial }}</span></div>
      </div>
      <div class="row q-gutter-sm items-start">
        <q-select v-model="codeForm.supplierId" class="col" :options="supplierOptions" emit-value map-options dense outlined label="المصدر (المنصة / المورد)" />
        <q-btn outline color="primary" label="+ منصة" @click="addSupplierOpen = true" />
      </div>
      <q-input v-model.number="codeForm.cost" dense outlined type="number" inputmode="numeric" label="سعر الشراء للبطاقة الواحدة (دج) *"
        hint="إجباري — منه يُحسب ربحك وسعر الزبائن" />
      <!-- Read-only check before adding: selling price stays on the card, only the cost comes with the batch -->
      <div v-if="preview" class="small q-pa-sm rounded-borders column q-gutter-xs" :class="preview.loss ? 'warn-loss' : 'preview-ok'">
        <div>سعر البيع: <b>{{ money(preview.base) }}</b> · سعر الشراء: <b>{{ money(preview.cost) }}</b> ·
          الربح الكلي: <b>{{ money(preview.margin) }}</b> ({{ preview.marginPct }}%)</div>
        <div v-if="preview.pay != null">يدفع الزبون (السعر الافتراضي): <b>{{ money(preview.pay) }}</b> · ربح الزبون: <b>{{ money(preview.base - preview.pay) }}</b> · ربحك: <b>{{ money(preview.mine) }}</b></div>
        <div v-if="preview.cost >= preview.base" class="text-weight-bold">تنبيه: سعر الشراء يساوي سعر البيع أو أكبر منه.</div>
        <div v-else-if="preview.mine < 0" class="text-weight-bold">تنبيه: الزبون يدفع أقل من سعر الشراء — خسارة {{ money(-preview.mine) }} في كل بطاقة.</div>
        <q-btn flat dense no-caps color="primary" icon="edit" label="تعديل سعر البيع" class="self-start" @click="openBase" />
      </div>
      <q-btn type="submit" unelevated no-caps color="primary" size="lg" :label="addLabel" :loading="busy"
        :disable="!codeForm.productId || !codeForm.lines.trim() || !(codeForm.cost > 0)" />
    </q-form>
    </div>

    <div v-show="tab === 'cards'" class="tab-pane">
    <div class="row justify-between items-center">
      <div class="section-title">البطاقات والمخزون</div>
      <q-btn dense unelevated color="primary" icon="add" label="بطاقة جديدة" @click="openProduct(null)" />
    </div>
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" />
    <!-- One small card per product (fits a phone screen); tap the name to edit -->
    <div v-for="p in shownStock" :key="p.product_id" class="card column q-gutter-xs" :class="{ 'out-of-stock': !p.active }">
      <div class="row items-center justify-between no-wrap q-gutter-x-sm">
        <a href="#" class="text-primary text-weight-medium" :style="p.active ? '' : 'text-decoration:line-through;color:#6B7280'" @click.prevent="openProduct(p)">{{ p.name }}</a>
        <span class="text-weight-bold no-wrap">{{ money(p.base_price) }}</span>
      </div>
      <div class="row q-gutter-md small">
        <span class="muted">{{ p.brand }}</span>
        <span>متوفر <b :class="p.available > 0 ? 'amount-pos' : 'amount-neg'">{{ p.available }}</b></span>
        <span>مباع {{ p.sold }}</span>
        <span v-if="p.voided > 0">ملغى {{ p.voided }}</span>
        <span v-if="!p.active" class="text-warning text-weight-bold">موقوفة</span>
      </div>
      <div class="row q-gutter-xs">
        <q-btn v-if="p.active" dense unelevated size="sm" color="primary" label="+ أكواد" @click="addCodesFor(p)" />
        <q-btn dense outline size="sm" :color="p.active ? 'warning' : 'positive'" :label="p.active ? 'إيقاف' : 'تفعيل'" @click="toggleProduct(p)" />
      </div>
    </div>
    <div v-if="!shownStock.length" class="text-center muted q-pa-md">{{ stock.length ? 'لا توجد بطاقات في هذا التصنيف' : 'لا توجد بطاقات بعد. أضف أول بطاقة.' }}</div>

    </div>

    <div v-show="tab === 'batches'" class="tab-pane">
    <!-- Filters: brand → card, supplier, «فيها متوفر» (on by default) -->
    <div class="card column q-gutter-xs">
      <div class="row q-gutter-xs">
        <button v-for="b in batchBrands" :key="b.name" type="button" class="brand-pick" :class="{ on: bf.brand === b.name }"
          :aria-pressed="bf.brand === b.name" @click="bf.brand = bf.brand === b.name ? null : b.name; bf.product = null">
          <img v-if="b.image" :src="b.image" :alt="b.name">
          <span v-else>{{ b.name }}</span>
        </button>
      </div>
      <div v-if="bf.brand && batchProducts.length > 1" class="row q-gutter-xs">
        <q-btn v-for="p in batchProducts" :key="p.id" dense rounded no-caps size="13px" class="q-px-sm" :ripple="false"
          :unelevated="bf.product === p.id" :outline="bf.product !== p.id" :color="bf.product === p.id ? 'indigo-7' : 'grey-7'"
          :label="p.label" @click="bf.product = bf.product === p.id ? null : p.id" />
      </div>
      <div v-if="batchSuppliers.length > 1" class="row q-gutter-xs">
        <q-btn v-for="sp in ['all', ...batchSuppliers]" :key="sp" dense rounded no-caps size="13px" class="q-px-sm" :ripple="false"
          :unelevated="bf.supplier === sp" :outline="bf.supplier !== sp" :color="bf.supplier === sp ? 'indigo-7' : 'grey-7'"
          :label="sp === 'all' ? 'كل المصادر' : sp" @click="bf.supplier = sp" />
      </div>
      <q-btn rounded no-caps dense class="self-start q-px-sm" :unelevated="bf.availOnly" :outline="!bf.availOnly" color="positive"
        :label="bf.availOnly ? '✓ فيها متوفر فقط' : 'فيها متوفر فقط'" :aria-pressed="bf.availOnly" @click="bf.availOnly = !bf.availOnly" />
    </div>
    <!-- One small card per batch (fits a phone screen) -->
    <div v-for="b in shownBatches" :key="b.batch_id" class="card column q-gutter-xs">
      <div class="row items-center justify-between no-wrap">
        <span class="text-weight-bold">{{ b.product_name }}</span>
        <span class="small muted">#{{ b.batch_id }}</span>
      </div>
      <div class="small muted">{{ b.supplier }} · {{ dateTime(b.created_at) }} · شراء {{ money(b.cost) }}</div>
      <div class="row q-gutter-md small">
        <span>متوفر <b class="amount-pos">{{ b.available }}</b></span>
        <span :class="b.frozen > 0 ? 'text-warning text-weight-bold' : ''">مجمّد {{ b.frozen }}</span>
        <span>مباع {{ b.sold }}</span>
        <span>ملغى {{ b.voided }}</span>
      </div>
      <div v-if="b.available + b.frozen > 0" class="row q-gutter-xs">
        <q-btn v-if="b.available > 0" dense outline size="sm" color="warning" label="تجميد" @click="freezeBatch(b, true)" />
        <q-btn v-if="b.frozen > 0" dense outline size="sm" color="positive" label="فك التجميد" @click="freezeBatch(b, false)" />
        <q-btn dense outline size="sm" color="negative" label="إلغاء غير المباع" @click="voidBatch(b)" />
      </div>
    </div>
    <div v-if="!shownBatches.length" class="text-center muted q-pa-md">
      {{ batchList.length ? 'لا توجد دفعات مطابقة' + (bf.availOnly ? ' فيها متوفر — اضغط «فيها متوفر فقط» لعرض الكل' : '') : 'لا توجد دفعات بعد.' }}
    </div>
    </div>

    <q-dialog v-model="productOpen">
      <q-card style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">{{ productForm.id ? 'تعديل بطاقة' : 'بطاقة جديدة' }}</div>
          <q-select v-model="productForm.brandId" :options="brandOptions" emit-value map-options dense outlined label="العلامة" />
          <q-input v-model="productForm.name" dense outlined label="الاسم (مثال: Mobilis 1000)" />
          <!-- Three linked fields: type any two, the third is computed (all % are of the selling price) -->
          <div class="small muted">اكتب أي خانتين وتُحسب الثالثة. مثال: شراء 910 وربح 9% ← سعر البيع 1000.</div>
          <div class="grid-3">
            <q-input :model-value="productForm.basePrice" dense outlined type="number" stack-label label="سعر البيع" suffix="دج"
              @update:model-value="(v) => editPrice('basePrice', v)" />
            <q-input :model-value="productForm.usualCost" dense outlined type="number" stack-label label="سعر الشراء" suffix="دج"
              @update:model-value="(v) => editPrice('usualCost', v)" />
            <q-input :model-value="productForm.margin" dense outlined type="number" stack-label label="الربح الكلي" suffix="%"
              @update:model-value="(v) => editPrice('margin', v)" />
          </div>
          <div v-if="productForm.basePrice > 0 && productForm.usualCost > 0" class="small" style="color:#4338CA">
            الربح الكلي {{ money(productForm.basePrice - productForm.usualCost) }} = {{ productForm.margin }}% من سعر البيع (يُقسم بينك وبين الزبون في «الأسعار»)
          </div>
          <div class="small muted">سعر الشراء اختياري: يُملأ تلقائيًا عند إضافة الأكواد، ويُحسب منه الربح قبل وصولها.</div>
          <q-input v-model.number="productForm.sort" dense outlined type="number" label="الترتيب (اختياري)" />
          <ImageField v-if="productForm.id" :src="productForm.image" kind="product" :id="productForm.id" label="صورة البطاقة (اختيارية)"
            @saved="(url) => { productForm.image = url; load() }" />
          <div class="small muted">{{ productForm.id ? 'بدون صورة يظهر شعار العلامة وعليه السعر.' : 'احفظ البطاقة أولًا ثم أضف صورتها.' }}</div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="إلغاء" v-close-popup />
          <q-btn unelevated color="primary" label="حفظ" :loading="busy"
            :disable="!productForm.brandId || !productForm.name || !(productForm.basePrice > 0)" @click="saveProduct" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog v-model="addSupplierOpen">
      <q-card style="width:100%;max-width:420px">
        <q-card-section><q-input v-model="newSupplier" dense outlined autofocus label="اسم المنصة أو المورد الجديد" /></q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="إلغاء" v-close-popup />
          <q-btn unelevated color="primary" label="حفظ" :disable="!newSupplier.trim()" @click="addSupplier" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Dialog, LocalStorage, Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { dateTime, money } from 'src/api/format'
import CatalogFilter from 'components/CatalogFilter.vue'
import ImageField from 'components/ImageField.vue'

const { busy, run } = useRun()

// --- tabs (remembered on this device)
const TABS = [{ id: 'codes', label: 'إضافة أكواد' }, { id: 'cards', label: 'البطاقات' }, { id: 'batches', label: 'الدفعات' }, { id: 'settings', label: 'إعدادات' }]
const TAB_KEY = 'cs_stock_tab'
const readTab = () => { try { const t = LocalStorage.getItem(TAB_KEY); return TABS.some((x) => x.id === t) ? t : 'codes' } catch { return 'codes' } }
const tab = ref(readTab())
watch(tab, (t) => {
  try { LocalStorage.set(TAB_KEY, t) } catch { /* storage blocked: first tab next time */ }
  window.scrollTo({ top: 0 })
})
// The tabs stick right under the fixed header, whatever its height
const headerHeight = ref(0)
const measureHeader = () => { headerHeight.value = document.querySelector('.q-header')?.offsetHeight || 0 }
onMounted(() => { measureHeader(); window.addEventListener('resize', measureHeader) })
onBeforeUnmount(() => window.removeEventListener('resize', measureHeader))
const stock = ref([])
const brands = ref([])
const suppliers = ref([])
const announcement = ref('')
const usualCost = ref({})   // product_id → usual purchase cost
const defaultRule = ref({})  // product_id → default customer price rule { mode, value }

// What this batch means before adding it (all % of the selling price)
const preview = computed(() => {
  const p = stock.value.find((x) => x.product_id === codeForm.value.productId)
  const cost = Number(codeForm.value.cost)
  if (!p || !(cost > 0)) return null
  const base = Number(p.base_price)
  const r = defaultRule.value[p.product_id] || { mode: 'fixed', value: base }
  const pay = r.mode === 'fixed' ? Math.round(r.value) : r.mode === 'amount' ? cost + Math.round(r.value)
    : r.mode === 'share' ? cost + Math.max(base - cost, 0) - Math.round(Math.max(base - cost, 0) * r.value / 100) : cost + Math.round(base * r.value / 100)
  return { base, cost, margin: base - cost, marginPct: Math.round((base - cost) / base * 10000) / 100, pay, mine: pay - cost, loss: cost >= base || pay < cost }
})

// «تعديل سعر البيع»: changes the card's selling price for everyone (e.g. games when the dollar rate moves)
function openBase () {
  const p = stock.value.find((x) => x.product_id === codeForm.value.productId)
  if (!p) return
  Dialog.create({
    title: 'تعديل سعر البيع', message: `${p.name}: السعر الجديد يظهر في المتجر لكل الزبائن.`,
    prompt: { model: String(p.base_price), type: 'number' }, cancel: 'إلغاء', ok: 'حفظ'
  }).onOk(async (v) => {
    const price = Number(v)
    if (!(price > 0)) return
    const ok = await run(() => api.saveProduct({ id: p.product_id, basePrice: price }).then(() => true), { success: 'حُفظ سعر البيع.' })
    if (ok) load()
  })
}

const cat = ref('all')
const brand = ref('all')
const inCat = (p) => cat.value === 'all' || p.category === cat.value
const brandList = computed(() => [...new Set(stock.value.filter(inCat).map((p) => p.brand))])
const shownStock = computed(() => stock.value.filter((p) => inCat(p) && (brand.value === 'all' || p.brand === brand.value)))

// Card picker for adding codes: brand first, then that brand's active cards
const pickBrand = ref(null)
const activeStock = computed(() => stock.value.filter((p) => p.active))
const pickBrands = computed(() => {
  const seen = new Map()
  for (const p of activeStock.value) if (!seen.has(p.brand)) seen.set(p.brand, { name: p.brand, image: p.brand_image })
  return [...seen.values()]
})
const pickProducts = computed(() => activeStock.value.filter((p) => p.brand === pickBrand.value))
const pickedProduct = computed(() => stock.value.find((p) => p.product_id === codeForm.value.productId) || null)
// «Idoom 4G 1500 · 150GO / شهر» → «1500 · 150GO / شهر» (the brand is already chosen)
function shortName (p) {
  const n = p.name.trim()
  return n.toLowerCase().startsWith(p.brand.toLowerCase()) && n.length > p.brand.length ? n.slice(p.brand.length).trim() : n
}
// Choosing another card while codes are loaded asks first, then clears them
function choose (brandName, productId) {
  const apply = () => { pickBrand.value = brandName; codeForm.value.productId = productId }
  if (brandName === pickBrand.value && (productId == null || productId === codeForm.value.productId)) return
  if (!codeForm.value.lines.trim() || !pickedProduct.value) return apply()
  Dialog.create({
    title: 'تغيير البطاقة',
    message: `توجد ${parsed.value.cards} كود لـ «${pickedProduct.value.name}». تغيير البطاقة يمسحها. متابعة؟`,
    cancel: 'رجوع', ok: { label: 'مسح وتغيير', color: 'negative' }
  }).onOk(() => {
    codeForm.value.lines = ''
    file.value = null
    apply()
  })
}
// «+ أكواد» in the cards table: same form, card already chosen
const codesFormEl = ref(null)
function addCodesFor (p) {
  tab.value = 'codes'
  choose(p.brand, p.product_id)
  codesFormEl.value?.$el.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
const supplierOptions = computed(() => suppliers.value.map((s) => ({ value: s.supplier_id, label: s.name })))
const brandOptions = computed(() => brands.value.map((b) => ({ value: b.brand_id, label: b.name })))

async function load () {
  const [s, b, sup, costs, prices] = await Promise.all([run(() => api.stock()), run(() => api.brands()), run(() => api.suppliers()), run(() => api.productCosts()), run(() => api.priceList(null))])
  if (prices) defaultRule.value = Object.fromEntries(prices.filter((r) => r.customer_id == null).map((r) => [r.product_id, { mode: r.mode, value: Number(r.value) }]))
  if (s) stock.value = s
  if (costs) usualCost.value = Object.fromEntries(costs.filter((c) => c.default_cost != null).map((c) => [c.product_id, Number(c.default_cost)]))
  if (b) brands.value = b
  if (sup) {
    suppliers.value = sup
    if (!codeForm.value.supplierId) codeForm.value.supplierId = sup.find((x) => x.is_default)?.supplier_id || null
  }
}

async function loadAnnouncement () {
  const text = await run(() => api.getAnnouncement())
  if (text != null) announcement.value = text
}

async function saveAnnouncement () {
  await run(() => api.setAnnouncement(announcement.value).then(() => true), { success: 'حُفظ الإعلان.' })
}

// --- codes
const codeForm = ref({ productId: null, supplierId: null, cost: null, lines: '' })
const file = ref(null)
// Picking a card fills the purchase cost with its usual cost (still editable)
watch(() => codeForm.value.productId, (id) => {
  if (id != null && usualCost.value[id] != null) codeForm.value.cost = usualCost.value[id]
})
// Same reading rule as the database: one card per line; first ; , or | separates code and serial
const fileName = ref('')
const parsed = computed(() => {
  const rows = codeForm.value.lines.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map((l) => {
    const sep = (l.match(/[;,|]/) || [';'])[0]
    const i = l.indexOf(sep)
    return i < 0 ? { code: l, serial: '' } : { code: l.slice(0, i).trim(), serial: l.slice(i + 1).trim() }
  }).filter((r) => r.code)
  const unique = new Set(rows.map((r) => r.code)).size
  // e.g. MOBILIS_1000_DA(50)_…txt or «Forfait 100 - 3 cards - 2026-10-23.txt»
  const m = fileName.value.match(/\((\d+)\)/) || fileName.value.match(/(\d+)\s*cards?\b/i)
  const expected = m ? Number(m[1]) : null
  return {
    cards: unique, dups: rows.length - unique, withSerial: rows.filter((r) => r.serial).length,
    first: rows[0] || {}, expected, mismatch: expected != null && expected !== unique
  }
})

// Card amounts named in the file (date, count and long ids left out) must appear in the chosen card's name
const nameMismatch = computed(() => {
  if (!fileName.value || !pickedProduct.value) return false
  const nums = (t) => t.match(/\d+/g) || []
  const inFile = nums(fileName.value.replace(/\d{4}-\d{2}-\d{2}/g, '').replace(/\(\d+\)|\d+\s*cards?\b/gi, '')).filter((n) => n.length <= 5)
  if (!inFile.length) return false
  const inCard = new Set(nums(pickedProduct.value.name).map(Number))
  return !inFile.some((n) => inCard.has(Number(n)))
})
const addLabel = computed(() => (pickedProduct.value && parsed.value.cards
  ? `إضافة ${parsed.value.cards} كود إلى ${pickedProduct.value.name}` : 'إضافة للمخزن'))

watch(file, async (f) => {
  fileName.value = f ? f.name : ''
  if (!f) return
  const text = await f.text()
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
  codeForm.value.lines = lines.join('\n')
  Notify.create({ type: 'info', message: `قُرئ الملف: ${parsed.value.cards} بطاقة. راجع العدد ثم اضغط «إضافة للمخزن».` })
})

async function addCodes () {
  const res = await run(() => api.addCodes(codeForm.value.productId, codeForm.value.supplierId, codeForm.value.cost, codeForm.value.lines),
    { success: (r) => `أضيف ${r.added} كود${r.duplicates ? `، ورُفض ${r.duplicates} مكرر` : ''}.` })
  if (!res) return
  codeForm.value.lines = ''
  file.value = null
  load()
}

// --- suppliers
const addSupplierOpen = ref(false)
const newSupplier = ref('')
async function addSupplier () {
  const id = await run(() => api.addSupplier(newSupplier.value), { success: 'أضيفت المنصة واختيرت مصدرًا.' })
  if (!id) return
  addSupplierOpen.value = false
  newSupplier.value = ''
  await load()
  codeForm.value.supplierId = id
}

// --- products
const productOpen = ref(false)
const productForm = ref({})
// Linked price fields: the two most recently typed stay, the oldest one is computed.
// cost = selling × (1 − margin%)  ⇔  selling = cost ÷ (1 − margin%)
let priceOrder = ['basePrice', 'usualCost', 'margin']
const num = (v) => (v === '' || v == null ? null : Number(v))
function recompute () {
  const f = productForm.value
  const target = priceOrder[2]
  if (target === 'margin') {
    f.margin = f.basePrice > 0 && f.usualCost > 0 ? Math.round((f.basePrice - f.usualCost) / f.basePrice * 10000) / 100 : null
  } else if (target === 'basePrice') {
    f.basePrice = f.usualCost > 0 && f.margin != null && f.margin < 100 ? Math.round(f.usualCost / (1 - f.margin / 100)) : f.basePrice
  } else {
    f.usualCost = f.basePrice > 0 && f.margin != null && f.margin < 100 ? Math.round(f.basePrice * (1 - f.margin / 100)) : f.usualCost
  }
}
function editPrice (key, v) {
  productForm.value[key] = num(v)
  priceOrder = [key, ...priceOrder.filter((k) => k !== key)]
  recompute()
}
function openProduct (p) {
  productForm.value = p
    ? { id: p.product_id, brandId: p.brand_id, name: p.name, basePrice: Number(p.base_price), sort: p.sort, image: p.image, usualCost: usualCost.value[p.product_id] ?? null, margin: null }
    : { id: null, brandId: null, name: '', basePrice: null, sort: 0, usualCost: null, margin: null }
  priceOrder = ['basePrice', 'usualCost', 'margin']
  recompute()
  productOpen.value = true
}
async function saveProduct () {
  const f = productForm.value
  const id = await run(async () => {
    const pid = await api.saveProduct(f)
    if ((f.usualCost || null) !== (usualCost.value[f.id] ?? null)) await api.setDefaultCost(pid, f.usualCost || null)
    return pid
  }, { success: 'حُفظت البطاقة.' })
  if (!id) return
  productOpen.value = false
  load()
}
async function toggleProduct (p) {
  const id = await run(() => api.saveProduct({ id: p.product_id, active: !p.active }),
    { success: p.active ? `أُوقفت «${p.name}» ولن تظهر للزبائن.` : `فُعّلت «${p.name}» وعادت للمتجر.` })
  if (id) load()
}

// --- batches
const batchList = ref([])
// All batches (the server returns at most 100 per call), filtered on the phone
async function loadBatches () {
  const rows = await run(async () => {
    const all = []
    for (let offset = 0; offset < 1000; offset += 100) {
      const page = await api.batches(null, 100, offset)
      all.push(...page)
      if (page.length < 100) break
    }
    return all
  })
  if (rows) batchList.value = rows.map((b) => ({ ...b, available: Number(b.available), frozen: Number(b.frozen), sold: Number(b.sold), voided: Number(b.voided) }))
}
async function reloadAll () { await Promise.all([load(), loadBatches()]) }

const bf = ref({ brand: null, product: null, supplier: 'all', availOnly: true })
const brandImage = computed(() => Object.fromEntries(stock.value.map((p) => [p.brand, p.brand_image])))
const batchBrands = computed(() => [...new Set(batchList.value.map((b) => b.brand))].map((name) => ({ name, image: brandImage.value[name] })))
const batchProducts = computed(() => {
  const seen = new Map()
  for (const b of batchList.value) if (b.brand === bf.value.brand && !seen.has(b.product_id)) seen.set(b.product_id, { id: b.product_id, label: shortName({ name: b.product_name, brand: b.brand }) })
  return [...seen.values()]
})
const batchSuppliers = computed(() => [...new Set(batchList.value.map((b) => b.supplier))])
const shownBatches = computed(() => batchList.value.filter((b) =>
  (!bf.value.brand || b.brand === bf.value.brand) &&
  (!bf.value.product || b.product_id === bf.value.product) &&
  (bf.value.supplier === 'all' || b.supplier === bf.value.supplier) &&
  (!bf.value.availOnly || b.available + b.frozen > 0)))

// Only codes still in stock change; a code sold meanwhile is skipped by the database.
async function stockCodeIds (b, test) {
  const codes = await api.batchCodes(b.batch_id)
  return codes.filter((c) => c.status === 'available' && test(c)).map((c) => c.code_id)
}

function freezeBatch (b, frozen) {
  const count = frozen ? b.available : b.frozen
  Dialog.create({
    title: frozen ? 'تجميد الدفعة' : 'فك تجميد الدفعة',
    message: frozen
      ? `${b.product_name} #${b.batch_id}: ${count} كود لن يُباع حتى تفك التجميد. الأكواد المباعة لا تتغير.`
      : `${b.product_name} #${b.batch_id}: ${count} كود يعود للبيع.`,
    cancel: 'إلغاء', ok: frozen ? 'تجميد' : 'فك التجميد'
  }).onOk(async () => {
    const n = await run(async () => api.freezeCodes(await stockCodeIds(b, (c) => c.frozen !== frozen), frozen),
      { success: (n) => frozen ? `جُمّد ${n} كود.` : `عاد ${n} كود للبيع.` })
    if (n !== undefined) reloadAll()
  })
}

function voidBatch (b) {
  Dialog.create({
    title: 'إلغاء الأكواد غير المباعة',
    message: `${b.product_name} #${b.batch_id}: ${b.available + b.frozen} كود يخرج من المخزن نهائيًا ويبقى في السجل. لا رجعة فيه. اكتب السبب:`,
    prompt: { model: '', type: 'text', isValid: (v) => v.trim().length > 0 },
    cancel: 'رجوع', ok: { label: 'إلغاء نهائي', color: 'negative' }
  }).onOk(async (reason) => {
    const n = await run(async () => api.voidCodes(await stockCodeIds(b, () => true), reason.trim()),
      { success: (n) => `أُلغي ${n} كود.` })
    if (n !== undefined) reloadAll()
  })
}

onMounted(() => { load(); loadBatches(); loadAnnouncement() })
</script>

<style scoped>
.warn-loss { background: #FEF2F2; color: #B91C1C; border: 1px solid #FCA5A5; }
.preview-ok { background: #F0F9FF; color: #075985; border: 1px solid #BAE6FD; }
/* sticky: stays visible under the header while the tab scrolls */
.stock-tabs { position: sticky; z-index: 5; background: #F4F5F8; margin: -14px -16px 0; padding: 10px 16px; }
.tab-pane { display: flex; flex-direction: column; gap: 12px; }
.brand-pick { width: 64px; height: 48px; padding: 3px; border-radius: 8px; border: 2px solid #E5E7EB; background: #fff; cursor: pointer;
  display: flex; align-items: center; justify-content: center; font: inherit; font-size: 11px; line-height: 1.1; }
.brand-pick img { max-width: 100%; max-height: 100%; object-fit: contain; }
.brand-pick.on { border-color: #4338CA; box-shadow: 0 0 0 2px #C7CAF5; }
</style>
