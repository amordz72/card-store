<template>
  <q-page class="page">
    <div class="card column q-gutter-sm">
      <q-input v-model="announcement" type="textarea" autogrow dense outlined label="إعلان الصفحة الرئيسية للزبائن (اتركه فارغًا لإخفائه)" />
      <q-btn outline color="primary" label="حفظ الإعلان" class="self-start" @click="saveAnnouncement" />
    </div>

    <q-form class="card column q-gutter-sm" @submit.prevent="addCodes">
      <div class="text-weight-bold">إضافة أكواد للمخزن</div>
      <q-select v-model="codeForm.productId" :options="productOptions" emit-value map-options dense outlined label="البطاقة" />
      <q-file v-model="file" dense outlined accept=".txt,.csv,text/plain,text/csv" label="رفع ملف أكواد (txt أو csv) — أو الصق في الخانة التالية" clearable>
        <template #prepend><q-icon name="upload_file" /></template>
      </q-file>
      <q-input v-model="codeForm.lines" type="textarea" outlined rows="5" label="الأكواد (كود في كل سطر، أو: الكود ; الرقم التسلسلي)" input-class="ltr text-left" />
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
      <q-btn type="submit" unelevated color="primary" size="lg" label="إضافة للمخزن" :loading="busy"
        :disable="!codeForm.productId || !codeForm.lines.trim() || !(codeForm.cost > 0)" />
    </q-form>

    <div class="row justify-between items-center">
      <div class="section-title">البطاقات والمخزون</div>
      <q-btn dense unelevated color="primary" icon="add" label="بطاقة جديدة" @click="openProduct(null)" />
    </div>
    <CatalogFilter v-model:cat="cat" v-model:brand="brand" :brands="brandList" />
    <div class="card q-pa-none" style="overflow-x:auto">
      <q-markup-table flat dense separator="horizontal" class="stock-table">
        <thead>
          <tr><th class="text-right">البطاقة</th><th>السعر</th><th>متوفر</th><th>مباع</th><th></th></tr>
        </thead>
        <tbody>
          <tr v-for="p in shownStock" :key="p.product_id">
            <td class="text-right">
              <a href="#" class="text-primary" :style="p.active ? '' : 'text-decoration:line-through;color:#6B7280'" @click.prevent="openProduct(p)">{{ p.name }}</a>
              <div class="small muted">{{ p.brand }}<span v-if="p.voided > 0"> · ملغى {{ p.voided }}</span></div>
            </td>
            <td class="text-center">{{ money(p.base_price) }}</td>
            <td class="text-center text-weight-bold" :class="p.available > 0 ? 'amount-pos' : 'amount-neg'">{{ p.available }}</td>
            <td class="text-center">{{ p.sold }}</td>
            <td class="text-center">
              <q-btn dense outline size="sm" :color="p.active ? 'warning' : 'positive'" :label="p.active ? 'إيقاف' : 'تفعيل'" @click="toggleProduct(p)" />
            </td>
          </tr>
          <tr v-if="!shownStock.length"><td colspan="5" class="text-center muted q-pa-md">{{ stock.length ? 'لا توجد بطاقات في هذا التصنيف' : 'لا توجد بطاقات بعد. أضف أول بطاقة.' }}</td></tr>
        </tbody>
      </q-markup-table>
    </div>

    <div class="section-title">الدفعات</div>
    <div class="card q-pa-none" style="overflow-x:auto">
      <q-markup-table flat dense separator="horizontal" class="stock-table">
        <thead>
          <tr><th class="text-right">الدفعة</th><th>متوفر</th><th>مجمّد</th><th>مباع</th><th>ملغى</th><th></th></tr>
        </thead>
        <tbody>
          <tr v-for="b in batchList" :key="b.batch_id">
            <td class="text-right">
              {{ b.product_name }}
              <div class="small muted">#{{ b.batch_id }} · {{ b.supplier }} · {{ dateTime(b.created_at) }} · شراء {{ money(b.cost) }}</div>
            </td>
            <td class="text-center text-weight-bold">{{ b.available }}</td>
            <td class="text-center" :class="b.frozen > 0 ? 'text-warning text-weight-bold' : ''">{{ b.frozen }}</td>
            <td class="text-center">{{ b.sold }}</td>
            <td class="text-center">{{ b.voided }}</td>
            <td class="text-center">
              <div class="column q-gutter-xs items-center">
                <q-btn v-if="b.available > 0" dense outline size="sm" color="warning" label="تجميد" @click="freezeBatch(b, true)" />
                <q-btn v-if="b.frozen > 0" dense outline size="sm" color="positive" label="فك التجميد" @click="freezeBatch(b, false)" />
                <q-btn v-if="b.available + b.frozen > 0" dense outline size="sm" color="negative" label="إلغاء غير المباع" @click="voidBatch(b)" />
              </div>
            </td>
          </tr>
          <tr v-if="!batchList.length"><td colspan="6" class="text-center muted q-pa-md">لا توجد دفعات بعد.</td></tr>
        </tbody>
      </q-markup-table>
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
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { dateTime, money } from 'src/api/format'
import CatalogFilter from 'components/CatalogFilter.vue'

const { busy, run } = useRun()
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

const productOptions = computed(() => stock.value.filter((p) => p.active).map((p) => ({ value: p.product_id, label: `${p.name} (متوفر ${p.available})` })))
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
  const m = fileName.value.match(/\((\d+)\)/)   // e.g. MOBILIS_1000_DA(50)_…txt
  const expected = m ? Number(m[1]) : null
  return {
    cards: unique, dups: rows.length - unique, withSerial: rows.filter((r) => r.serial).length,
    first: rows[0] || {}, expected, mismatch: expected != null && expected !== unique
  }
})

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
    ? { id: p.product_id, brandId: p.brand_id, name: p.name, basePrice: Number(p.base_price), sort: p.sort, usualCost: usualCost.value[p.product_id] ?? null, margin: null }
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
async function loadBatches () {
  const rows = await run(() => api.batches(null, 50, 0))
  if (rows) batchList.value = rows.map((b) => ({ ...b, available: Number(b.available), frozen: Number(b.frozen), sold: Number(b.sold), voided: Number(b.voided) }))
}
async function reloadAll () { await Promise.all([load(), loadBatches()]) }

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
.stock-table :deep(th), .stock-table :deep(td) { padding: 6px 4px; }
</style>
