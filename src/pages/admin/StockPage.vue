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
      <div class="row q-gutter-sm items-start">
        <q-select v-model="codeForm.supplierId" class="col" :options="supplierOptions" emit-value map-options dense outlined label="المصدر (المنصة / المورد)" />
        <q-btn outline color="primary" label="+ منصة" @click="addSupplierOpen = true" />
      </div>
      <q-input v-model.number="codeForm.cost" dense outlined type="number" label="تكلفة البطاقة (دج) — اختياري" hint="اتركها فارغة إن لم تتبعها" />
      <q-btn type="submit" unelevated color="primary" size="lg" label="إضافة للمخزن" :loading="busy"
        :disable="!codeForm.productId || !codeForm.lines.trim()" />
    </q-form>

    <div class="row justify-between items-center">
      <div class="section-title">البطاقات والمخزون</div>
      <q-btn dense unelevated color="primary" icon="add" label="بطاقة جديدة" @click="openProduct(null)" />
    </div>
    <div class="card q-pa-none" style="overflow-x:auto">
      <q-markup-table flat dense separator="horizontal">
        <thead>
          <tr><th class="text-right">البطاقة</th><th>السعر</th><th>متوفر</th><th>مباع</th><th>ملغى</th><th>الحالة</th></tr>
        </thead>
        <tbody>
          <tr v-for="p in stock" :key="p.product_id">
            <td class="text-right">
              <a href="#" class="text-primary" :style="p.active ? '' : 'text-decoration:line-through;color:#6B7280'" @click.prevent="openProduct(p)">{{ p.name }}</a>
              <div class="small muted ltr text-right">{{ p.brand }}</div>
            </td>
            <td class="text-center">{{ money(p.base_price) }}</td>
            <td class="text-center text-weight-bold" :class="p.available > 0 ? 'amount-pos' : 'amount-neg'">{{ p.available }}</td>
            <td class="text-center">{{ p.sold }}</td>
            <td class="text-center">{{ p.voided }}</td>
            <td class="text-center">
              <q-btn dense outline size="sm" :color="p.active ? 'warning' : 'positive'" :label="p.active ? 'إيقاف' : 'تفعيل'" @click="toggleProduct(p)" />
            </td>
          </tr>
          <tr v-if="!stock.length"><td colspan="6" class="text-center muted q-pa-md">لا توجد بطاقات بعد. أضف أول بطاقة.</td></tr>
        </tbody>
      </q-markup-table>
    </div>

    <q-dialog v-model="productOpen">
      <q-card style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">{{ productForm.id ? 'تعديل بطاقة' : 'بطاقة جديدة' }}</div>
          <q-select v-model="productForm.brandId" :options="brandOptions" emit-value map-options dense outlined label="العلامة" />
          <q-input v-model="productForm.name" dense outlined label="الاسم (مثال: Mobilis 1000)" />
          <q-input v-model.number="productForm.basePrice" dense outlined type="number" label="سعر البيع الافتراضي (دج)" />
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
import { Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { money } from 'src/api/format'

const { busy, run } = useRun()
const stock = ref([])
const brands = ref([])
const suppliers = ref([])
const announcement = ref('')

const productOptions = computed(() => stock.value.map((p) => ({ value: p.product_id, label: `${p.name} (متوفر ${p.available})` })))
const supplierOptions = computed(() => suppliers.value.map((s) => ({ value: s.supplier_id, label: s.name })))
const brandOptions = computed(() => brands.value.map((b) => ({ value: b.brand_id, label: b.name })))

async function load () {
  const [s, b, sup] = await Promise.all([run(() => api.stock()), run(() => api.brands()), run(() => api.suppliers())])
  if (s) stock.value = s
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
watch(file, async (f) => {
  if (!f) return
  const text = await f.text()
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
  codeForm.value.lines = lines.join('\n')
  Notify.create({ type: 'info', message: `قُرئ الملف: ${lines.length} سطر. راجعها ثم اضغط «إضافة للمخزن».` })
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
function openProduct (p) {
  productForm.value = p
    ? { id: p.product_id, brandId: p.brand_id, name: p.name, basePrice: Number(p.base_price), sort: p.sort }
    : { id: null, brandId: null, name: '', basePrice: null, sort: 0 }
  productOpen.value = true
}
async function saveProduct () {
  const id = await run(() => api.saveProduct(productForm.value), { success: 'حُفظت البطاقة.' })
  if (!id) return
  productOpen.value = false
  load()
}
async function toggleProduct (p) {
  const id = await run(() => api.saveProduct({ id: p.product_id, active: !p.active }),
    { success: p.active ? `أُوقفت «${p.name}» ولن تظهر للزبائن.` : `فُعّلت «${p.name}» وعادت للمتجر.` })
  if (id) load()
}

onMounted(() => { load(); loadAnnouncement() })
</script>
