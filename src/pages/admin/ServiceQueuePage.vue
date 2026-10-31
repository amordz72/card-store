<template>
  <!-- «الخدمات» for the owner (owner 2026-10-31, developer projects/card-store/SERVICES-2026-10-31.md):
       the orders waiting for him (he alone works them), the finished ones, and the services themselves -->
  <q-page class="page column q-gutter-sm">
    <div class="row q-gutter-xs">
      <q-btn v-for="t in TABS" :key="t.id" rounded no-caps :unelevated="tab === t.id" :outline="tab !== t.id"
        :color="tab === t.id ? 'primary' : 'grey-8'" :label="t.id === 'open' && openCount ? `${t.label} (${openCount})` : t.label"
        :aria-pressed="tab === t.id" @click="tab = t.id" />
    </div>
    <div v-if="missingSql" class="card text-negative">الخدمات تنتظر تطبيق ملف SQL الخاص بها (من «ينتظر تطبيقك»).</div>

    <!-- ===== the queue ===== -->
    <template v-if="tab !== 'services'">
      <div v-if="loaded && !orders.length" class="card muted text-center q-pa-lg">{{ tab === 'open' ? 'لا طلبات تنتظرك.' : 'لا طلبات منتهية بعد.' }}</div>
      <div v-for="o in orders" :key="o.id" class="card column q-gutter-xs">
        <div class="row items-center no-wrap">
          <div class="col text-weight-bold">{{ o.product_name }} <span class="muted">× {{ o.qty_done ?? o.qty }}</span></div>
          <q-badge :color="STATUS[o.status].color" :label="STATUS[o.status].label" />
        </div>
        <div class="small">{{ o.customer_name }} · <bdi dir="ltr">{{ o.customer_phone }}</bdi></div>
        <div class="small muted">طلب رقم {{ o.id }} · {{ when(o.created_at) }}<template v-if="o.finished_at"> · انتهى {{ when(o.finished_at) }}</template></div>
        <div v-for="f in o.fields" :key="f.key" class="small"><span class="muted">{{ f.label }}:</span> <bdi>{{ f.value }}</bdi></div>
        <div v-if="o.note" class="small"><span class="muted">ملاحظة الزبون:</span> {{ o.note }}</div>
        <div v-if="o.reply" class="small"><span class="muted">{{ o.status === 'failed' ? 'السبب' : 'ردك' }}:</span> {{ o.reply }}</div>
        <div v-for="(c, i) in o.changes.filter((x) => x.what === 'price')" :key="i" class="small text-deep-orange">
          السعر {{ when(c.at) }}: {{ money(c.old_total) }} ← {{ money(c.new_total) }} · {{ c.reason }}
        </div>
        <div class="row q-gutter-md small">
          <span>سعر الوحدة <b>{{ money(o.unit_price) }}</b></span>
          <span>{{ o.status === 'queued' || o.status === 'claimed' ? 'محجوز' : 'محسوب' }} <b>{{ money(o.total) }}</b></span>
          <span v-if="o.debt > 0" class="text-negative">منه دين {{ money(o.debt) }}</span>
          <span v-if="o.cost_total != null">التكلفة {{ money(o.cost_total) }} · الربح {{ money(o.total - o.cost_total) }}</span>
        </div>
        <div class="row q-gutter-xs">
          <q-btn v-if="o.fields.length || o.note" flat dense no-caps color="primary" icon="content_copy" label="انسخ البيانات" @click="copyData(o)" />
          <q-btn v-if="o.status === 'queued'" unelevated dense no-caps color="primary" icon="play_arrow" label="أبدأ" :loading="busy && acting === o.id"
            @click="claim(o)" />
          <q-btn v-if="o.status === 'queued' || o.status === 'claimed'" unelevated dense no-caps color="positive" icon="check" label="تم" @click="openDone(o)" />
          <q-btn v-if="o.status === 'queued' || o.status === 'claimed'" outline dense no-caps color="negative" label="لم يتم" @click="openFail(o)" />
          <q-btn v-if="o.status !== 'failed' && o.status !== 'cancelled'" flat dense no-caps color="deep-orange" icon="edit" label="غيّر السعر" @click="openPrice(o)" />
        </div>
      </div>
      <LoadMoreBar v-if="orders.length" :total="null" :shown="orders.length" :size="PAGE" :has-more="more" :loading="busy" @more="loadOrders(true)" />
    </template>

    <!-- ===== the services ===== -->
    <template v-else>
      <div class="help small muted">الخدمة بلا مخزون: يطلبها الزبون فيُحجز المبلغ، وتنفّذها أنت. المغلقة تبقى ظاهرة «مغلقة الآن».</div>
      <div v-for="s in services" :key="s.product_id" class="card column q-gutter-sm">
        <div class="row items-center no-wrap">
          <div class="col">
            <div class="text-weight-bold">{{ s.name }}</div>
            <div class="small muted">{{ s.brand }} · سعر البيع {{ money(s.base_price) }} · التكلفة المعتادة {{ money(s.default_cost) }}
              <template v-if="s.waiting"> · {{ s.waiting }} تنتظر</template><template v-if="!s.active"> · موقوفة في المخزن</template></div>
          </div>
          <q-toggle :model-value="s.open" color="positive" :label="s.open ? 'مفتوحة' : 'مغلقة'" :disable="busy" @update:model-value="(v) => save(s, { open: v })" />
        </div>
        <q-expansion-item dense class="q-pa-none" label="الخانات والتكلفة والسعر" header-class="text-primary" @show="startEdit(s)">
          <div v-if="edit[s.product_id]" class="column q-gutter-sm q-pt-sm">
            <div class="row q-gutter-sm">
              <q-input v-model.number="edit[s.product_id].price" class="col" dense outlined type="number" inputmode="numeric" label="سعر البيع" suffix="دج" />
              <q-input v-model.number="edit[s.product_id].cost" class="col" dense outlined type="number" inputmode="numeric" label="التكلفة المعتادة" suffix="دج" />
            </div>
            <ServiceFieldsEditor v-model="edit[s.product_id].fields" />
            <div class="row q-gutter-sm">
              <q-btn unelevated color="primary" label="حفظ" :loading="busy" @click="saveEdit(s)" />
              <q-btn flat color="negative" no-caps label="لم تعد خدمة" @click="unmark(s)" />
            </div>
          </div>
        </q-expansion-item>
      </div>
      <div v-if="loaded && !services.length" class="card muted text-center">لا خدمات بعد.</div>

      <q-expansion-item class="card q-pa-none" icon="add" label="خدمة جديدة" header-class="text-primary text-weight-bold" @show="loadBrands">
        <div class="column q-gutter-sm q-pa-md">
          <q-select v-model="form.brandId" dense outlined emit-value map-options :options="brandOpts" label="القسم (العلامة)" />
          <q-input v-if="form.brandId === 'new'" v-model="form.brandName" dense outlined label="اسم القسم الجديد" hint="يظهر في «منتجات أخرى»، آخر أقسام المتجر" />
          <q-input v-model="form.name" dense outlined label="اسم الخدمة (مثلًا: شراء قرص صلب، عملة لعبة)" maxlength="80" />
          <div class="row q-gutter-sm">
            <q-input v-model.number="form.price" class="col" dense outlined type="number" inputmode="numeric" label="سعر البيع للوحدة" suffix="دج" />
            <q-input v-model.number="form.cost" class="col" dense outlined type="number" inputmode="numeric" label="التكلفة المعتادة" suffix="دج" />
          </div>
          <div class="text-weight-bold small">الخانات التي يملؤها الزبون</div>
          <ServiceFieldsEditor v-model="form.fields" />
          <q-btn unelevated color="primary" label="أنشئ الخدمة" :loading="busy" :disable="!canCreate" @click="create" />
        </div>
      </q-expansion-item>

      <q-expansion-item class="card q-pa-none" icon="swap_horiz" label="اجعل منتجًا موجودًا خدمة" header-class="text-primary" @show="loadProducts">
        <div class="column q-gutter-sm q-pa-md">
          <div class="help small muted">يبقى المنتج في قسمه، وزره «اطلب» بدل «شراء»: يظهر لك هنا كخدمة، وللزبون «جاري تأكيد الطلبية».</div>
          <q-select v-model="mark.productId" dense outlined use-input input-debounce="0" emit-value map-options :options="productOpts"
            label="المنتج" @filter="filterProducts" />
          <q-input v-model.number="mark.cost" dense outlined type="number" inputmode="numeric" label="التكلفة المعتادة" suffix="دج" />
          <q-btn unelevated color="primary" label="اجعله خدمة" :loading="busy" :disable="!mark.productId || !(mark.cost > 0)" @click="markProduct" />
        </div>
      </q-expansion-item>
    </template>
    <q-inner-loading :showing="!loaded" />

    <!-- «تم»: the count sent (only that is charged), the real cost, the reply the customer reads -->
    <q-dialog v-model="doneOpen">
      <q-card v-if="sel" style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">تم: {{ sel.product_name }}</div>
          <q-input v-model.number="done.qty" dense outlined type="number" inputmode="numeric" :label="`العدد المرسَل (طلب ${sel.qty})`" />
          <q-input v-model.number="done.cost" dense outlined type="number" inputmode="numeric" label="التكلفة الحقيقية الكلية" suffix="دج" />
          <q-input v-model="done.reply" dense outlined autogrow type="textarea" label="رد للزبون (اختياري)" maxlength="1000" />
          <div class="small">يُحسب على الزبون: <b>{{ money(sel.unit_price * (done.qty || 0)) }}</b>
            <template v-if="done.qty && sel.unit_price * done.qty !== sel.total"> ({{ sel.unit_price * done.qty < sel.total ? 'يُرجع له' : 'يُخصم منه' }}
              {{ money(Math.abs(sel.total - sel.unit_price * done.qty)) }})</template></div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="رجوع" v-close-popup />
          <q-btn unelevated color="positive" label="تم" :loading="busy" :disable="!(done.qty >= 1 && done.qty <= 500)" @click="confirmDone" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog v-model="failOpen">
      <q-card v-if="sel" style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">لم يتم: {{ sel.product_name }}</div>
          <div class="small">يُرجع للزبون كل ما دُفع ({{ money(sel.total) }}).</div>
          <q-input v-model="failReason" dense outlined autogrow type="textarea" label="السبب للزبون (اختياري)" maxlength="1000" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="رجوع" v-close-popup />
          <q-btn unelevated color="negative" label="لم يتم، أرجع المبلغ" :loading="busy" @click="confirmFail" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog v-model="priceOpen">
      <q-card v-if="sel" style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">سعر الوحدة: {{ sel.product_name }}</div>
          <q-input v-model.number="price.unit" dense outlined type="number" inputmode="numeric" label="سعر الوحدة الجديد" suffix="دج" />
          <q-input v-model="price.reason" dense outlined label="السبب (يراه الزبون) *" maxlength="300" />
          <div v-if="price.unit > 0" class="small">المجموع {{ money(sel.total) }} ← <b>{{ money(price.unit * (sel.qty_done ?? sel.qty)) }}</b>.
            <template v-if="price.unit * (sel.qty_done ?? sel.qty) > sel.total">الزيادة تُخصم من رصيده، وما لا يكفيه يصير دينًا عليه (ولو تجاوز حد دينه).</template>
            <template v-else-if="price.unit * (sel.qty_done ?? sel.qty) < sel.total">الفرق يُرجع له (من دينه أولًا إن كان).</template></div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="رجوع" v-close-popup />
          <q-btn unelevated color="deep-orange" label="غيّر السعر" :loading="busy" :disable="!(price.unit > 0) || !price.reason.trim()" @click="confirmPrice" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useBell } from 'src/composables/useBell'
import { copyText } from 'src/composables/useCopy'
import { money } from 'src/api/format'
import { when } from 'src/api/when'
import * as api from 'src/api/admin'
import LoadMoreBar from 'components/LoadMoreBar.vue'
import ServiceFieldsEditor from 'components/ServiceFieldsEditor.vue'

const TABS = [{ id: 'open', label: 'تنتظرك' }, { id: 'done', label: 'انتهت' }, { id: 'services', label: 'الخدمات' }]
const STATUS = {
  queued: { label: 'جديد', color: 'orange-8' },
  claimed: { label: 'بدأته', color: 'primary' },
  done: { label: 'تم', color: 'positive' },
  failed: { label: 'لم يتم', color: 'negative' },
  cancelled: { label: 'ألغاه الزبون', color: 'grey-7' }
}
const PAGE = 30
const { busy, run } = useRun()
const { refreshBell } = useBell()
const tab = ref('open')
const loaded = ref(false)
const missingSql = ref(false)
const orders = ref([])
const more = ref(false)
const openCount = ref(0)
const services = ref([])
const acting = ref(null)

async function loadOrders (append = false) {
  try {
    const rows = await api.serviceQueue(tab.value === 'open', PAGE, append ? orders.value.length : 0)
    orders.value = append ? [...orders.value, ...rows] : rows
    more.value = rows.length === PAGE
    missingSql.value = false
  } catch (e) {
    missingSql.value = isMissing(e)
    if (!missingSql.value) await run(() => Promise.reject(e))
  }
  openCount.value = Number(await api.serviceOpenCount().catch(() => openCount.value)) || 0
  loaded.value = true
}
// Before the services SQL is applied the functions do not exist (PostgREST PGRST202): say so once, no error toast
const isMissing = (e) => e?.raw?.code === 'PGRST202' || /Could not find the function/i.test(String(e?.raw?.message || ''))
async function loadServices () {
  try {
    services.value = await api.services()
    missingSql.value = false
  } catch (e) {
    missingSql.value = isMissing(e)
    if (!missingSql.value) await run(() => Promise.reject(e))
  }
  loaded.value = true
}
const load = () => (tab.value === 'services' ? loadServices() : loadOrders())
watch(tab, () => { loaded.value = false; load() })

// Changing one order: read the queue again and the bell
async function act (o, fn, success) {
  acting.value = o.id
  const res = await run(fn, { success })
  acting.value = null
  if (res) { loadOrders(); refreshBell() }
  return res
}
const claim = (o) => act(o, () => api.serviceClaim(o.id), 'بدأت الطلب: لم يعد الزبون يستطيع إلغاءه.')
function copyData (o) {
  const lines = [o.product_name + ' × ' + o.qty, ...o.fields.map((f) => f.label + ': ' + f.value), ...(o.note ? ['ملاحظة: ' + o.note] : [])]
  copyText(lines.join('\n'))
}

const sel = ref(null)
const doneOpen = ref(false)
const done = ref({ qty: 1, cost: null, reply: '' })
function openDone (o) {
  sel.value = o
  done.value = { qty: o.qty, cost: o.unit_cost ? o.unit_cost * o.qty : null, reply: '' }
  doneOpen.value = true
}
watch(() => done.value.qty, (q) => { if (sel.value?.unit_cost && q > 0) done.value.cost = sel.value.unit_cost * q })
async function confirmDone () {
  if (await act(sel.value, () => api.serviceDone(sel.value.id, done.value.qty, done.value.cost === '' ? null : done.value.cost, done.value.reply),
    'تم: وصل الزبون «تمت الطلبية».')) doneOpen.value = false
}

const failOpen = ref(false)
const failReason = ref('')
function openFail (o) { sel.value = o; failReason.value = ''; failOpen.value = true }
async function confirmFail () {
  if (await act(sel.value, () => api.serviceFail(sel.value.id, failReason.value), 'أُرجع المبلغ كاملًا للزبون.')) failOpen.value = false
}

const priceOpen = ref(false)
const price = ref({ unit: null, reason: '' })
function openPrice (o) { sel.value = o; price.value = { unit: o.unit_price, reason: '' }; priceOpen.value = true }
async function confirmPrice () {
  if (await act(sel.value, () => api.servicePrice(sel.value.id, price.value.unit, price.value.reason.trim()), 'تغيّر السعر، ويرى الزبون السبب.')) priceOpen.value = false
}

// ----- the services -----
async function save (s, patch) {
  if (await run(() => api.serviceSave(s.product_id, patch).then(() => true))) loadServices()
}
const edit = ref({})
function startEdit (s) { edit.value[s.product_id] = { price: s.base_price, cost: s.default_cost, fields: s.fields || [] } }
async function saveEdit (s) {
  const e = edit.value[s.product_id]
  const ok = await run(async () => {
    if (e.price > 0 && e.price !== s.base_price) await api.saveProduct({ id: s.product_id, basePrice: e.price })
    await api.serviceSave(s.product_id, { fields: e.fields, defaultCost: e.cost > 0 ? e.cost : null })
    return true
  }, { success: 'حُفظت الخدمة.' })
  if (ok) loadServices()
}
async function unmark (s) {
  if (s.waiting) return run(() => Promise.reject(new Error('لها طلبات تنتظر: أنهها أولًا.')))
  if (await run(() => api.serviceSave(s.product_id, { isService: false }).then(() => true), { success: 'لم تعد خدمة: عاد منتجًا عاديًا.' })) loadServices()
}

const brands = ref([])
const brandOpts = computed(() => [
  ...brands.value.filter((b) => b.active).map((b) => ({ value: b.brand_id, label: b.name + (b.category === 'other' ? ' (منتجات أخرى)' : '') })),
  { value: 'new', label: '+ قسم جديد في «منتجات أخرى»' }])
const form = ref({ brandId: null, brandName: '', name: '', price: null, cost: null, fields: [] })
async function loadBrands () {
  const rows = await run(() => api.brands())
  if (!rows) return
  brands.value = rows
  if (!form.value.brandId) form.value.brandId = rows.find((b) => b.category === 'other' && b.active)?.brand_id || 'new'
}
const canCreate = computed(() => form.value.name.trim() && form.value.price > 0 && form.value.cost > 0 &&
  form.value.brandId && (form.value.brandId !== 'new' || form.value.brandName.trim()))
async function create () {
  const f = form.value
  const ok = await run(async () => {
    const brandId = f.brandId === 'new' ? await api.saveBrand({ name: f.brandName.trim(), category: 'other', sort: 99, active: true }) : f.brandId
    const pid = await api.saveProduct({ brandId, name: f.name.trim(), basePrice: f.price, active: true })
    await api.serviceSave(pid, { isService: true, open: true, fields: f.fields, defaultCost: f.cost })
    return true
  }, { success: 'أُنشئت الخدمة، وهي مفتوحة للزبائن.' })
  if (ok) { form.value = { brandId: null, brandName: '', name: '', price: null, cost: null, fields: [] }; loadBrands(); loadServices() }
}

const allProducts = ref([])
const productOpts = ref([])
const mark = ref({ productId: null, cost: null })
const productLabel = (p) => `${p.brand} · ${p.name}`
async function loadProducts () {
  const rows = await run(() => api.stock())
  if (!rows) return
  const svcIds = new Set(services.value.map((s) => Number(s.product_id)))
  allProducts.value = rows.filter((p) => p.active && !svcIds.has(Number(p.product_id))).map((p) => ({ value: p.product_id, label: productLabel(p) }))
  productOpts.value = allProducts.value
}
function filterProducts (q, update) {
  update(() => { const t = (q || '').trim(); productOpts.value = t ? allProducts.value.filter((o) => o.label.includes(t)) : allProducts.value })
}
async function markProduct () {
  const ok = await run(() => api.serviceSave(mark.value.productId, { isService: true, open: true, defaultCost: mark.value.cost }).then(() => true),
    { success: 'صار خدمة: زره في المتجر «اطلب».' })
  if (ok) { mark.value = { productId: null, cost: null }; loadServices(); loadProducts() }
}

// New orders arrive while the page is open: read the open queue every 20 s while it is shown
let timer = null
onMounted(() => {
  load()
  timer = setInterval(() => { if (!document.hidden && tab.value === 'open' && !doneOpen.value && !failOpen.value && !priceOpen.value) loadOrders() }, 20000)
})
onUnmounted(() => clearInterval(timer))
</script>
