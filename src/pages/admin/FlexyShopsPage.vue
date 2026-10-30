<template>
  <q-page class="page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
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
      <div class="help small muted">الرئيسي يوقف إرسال كل المحلات فورًا. مفتاح متعامل مقفل = «قريبًا» عند المحل. إرسالك أنت له مفتاحه الخاص.</div>
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
      <div class="help small muted">محل له نسبة لا يتغير. النسبة المكتوبة تبقى للمحلات التي تُفعَّل لاحقًا. نسبة فارغة لمتعامل = مقفل لذلك المحل.</div>
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

    <!-- The same window for the selection and for one shop: edits stay in the window until «حفظ»; only what was changed is sent -->
    <q-dialog v-model="editing" persistent>
      <q-card v-if="form" style="min-width: 320px">
        <q-card-section class="text-weight-bold">{{ form.title }}</q-card-section>
        <q-card-section class="column q-gutter-xs">
          <template v-if="form.single">
            <q-toggle v-model="form.enabled" label="تفعيل الفليكسي" :disable="busy" />
            <q-select v-model="form.role" dense outlined emit-value map-options label="الدور" :options="ROLE_OPTIONS" :disable="busy" />
          </template>
          <div v-for="sv in SERVICES" :key="sv.key" class="svc-row">
            <span class="text-weight-bold">{{ sv.name }} <q-badge v-if="changedService(sv)" color="warning" label="معدَّل" /></span>
            <q-option-group dense inline :model-value="form.block[sv.key] ? 'block' : 'allow'" :options="ALLOW" :disable="busy" @update:model-value="form.block[sv.key] = $event === 'block'" />
            <q-input v-model.number="form.rate[sv.key]" dense outlined type="number" step="0.25" suffix="%" :disable="busy || form.block[sv.key] === true" />
          </div>
          <div class="svc-row">
            <span class="text-weight-bold">أكبر مبلغ</span><span></span>
            <q-input v-model.number="form.max" dense outlined type="number" :disable="busy" />
          </div>
          <div class="small muted">لا يُحفظ شيء حتى «حفظ»، ويُرسل ما غيّرته فقط{{ form.single ? '' : ' عند المحدَّدين كلهم' }}؛ الحقل الذي لم تلمسه يبقى كما هو{{ form.single ? '' : ' عند كل محل' }}. «منع» يقفل الخدمة ويحفظ النسبة جانبًا. المحل لا يرى نسبته ولا دوره.</div>
        </q-card-section>
        <q-card-actions align="left">
          <q-btn unelevated no-caps color="primary" label="حفظ" :loading="busy" :disable="!formChanges.length" @click="saveForm" />
          <q-btn flat no-caps color="primary" label="إغلاق" :disable="busy" @click="closeForm" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
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
const core = reactive({ apps: null, djezzy: null, ooredoo: null, ooredooOffers: null, djezzyOffers: null, forcedOff: false })
const isOpen = computed(() => settings.open && core.apps === true && !core.forcedOff)
function showCore (res) {
  if (res.status !== 200) throw new Error('تعذّر الوصول إلى مفتاح Flexy Core (' + (res.body?.error || 'FLEXY_CORE') + ').')
  core.apps = res.body.apps_send_enabled === true
  core.djezzy = res.body.apps_djezzy_send_enabled === true
  core.ooredoo = res.body.apps_ooredoo_send_enabled === true
  core.ooredooOffers = res.body.apps_ooredoo_offers_enabled === true
  core.djezzyOffers = res.body.apps_djezzy_offers_enabled === true
  core.forcedOff = res.body.forced_off === true
}
const OPERATORS = [
  { key: 'ooredoo', name: 'أوريدو', set: flexy.setAppsOoredooSwitch },
  { key: 'djezzy', name: 'جازي', set: flexy.setAppsDjezzySwitch },
  // v1.55 (owner 2026-10-30): the shops' Ooredoo offers, off until he opens them; only offers set «الكل» in «العروض»
  { key: 'ooredooOffers', name: 'عروض أوريدو', set: flexy.setAppsOoredooOffersSwitch },
  { key: 'djezzyOffers', name: 'عروض جازي', set: flexy.setAppsDjezzyOffersSwitch }
]
// The owner's order (2026-10-29): Mobilis, offers, Ooredoo, Djezzy; the key is the store's service name
const SERVICES = [
  { key: 'mobilis', name: 'موبيليس', rate: 'rate_630', block: 'block_630' },
  { key: 'offer', name: 'عروض', rate: 'rate_offer', block: 'block_offer' },
  { key: 'ooredoo', name: 'أوريدو', rate: 'rate_630_ooredoo', block: 'block_ooredoo' },
  { key: 'djezzy', name: 'جازي', rate: 'rate_630_djezzy', block: 'block_djezzy' },
  // v1.55: its own rate (empty = the offers' rate)
  { key: 'offer_ooredoo', name: 'عروض أوريدو', rate: 'rate_offer_ooredoo', block: 'block_offer_ooredoo' },
  { key: 'offer_djezzy', name: 'عروض جازي', rate: 'rate_offer_djezzy', block: 'block_offer_djezzy' }
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
  const rate = {}; const block = {}
  SERVICES.forEach((sv) => {
    rate[sv.key] = c ? num(c[sv.rate]) : null
    block[sv.key] = rows.length > 0 && rows.every((x) => x[sv.block] === true)
  })
  form.value = { ids, single: !!c, title: c ? c.name : `${ids.length} محلات محدَّدة`, enabled: c?.enabled ?? null, role: c?.role ?? null, rate, block, max: c ? c.max_amount : null, orig: { enabled: c?.enabled ?? null, role: c?.role ?? null, rate: { ...rate }, block: { ...block }, max: c ? c.max_amount : null } }
  editing.value = true
}
const blank = (v) => v == null || v === ''
const rateOf = (f, sv) => (blank(f.rate[sv.key]) ? null : Number(f.rate[sv.key]))
// A rate counts as changed only if it differs from what the window opened with; for a selection an empty field is never sent
function rateChanged (f, sv) {
  const v = rateOf(f, sv)
  return v !== f.orig.rate[sv.key] && !(v == null && !f.single)
}
const changedService = (sv) => { const f = form.value; return rateChanged(f, sv) || f.block[sv.key] !== f.orig.block[sv.key] }
// Only what was touched, in a safe order: enabled first (it may fill default rates), then the explicit values on top
const formChanges = computed(() => {
  const f = form.value
  if (!f) return []
  const out = []
  if (f.single && f.enabled !== f.orig.enabled) out.push({ change: { enabled: f.enabled }, done: () => f.enabled ? 'فُعّل الفليكسي' : 'أُوقف الفليكسي' })
  if (f.single && f.role !== f.orig.role) out.push({ change: { role: f.role }, done: () => 'الدور' })
  SERVICES.forEach((sv) => {
    if (rateChanged(f, sv)) { const v = rateOf(f, sv); out.push({ sv, rate: v, change: { service: sv.key, rate: v }, done: () => v == null ? `${sv.name} بلا نسبة` : `${sv.name} ${v}%` }) }
    if (f.block[sv.key] !== f.orig.block[sv.key]) { const b = f.block[sv.key]; out.push({ change: { service: sv.key, block: b }, done: () => `${sv.name} ${b ? 'ممنوع' : 'مسموح'}` }) }
  })
  if (!blank(f.max) && Number(f.max) !== f.orig.max) out.push({ max: Number(f.max), change: { max: Number(f.max) }, done: () => `أكبر مبلغ ${money(f.max)}` })
  return out
})
function markSaved (f, ch) {
  const c = ch.change
  if ('enabled' in c && c.enabled !== null) f.orig.enabled = c.enabled
  else if ('role' in c && c.role !== null) f.orig.role = c.role
  else if (c.block != null) f.orig.block[c.service] = c.block
  else if (c.service) f.orig.rate[c.service] = c.rate
  else if (c.max != null) f.orig.max = c.max
}
// «حفظ»: sends each changed value once, refreshes the list once, closes. A failure stops there and keeps the rest to retry.
async function saveForm () {
  const f = form.value
  const list = formChanges.value
  const bad = list.find((x) => (x.rate != null && (x.rate < 0 || x.rate >= 100)) || (x.max != null && x.max < 10))
  if (bad) { Notify.create({ type: 'negative', message: bad.rate != null ? 'النسبة بين 0 وأقل من 100.' : 'أكبر مبلغ 10 دج على الأقل.' }); return }
  const done = []
  let n = 0
  const ok = await run(async () => {
    for (const ch of list) {
      n = await api.flexyBulk(f.ids, ch.change)
      markSaved(f, ch)
      done.push(ch.done())
    }
    return true
  })
  await reloadShops()
  if (done.length) Notify.create({ type: 'positive', message: `حُفظ لـ ${n} محل: ${done.join('، ')}.` })
  if (ok) editing.value = false
}
function closeForm () {
  if (!formChanges.value.length) { editing.value = false; return }
  Dialog.create({ title: 'خروج بلا حفظ؟', message: 'التغييرات في هذه النافذة لن تُحفظ.', cancel: 'رجوع', ok: 'خروج بلا حفظ' })
    .onOk(() => { editing.value = false })
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
