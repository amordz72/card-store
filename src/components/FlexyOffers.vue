<template>
  <div class="column q-gutter-sm">
    <!-- The line's group (kept, or discovered without money), then its offers: name and price -->
    <div v-if="!phoneOk" class="card text-center muted q-pa-lg">اكتب رقم الزبون لتظهر عروضه.</div>
    <!-- No spinner while the automix shows (owner 2026-10-29): the discovery goes on behind it -->
    <div v-else-if="loading && !showAutomix" class="card column items-center q-gutter-sm q-pa-lg">
      <q-spinner color="primary" size="32px" />
      <div class="small muted">جارٍ معرفة نوع خط الزبون… قد يأخذ حتى دقيقة.</div>
    </div>
    <div v-else-if="error && !showAutomix" class="card column items-center q-gutter-sm q-pa-lg">
      <div class="small text-negative text-center">{{ error }}</div>
      <q-btn flat no-caps color="primary" icon="refresh" label="أعد المحاولة" @click="load({ retry: true })" />
    </div>
    <!-- Sections come from the offers themselves (owner 2026-10-28): each offer's category (bundle /
         internet); no category = bundle, so an operator without categories (Sama) looks as before. -->
    <template v-else-if="!holding && (families.length || internet.length)">
      <!-- Known now, before any press: a short line and a brief colour, so the seller sees the screen changed -->
      <div v-if="justKnown && group" class="card small text-weight-bold known">عُرف الخط: {{ group }}</div>
      <div v-if="families.length" class="card q-pa-none">
        <q-expansion-item v-for="f in families" :key="f.name" :label="f.name" :default-opened="families.length === 1"
          group="families" header-class="family" expand-separator>
          <div v-for="o in f.offers" :key="o.label" class="offer-row" :class="{ busy }" role="button" tabindex="0"
            :aria-disabled="busy" @click="confirm(o)" @keyup.enter="confirm(o)">
            <span class="text-weight-bold"><bdi dir="auto">{{ o.label }}</bdi><q-badge v-if="o.review" class="q-ml-xs" color="purple-6" label="جديد" /><q-badge v-else-if="o.visibility === 'admin'" class="q-ml-xs" color="amber-8" label="للإدارة" /></span>
            <span class="row items-center no-wrap q-gutter-xs">
              <q-btn v-if="detailOf(o)" flat round dense size="sm" icon="info_outline" aria-label="التفاصيل"
                @click.stop="details(o)" />
              <span class="price">{{ money(o.amount) }}</span>
            </span>
          </div>
        </q-expansion-item>
      </div>
      <div v-if="internet.length" class="card q-pa-none net-card">
        <div class="net-head"><q-icon name="swap_vert" size="18px" /> إنترنت فقط</div>
        <div v-for="o in internet" :key="o.label" class="offer-row net" :class="{ busy }" role="button" tabindex="0"
          :aria-disabled="busy" @click="confirm(o)" @keyup.enter="confirm(o)">
          <span class="column">
            <span class="text-weight-bold"><bdi dir="auto">{{ o.label }}</bdi></span>
            <span v-if="detailOf(o)" class="small muted">{{ detailOf(o) }}</span>
          </span>
          <span class="price net-price">{{ money(o.amount) }}</span>
        </div>
      </div>
    </template>
    <!-- «صيغ» (Flexy Core 0067): this number's menu is a known label's but no variant matches it exactly -->
    <div v-else-if="shape" class="card column q-gutter-sm ask">
      <div class="text-weight-bold">
        {{ shape.status === 'confirm' ? 'قائمة هذا الرقم تطابق ' + (shape.candidates[0]?.label || shape.group) + '. تبدأ البيع؟'
          : 'قائمة هذا الرقم من ' + shape.word + ' لكنها تختلف عن ' + (shape.candidates.length > 1 ? 'صيغه المعروفة' : 'المعتمدة') + '.' }}
      </div>
      <div class="small muted">ما أرسلته الشبكة:</div>
      <div class="menu-lines ltr">
        <div v-for="it in shape.items" :key="it.code + it.name"><b>{{ it.code }}</b> · {{ it.name }}</div>
      </div>
      <template v-if="shape.status === 'confirm'">
        <q-btn unelevated no-caps color="positive" label="نعم، ابدأ البيع" :loading="deciding === 'confirm' + shape.group" :disable="Boolean(deciding)"
          @click="decideShape('confirm', shape.group)" />
      </template>
      <template v-else>
        <q-btn v-for="c in shape.candidates" :key="c.key" outline no-caps color="deep-orange" :loading="deciding === 'change' + c.key" :disable="Boolean(deciding)"
          :label="'تغيير في ' + c.key + (c.numbers ? ' (' + c.numbers + ' رقمًا)' : '')" @click="decideShape('change', c.key)" />
      </template>
      <q-btn unelevated no-caps color="cyan-9" label="صيغة جديدة" :loading="deciding === 'new'" :disable="Boolean(deciding)" @click="decideShape('new')" />
      <div class="small muted">«صيغة جديدة» تنشئ {{ shape.word || shape.candidates[0]?.label }} أخرى لهذا النوع من الخطوط، وتستكشفها الآن للإدارة. لا مال في أي خيار.</div>
    </div>
    <!-- Only the network's own «no offers» says so (owner rule): the automix is gone, ordinary credit stays -->
    <div v-else-if="looked && noOffers" class="card text-center q-pa-lg">لا توجد عروض لهذا الرقم. أرسل له رصيدًا عاديًا.</div>
    <div v-else-if="looked && !newGroup && !blocked.length" class="card text-center muted q-pa-lg">لا توجد عروض متاحة لهذا الرقم الآن.</div>
    <!-- Offers the index guard stops (Ooredoo, Flexy Core 0065): a code the menu shows twice. Never sold from here;
         «اكشف» asks the network which offer that code gives (its price, before the PIN; no money). -->
    <div v-if="blocked.length && !loading" class="card q-pa-none blocked">
      <div class="net-head text-grey-8"><q-icon name="block" size="18px" /> موقوفة: رمزها مكرر في القائمة</div>
      <div v-for="o in blocked" :key="o.id" class="offer-row column items-stretch">
        <div class="row items-center justify-between no-wrap q-gutter-xs">
          <span class="text-grey-7"><span class="ltr text-weight-bold">{{ o.code }}</span> · <bdi dir="auto">{{ o.label }}</bdi></span>
          <span class="row items-center no-wrap q-gutter-xs">
            <span class="price text-grey-7">{{ money(o.amount) }}</span>
            <q-btn v-if="probe" dense no-caps unelevated size="sm" color="deep-orange" label="اكشف" :loading="probing === o.code"
              :disable="Boolean(probing)" @click="runProbe(o.code)" />
          </span>
        </div>
        <div v-if="verdictOf(o)" class="small" :class="verdictOf(o).match ? 'text-positive' : 'text-negative'">{{ verdictOf(o).text }}</div>
      </div>
      <div v-if="probeError" class="small text-negative q-px-md q-pb-sm">{{ probeError }}</div>
      <div v-if="anyMatch" class="small muted q-px-md q-pb-sm">
        للبيع: {{ newGroup ? 'اعتمد المجموعة في شاشة العروض، ثم' : 'في شاشة العروض ←' }} «اعتماد الرمز» على العرض المطابق. الآخر يبقى موقوفًا.
      </div>
    </div>
    <!-- «أوتوميكس» (owner 2026-10-29): a Mobilis number whose line is not known yet sells at once, without waiting
         for the discovery. 100 goes by Arsselli first (the network gives the line's own offer at that price); «مختلط»
         and «إنترنت» open a Sama session that buys only when the line has that offer, else stops before any money and
         the line's offers show. Each row only while a SIM can take it; otherwise «حاول بعد دقيقة» (the owner is told). -->
    <div v-if="showAutomix" class="card column q-gutter-sm automix">
      <div class="text-weight-bold">اختر مباشرة دون انتظار</div>
      <div v-if="!holding && loading" class="small muted">عروض الخط تظهر هنا حين تُعرف.</div>
      <div v-if="holding" class="row items-center q-gutter-sm small text-primary"><q-spinner size="16px" /><span>جارٍ تنفيذ العرض… النتيجة في «آخر العمليات». لا تُرسل غيره حتى ينتهي.</span></div>
      <div v-if="automix.small === null" class="row items-center q-gutter-sm small muted"><q-spinner size="16px" /><span>جارٍ التحقق من الشرائح…</span></div>
      <div v-else-if="!automix.small && !automix.big" class="small text-negative">لا توجد عروض الآن، حاول بعد دقيقة.</div>
      <template v-else>
        <div v-if="automix.small" class="column q-gutter-xs">
          <div class="small muted">عرض الخط بهذا المبلغ</div>
          <div class="amounts">
            <q-btn v-for="o in AUTO.small.filter(fits)" :key="o.label" unelevated no-caps color="primary" :label="money(o.amount)" :disable="busy || holding" @click="confirm(o, true)" />
          </div>
        </div>
        <div v-else class="small text-deep-orange-9">100 غير متاح الآن، حاول بعد دقيقة.</div>
        <template v-if="automix.big">
          <div class="small muted">مختلط (مكالمات ورسائل وإنترنت)</div>
          <div class="amounts">
            <q-btn v-for="o in AUTO.mix.filter(fits)" :key="o.label" outline no-caps color="primary" :label="money(o.amount)" :disable="busy || holding" @click="confirm(o, true)" />
          </div>
          <div class="small muted">إنترنت</div>
          <div class="amounts">
            <q-btn v-for="o in AUTO.net.filter(fits)" :key="o.label" outline no-caps color="cyan-9" :label="money(o.amount)" :disable="busy || holding" @click="confirm(o, true)" />
          </div>
        </template>
        <div v-else class="small text-deep-orange-9">العروض الأخرى غير متاحة الآن، حاول بعد دقيقة.</div>
      </template>
    </div>
    <!-- A group none of whose offers is decided yet (Ooredoo, Flexy Core 0060): its offers show above, sellable by the
         owner; the live menu opens by itself below to move through the next pages, each one recorded. -->
    <div v-if="newGroup && !loading" class="card column q-gutter-sm live">
      <div class="text-weight-bold">⚡ مجموعة جديدة: {{ newGroup.group || 'غير معروفة' }} · استكشاف</div>
      <div class="small muted">تنقّل لتُسجَّل كل الصفحات. الاستكشاف لا يشتري: البيع من القائمة فوق.</div>
      <ModemPanel v-if="newGroup.sim" :sim-uuid="newGroup.sim" sim-type="ooredoo-flexy" ussd-only explore :start-code="'*585*' + phone + '#'" />
      <q-btn unelevated no-caps color="cyan-9" icon="local_offer" label="شاشة العروض ← اعتماد" to="/flexy/offers" />
    </div>
  </div>
</template>

<script setup>
// The offers of one number, shared by the shop page and the owner's page (one UI, two callers):
// `lookup(phone)` answers { status: 'ready' | 'discovering' | …, offers: [{ label, family, amount, available? }] },
// `send(phone, label)` sends one offer and resolves to something truthy when it was accepted for sending;
// `repeatOf(phone, { offer })` names the last operation when it was this same offer to this number.
import { computed, defineAsyncComponent, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'

const props = defineProps({
  phone: { type: String, required: true },
  phoneOk: { type: Boolean, required: true },
  active: { type: Boolean, default: true },
  maxAmount: { type: Number, default: Infinity },
  lookup: { type: Function, required: true },
  send: { type: Function, required: true },
  repeatOf: { type: Function, default: () => null },
  // «أوتوميكس»: available(names) → { name: bool } (the shop's page); absent = every row shown (the owner's page)
  available: { type: Function, default: null },
  // An offer of this number is running (from «آخر العمليات»): the automix screen stays as it is until it ends
  running: { type: Boolean, default: false },
  // «اكشف» (owner's page, Ooredoo): probe(phone, code, again) → { status: 'probing' | 'done', price, offers }
  probe: { type: Function, default: null },
  // «صيغ»: decide(phone, 'confirm' | 'change' | 'new', group) when a menu matched no variant exactly
  decide: { type: Function, default: null }
})
const emit = defineEmits(['sent'])
// The lab, only for the owner's live session on a new group (never loaded on a shop's page)
const ModemPanel = defineAsyncComponent(() => import('src/components/ModemPanel.vue'))
const newGroup = ref(null)
// «أوتوميكس»: the quick offers by their catalog names (Flexy Core sends each by its known route)
const autoOffer = (family, amount, display, category = 'bundle') => ({ label: `${family} ${amount}`, amount, display, category })
const AUTO = {
  // 50 dropped (owner 2026-10-29): the network refuses 50 DA to Sama Mix and Revolution lines
  small: [100].map((a) => autoOffer('Mixed', a, `عرض ${a} دج (حسب خط الزبون)`)),
  // «Mixed N» (Flexy Core): the line's own offer of kind «مختلط» and that amount, whatever its group
  mix: [500, 1000, 1500, 2000].map((a) => autoOffer('Mixed', a, `مختلط ${a} دج`)),
  net: [500, 1000, 1500, 2000].map((a) => autoOffer('Sama Net', a, `إنترنت ${a} دج`, 'internet'))
}
const fits = (o) => o.amount <= props.maxAmount
const automix = ref({ for: '', small: null, big: null })
let automixRun = 0
async function checkAutomix (p) {
  const mine = ++automixRun
  automix.value = { for: p, small: null, big: null }
  if (!props.available) { automix.value = { for: p, small: true, big: true }; return }
  try {
    const a = await props.available(['Mixed 100', 'Sama Net 500'])
    if (mine === automixRun) automix.value = { for: p, small: a['Mixed 100'] !== false, big: a['Sama Net 500'] !== false }
  } catch {
    // Not known: the rows show, the send itself still refuses («غير متاح») without taking anything
    if (mine === automixRun) automix.value = { for: p, small: true, big: true }
  }
}
// The owner's question (Ooredoo «صيغ», Flexy Core 0067): { status: 'ask' | 'confirm', word, group, candidates, items }
const shape = ref(null)
const deciding = ref('')
async function decideShape (decision, group = null) {
  if (!props.decide || deciding.value) return
  deciding.value = decision + (group || '')
  try {
    await props.decide(props.phone, decision, group)
    shape.value = null
    await load()
  } catch (e) {
    error.value = e?.message || 'تعذّر حفظ القرار.'
  } finally {
    deciding.value = ''
  }
}
const { busy, run } = useRun()

// What the customer gets for each offer (shown from «i»). The price is the number in the name.
const DETAILS = {
  'Sama Mix 100': '500Mo — يوم واحد', 'Sama Mix 500': '5Go — 15 يومًا', 'Sama Mix 1000': '15Go — 30 يومًا',
  'Sama Mix 1500': '30Go — 30 يومًا', 'Sama Mix 2000': '50Go — 30 يومًا',
  'Sama Talk 500': '500Mo — 15 يومًا', 'Sama Talk 1000': '2Go — 30 يومًا', 'Sama Talk 1500': '3Go — 30 يومًا',
  'Sama Talk 2000': '4Go — 30 يومًا',
  'Sama Net 500': '10Go — 15 يومًا', 'Sama Net 1000': '30Go — 30 يومًا', 'Sama Net 1500': '60Go — 30 يومًا',
  'Sama Net 2000': '90Go — 30 يومًا',
  'PixX 50': '500Mo — يوم واحد', 'PixX 100': '1Go — يوم واحد', 'PixX 500': '5Go — 15 يومًا',
  'PixX 1000': '13Go — 30 يومًا', 'PixX 2000': '30Go',
  // Djezzy (owner's market screenshots 2026-10-27, «حسب السوق»)
  'LEGEND 50': '24 ساعة · 60 دقيقة نحو جيزي · 10 دقائق نحو الكل'
}
const spaced = (d) => (d || '').replace(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/, '$1 $2 $3 $4 $5')

const loading = ref(false)
// Offers the index guard stops, and what «اكشف» learnt this time (by code)
const blocked = ref([])
const probing = ref('')
const probeError = ref('')
const probed = ref({})
function verdictOf (o) {
  const r = probed.value[o.code]
  const price = r ? r.price : o.probe?.code === o.code ? o.probe.price : null
  if (price === null || price === undefined) return r ? { match: false, text: 'الشبكة لم تذكر سعرًا: ' + (r.text || r.result || '—') } : null
  const match = Number(price) === Number(o.amount)
  const when = r ? 'الآن' : 'كشف سابق'
  return { match, text: (match ? '✓ ' : '✗ ') + when + ': الرمز ' + o.code + ' يعطي ' + money(price) + (match ? ' = هذا العرض' : ' ≠ هذا العرض') }
}
const anyMatch = computed(() => blocked.value.some((o) => verdictOf(o)?.match))
async function runProbe (code) {
  const p = props.phone
  if (!props.probe || probing.value) return
  probing.value = code
  probeError.value = ''
  try {
    let r = await props.probe(p, code, Boolean(probed.value[code]))
    for (let i = 0; r?.status === 'probing' && i < 30; i++) {
      await new Promise((resolve) => setTimeout(resolve, 3000))
      r = await props.probe(p, code)
    }
    if (r?.status !== 'done') throw new Error('لم تردّ الشبكة. أعد «اكشف».')
    probed.value = { ...probed.value, [code]: r }
  } catch (e) {
    probeError.value = e?.message || 'تعذّر الكشف الآن.'
  } finally {
    probing.value = ''
  }
}
const looked = ref(false)
const error = ref('')
const offers = ref([])
let loadedFor = ''
let runId = 0
const group = ref('')

// Prices rising; the catalog's order only between equal prices (owner 2026-10-28: by amount by default).
// `ordered` (Ooredoo, Flexy Core 0062): the owner's own order from the offers screen, one for everybody.
const ordered = ref(false)
const byPrice = (a, b) => (ordered.value ? (a.order ?? 0) - (b.order ?? 0) : a.amount - b.amount || (a.order ?? 0) - (b.order ?? 0))
const shown = computed(() => offers.value.filter((x) => x.available !== false && x.amount <= props.maxAmount))
// Bundles: by family in the catalog's order (Mix, Talk, Net…). An offer without a category is a bundle.
const families = computed(() => {
  const out = []
  for (const o of shown.value.filter((x) => x.category !== 'internet')) {
    let f = out.find((x) => x.name === o.family)
    if (!f) out.push(f = { name: o.family, offers: [] })
    f.offers.push(o)
  }
  for (const f of out) f.offers.sort(byPrice)
  return out
})
// Internet only: its own section and colour, never beside a bundle of the same price
const internet = computed(() => shown.value.filter((x) => x.category === 'internet').sort(byPrice))
const detailOf = (o) => DETAILS[o.label] || o.details || ''
// Only while this Mobilis number's line is not known: waiting for it, or its discovery failed
// Owner 2026-10-29: while an automix send of this number runs, nothing appears or disappears; when it ends,
// the line's offers are read again (its group is known by then).
const autoSent = ref('')
// Until its row shows in «آخر العمليات» (a few seconds), the send counts as running
const justSent = ref(false)
const justKnown = ref(false)
// The network said this number takes no offers (its own reply, never a silence)
const noOffers = ref(false)
// Owner 2026-10-29: no «أعد المحاولة». A failed discovery under the automix is tried again by itself, quietly,
// at most 3 times, spaced (Sama SIMs are not worn); the automix buttons keep working meanwhile.
const RETRY_AFTER_MS = [20000, 40000, 60000]
let retries = { phone: '', n: 0 }
function retryLater (p) {
  if (retries.phone !== p) retries = { phone: p, n: 0 }
  if (retries.n >= RETRY_AFTER_MS.length) return
  const wait = RETRY_AFTER_MS[retries.n++]
  setTimeout(() => {
    if (props.phone !== p || !props.active || holding.value || !error.value) return
    load({ retry: true })
  }, wait)
}
const holding = computed(() => autoSent.value !== '' && autoSent.value === props.phone && (props.running || justSent.value))
const showAutomix = computed(() => props.phoneOk && props.phone.startsWith('06') && automix.value.for === props.phone &&
  (loading.value || Boolean(error.value) || holding.value))
watch(() => props.running, (now, before) => {
  if (before && !now && autoSent.value && autoSent.value === props.phone) { autoSent.value = ''; load() }
})

// One request; while the core discovers the line, ask again every 3 s (at most 90 s).
// `retry` («أعد المحاولة») asks the core for a new discovery when the last one ended.
let loadingFor = ''
let shownFor = ''
async function load ({ retry = false } = {}) {
  const p = props.phone
  const mine = ++runId
  loadingFor = p
  offers.value = []
  error.value = ''
  noOffers.value = false
  looked.value = false
  newGroup.value = null
  shape.value = null
  blocked.value = []
  probed.value = {}
  probeError.value = ''
  loading.value = true
  if (p.startsWith('06') && automix.value.for !== p) checkAutomix(p)
  try {
    let r = await props.lookup(p, { retry })
    for (let i = 0; r?.status === 'discovering' && i < 30 && mine === runId; i++) {
      await new Promise((resolve) => setTimeout(resolve, 3000))
      r = await props.lookup(p)
    }
    if (mine !== runId) return
    ordered.value = r?.ordered === true
    blocked.value = Array.isArray(r?.blocked) ? r.blocked : []
    if (r?.status === 'ready') {
      // Replacing the automix buttons: mark it for a moment
      if (automix.value.for === p && !holding.value) { justKnown.value = true; setTimeout(() => { justKnown.value = false }, 2500) }
      loadedFor = p
      offers.value = r.offers || []
      looked.value = true
      group.value = r.group || ''
    } else if (r?.status === 'new_group') {
      loadedFor = p
      looked.value = true
      offers.value = r.offers || []
      group.value = r.group || ''
      newGroup.value = { group: r.group || '', sim: r.sim_uuid || '' }
    } else if (r?.status === 'ask' || r?.status === 'confirm') {
      // The menu is a known label's but matches no variant exactly (or the variant asks first): the owner decides
      loadedFor = p
      looked.value = true
      offers.value = []
      group.value = ''
      shape.value = r
    } else if (r?.status === 'no_offers') {
      // The network said the number takes no offers now: the empty list says it, no error (owner 2026-10-26)
      noOffers.value = true
      loadedFor = p
      offers.value = []
      looked.value = true
      group.value = ''
    } else {
      error.value = r?.status === 'discovering' ? 'لم تردّ الشبكة. أعد المحاولة.' : (r?.message || 'تعذّر معرفة نوع خط الزبون الآن.')
      if (p.startsWith('06') && automix.value.for === p) retryLater(p)
    }
  } catch (e) {
    if (mine === runId) {
      error.value = e?.message || 'تعذّر جلب العروض الآن.'
      if (p.startsWith('06') && automix.value.for === p) retryLater(p)
    }
  } finally {
    if (mine === runId) { loading.value = false; loadingFor = ''; shownFor = p }
  }
}

// Opening the tab, or a new number, loads that number's offers. Back on the tab with the same number
// (owner 2026-10-26): a wait still running goes on, an answer or an error stays (its own button retries).
watch(() => [props.active, props.phone, props.phoneOk], () => {
  if (!props.active) return
  if (!props.phoneOk) { runId++; loading.value = false; loadingFor = ''; shownFor = ''; offers.value = []; looked.value = false; error.value = ''; newGroup.value = null; blocked.value = []; return }
  if (loading.value && loadingFor === props.phone) return
  if (shownFor === props.phone && (looked.value || error.value)) return
  load()
}, { immediate: true })

// After an offer of this number stopped: read its offers again. True when the line's group changed
// (the sale stopped before buying and the core kept the new group): the new offers are now shown.
async function recheck (p) {
  if (p !== props.phone || !props.phoneOk) return false
  const before = group.value
  await load()
  return Boolean(before && group.value && before !== group.value)
}
defineExpose({ recheck })

function details (o) {
  Dialog.create({ title: o.label, message: detailOf(o), ok: 'حسنًا', position: 'bottom' })
}

// One offer at a time: a tap while one is being sent opens nothing
let asking = false
function confirm (o, auto = false) {
  const p = props.phone
  if (busy.value || asking) return
  if (!auto && p !== loadedFor) { load(); return }
  const last = props.repeatOf(p, { offer: o.label })
  asking = true
  Dialog.create({
    title: last ? 'نفس آخر عملية' : 'تأكيد العرض',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      ${o.category === 'internet' ? '<div style="text-align:center;margin:4px 0"><span style="background:#ECFEFF;color:#0E7490;border-radius:6px;padding:2px 8px;font-weight:700">إنترنت فقط</span></div>' : ''}
      <div style="text-align:center${o.category === 'internet' ? ';color:#0E7490' : ''}"><b>${o.display || o.label}</b>${!o.display && detailOf(o) ? ' — ' + detailOf(o) : ''}</div>${o.display
        ? '<div style="font-size:12px;color:#5B6170;text-align:center">إن لم يكن لخط الزبون هذا العرض يتوقف قبل أي خصم، وتظهر عروض خطه.</div>' : ''}
      <div style="text-align:center">السعر: <b>${money(o.amount)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>${last
        ? `<div style="margin-top:8px;padding:8px;border-radius:8px;background:#FFF3E0;color:#BF360C;text-align:center">
            آخر عملية كانت نفس العرض لنفس الرقم (${last.badge.label}).<br><b>أرسل مرة ثانية؟</b></div>`
        : ''}`,
    cancel: 'رجوع',
    ok: last ? 'نعم، أرسل مرة ثانية' : 'نعم، أرسل'
  }).onDismiss(() => { asking = false }).onOk(async () => {
    const r = await run(() => props.send(p, o.label))
    if (r) {
      if (auto) { autoSent.value = p; justSent.value = true; setTimeout(() => { justSent.value = false }, 10000) }
      emit('sent', { phone: p, offer: o, result: r, auto })
    }
  })
}
</script>

<style scoped>
.offer-row { border-top: 1px solid #ECEEF3; padding: 10px 14px; cursor: pointer;
  display: flex; align-items: center; justify-content: space-between; gap: 8px; text-align: right; }
:deep(.family) { font-weight: 700; }
.price { font-weight: 700; white-space: nowrap; }
.offer-row.busy { opacity: 0.5; cursor: default; }
.net-card { border-inline-start: 4px solid #0E7490; }
.net-head { display: flex; align-items: center; gap: 6px; padding: 10px 14px; font-weight: 700; color: #0E7490; }
.net-price { color: #0E7490; }
.blocked { border-style: dashed; }
.ask { border: 2px solid #C2410C; padding: 12px; }
.menu-lines { background: #F6F6F6; border-radius: 8px; padding: 8px 10px; font-family: monospace; font-size: 12px; max-height: 180px; overflow: auto; }
.live { border: 2px solid #0E7490; padding: 12px; }
.automix { border: 2px solid #1D4ED8; padding: 12px; }
.known { background: #FEF3C7; color: #92400E; padding: 8px 12px; }
.link { background: none; border: 0; padding: 0; cursor: pointer; font: inherit; text-decoration: underline; }
.amounts { display: flex; flex-wrap: wrap; gap: 8px; }
.amounts .q-btn { min-width: 72px; min-height: 44px; }
</style>
