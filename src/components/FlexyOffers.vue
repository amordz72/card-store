<template>
  <div class="column q-gutter-sm">
    <!-- The line's group (kept, or discovered without money), then its offers: name and price -->
    <div v-if="!phoneOk" class="card text-center muted q-pa-lg">اكتب رقم الزبون لتظهر عروضه.</div>
    <!-- Learned (Flexy Core 0093): what this number refused before, said before sending it again -->
    <div v-if="phoneOk && refusals.length" class="card warn small">
      ⚠ هذا الرقم رفض من قبل: <b>{{ refusals.map((r) => (r.offer || (r.amount + ' دج')) + ' (' + new Date(r.at).toLocaleDateString('ar-DZ', { day: '2-digit', month: '2-digit' }) + ')').join('، ') }}</b>
      — الأرجح أن خطه لا يقبله: جرّب عرضًا آخر.
    </div>
    <!-- No spinner while the Sama board shows (owner 2026-10-29): the discovery goes on behind it -->
    <div v-else-if="loading && !boardOn && !curtain" class="card column items-center q-gutter-sm q-pa-lg">
      <q-spinner color="primary" size="32px" />
      <div class="small muted">جارٍ معرفة نوع خط الزبون… قد يأخذ حتى دقيقة.</div>
    </div>
    <div v-else-if="error && !boardOn && !curtain" class="card column items-center q-gutter-sm q-pa-lg">
      <div class="small text-negative text-center">{{ error }}</div>
      <q-btn flat no-caps color="primary" icon="refresh" label="أعد المحاولة" @click="load({ retry: true })" />
    </div>
    <!-- Sections come from the offers themselves (owner 2026-10-28): each offer's category (bundle /
         internet); no category = bundle, so an operator without categories (Sama) looks as before. -->
    <template v-else-if="!curtain && !boardOn && !holding && (families.length || internet.length)">
      <div v-if="families.length" class="card q-pa-none">
        <q-expansion-item v-for="f in families" :key="f.name" :label="f.name" :default-opened="families.length === 1"
          group="families" header-class="family" expand-separator>
          <div v-for="o in f.offers" :key="o.label" class="offer-row" :class="{ busy }" role="button" tabindex="0"
            :aria-disabled="busy" @click="confirm(o)" @keyup.enter="confirm(o)">
            <span class="text-weight-bold"><bdi dir="auto">{{ o.label }}</bdi><q-badge v-if="o.review" class="q-ml-xs" color="purple-6" label="جديد" /><q-badge v-else-if="o.visibility === 'admin'" class="q-ml-xs" color="amber-8" label="للإدارة" /><q-badge v-if="o.probe_ok" class="q-ml-xs" color="positive" label="معتمد بالكشف" /></span>
            <span class="row items-center no-wrap q-gutter-xs">
              <q-btn v-if="detailOf(o)" flat round dense size="sm" icon="info_outline" aria-label="التفاصيل"
                @click.stop="details(o)" />
              <q-btn v-if="session.isAdmin && o.probe_ok && o.visibility === 'admin' && o.id" dense flat no-caps size="sm" color="primary" label="افتحه للمحلات"
                :loading="approving === o.id" @click.stop="openToShops(o)" />
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
    <div v-else-if="looked && noOffers && !boardOn && !curtain" class="card text-center q-pa-lg">لا توجد عروض لهذا الرقم. أرسل له رصيدًا عاديًا.</div>
    <div v-else-if="looked && !boardOn && !newGroup && !blocked.length && !curtain" class="card text-center muted q-pa-lg">لا توجد عروض متاحة لهذا الرقم الآن.</div>
    <!-- The Sama board (owner 2026-10-31, «نفذ»): one look for every Mobilis number, the owner's page too. Tabs closed
         at first; fixed rows «Sama Mix N» / «Sama Net N» that never change by themselves. A press sends at once: the line's
         own offer when known (the discovery gets up to 5 s, shown as the send's own wait), else the automatic one (it
         stops before any money). A row the known line lacks says «لا يوجد عرض متاح لهذا الرقم» when pressed and goes.
         No word on the screen tells how it works (no «أوتوميكس», no «عُرف الخط»). -->
    <!-- Opening «عروض» (owner 2026-10-31): 3 s of loading like every app, the same for every Mobilis number; the line is
         read behind it (it started when the number was whole). -->
    <div v-if="curtain" class="card column items-center q-pa-xl"><q-spinner-dots color="primary" size="40px" /></div>
    <div v-else-if="boardOn" class="card column q-gutter-sm q-pa-md board">
      <div v-if="boardStatus" class="board-status small text-primary"><q-spinner size="14px" class="q-mr-xs" />{{ boardStatus }}</div>
      <q-expansion-item v-for="sec in board" :key="sec.key" :label="sec.title" group="board" :default-opened="sec.key === 'mix'"
        class="tab-card" header-class="tab-head">
        <div v-if="sec.note" class="small muted text-center q-pa-md">
          <q-spinner v-if="sec.spin" size="16px" class="q-mr-xs" />{{ sec.note }}
        </div>
        <div v-for="r in sec.rows" :key="r.key" class="offer-row" :class="{ busy: busy || holding || Boolean(waiting) || !r.ok, net: r.net }"
          role="button" tabindex="0" :aria-disabled="busy || holding || Boolean(waiting) || !r.ok" @click="pick(r)" @keyup.enter="pick(r)">
          <span class="column">
            <span class="text-weight-bold"><bdi dir="auto">{{ r.text }}</bdi><template v-if="r.real"><q-badge v-if="r.real.review" class="q-ml-xs" color="purple-6" label="جديد" /><q-badge v-else-if="r.real.visibility === 'admin'" class="q-ml-xs" color="amber-8" label="للإدارة" /></template></span>
            <span v-if="r.sub" class="small muted">{{ r.sub }}</span>
          </span>
          <span class="row items-center no-wrap q-gutter-xs">
            <q-spinner v-if="waiting === r.key" size="16px" color="primary" />
            <q-btn v-if="r.info" flat round dense size="sm" icon="info_outline" aria-label="التفاصيل" @click.stop="details(r.info)" />
            <q-btn v-if="r.real && session.isAdmin && r.real.probe_ok && r.real.visibility === 'admin' && r.real.id" dense flat no-caps size="sm" color="primary"
              label="افتحه للمحلات" :loading="approving === r.real.id" @click.stop="openToShops(r.real)" />
            <span class="price" :class="{ 'net-price': r.net }">{{ money(r.amount) }}</span>
          </span>
        </div>
      </q-expansion-item>
    </div>
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
        <!-- «اعتماد الرمز» from here (owner 2026-10-30): the probe named this offer's price; on the owner's word -->
        <q-btn v-if="session.isAdmin && verdictOf(o)?.match" dense unelevated no-caps size="sm" color="positive" icon="verified" class="self-start q-mt-xs"
          :label="'اعتمد الرمز ' + o.code + ' لهذا العرض'" :loading="approving === o.id" @click="approveCode(o)" />
      </div>
      <div v-if="probeError" class="small text-negative q-px-md q-pb-sm">{{ probeError }}</div>
      <div v-if="anyMatch" class="small muted q-px-md q-pb-sm">
        بعد «اعتمد» يُباع هذا العرض، ولا يُرسل الـPIN إلا إذا قالت الشبكة نفس السعر. الآخر بنفس الرمز يبقى موقوفًا.{{ newGroup ? ' (اعتمد المجموعة في شاشة العروض أولًا.)' : '' }}
      </div>
    </div>
    <!-- Djezzy (Flexy Core 0075): the number's «Offres Internet» pages read once, no money; then its offers show -->
    <q-btn v-if="internetMenu && explore && looked && !loading && !holding && !boardOn" outline no-caps color="cyan-9" icon="travel_explore"
      :label="exploring ? 'جارٍ قراءة عروض الإنترنت…' : 'اقرأ عروض الإنترنت'" :loading="exploring" @click="readInternet" />
    <div v-if="exploreError" class="small text-negative">{{ exploreError }}</div>
    <!-- A group none of whose offers is decided yet (Ooredoo, Flexy Core 0060): its offers show above, sellable by the
         owner; the live menu opens by itself below to move through the next pages, each one recorded. -->
    <div v-if="newGroup && !loading" class="card column q-gutter-sm live">
      <div class="text-weight-bold">⚡ {{ /\s\d+$/.test(newGroup.group || '') ? 'صيغة جديدة حُفظت وحدها' : 'مجموعة جديدة' }}: {{ newGroup.group || 'غير معروفة' }} · استكشاف</div>
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
import { Dialog, Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import * as flexyApi from 'src/api/flexy'
import { useSessionStore } from 'stores/session'

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
  decide: { type: Function, default: null },
  // Djezzy: explore(phone) → { status: 'discovering' | 'done' }, the line's «Offres Internet» read once
  explore: { type: Function, default: null },
  // The «عروض» tab is on screen (the line is read before, as soon as the number is whole)
  visible: { type: Boolean, default: true },
  // The owner's switch («المفاتيح»): the Sama board with its automatic offers; off = the line's offers once known
  boardSwitch: { type: Boolean, default: true }
})
const emit = defineEmits(['sent'])
// The lab, only for the owner's live session on a new group (never loaded on a shop's page)
const ModemPanel = defineAsyncComponent(() => import('src/components/ModemPanel.vue'))
const newGroup = ref(null)
// The automatic offers by their catalog names (Flexy Core sends each by its known route). Shown as «Sama Mix N» /
// «Sama Net N» to everybody (owner 2026-10-31: the screen never says how it works).
const autoOffer = (family, amount, display, category = 'bundle') => ({ label: `${family} ${amount}`, amount, display, category })
const AUTO = {
  // 50 back (owner 2026-10-29): tried by Arsselli, a Sama line got «Sama Mix 50 500Mo + Bonus 50DA»
  small: [50, 100].map((a) => autoOffer('Mixed', a, `Sama Mix ${a}`)),
  // «Mixed N» (Flexy Core): the line's own offer of kind «مختلط» and that amount, whatever its group
  mix: [500, 1000, 1500, 2000].map((a) => autoOffer('Mixed', a, `Sama Mix ${a}`)),
  net: [500, 1000, 1500, 2000].map((a) => autoOffer('Sama Net', a, `Sama Net ${a}`, 'internet')),
  // Between Mix and Net to slow a little (owner 2026-10-31: rarely chosen). No automatic route: never sent blind
  // (the core would swap it for the line's mixed offer), it waits for the line to be known.
  talk: [500, 1000, 1500, 2000].map((a) => autoOffer('Sama Talk', a, `Sama Talk ${a}`))
}
const fits = (o) => o.amount <= props.maxAmount
// The owner's page only for now (the shops' page reads through the store)
const session = useSessionStore()
const refusals = ref([])
watch(() => [props.phone, props.phoneOk], async ([p, ok]) => {
  refusals.value = []
  if (!ok || !session.isAdmin) return
  try {
    const r = await flexyApi.numberMemory(p)
    if (r.status === 200 && p === props.phone) refusals.value = r.body?.refusals || []
  } catch { /* the warning is a help, never a block */ }
}, { immediate: true })
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
// «اعتمد» here: the offer leaves «موقوفة» for its place (Flexy Core moves it once approved); «افتحه للمحلات» after, if wanted
const approving = ref(null)
function approveCode (o) {
  Dialog.create({
    title: 'اعتماد الرمز ' + o.code + ' لـ' + o.label,
    message: 'الكشف قال إن الرمز ' + o.code + ' يعطي ' + money(o.amount) + ' = هذا العرض. يُباع لك (الإدارة)، والـPIN لا يُرسل إلا إذا قالت الشبكة نفس السعر. العرض الآخر بنفس الرمز يبقى موقوفًا.',
    cancel: 'رجوع',
    ok: 'اعتمد'
  }).onOk(() => act(o, () => flexyApi.ownerOfferProbeApprove(o.id), 'اعتُمد: صار في مكانه بين العروض.'))
}
function openToShops (o) {
  Dialog.create({ title: 'افتح ' + o.label + ' للمحلات؟', message: 'تراه المحلات وتبيعه. الحماية نفسها: لا PIN إلا بنفس السعر.', cancel: 'رجوع', ok: 'افتحه' })
    .onOk(() => act(o, () => flexyApi.ownerOfferCatalogSet(o.id, { audience: 'all' }), 'فُتح للمحلات.'))
}
async function act (o, fn, done) {
  approving.value = o.id
  try {
    const r = await fn()
    if (r.status !== 200 || !r.body?.ok) throw new Error(r.body?.error || 'FLEXY_CORE')
    Notify.create({ type: 'positive', message: done })
    loadedFor = ''
    await load()
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message === 'PROBE_NOT_MATCHING' ? 'الكشف المحفوظ لا يطابق هذا العرض: أعد «اكشف».' : e.message })
  } finally {
    approving.value = null
  }
}
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
// The network said this number takes no offers (its own reply, never a silence)
const noOffers = ref(false)
const internetMenu = ref(false)
const exploring = ref(false)
const exploreError = ref('')
async function readInternet () {
  if (exploring.value) return
  const p = props.phone
  exploring.value = true
  exploreError.value = ''
  try {
    let r = await props.explore(p)
    for (const end = Date.now() + 90_000; r?.status === 'discovering' && Date.now() < end;) {
      await new Promise((resolve) => setTimeout(resolve, 3000))
      r = await props.explore(p)
    }
    if (r?.status !== 'done') throw new Error('لم تردّ الشبكة. أعد المحاولة.')
    internetMenu.value = false
    if (props.phone === p) await load()
  } catch (e) {
    exploreError.value = e?.message || 'تعذّرت قراءة عروض الإنترنت.'
  } finally {
    exploring.value = false
  }
}
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
watch(() => props.running, (now, before) => {
  if (before && !now && autoSent.value && autoSent.value === props.phone) { autoSent.value = ''; load() }
})
// The 3 s curtain each time «عروض» opens for a Mobilis number
const curtain = ref(false)
let curtainTimer = null
watch(() => [props.visible, props.phone], ([v], old) => {
  const opened = v && !(old && old[0])
  if (!v || !props.phoneOk || !props.phone.startsWith('06')) { curtain.value = false; return }
  if (!opened) return
  curtain.value = true
  clearTimeout(curtainTimer)
  curtainTimer = setTimeout(() => { curtain.value = false }, 3000)
}, { immediate: true })

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
      loadedFor = p
      offers.value = r.offers || []
      looked.value = true
      group.value = r.group || ''
      internetMenu.value = r.internet_menu === true
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
  const sent = autoRow && autoRow.phone === p ? autoRow : null
  await load()
  // The automatic offer stopped because the line has none at that price: the same window as a press, the line's offers behind it
  if (sent && boardOn.value && lineHas(sent.kind, sent.amount) === null) { autoRow = null; absent(sent); return 'told' }
  return Boolean(before && group.value && before !== group.value)
}
defineExpose({ recheck })

function details (o) {
  Dialog.create({ title: o.label, message: detailOf(o), ok: 'حسنًا', position: 'bottom' })
}

// ---- The Sama board (owner 2026-10-31, «نفذ»): fixed rows, tabs closed at first; nothing changes before a press ----
// realView: after «لا يوجد عرض…», the line's own offers in the ordinary look (owner 2026-10-31), this number only
const realView = ref(false)
watch(() => props.phone, () => { realView.value = false })
// A line already known and not Sama (Revolution, PixX…): its own offers at once, by their names (owner 2026-11-01, «نفذ»);
// the board stays for a Sama line, and for a line not known yet (the discovery goes on behind it)
const knownOtherLine = computed(() => certain.value && offers.value.length > 0 &&
  offers.value.every((o) => !/^sama\b/i.test(o.family || o.label || '')))
const boardOn = computed(() => props.boardSwitch && !realView.value && !knownOtherLine.value && props.phoneOk && props.phone.startsWith('06') && automix.value.for === props.phone &&
  !shape.value && !newGroup.value)
// The line's own offer for one row: same price; Mix before other families for the mixed rows (unavailable ones too)
function realFor (kind, amount) {
  const list = offers.value.filter((o) => o.amount === amount)
  if (kind === 'net') return list.find((o) => o.category === 'internet') || null
  const bundles = list.filter((o) => o.category !== 'internet')
  if (kind === 'talk') return bundles.find((o) => /talk/i.test(o.family || o.label)) || null
  return bundles.find((o) => /mix/i.test(o.family || o.label)) || bundles[0] || null
}
// What the line surely has for a row: its offer, null = surely none, undefined = not known (send the automatic one)
const certain = computed(() => looked.value && !holding.value && !shape.value && !newGroup.value && loadedFor === props.phone)
function lineHas (kind, amount) {
  if (!certain.value) return undefined
  if (noOffers.value) return null
  const real = realFor(kind, amount)
  if (real) return real
  // Its internet menu not read yet: no «none» from a list never read
  if (kind === 'net' && internetMenu.value && !internet.value.length) return undefined
  return offers.value.length ? null : undefined
}
const board = computed(() => {
  const checking = automix.value.small === null
  const avail = (kind) => (kind === 'small' ? automix.value.small : automix.value.big) !== false
  const used = new Set()
  const rows = (kind, list) => list.filter(fits).map((a) => {
    const real = lineHas(kind, a.amount)
    if (real) used.add(real)
    const ok = !checking && avail(kind)
    const info = DETAILS[a.display] ? { label: a.display } : null
    return {
      key: kind + a.amount, kind, amount: a.amount, text: a.display, auto: a, net: kind === 'net', ok, info, real: null,
      sub: ok || checking ? (DETAILS[a.display] || '') : 'غير متاح الآن، حاول بعد دقيقة'
    }
  })
  const mix = [...rows('small', AUTO.small), ...rows('mix', AUTO.mix)]
  const talk = rows('talk', AUTO.talk)
  const net = rows('net', AUTO.net)
  const other = { key: 'other', title: 'عروض أخرى', rows: [] }
  if (certain.value) {
    other.rows = shown.value.filter((o) => !used.has(o))
      .sort((a, b) => (a.category === 'internet') - (b.category === 'internet') || byPrice(a, b))
      .map((o) => ({ key: 'x' + o.label, amount: o.amount, text: o.label, sub: [o.family, detailOf(o)].filter(Boolean).join(' · '),
        offer: o, real: o, other: true, ok: true, net: o.category === 'internet', info: detailOf(o) ? o : null }))
    if (!other.rows.length) other.note = 'لا توجد عروض أخرى لهذا الرقم.'
  } else if (error.value && !loading.value) {
    other.note = 'تعذّر التحميل الآن، حاول بعد قليل.'
  } else {
    other.note = 'جارٍ التحميل…'
    other.spin = true
  }
  return [
    { key: 'mix', title: 'Sama Mix', rows: mix },
    { key: 'talk', title: 'Sama Talk', rows: talk },
    { key: 'net', title: 'Sama Net', net: true, rows: net },
    other
  ]
})
const waiting = ref('')
const boardStatus = computed(() => {
  if (holding.value) return 'جارٍ تنفيذ العرض… النتيجة في «آخر العمليات». لا تُرسل غيره حتى ينتهي.'
  if (waiting.value) return 'جارٍ الإرسال…'
  return ''
})
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
function pick (r) {
  if (r.other) return confirm(r.offer)
  if (!r.ok || holding.value || busy.value || waiting.value || asking) return
  const p = props.phone
  const known = lineHas(r.kind, r.amount)
  const last = props.repeatOf(p, { offer: r.auto.label }) || (known ? props.repeatOf(p, { offer: known.label }) : null)
  asking = true
  // The price only (owner 2026-10-31): no network name that could differ from the row pressed
  Dialog.create({
    title: last ? 'نفس آخر عملية' : 'تأكيد العرض',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      ${r.net ? '<div style="text-align:center;margin:4px 0"><span style="background:#ECFEFF;color:#0E7490;border-radius:6px;padding:2px 8px;font-weight:700">إنترنت</span></div>' : ''}
      <div style="text-align:center">عرض <b>${money(r.amount)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>${last
        ? `<div style="margin-top:8px;padding:8px;border-radius:8px;background:#FFF3E0;color:#BF360C;text-align:center">
            آخر عملية كانت نفس العرض لنفس الرقم (${last.badge.label}).<br><b>أرسل مرة ثانية؟</b></div>`
        : ''}`,
    cancel: 'رجوع',
    ok: last ? 'نعم، أرسل مرة ثانية' : 'نعم، أرسل'
  }).onDismiss(() => { asking = false }).onOk(() => sendRow(p, r))
}
// «لا يوجد عرض…» (owner 2026-10-31): a window that goes by itself in 2–3 s; behind it the screen turns into the line's
// own offers in the ordinary look, so the change is never seen happening
function absent (r) {
  const noNet = r.kind === 'net' && !internet.value.length
  const d = Dialog.create({ message: noNet ? 'لا توجد عروض إنترنت لهذا الرقم' : 'لا يوجد عرض ' + money(r.amount) + ' لهذا الرقم', ok: 'حسنًا' })
  realView.value = true
  setTimeout(() => d.hide(), 2500)
}
let autoRow = null
async function sendRow (p, r) {
  waiting.value = r.key
  try {
    // The line not known yet: up to 5 s more, as the send's own wait (owner 2026-10-31); «Sama Talk» has no automatic
    // route, so it waits for the line (at most 30 s) and never goes blind
    const limit = r.kind === 'talk' ? 30000 : 5000
    for (const end = Date.now() + limit; lineHas(r.kind, r.amount) === undefined && (loading.value || r.kind === 'talk') && Date.now() < end && props.phone === p;) await sleep(250)
    if (props.phone !== p) return
    const has = lineHas(r.kind, r.amount)
    if (has === null) { absent(r); return }
    if (has && has.available === false) {
      Notify.create({ message: 'غير متاح الآن، حاول بعد دقيقة.', position: 'top', timeout: 3000, color: 'deep-orange' })
      return
    }
    if (!has && r.kind === 'talk') {
      Notify.create({ message: 'تعذّر الإرسال الآن، حاول بعد قليل.', position: 'top', timeout: 3000, color: 'deep-orange' })
      return
    }
    const o = has || r.auto
    const res = await run(() => props.send(p, o.label))
    if (res) {
      const auto = !has
      if (auto) { autoRow = { phone: p, kind: r.kind, amount: r.amount }; autoSent.value = p; justSent.value = true; setTimeout(() => { justSent.value = false }, 10000) }
      emit('sent', { phone: p, offer: o, result: res, auto })
    }
  } finally {
    waiting.value = ''
  }
}

// One offer at a time: a tap while one is being sent opens nothing
let asking = false
function confirm (o) {
  const p = props.phone
  if (busy.value || asking) return
  if (p !== loadedFor) { load(); return }
  const last = props.repeatOf(p, { offer: o.label })
  asking = true
  Dialog.create({
    title: last ? 'نفس آخر عملية' : 'تأكيد العرض',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      ${o.category === 'internet' ? '<div style="text-align:center;margin:4px 0"><span style="background:#ECFEFF;color:#0E7490;border-radius:6px;padding:2px 8px;font-weight:700">إنترنت فقط</span></div>' : ''}
      <div style="text-align:center${o.category === 'internet' ? ';color:#0E7490' : ''}"><b>${o.label}</b>${detailOf(o) ? ' — ' + detailOf(o) : ''}</div>
      <div style="text-align:center">السعر: <b>${money(o.amount)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>${last
        ? `<div style="margin-top:8px;padding:8px;border-radius:8px;background:#FFF3E0;color:#BF360C;text-align:center">
            آخر عملية كانت نفس العرض لنفس الرقم (${last.badge.label}).<br><b>أرسل مرة ثانية؟</b></div>`
        : ''}`,
    cancel: 'رجوع',
    ok: last ? 'نعم، أرسل مرة ثانية' : 'نعم، أرسل'
  }).onDismiss(() => { asking = false }).onOk(async () => {
    const r = await run(() => props.send(p, o.label))
    if (r) emit('sent', { phone: p, offer: o, result: r, auto: false })
  })
}
</script>

<style scoped>
.warn { background: #fff3e0; color: #8a4b00; border: 1px solid #ffb74d; }
.offer-row { border-top: 1px solid #ECEEF3; padding: 10px 14px; cursor: pointer;
  display: flex; align-items: center; justify-content: space-between; gap: 8px; text-align: right; }
:deep(.family) { font-weight: 700; }
.price { font-weight: 700; white-space: nowrap; background: var(--q-primary); color: #fff; border-radius: 8px; padding: 6px 10px;
  min-width: 88px; text-align: center; display: inline-block; }
.price.text-grey-7 { background: #E5E7EB; color: #4B5563 !important; }
.offer-row.busy { opacity: 0.5; cursor: default; }
.net-card { border-inline-start: 4px solid #0E7490; }
.net-head { display: flex; align-items: center; gap: 6px; padding: 10px 14px; font-weight: 700; color: #0E7490; }
.net-price { background: #0E7490; color: #fff; }
.blocked { border-style: dashed; }
.ask { border: 2px solid var(--brand-accent, #C2410C); padding: 12px; }
.menu-lines { background: #F6F6F6; border-radius: 8px; padding: 8px 10px; font-family: monospace; font-size: 12px; max-height: 180px; overflow: auto; }
.live { border: 2px solid #0E7490; padding: 12px; }
.board-status { padding: 10px 14px; min-height: 40px; display: flex; align-items: center; color: #5B6170; }
.board .offer-row { min-height: 60px; }
.tab-card { background: #fff; border-radius: 12px; box-shadow: 0 2px 8px rgba(30, 41, 59, 0.08); overflow: hidden; }
:deep(.tab-head) { min-height: 64px; }
:deep(.tab-head .q-item__label) { text-align: center; font-size: 1.15rem; font-weight: 600; color: #475569; }
.board { background: transparent; box-shadow: none; }
.offer-row.net { border-inline-start: 4px solid #0E7490; }
.link { background: none; border: 0; padding: 0; cursor: pointer; font: inherit; text-decoration: underline; }
.amounts { display: flex; flex-wrap: wrap; gap: 8px; }
.amounts .q-btn { min-width: 72px; min-height: 44px; }
</style>
