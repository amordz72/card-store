<template>
  <q-page class="page">
    <!-- Review first: these hold a shop's money until the owner decides -->
    <div v-if="reviews.length" class="card column q-gutter-sm">
      <div class="row items-center">
        <div class="col section-title">تحتاج حكمك</div>
        <q-badge color="deep-orange" :label="reviews.length" />
      </div>
      <div v-for="j in reviews" :key="j.job_id" class="review column q-gutter-xs">
        <div class="text-weight-bold"><bdi dir="ltr">{{ j.phone }}</bdi> · {{ money(j.amount) }}</div>
        <div class="small muted">{{ j.customer_name }} · خُصم {{ money(j.charged) }} · {{ when(j.created_at) }}</div>
        <div class="small muted ltr text-right">{{ j.network_reply || 'لا رد مفهوم من الشبكة.' }}</div>
        <div class="grid-2">
          <q-btn unelevated no-caps color="positive" label="تم الإرسال" :loading="busy" @click="resolve(j, true)" />
          <q-btn outline no-caps color="negative" label="فشل، أرجع المبلغ" :loading="busy" @click="resolve(j, false)" />
        </div>
      </div>
    </div>

    <!-- Switches on top (owner 2026-10-29): the store's master, then Ooredoo and Djezzy for the shops -->
    <div class="card column q-gutter-xs">
      <div class="section-title">المفاتيح</div>
      <q-toggle :model-value="isOpen" color="primary" :disable="busy || core.apps === null || core.forcedOff"
        :label="isOpen ? 'فليكسي المحلات مفتوح' : 'فليكسي المحلات مقفل'" @update:model-value="setOpen" />
      <q-toggle v-for="op in OPERATORS" :key="op.key" :model-value="core[op.key] === true" color="primary"
        :disable="busy || core[op.key] === null || core.forcedOff" :class="{ 'dim': !isOpen }"
        :label="`${op.name} للمحلات`" @update:model-value="setOperator(op, $event)" />
      <div v-if="core.forcedOff" class="small text-negative">الإرسال موقوف من الخادم (طوارئ).</div>
      <div v-else-if="core.apps === null" class="small text-negative">تعذّرت قراءة مفتاح Flexy Core.</div>
      <div v-else-if="settings.open !== core.apps" class="small text-deep-orange">نصف مفتوح: المتجر {{ settings.open ? 'مفتوح' : 'مقفل' }} وFlexy Core {{ core.apps ? 'مفتوح' : 'مقفل' }}. أعد الضغط لتوحيدهما.</div>
      <div class="small muted">الرئيسي يوقف إرسال كل المحلات فورًا. مفتاح متعامل مقفل = «قريبًا» عند المحل. إرسالك أنت له مفتاحه الخاص.</div>
    </div>

    <!-- Rates, one row per service in the owner's order: the rate is kept as the default (shops enabled
         later) and «أعطِ» gives it to every enabled shop that has none for that service -->
    <div class="card column q-gutter-xs">
      <div class="section-title">النسب</div>
      <div v-for="sv in SERVICES" :key="sv.key" class="rate-row">
        <span class="text-weight-bold">{{ sv.name }}</span>
        <q-input v-model.number="defaults[sv.key]" dense outlined type="number" step="0.25" suffix="%" />
        <q-btn outline no-caps color="primary" label="أعطِ لمن بلا نسبة" :loading="busy" :disable="defaults[sv.key] == null" @click="fillRate(sv)" />
      </div>
      <div class="rate-row">
        <span class="text-weight-bold">أكبر مبلغ</span>
        <q-input v-model.number="defaults.max" dense outlined type="number" />
        <q-btn flat no-caps color="primary" label="حفظ" :loading="busy" @click="saveMax" />
      </div>
      <div class="small muted">محل له نسبة لا يتغير. النسبة المكتوبة تبقى للمحلات التي تُفعَّل لاحقًا. نسبة فارغة لمتعامل = مقفل لذلك المحل.</div>
    </div>

    <!-- «تحديد» (owner 2026-10-29): pick shops (e.g. every trader through the filter and «الكل»), then
         «نسبة…» opens the same window as one shop's, saved at once for all of them. 10 per page. -->
    <div class="card column q-gutter-sm">
      <div class="row items-center q-gutter-sm">
        <div class="col section-title">نسب المحلات</div>
        <q-btn v-if="!selecting" outline no-caps color="primary" label="تحديد" @click="selecting = true" />
        <q-btn v-else flat no-caps color="primary" label="إلغاء" @click="stopSelect" />
      </div>
      <div class="row items-center q-gutter-sm">
        <q-select v-model="roleFilter" dense outlined emit-value map-options :options="ROLE_FILTER" style="min-width: 110px" />
        <q-input v-model="search" dense outlined clearable placeholder="بحث بالاسم" class="col" />
      </div>
      <div class="shop-head small muted" :class="{ sel: selecting }">
        <q-checkbox v-if="selecting" dense :model-value="allPicked" @update:model-value="toggleAll" />
        <span>{{ selecting ? `الكل (${filtered.length})` : 'المحل' }}</span><span>موبيليس</span><span>عروض</span><span>أوريدو</span><span>جازي</span>
      </div>
      <button v-for="c in page" :key="c.customer_id" type="button" class="shop-row" :class="{ sel: selecting }" @click="selecting ? toggle(c) : openRates(c)">
        <q-checkbox v-if="selecting" dense :model-value="picked.has(c.customer_id)" @update:model-value="toggle(c)" @click.stop />
        <span class="column items-start">
          <span>{{ c.name }}</span>
          <span class="row q-gutter-xs">
            <q-badge :color="c.role === 'wholesale' ? 'info' : 'positive'" :label="ROLES[c.role]" />
            <q-badge v-if="!c.enabled" color="grey-6" label="غير مفعّل" />
          </span>
        </span>
        <span v-for="sv in SERVICES" :key="sv.key">
          <span v-if="c[sv.rate] != null" class="rate" :class="{ off: c[sv.block] }">{{ c[sv.rate] }}%</span><span v-else class="muted">—</span>
        </span>
      </button>
      <div v-if="!filtered.length" class="text-center muted q-pa-md">لا محلات</div>
      <div v-else class="row items-center justify-between q-pt-xs">
        <q-btn flat dense no-caps color="primary" label="التالي" icon-right="chevron_left" :disable="(pageNo + 1) * pageSize >= filtered.length" @click="pageNo++" />
        <span class="small muted">{{ pageNo * pageSize + 1 }}–{{ Math.min((pageNo + 1) * pageSize, filtered.length) }} من {{ filtered.length }}</span>
        <q-btn-toggle v-model="pageSize" dense no-caps unelevated toggle-color="dark" color="grey-3" text-color="dark" size="sm" :options="SIZES" />
        <q-btn flat dense no-caps color="primary" label="السابق" icon="chevron_right" :disable="pageNo === 0" @click="pageNo--" />
      </div>
    </div>
    <div v-if="selecting" class="bulk row items-center q-gutter-sm">
      <span class="text-weight-bold">{{ picked.size }} محدَّدة</span>
      <q-btn unelevated no-caps color="primary" label="نسبة…" :disable="!picked.size" class="col" @click="openRates(null)" />
      <q-btn outline no-caps color="primary" label="تفعيل" :disable="!picked.size" :loading="busy" @click="bulkEnabled(true)" />
      <q-btn outline no-caps color="primary" label="إيقاف" :disable="!picked.size" :loading="busy" @click="bulkEnabled(false)" />
    </div>

    <div class="card q-pa-none">
      <div class="section-title q-pa-sm">آخر عمليات المحلات</div>
      <div v-for="j in jobs" :key="j.job_id" class="op-row">
        <div class="row items-center no-wrap q-gutter-sm">
          <span class="col text-weight-bold"><bdi dir="ltr">{{ j.phone }}</bdi> · {{ money(j.amount) }}</span>
          <q-badge :color="STATUS[j.status]?.color || 'grey'" :label="STATUS[j.status]?.label || j.status" />
        </div>
        <div class="small muted">{{ j.customer_name }} · خُصم {{ money(j.charged) }} · {{ when(j.created_at) }}</div>
      </div>
      <div v-if="!jobs.length" class="text-center muted q-pa-lg">لا عمليات بعد</div>
    </div>

    <!-- The same window for the selection and for one shop: each change is saved at once (no save button) -->
    <q-dialog v-model="editing">
      <q-card v-if="form" style="min-width: 320px">
        <q-card-section class="text-weight-bold">{{ form.title }}</q-card-section>
        <q-card-section class="column q-gutter-xs">
          <template v-if="form.single">
            <q-toggle :model-value="form.enabled" label="تفعيل الفليكسي" :disable="busy" @update:model-value="setEnabled" />
            <q-select :model-value="form.role" dense outlined emit-value map-options label="الدور" :options="ROLE_OPTIONS" :disable="busy" @update:model-value="setRole" />
          </template>
          <div v-for="sv in SERVICES" :key="sv.key" class="svc-row">
            <span class="text-weight-bold">{{ sv.name }} <q-icon v-if="form.saved[sv.key]" name="check" color="positive" /></span>
            <q-option-group dense inline :model-value="form.block[sv.key] ? 'block' : 'allow'" :options="ALLOW" :disable="busy" @update:model-value="setBlock(sv, $event)" />
            <q-input v-model.number="form.rate[sv.key]" dense outlined type="number" step="0.25" suffix="%" :disable="busy || form.block[sv.key] === true"
              @blur="saveRate(sv)" @keyup.enter="$event.target.blur()" />
          </div>
          <div class="svc-row">
            <span class="text-weight-bold">أكبر مبلغ</span><span></span>
            <q-input v-model.number="form.max" dense outlined type="number" :disable="busy" @blur="saveMaxShop" @keyup.enter="$event.target.blur()" />
          </div>
          <div class="small muted">اكتب واخرج من الحقل: يُحفظ فورًا{{ form.single ? '' : ' عند المحدَّدين كلهم' }}. «منع» يقفل الخدمة ويحفظ النسبة جانبًا. المحل لا يرى نسبته ولا دوره.</div>
        </q-card-section>
        <q-card-actions align="left">
          <q-btn flat no-caps color="primary" label="إغلاق" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import * as api from 'src/api/admin'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import { useRun } from 'src/composables/useRun'
import { useBell } from 'src/composables/useBell'

const { busy, run } = useRun()
const { refreshBell } = useBell()
const ROLES = { trader: 'تاجر', wholesale: 'تاجر الجملة' }
const ROLE_OPTIONS = [{ label: 'تاجر', value: 'trader' }, { label: 'تاجر الجملة', value: 'wholesale' }]
const ROLE_FILTER = [{ label: 'الكل', value: null }, ...ROLE_OPTIONS]
const STATUS = {
  queued: { label: 'في الطريق', color: 'grey-7' },
  sent: { label: 'جارٍ', color: 'info' },
  success: { label: 'ناجحة', color: 'positive' },
  failed: { label: 'فاشلة · أُعيد', color: 'negative' },
  not_sent: { label: 'لم تُرسل · أُعيد', color: 'grey-7' },
  review: { label: 'مراجعة', color: 'deep-orange' }
}
const when = (t) => new Date(t).toLocaleString('ar-DZ')

const settings = reactive({ open: false })
// Shops send only when both are on: the store's switch and Flexy Core's apps switch.
const core = reactive({ apps: null, djezzy: null, ooredoo: null, forcedOff: false })
const isOpen = computed(() => settings.open && core.apps === true && !core.forcedOff)
function showCore (res) {
  if (res.status !== 200) throw new Error('تعذّر الوصول إلى مفتاح Flexy Core (' + (res.body?.error || 'FLEXY_CORE') + ').')
  core.apps = res.body.apps_send_enabled === true
  core.djezzy = res.body.apps_djezzy_send_enabled === true
  core.ooredoo = res.body.apps_ooredoo_send_enabled === true
  core.forcedOff = res.body.forced_off === true
}
const OPERATORS = [
  { key: 'ooredoo', name: 'أوريدو', set: flexy.setAppsOoredooSwitch },
  { key: 'djezzy', name: 'جازي', set: flexy.setAppsDjezzySwitch }
]
// The owner's order (2026-10-29): Mobilis, offers, Ooredoo, Djezzy; the key is the store's service name
const SERVICES = [
  { key: 'mobilis', name: 'موبيليس', rate: 'rate_630', block: 'block_630' },
  { key: 'offer', name: 'عروض', rate: 'rate_offer', block: 'block_offer' },
  { key: 'ooredoo', name: 'أوريدو', rate: 'rate_630_ooredoo', block: 'block_ooredoo' },
  { key: 'djezzy', name: 'جازي', rate: 'rate_630_djezzy', block: 'block_djezzy' }
]
const ALLOW = [{ label: 'سماح', value: 'allow' }, { label: 'منع', value: 'block' }]
const SIZES = [{ label: '10', value: 10 }, { label: '20', value: 20 }, { label: '50', value: 50 }]
// Only conveniences on this phone: the page size and the role filter. No rates, no names.
const PAGE_KEY = 'flexy-shops-page-size'
const ROLE_KEY = 'flexy-shops-role'
function remembered (key, allowed, fallback) {
  try { const v = JSON.parse(localStorage.getItem(key)); return allowed.includes(v) ? v : fallback } catch { return fallback }
}
function remember (key, v) { try { localStorage.setItem(key, JSON.stringify(v)) } catch { /* private mode */ } }
const defaults = reactive({ mobilis: null, offer: null, max: null, djezzy: null, ooredoo: null })
const shops = ref([])
const jobs = ref([])
const reviews = ref([])
const roleFilter = ref(remembered(ROLE_KEY, [null, 'trader', 'wholesale'], null))
const search = ref('')
const pageSize = ref(remembered(PAGE_KEY, [10, 20, 50], 10))
const pageNo = ref(0)
// Enabled shops first (owner 2026-10-29 «ترتيب»), then by name
const filtered = computed(() => shops.value.filter((c) => (!roleFilter.value || c.role === roleFilter.value) &&
  (!search.value || c.name.includes(search.value)))
  .sort((a, b) => Number(b.enabled) - Number(a.enabled) || a.name.localeCompare(b.name, 'ar')))
const page = computed(() => filtered.value.slice(pageNo.value * pageSize.value, (pageNo.value + 1) * pageSize.value))
watch([roleFilter, search, pageSize], () => { pageNo.value = 0; remember(ROLE_KEY, roleFilter.value); remember(PAGE_KEY, pageSize.value) })

// Selection: «الكل» takes every shop matching the filter and the search, not only this page
const selecting = ref(false)
const picked = ref(new Set())
const allPicked = computed(() => filtered.value.length > 0 && filtered.value.every((c) => picked.value.has(c.customer_id)))
function toggle (c) {
  const next = new Set(picked.value)
  if (next.has(c.customer_id)) next.delete(c.customer_id); else next.add(c.customer_id)
  picked.value = next
}
function toggleAll () {
  const next = new Set(picked.value)
  filtered.value.forEach((c) => (allPicked.value ? next.delete(c.customer_id) : next.add(c.customer_id)))
  picked.value = next
}
function stopSelect () { selecting.value = false; picked.value = new Set() }

async function load () {
  const [s, c, j, r, k] = await Promise.all([api.flexySettings(), api.flexyCustomers(), api.flexyJobs(null, 20), api.flexyJobs('review', 50), flexy.ownerSwitch()])
  try { showCore(k) } catch { core.apps = null }
  if (s) {
    settings.open = s.open
    const num = (v) => (v == null ? null : Number(v))
    defaults.mobilis = num(s.default_rate_630)
    defaults.offer = num(s.default_rate_offer)
    defaults.max = s.default_max
    defaults.djezzy = num(s.default_rate_630_djezzy)
    defaults.ooredoo = num(s.default_rate_630_ooredoo)
  }
  shops.value = c
  jobs.value = j
  reviews.value = r
}

// One toggle for both switches. Opening: Flexy Core first, then the store; closing: the store first.
async function setOpen (on) {
  const apply = async () => {
    const ok = await run(async () => {
      if (on) showCore(await flexy.setAppsSwitch(true))
      await api.setFlexySettings(on, null, null, null)
      settings.open = on
      if (!on) showCore(await flexy.setAppsSwitch(false))
      return true
    })
    if (!ok) load()
  }
  if (!on) return apply()
  Dialog.create({ title: 'فتح فليكسي المحلات', message: 'كل «أرسل» من محل مفعّل يُخرج رصيدًا حقيقيًا من الشريحة. متأكد؟', cancel: 'لا', ok: 'نعم، افتح' }).onOk(apply)
}
async function saveMax () {
  if (await run(() => api.setFlexySettings(null, null, null, defaults.max).then(() => true), { success: 'حُفظ.' })) load()
}
// The operator's switch in Flexy Core for the shops (the store's master switch stays the master)
function setOperator (op, on) {
  const apply = () => run(async () => { showCore(await op.set(on)); return true })
  if (!on) return apply()
  Dialog.create({ title: `فتح ${op.name} للمحلات`, message: `كل «أرسل» إلى رقم ${op.name} من محل له نسبة يُخرج رصيدًا حقيقيًا من شريحة ${op.name}. متأكد؟`, cancel: 'لا', ok: 'نعم، افتح' }).onOk(apply)
}
// The rate becomes the default (shops enabled later) and goes to every enabled shop that has none for this service
function fillRate (sv) {
  const rate = defaults[sv.key]
  Dialog.create({ title: `نسبة ${sv.name} لمن بلا نسبة`, message: `تُعطى ${rate}% لكل محل مفعّل ليس له نسبة ${sv.name}. المحلات التي لها نسبة لا تتغير.`, cancel: 'لا', ok: 'نعم' })
    .onOk(async () => {
      await run(async () => {
        const n = await api.fillRate(sv.key, rate)
        Notify.create({ type: 'positive', message: `أُعطيت نسبة ${sv.name} ${rate}% لـ ${n} محل.` })
        return true
      })
      load()
    })
}

const editing = ref(false)
const form = ref(null)
const num = (v) => (v == null ? null : Number(v))
async function reloadShops () { shops.value = await api.flexyCustomers() }
// One shop (prefilled) or the selection (empty fields: the shops may differ; a radio shows «منع» only when all are blocked)
function openRates (c) {
  const ids = c ? [c.customer_id] : [...picked.value]
  const rows = c ? [c] : shops.value.filter((x) => picked.value.has(x.customer_id))
  const rate = {}; const block = {}; const last = {}
  SERVICES.forEach((sv) => {
    rate[sv.key] = c ? num(c[sv.rate]) : null
    block[sv.key] = rows.length > 0 && rows.every((x) => x[sv.block] === true)
    last[sv.key] = rate[sv.key]
  })
  form.value = { ids, single: !!c, title: c ? c.name : `${ids.length} محلات محدَّدة`, enabled: c?.enabled ?? null, role: c?.role ?? null, rate, block, last, max: c ? c.max_amount : null, lastMax: c ? c.max_amount : null, saved: {} }
  editing.value = true
}
async function applyBulk (change, done) {
  const f = form.value
  const ok = await run(async () => {
    const n = await api.flexyBulk(f.ids, change)
    Notify.create({ type: 'positive', message: done(n), timeout: 1500 })
    await reloadShops()
    return true
  })
  if (!ok) await reloadShops()
  return ok
}
// Typed a rate and left the field: saved at once. An empty field saves nothing for a selection (no accidental closing).
async function saveRate (sv) {
  const f = form.value
  const v = f.rate[sv.key] === '' ? null : f.rate[sv.key]
  if (v === f.last[sv.key] || (v == null && !f.single)) return
  if (v != null && (v < 0 || v >= 100)) return
  if (await applyBulk({ service: sv.key, rate: v }, (n) => v == null ? `${sv.name}: بلا نسبة (مقفل).` : `${sv.name} ${v}% لـ ${n} محل.`)) { f.last[sv.key] = v; f.saved[sv.key] = true }
}
async function setBlock (sv, v) {
  const f = form.value
  const block = v === 'block'
  if (await applyBulk({ service: sv.key, block }, (n) => `${sv.name} ${block ? 'ممنوع' : 'مسموح'} لـ ${n} محل.`)) { f.block[sv.key] = block; f.saved[sv.key] = true }
}
async function saveMaxShop () {
  const f = form.value
  if (f.max == null || f.max === '' || f.max === f.lastMax || f.max < 10) return
  if (await applyBulk({ max: f.max }, (n) => `أكبر مبلغ ${money(f.max)} لـ ${n} محل.`)) f.lastMax = f.max
}
async function setEnabled (on) {
  if (await applyBulk({ enabled: on }, () => on ? 'فُعّل الفليكسي.' : 'أُوقف الفليكسي.')) {
    form.value.enabled = on
    const c = shops.value.find((x) => x.customer_id === form.value.ids[0])
    if (c) SERVICES.forEach((sv) => { form.value.rate[sv.key] = num(c[sv.rate]); form.value.last[sv.key] = form.value.rate[sv.key] })
  }
}
async function setRole (role) {
  if (await applyBulk({ role }, () => 'حُفظ الدور.')) form.value.role = role
}
function bulkEnabled (on) {
  const ids = [...picked.value]
  Dialog.create({ title: on ? 'تفعيل الفليكسي' : 'إيقاف الفليكسي', message: `${on ? 'يُفعَّل' : 'يُوقَف'} الفليكسي لـ ${ids.length} محل.`, cancel: 'لا', ok: 'نعم' })
    .onOk(() => run(async () => {
      const n = await api.flexyBulk(ids, { enabled: on })
      Notify.create({ type: 'positive', message: `${on ? 'فُعّل' : 'أُوقف'} لـ ${n} محل.` })
      await reloadShops()
      return true
    }))
}

function resolve (j, done) {
  Dialog.create({
    title: done ? 'تم الإرسال؟' : 'لم يُرسل؟',
    message: done ? 'يبقى المبلغ مخصومًا من المحل.' : `يُعاد ${money(j.charged)} إلى رصيد المحل.`,
    cancel: 'رجوع',
    ok: 'تأكيد'
  }).onOk(async () => {
    if (await run(() => api.flexyResolve(j.job_id, done))) { load(); refreshBell() }
  })
}

onMounted(() => run(load))
</script>

<style scoped>
.review { border: 1px solid #F3D9B8; background: #FFF8EE; border-radius: 12px; padding: 10px; }
.shop-head, .shop-row { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr 1fr; gap: 4px; align-items: center; }
.shop-head.sel, .shop-row.sel { grid-template-columns: 28px 2fr 1fr 1fr 1fr 1fr; }
.rate.off { background: #E5E7EB; color: #9CA3AF; text-decoration: line-through; }
.svc-row { display: grid; grid-template-columns: 64px 1fr 86px; gap: 6px; align-items: center; }
.bulk { position: sticky; bottom: 0; z-index: 2; background: #FFF; border-top: 2px solid #C2410C; margin: 0 -4px; padding: 8px 10px; }
.shop-row { width: 100%; border: 0; border-top: 1px solid #EEF0F4; background: transparent; padding: 8px 0; text-align: right; font: inherit; color: inherit; cursor: pointer; }
.rate-row { display: grid; grid-template-columns: 72px 86px 1fr; gap: 8px; align-items: center; }
.dim { opacity: .45; }
.rate { background: #1E293B; color: #FFF; border-radius: 6px; padding: 2px 6px; font-weight: 700; font-size: 12px; }
.op-row { padding: 10px 14px; border-top: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
</style>
