<template>
  <q-page class="page">
    <q-btn flat dense no-caps color="primary" icon="arrow_forward" label="رجوع للزبائن" to="/customers" class="self-start" />
    <template v-if="c">
      <!-- «تعديل الحساب» (owner 2026-10-31, «نفذ تعديل الحساب بتبويبات»): everything about one account here, in tabs
           (no long page of folds); the header stays, the tab is remembered and can be opened from elsewhere (?tab=flexy) -->
      <div class="card column q-gutter-sm">
        <div class="row justify-between items-center">
          <div>
            <div class="text-h6 text-weight-bold">{{ c.name }}</div>
            <div class="small muted ltr text-right">{{ c.phone }}</div>
          </div>
          <q-badge v-if="!c.active" color="grey" label="موقوف" />
        </div>
        <div class="grid-2">
          <div class="q-pa-sm rounded-borders column" style="background:#ECFDF3"><span class="small" style="color:#166534">الرصيد</span><b class="amount-pos" style="font-size:17px">{{ money(c.balance) }}</b></div>
          <div class="q-pa-sm rounded-borders column" style="background:#F7F8FB"><span class="small">{{ debt.label }} (الحد {{ money(c.debt_limit) }})</span><b :class="debt.cls" style="font-size:17px">{{ debt.text }}</b></div>
        </div>
      </div>
      <div class="acc-tabs row no-wrap q-gutter-xs" :style="{ top: headerHeight + 'px' }">
        <q-btn v-for="t in TABS" :key="t.id" class="col" rounded no-caps dense :ripple="false" :unelevated="tab === t.id" :outline="tab !== t.id"
          :color="tab === t.id ? 'primary' : 'grey-8'" :label="t.label" :aria-pressed="tab === t.id" @click="tab = t.id" />
      </div>

      <!-- البيانات -->
      <template v-if="tab === 'info'">
        <q-form class="card column q-gutter-sm" @submit.prevent="saveInfo">
          <div class="text-weight-bold">بيانات الزبون</div>
          <q-input v-model="infoDraft.name" dense outlined label="الاسم" />
          <q-input v-model="infoDraft.phone" dense outlined label="رقم الهاتف (يدخل به)" inputmode="tel" input-class="ltr text-right"
            hint="10 أرقام يبدأ بـ 05 أو 06 أو 07، ولا يتكرر لزبونين" />
          <q-btn type="submit" outline color="primary" label="حفظ البيانات" class="self-start" :loading="busy"
            :disable="!infoDraft.name.trim() || !infoDraft.phone.trim() || (infoDraft.name.trim() === c.name && infoDraft.phone.trim() === c.phone)" />
        </q-form>
        <div class="card column q-gutter-sm">
          <q-toggle :model-value="c.active" label="الحساب مفعّل" color="positive"
            @update:model-value="(v) => save({ active: v }, v ? 'فُعّل الحساب' : 'أُوقف الحساب وأُخرج من كل الأجهزة')" />
          <!-- s169 (owner 2026-11-01): out of the lists, never deleted (orders and money stay) -->
          <q-toggle v-if="hiddenKnown" :model-value="hidden" label="مخفي من القوائم" color="grey-8" @update:model-value="setHidden" />
          <div class="row q-gutter-sm items-start">
            <q-input v-model="newPw" class="col" dense outlined label="كلمة سر جديدة (8 أحرف على الأقل)" input-class="ltr text-right" />
            <q-btn outline color="primary" label="تعيين" :disable="newPw.length < 8" @click="setPw" />
          </div>
          <q-btn outline color="primary" icon="content_copy" label="كلمة سر جديدة وانسخ بيانات الدخول" @click="newPwCopy" />
          <q-btn flat color="negative" icon="devices" label="إخراجه من كل الأجهزة" @click="revoke" />
          <q-btn flat color="warning" icon="lock_open" label="إيقاف قفل البرنامج (إن نسي رمزه)" @click="lockOff" />
        </div>
      </template>

      <!-- المال -->
      <template v-if="tab === 'money'">
        <div class="card column q-gutter-sm">
          <div class="row q-gutter-sm items-start">
            <q-input v-model.number="limitDraft" class="col" dense outlined type="number" stack-label label="حد الدين (دج)" hint="يمنع الشحن الذاتي فقط؛ لا يمنعك أنت" />
            <q-btn outline color="primary" label="حفظ" @click="save({ debtLimit: limitDraft }, 'حُفظ حد الدين')" />
          </div>
          <q-toggle :model-value="c.self_topup" label="السماح بالشحن الذاتي (للزبون الموثوق)" color="warning"
            @update:model-value="(v) => save({ selfTopup: v }, v ? 'فُعّل الشحن الذاتي' : 'أُوقف الشحن الذاتي')" />
        </div>
        <div class="card column q-gutter-sm">
          <div class="text-weight-bold">تحويل جديد</div>
          <div class="grid-3">
            <q-btn v-for="k in manualKinds" :key="k" no-caps :unelevated="kind === k" :outline="kind !== k"
              :style="kind === k ? { background: KINDS[k].color, color: '#fff' } : {}" :label="KINDS[k].label" @click="kind = k" />
          </div>
          <div class="small q-pa-sm rounded-borders" style="background:#F7F8FB">{{ KINDS[kind].label }}: {{ KINDS[kind].help }}</div>
          <q-input v-model.number="amount" dense outlined type="number" inputmode="numeric" label="المبلغ (دج)" />
          <q-input v-model="note" dense outlined label="ملاحظة (اختيارية)" placeholder="مثال: دفع في المحل" />
          <div v-if="preview" class="small q-pa-sm rounded-borders" style="border:1px dashed #A5A9F0">{{ preview }}</div>
          <q-btn unelevated color="primary" size="lg" label="تسجيل التحويل" :loading="busy" :disable="!(amount > 0)" @click="doTransfer" />
        </div>
        <div class="section-title">كشف الحساب</div>
        <div class="card q-pa-none" style="overflow:hidden">
          <EntryRow v-for="e in entries" :key="e.entry_id" :e="e" admin @reverse="openReverse(e)" />
          <div v-if="!entries.length" class="text-center muted q-pa-lg">لا توجد حركات</div>
        </div>
        <LoadMoreBar :total="total" :shown="entries.length" :size="size" :loading="loadingMore" @more="more" />
      </template>

      <!-- الفليكسي: the same values as «فليكسي المحلات» (owner 2026-10-31: «لم أجد حد مبلغ كمال») -->
      <div v-if="tab === 'flexy'" class="card column q-gutter-sm">
        <div v-if="!flexyRow" class="muted">هذا الحساب لا يظهر في الفليكسي.</div>
        <template v-else-if="fx">
          <q-toggle v-model="fx.enabled" color="positive" :disable="busy"><b>تفعيل الفليكسي</b> <span class="small muted">(رصيد عادي وعروض من رصيده)</span></q-toggle>
          <q-select v-model="fx.role" dense outlined emit-value map-options label="الدور" :options="ROLE_OPTIONS" :disable="busy" />
          <div class="row items-center q-gutter-sm no-wrap">
            <span class="text-weight-bold">أكبر مبلغ للعملية</span>
            <q-input v-model.number="fx.max" class="col" dense outlined type="number" suffix="دج" :disable="busy" />
          </div>
          <div class="small muted">العروض الأغلى من هذا المبلغ لا تظهر له.</div>
          <div class="text-weight-bold q-mt-sm">الخدمات ونسبه</div>
          <div v-for="sv in FLEXY_SERVICES" :key="sv.key" class="fx-row">
            <span class="text-weight-bold">{{ sv.name }}</span>
            <q-option-group dense inline :model-value="fx.block[sv.key] ? 'block' : 'allow'" :options="ALLOW" :disable="busy"
              @update:model-value="fx.block[sv.key] = $event === 'block'" />
            <q-input v-if="!sv.oneRate" v-model.number="fx.rate[sv.key]" dense outlined type="number" step="0.25" suffix="%" :disable="busy || fx.block[sv.key]" />
            <span v-else class="small muted">= نسبة جازي</span>
          </div>
          <div class="small muted">نسبته من كل إرسال؛ فارغ = النسبة الافتراضية. «منع» يقفل الخدمة ويحفظ النسبة جانبًا. المحل لا يرى نسبته ولا دوره.</div>
          <q-btn unelevated no-caps color="primary" label="حفظ الفليكسي" class="self-start" :loading="busy" :disable="!fxChanges.length" @click="saveFlexy" />
        </template>
      </div>

      <!-- الخدمات -->
      <div v-if="tab === 'services'" class="card column q-gutter-sm">
        <q-toggle :model-value="idoomOn" color="positive" :disable="busy" @update:model-value="setIdoom">
          <b>تعبئة إيدوم</b> <span class="small muted">(يعبّئ خطوط إيدوم من رصيده)</span>
        </q-toggle>
        <div class="row items-center q-gutter-sm q-pl-sm">
          <q-icon name="sports_esports" color="positive" size="22px" />
          <span><b>شحن الألعاب</b> <span class="small muted">(بالمعرّف: مفتوح لكل الحسابات)</span></span>
        </div>
        <q-toggle :model-value="operatorOn" color="positive" :disable="busy" @update:model-value="setOperator">
          <b>عامل شحن الألعاب</b> <span class="small muted">(يرى طلبات الشحن بالمعرّف ويضغط «متاح»)</span>
        </q-toggle>
        <div class="row items-center q-gutter-sm q-pl-sm">
          <q-icon name="bolt" :color="flexyRow?.enabled ? 'positive' : 'grey'" size="22px" />
          <span><b>فليكسي</b> <span class="small muted">({{ flexyRow?.enabled ? 'مفعّل' : 'غير مفعّل' }})</span></span>
          <q-btn flat dense no-caps color="primary" label="تبويب الفليكسي" @click="tab = 'flexy'" />
        </div>
      </div>

      <!-- الأسعار -->
      <div v-if="tab === 'prices'" class="card column q-gutter-sm">
        <div class="small muted">سعر كل بطاقة لهذا الزبون ونسبه في صفحة الأسعار، مفتوحة عليه وحده.</div>
        <q-btn unelevated no-caps color="primary" icon="sell" label="أسعار ونسب هذا الزبون" class="self-start"
          :to="{ path: '/prices', query: { who: id } }" />
      </div>
    </template>
    <q-inner-loading :showing="!c" />

    <q-dialog v-model="revOpen">
      <q-card v-if="revEntry" style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold" style="color:#155E75">{{ revTitle }}</div>
          <div class="small" style="color:#164E63">لا تُحذف الحركة الأصلية؛ تُضاف حركة معاكسة بنفس المبلغ.{{ revEntry.kind === 'purchase' ? ' وتُلغى أكواد هذا الطلب (لا تعود للبيع لأن الزبون رآها).' : '' }}</div>
          <q-input v-model="revNote" dense outlined label="السبب (اختياري)" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="إلغاء" v-close-popup />
          <q-btn unelevated color="info" label="تأكيد الاسترداد" :loading="busy" @click="doReverse" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useRun } from 'src/composables/useRun'
import { Notify } from 'quasar'
import { useLoadMore } from 'src/composables/useLoadMore'
import * as api from 'src/api/admin'
import { newRequestId } from 'src/api/rpc'
import { money, debtView, KINDS } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import LoadMoreBar from 'components/LoadMoreBar.vue'
import { easyPassword, showLoginCopy } from 'src/api/loginCopy'

const props = defineProps({ id: { type: String, required: true } })
const cid = computed(() => Number(props.id))
const { busy, run } = useRun()

const c = ref(null)
const debt = computed(() => debtView(c.value?.debt || 0, false))
const limitDraft = ref(0)
const infoDraft = ref({ name: '', phone: '' })

async function loadCustomer () {
  // all customers: a hidden one (s169) still opens here
  const list = await run(() => api.customersAll())
  c.value = list?.find((x) => Number(x.customer_id) === cid.value) || null
  if (c.value) loadHidden(cid.value)
  if (c.value) {
    limitDraft.value = Number(c.value.debt_limit)
    infoDraft.value = { name: c.value.name, phone: c.value.phone }
  }
}

const { rows: entries, total, loadingMore, reset: loadEntries, refresh: refreshEntries, more, size } =
  useLoadMore((limit, offset) => run(() => api.entries({ customerId: cid.value, limit, offset })), { key: 'entry_id' })

// «تعبئة إيدوم» for this customer: off by default, the owner turns it on for customers he trusts
const idoomOn = ref(false)
async function loadIdoom () {
  const ids = await run(() => api.idoomTopupCustomers())
  if (ids) idoomOn.value = ids.map(Number).includes(cid.value)
}
async function setIdoom (v) {
  const ok = await run(() => api.setIdoomTopup(cid.value, v).then(() => true),
    { success: v ? 'فُعّلت تعبئة إيدوم لهذا الزبون.' : 'أُوقفت تعبئة إيدوم لهذا الزبون.' })
  if (ok) idoomOn.value = v
}

// «عامل شحن الألعاب»: this account works the game top-up queue with the owner (v1.25)
const operatorOn = ref(false)
async function loadOperator () {
  const ids = await run(() => api.gameOperators())
  if (ids) operatorOn.value = ids.map(Number).includes(cid.value)
}
async function setOperator (v) {
  const ok = await run(() => api.setGameOperator(cid.value, v).then(() => true),
    { success: v ? 'أصبح عامل شحن الألعاب.' : 'لم يعد عامل شحن الألعاب.' })
  if (ok) operatorOn.value = v
}

// Tabs (owner 2026-10-31): the one opened from elsewhere (?tab=flexy), else the last one on this phone
const TABS = [{ id: 'info', label: 'البيانات' }, { id: 'money', label: 'المال' }, { id: 'flexy', label: 'الفليكسي' }, { id: 'services', label: 'الخدمات' }, { id: 'prices', label: 'الأسعار' }]
const TAB_KEY = 'customer-tab'
const route = useRoute()
function firstTab () {
  if (TABS.some((t) => t.id === route.query.tab)) return route.query.tab
  try { const t = localStorage.getItem(TAB_KEY); if (TABS.some((x) => x.id === t)) return t } catch { /* private mode */ }
  return 'money'
}
const tab = ref(firstTab())
// Under the header while scrolling (as «المخزون»)
const headerHeight = ref(0)
const measureHeader = () => { headerHeight.value = document.querySelector('.q-header')?.offsetHeight || 0 }
onMounted(measureHeader)
watch(tab, (t) => { try { localStorage.setItem(TAB_KEY, t) } catch { /* private mode */ } })

// «فليكسي» of this account: the same store function and values as «فليكسي المحلات» (one «حفظ», only what changed)
const FLEXY_SERVICES = [
  { key: 'mobilis', name: 'موبيليس', rate: 'rate_630', block: 'block_630' },
  { key: 'offer', name: 'عروض', rate: 'rate_offer', block: 'block_offer' },
  { key: 'ooredoo', name: 'أوريدو', rate: 'rate_630_ooredoo', block: 'block_ooredoo' },
  { key: 'djezzy', name: 'جازي', rate: 'rate_630_djezzy', block: 'block_djezzy' },
  { key: 'offer_ooredoo', name: 'عروض أوريدو', rate: 'rate_offer_ooredoo', block: 'block_offer_ooredoo' },
  // s188: Djezzy has one rate (owner 2026-11-01): its offers take the ordinary Djezzy rate; only «منع» here
  { key: 'offer_djezzy', name: 'عروض جازي (بنسبة جازي)', rate: 'rate_offer_djezzy', block: 'block_offer_djezzy', oneRate: true }
]
const ROLE_OPTIONS = [{ label: 'تاجر', value: 'trader' }, { label: 'تاجر الجملة', value: 'wholesale' }]
const ALLOW = [{ label: 'سماح', value: 'allow' }, { label: 'منع', value: 'block' }]
const flexyRow = ref(null)
const fx = ref(null)
const rateNum = (v) => (v === null || v === undefined || v === '' ? null : Number(v))
function fxFrom (r) {
  return {
    enabled: r.enabled === true, role: r.role ?? null, max: rateNum(r.max_amount),
    rate: Object.fromEntries(FLEXY_SERVICES.map((sv) => [sv.key, rateNum(r[sv.rate])])),
    block: Object.fromEntries(FLEXY_SERVICES.map((sv) => [sv.key, r[sv.block] === true]))
  }
}
async function loadFlexy () {
  const rows = await api.flexyCustomers().catch(() => null)
  flexyRow.value = (rows || []).find((x) => Number(x.customer_id) === cid.value) || null
  fx.value = flexyRow.value ? fxFrom(flexyRow.value) : null
}
// Enabled first (it may fill default rates), then the explicit values on top
const fxChanges = computed(() => {
  const f = fx.value
  const o = flexyRow.value ? fxFrom(flexyRow.value) : null
  if (!f || !o) return []
  const out = []
  if (f.enabled !== o.enabled) out.push({ enabled: f.enabled })
  if (f.role !== o.role && f.role) out.push({ role: f.role })
  for (const sv of FLEXY_SERVICES) {
    if (f.block[sv.key] !== o.block[sv.key]) out.push({ service: sv.key, block: f.block[sv.key] })
    if (!sv.oneRate && rateNum(f.rate[sv.key]) !== o.rate[sv.key]) out.push({ service: sv.key, rate: rateNum(f.rate[sv.key]) })
  }
  if (rateNum(f.max) !== null && rateNum(f.max) !== o.max) out.push({ max: rateNum(f.max) })
  return out
})
async function saveFlexy () {
  const list = fxChanges.value
  const bad = list.find((x) => (x.rate != null && (x.rate < 0 || x.rate >= 100)) || (x.max != null && x.max < 10))
  if (bad) { Notify.create({ type: 'negative', message: bad.rate != null ? 'النسبة بين 0 وأقل من 100.' : 'أكبر مبلغ 10 دج على الأقل.' }); return }
  await run(async () => {
    for (const ch of list) await api.flexyBulk([cid.value], ch)
    return true
  }, { success: 'حُفظ الفليكسي.' })
  loadFlexy()
}

async function reloadAll () {
  loadFlexy()
  loadIdoom()
  loadOperator()
  await loadCustomer()
  await loadEntries()
}
onMounted(reloadAll)

// --- transfers
const manualKinds = ['debt', 'cash', 'pay', 'debt_refund', 'cash_refund', 'pay_refund']
const EFFECT = { debt: [1, 1], debt_refund: [-1, -1], cash: [1, 0], cash_refund: [-1, 0], pay: [0, -1], pay_refund: [0, 1] }
const kind = ref('debt')
const amount = ref(null)
const note = ref('')
let transferRequest = null
watch([kind, amount, note], () => { transferRequest = null })

const preview = computed(() => {
  if (!c.value || !(amount.value > 0)) return ''
  const [b, d] = EFFECT[kind.value]
  const nb = Number(c.value.balance) + b * amount.value
  const nd = Number(c.value.debt) + d * amount.value
  const dv = debtView(nd, false)
  let s = `بعد التسجيل: الرصيد ${money(nb)}${nb < 0 ? ' (غير مسموح)' : ''} · ${dv.label} ${dv.text}`
  if (d > 0 && nd > Number(c.value.debt_limit)) s += ` — تنبيه: فوق حد الدين (${money(c.value.debt_limit)})، مسموح لك كمدير`
  return s
})

async function doTransfer () {
  transferRequest = transferRequest || newRequestId()
  const res = await run(() => api.transfer(cid.value, kind.value, amount.value, note.value, transferRequest),
    { success: (r) => `سُجّل: ${KINDS[kind.value].label} ${money(amount.value)}${r.over_limit ? ' — فوق حد الدين' : ''}` })
  if (!res) return
  amount.value = null
  note.value = ''
  transferRequest = null
  await reloadAll()
}

// --- reverse
const revOpen = ref(false)
const revEntry = ref(null)
const revNote = ref('')
let reverseRequest = null
const revTitle = computed(() => revEntry.value ? `استرداد: ${KINDS[revEntry.value.kind].label} ${money(revEntry.value.amount)}` : '')

function openReverse (e) {
  revEntry.value = e
  revNote.value = ''
  reverseRequest = newRequestId()
  revOpen.value = true
}

async function doReverse () {
  const res = await run(() => api.reverse(revEntry.value.entry_id, revNote.value, reverseRequest), { success: 'تم الاسترداد.' })
  if (!res) return
  revOpen.value = false
  await loadCustomer()
  await refreshEntries()
}

// --- settings
const hidden = ref(false)
const hiddenKnown = ref(false)
async function loadHidden (id) {
  try {
    const ids = await api.hiddenCustomers()
    hidden.value = (ids || []).map(Number).includes(Number(id))
    // the function exists once s169 is applied: probe it by asking for the list
    hiddenKnown.value = await api.customerHide(-1, false).then(() => true, (e) => !/Could not find the function|does not exist/.test(String(e?.raw?.message || e?.message || '')))
  } catch { hiddenKnown.value = false }
}
async function setHidden (v) {
  const r = await run(() => api.customerHide(c.value.customer_id ?? c.value.id, v), { success: v ? 'أُخفي من القوائم.' : 'رجع إلى القوائم.' })
  if (r !== undefined) hidden.value = v
}
async function save (patch, msg) {
  const ok = await run(() => api.updateCustomer(cid.value, patch).then(() => true), { success: msg })
  if (ok) loadCustomer()
}

// name and phone; the database rejects a phone already used by another customer
function saveInfo () {
  save({ name: infoDraft.value.name.trim(), phone: infoDraft.value.phone.trim() }, 'حُفظت بيانات الزبون.')
}

const newPw = ref('')
async function setPw () {
  const ok = await run(() => api.setPassword(cid.value, newPw.value).then(() => true),
    { success: 'تم تعيين كلمة السر وأُخرج الزبون من كل الأجهزة.' })
  if (ok) newPw.value = ''
}

// «انسخ بيانات الدخول» (owner 2026-10-30): the old password cannot be read (hashed), so a new one, then the message
async function newPwCopy () {
  const pw = easyPassword()
  const ok = await run(() => api.setPassword(cid.value, pw).then(() => true))
  if (ok) showLoginCopy(c.value.name, c.value.phone, pw)
}

function lockOff () {
  run(() => api.customerLockOff(cid.value), { success: (had) => (had ? 'أُوقف قفل البرنامج لهذا الزبون.' : 'لم يكن القفل مفعّلًا عنده.') })
}

function revoke () {
  run(() => api.revokeSessions(cid.value), { success: (n) => `أُلغيت ${n} جلسة.` })
}
</script>

<style scoped>
.acc-tabs { position: sticky; z-index: 5; background: #F4F5F8; padding: 6px 0; }
.fx-row { display: grid; grid-template-columns: 72px 1fr 92px; gap: 6px; align-items: center; }
</style>
