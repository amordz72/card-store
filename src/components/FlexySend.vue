<template>
  <div class="column q-gutter-md">
    <!-- The page's own line (the shop's «الخدمة متاحة» or the owner's money switch) -->
    <slot />

    <div class="card column q-gutter-sm">
      <q-input :model-value="phone" dense outlined label="رقم الزبون" inputmode="tel" maxlength="16"
        placeholder="0X XX XX XX XX" input-class="ltr text-center phone" @update:model-value="typed">
        <template v-if="carrier" #append><span class="carrier" :class="carrier.cls">{{ carrier.name }}</span></template>
      </q-input>
    </div>

    <q-tabs v-model="tab" dense class="tabs" active-color="primary" indicator-color="primary" no-caps>
      <q-tab name="630" label="رصيد عادي" />
      <q-tab name="offer" label="عروض" />
    </q-tabs>

    <template v-if="tab === '630'">
      <!-- The amounts show once the number is whole (owner 2026-10-29, as the other app): then they are this
           operator's own (Ooredoo from 10, Mobilis 40, Djezzy 100) and do not change under the hand -->
      <div v-if="!phoneFull" class="card text-center muted q-pa-md">اكتب رقم الزبون لتظهر المبالغ.</div>
      <div v-else class="card column q-gutter-sm">
        <div class="amounts">
          <q-btn v-for="a in amounts" :key="a" dense unelevated no-caps class="chip"
            :outline="amount !== a" :color="amount === a ? 'primary' : 'grey-7'" :label="money(a)" @click="pick(a)" />
        </div>
        <q-input v-model.number="other" dense outlined type="number" inputmode="numeric"
          :label="`أو اكتب مبلغًا (${minAmount} إلى ${money(maxAmount)})`" @update:model-value="amount = null" />
      </div>
      <div v-if="note" class="small muted">{{ note }}</div>
      <q-btn unelevated color="primary" size="lg" icon="send" label="إرسال" :loading="busy"
        :disable="!canSend" @click="pressSend" />
      <div v-if="waiting" class="small muted text-center">{{ waiting }}</div>
    </template>
    <div v-else-if="!offers" class="card text-center muted q-pa-lg">العروض غير مفعّلة لحسابك.</div>
    <div v-else-if="phoneFull && !phoneOk" class="card text-center muted q-pa-lg">قريبًا: عروض هذا المتعامل غير متوفرة بعد.</div>
    <FlexyOffers v-else ref="offersRef" :phone="digits" :phone-ok="phoneOk" :active="tab === 'offer'" :max-amount="maxAmount"
      :lookup="lookup" :send="sendOffer" :available="availableOffers" :running="offerRunning" :probe="probeOffer" :decide="decideOffer" :explore="exploreOffer" :repeat-of="repeatOf" @sent="sentOffer" />

    <div>
      <div class="row items-center justify-between">
        <div class="text-weight-bold">آخر العمليات</div>
        <q-btn flat dense icon="refresh" aria-label="تحديث" :loading="refreshing" @click="emit('refresh')" />
      </div>
      <div class="card q-pa-none q-mt-sm">
        <button v-for="j in shown" :key="j.id" type="button" class="op-row" :aria-expanded="opened === j.id"
          @click="opened = opened === j.id ? null : j.id">
          <div class="row items-center no-wrap q-gutter-sm">
            <div class="col column">
              <span class="text-weight-bold">{{ j.title }}</span>
              <span class="small muted">{{ j.kind === 'offer' ? 'عرض' : 'رصيد عادي' }} · <bdi dir="ltr">{{ spaced(j.phone) }}</bdi></span>
            </div>
            <span v-if="j.running" class="row items-center no-wrap q-gutter-xs text-primary small">
              <q-spinner size="20px" /><span>جارٍ…</span>
            </span>
            <q-badge v-else :color="j.badge.color" class="q-pa-xs">{{ j.badge.label }}</q-badge>
          </div>
          <div v-if="opened === j.id" class="details column q-gutter-xs">
            <div class="small text-weight-bold">{{ j.explain || j.badge.label }}</div>
            <div class="small">أُرسلت: <bdi dir="ltr">{{ algeriaTime(j.at) }}</bdi></div>
            <div v-if="!j.running && j.doneAt && j.doneAt !== j.at" class="small">انتهت: <bdi dir="ltr">{{ algeriaTime(j.doneAt) }}</bdi></div>
            <template v-if="j.reply">
              <div class="small">رد الشبكة:</div>
              <div class="small muted ltr text-right reply">{{ j.reply }}</div>
            </template>
            <!-- The owner only: which SIM ran it, and the ones it left (owner 2026-10-26) -->
            <!-- The owner only: settle an open operation himself, with his note (Flexy Core 0057) -->
            <div v-if="settle && j.open" class="row q-gutter-xs q-mt-xs" @click.stop>
              <span class="small muted col-12">احسمها بنفسك:</span>
              <q-btn dense unelevated no-caps size="sm" color="positive" label="نجحت" @click.stop="settle(j, 'success')" />
              <q-btn dense unelevated no-caps size="sm" color="negative" label="فشلت" @click.stop="settle(j, 'failed')" />
              <q-btn dense outline no-caps size="sm" color="grey-8" label="لم تُرسل" @click.stop="settle(j, 'not_sent')" />
            </div>
            <!-- The owner only: what was offline at that minute, for a complaint (Flexy Core 0070) -->
            <div v-if="presence" class="q-mt-xs" @click.stop>
              <q-btn dense flat no-caps size="sm" color="primary" icon="history" label="ماذا كان منقطعًا وقتها" :loading="presenceBusy === j.id" @click.stop="loadPresence(j)" />
              <div v-if="presenceOf[j.id]" class="small">
                <div v-if="presenceOf[j.id].error" class="text-negative">{{ presenceOf[j.id].error }}</div>
                <template v-else>
                  <div v-if="!presenceOf[j.id].offline.length" class="text-positive">لا شيء كان منقطعًا في تلك الدقيقة.</div>
                  <div v-for="(x, i) in presenceOf[j.id].offline" :key="'o' + i" class="text-negative">
                    منقطع: {{ KIND_NAME[x.kind] }} {{ x.code }}<template v-if="x.station_code"> ({{ x.station_code }}<template v-if="x.usb != null"> · USB {{ x.usb }}</template>)</template>
                    من <bdi dir="ltr">{{ algeriaTime(x.since) }}</bdi><template v-if="x.until"> إلى <bdi dir="ltr">{{ algeriaTime(x.until) }}</bdi></template><template v-else> وما زال</template>
                  </div>
                  <div v-for="(x, i) in presenceOf[j.id].events" :key="'e' + i" class="muted">
                    <bdi dir="ltr">{{ algeriaTime(x.at) }}</bdi> · {{ KIND_NAME[x.kind] }} {{ x.code }} {{ x.state === 'online' ? 'رجع' : 'انقطع' }}
                  </div>
                </template>
              </div>
            </div>
            <template v-if="j.sims && j.sims.length">
              <div class="small">الشريحة: <bdi dir="ltr">{{ simLine(j.sims[j.sims.length - 1]) }}</bdi></div>
              <div v-for="(w, i) in j.sims.slice(0, -1)" :key="i" class="small moved">
                تحوّلت من <bdi dir="ltr">{{ simLine(w) }}</bdi>: {{ movedWhy(j.sims[i + 1].moved_because) }}
              </div>
            </template>
          </div>
        </button>
        <div v-if="!shown.length" class="text-center muted q-pa-lg">لا توجد عمليات بعد</div>
      </div>
      <q-btn v-if="hasMore" flat no-caps color="primary" label="عرض المزيد" :loading="loadingMore" @click="emit('more')" />
    </div>
  </div>
</template>

<script setup>
// One Flexy send screen for the shop's «فليكسي» and the owner's «إرسال فليكسي» (owner rule: admin and
// customer share the same pages; developer/guidelines/role-aware-labels-and-context.md). Each page passes
// its own way to the server; nothing here knows about wallets, keys or switches:
//   send(phone, amount, { wait, key }) sends one 630 credit under `key` and resolves truthy once it is
//     accepted for sending (it may call wait(text) while the server gets ready); it throws an Error with an
//     Arabic message, marked `lost` when no answer came (the request may have been taken).
//   lookup(phone) / sendOffer(phone, label, key): as FlexyOffers.
//   rows: [{ id, title, phone, kind: '630' | 'offer', amount, offer, badge: { label, color }, at, reply,
//     running, stopped, lineChanged?, explain, doneAt, sims? }], newest first. `stopped`: ended with nothing
//     sent (not_sent); `lineChanged` (owner's rows): stopped because the line's group changed. A running row shows a spinner and turns into its
//     badge in place; a tapped row says what happened (explain), in Algeria time. `sims` (the owner's page
//     only): each SIM it went to, the last one ran it (owner 2026-10-26).
//
// Two guards before money leaves (owner 2026-10-25):
//   * one key per press, kept while its answer is lost: pressing again re-asks the same request, never a
//     second send. A definite answer (sent or refused) frees it.
//   * the last operation of this shop (or of the owner) to the same number with the same amount or offer
//     asks «أرسل مرة ثانية؟» first. Nothing is blocked.
import { computed, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import FlexyOffers from 'src/components/FlexyOffers.vue'
import { algeriaTime, movedWhy, simLine } from 'src/api/flexyExplain'

// The connection log, per row opened by the owner
const KIND_NAME = { station: 'الكمبيوتر', modem: 'المودم', sim: 'الشريحة' }
const presenceOf = ref({})
const presenceBusy = ref(null)
async function loadPresence (j) {
  presenceBusy.value = j.id
  try {
    const r = await props.presence(j.at)
    presenceOf.value = { ...presenceOf.value, [j.id]: { offline: r.offline || [], events: r.events || [] } }
  } catch (e) {
    presenceOf.value = { ...presenceOf.value, [j.id]: { error: e?.message || 'تعذّرت القراءة.' } }
  } finally {
    presenceBusy.value = null
  }
}

const props = defineProps({
  open: { type: Boolean, required: true },
  maxAmount: { type: Number, required: true },
  offers: { type: Boolean, default: true },
  note: { type: String, default: '' },
  send: { type: Function, required: true },
  lookup: { type: Function, required: true },
  sendOffer: { type: Function, required: true },
  // The owner's page only: «اكشف» on an offer the index guard stops (Ooredoo, a code shown twice)
  probeOffer: { type: Function, default: null },
  exploreOffer: { type: Function, default: null },
  // The shop's page only: «أوتوميكس», which quick offers a SIM can take now (names → { name: bool })
  availableOffers: { type: Function, default: null },
  // The owner's page only: the word on a menu that matched no variant (Ooredoo «صيغ»)
  decideOffer: { type: Function, default: null },
  // The owner's page only: settle(row, to) for an open operation (row.open)
  settle: { type: Function, default: null },
  // The owner's page only: presence(at) → what was offline at that minute (the connection log)
  presence: { type: Function, default: null },
  rows: { type: Array, required: true },
  hasMore: { type: Boolean, default: false },
  loadingMore: { type: Boolean, default: false },
  refreshing: { type: Boolean, default: false },
  // Keeps the typed number on this phone under this name (owner / shop), see «The number stays» below
  remember: { type: String, default: '' },
  // Prefixes whose ordinary credit this screen may send (owner 2026-10-27: his page adds 07, Djezzy);
  // the others hear «قريبًا» on «إرسال». Offers stay Mobilis only.
  creditPrefixes: { type: Array, default: () => ['06'] },
  // Prefixes whose OFFERS this screen may show (owner 2026-10-27: his page adds 07, Djezzy LEGEND/IZZY)
  offerPrefixes: { type: Array, default: () => ['06'] }
})
const emit = defineEmits(['sent', 'refresh', 'more'])
const { busy, run } = useRun()

const tab = ref('630')
// The number stays (owner 2026-10-26): leaving the page, «تحديث الآن» or closing the browser keeps it;
// a successful send clears it, and so do 30 minutes without touching it.
const PHONE_KEEP_MS = 30 * 60_000
const phoneKey = props.remember ? 'flexy-phone:' + props.remember : ''
function keptPhone () {
  try {
    const k = JSON.parse(localStorage.getItem(phoneKey) || 'null')
    return k && typeof k.v === 'string' && Date.now() - k.at < PHONE_KEEP_MS ? k.v : ''
  } catch { return '' }
}
const phone = ref(phoneKey ? keptPhone() : '')
watch(phone, (v) => {
  if (!phoneKey) return
  try {
    if (v) localStorage.setItem(phoneKey, JSON.stringify({ v, at: Date.now() }))
    else localStorage.removeItem(phoneKey)
  } catch { /* private mode: it lives with the page only */ }
})
const amount = ref(null)
const other = ref(null)
const opened = ref(null)
const waiting = ref('')

const digits = computed(() => {
  let d = phone.value.replace(/\D/g, '')
  if (/^213\d{9}$/.test(d)) d = '0' + d.slice(3)
  return d
})
// Any Algerian mobile can be typed; only Mobilis is sent today, the others hear «قريبًا» on «إرسال»
const phoneFull = computed(() => /^0[567]\d{8}$/.test(digits.value))
const phoneOk = computed(() => phoneFull.value && props.offerPrefixes.includes(digits.value.slice(0, 2)))
const creditOk = computed(() => phoneFull.value && props.creditPrefixes.includes(digits.value.slice(0, 2)))
const CARRIERS = { 5: { name: 'Ooredoo', cls: 'ooredoo' }, 6: { name: 'Mobilis', cls: 'mobilis' }, 7: { name: 'Djezzy', cls: 'djezzy' } }
const carrier = computed(() => (/^0[567]/.test(digits.value) ? CARRIERS[digits.value[1]] : null))
// The smallest credit: Ooredoo takes 10 DA (owner 2026-10-29, Flexy Core 0066), Djezzy 100 (owner 2026-10-29), Mobilis 40
const minAmount = computed(() => (digits.value.startsWith('05') ? 10 : digits.value.startsWith('07') ? 100 : 40))
const amounts = computed(() => [...new Set([minAmount.value, 50, 100, 200, 500, 1000, 2000, 5000])]
  .filter((a) => a >= minAmount.value && a <= props.maxAmount))
const value = computed(() => amount.value || Number(other.value) || 0)
// A number of another operator: an amount under its smallest is dropped, never sent
watch(minAmount, (min) => {
  if (amount.value !== null && amount.value < min) amount.value = null
  if (other.value && Number(other.value) < min) other.value = null
})
const canSend = computed(() => props.open && phoneFull.value && value.value >= minAmount.value && value.value <= props.maxAmount)
const spaced = (d) => (d || '').replace(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/, '$1 $2 $3 $4 $5')
const when = (t) => algeriaTime(t)
function pick (a) { amount.value = a; other.value = null }

// An offer stopped because the customer's line changed group (owner 2026-10-26): nothing was bought,
// so no row in «آخر العمليات»; a short note at the top, and the number's new offers are shown.
// `lineChanged` comes with the owner's rows; for the others a stopped offer whose number's group is
// now different is the same case. The hidden rows are kept on this phone.
const offersRef = ref(null)
const HIDDEN_MAX = 50
const hiddenKey = props.remember ? 'flexy-hidden:' + props.remember : ''
function keptHidden () {
  try { return new Set(JSON.parse(localStorage.getItem(hiddenKey) || '[]')) } catch { return new Set() }
}
const hidden = ref(hiddenKey ? keptHidden() : new Set())
function hide (id) {
  hidden.value = new Set([...hidden.value, id].slice(-HIDDEN_MAX))
  if (hiddenKey) try { localStorage.setItem(hiddenKey, JSON.stringify([...hidden.value])) } catch { /* private mode */ }
}
const shown = computed(() => props.rows.filter((j) => !j.lineChanged && !hidden.value.has(j.id)))
const lastStatus = new Map()
watch(() => props.rows, async (list) => {
  for (const j of list) {
    const was = lastStatus.get(j.id)
    lastStatus.set(j.id, j.running ? 'running' : j.badge?.label)
    if (j.kind !== 'offer' || j.running || was !== 'running' || !j.stopped) continue
    const changed = j.lineChanged || (offersRef.value ? await offersRef.value.recheck(j.phone) : false)
    if (j.lineChanged && offersRef.value) await offersRef.value.recheck(j.phone)
    if (!changed) continue
    hide(j.id)
    Notify.create({ message: 'لم يُنفَّذ العرض: لهذا الرقم عروض جديدة', position: 'top', timeout: 4000, color: 'deep-orange' })
  }
}, { deep: true })

// Shown in pairs while typing (06 67 06 89 43): a wrong digit is seen before sending
function typed (v) {
  const s = String(v || '')
  phone.value = /^[\d\s]*$/.test(s) ? s.replace(/\D/g, '').slice(0, 10).replace(/(\d{2})(?=\d)/g, '$1 ') : s
}

// The key of a press whose answer was lost, per request: the same request pressed again reuses it
const lost = new Map()
async function keyed (id, fn) {
  const key = lost.get(id) || crypto.randomUUID()
  try {
    const r = await fn(key)
    lost.delete(id)
    return r
  } catch (e) {
    if (e?.lost) lost.set(id, key)
    else lost.delete(id)
    throw e
  }
}

// The last operation, when it went to the same number with the same amount (630) or the same offer
function repeatOf (p, { amount = null, offer = null }) {
  const last = props.rows[0]
  if (!last || last.phone !== p) return null
  const same = offer ? last.kind === 'offer' && last.offer === offer : last.kind !== 'offer' && Number(last.amount) === Number(amount)
  return same ? last : null
}
const repeatLine = (last) => last
  ? `<div style="margin-top:8px;padding:8px;border-radius:8px;background:#FFF3E0;color:#BF360C;text-align:center">
      آخر عملية كانت لنفس الرقم ونفس ${last.kind === 'offer' ? 'العرض' : 'المبلغ'} (${last.badge.label}، ${when(last.at)}).<br><b>أرسل مرة ثانية؟</b></div>`
  : ''

// Djezzy (07) and Ooredoo (05): the carrier confirms at once (recorded 2026-10-27); an unrecorded reply stays «قيد المراجعة»
const djezzyLine = (p) => p.startsWith('07')
  ? '<div style="margin-top:8px;padding:8px;border-radius:8px;background:#E3F2FD;color:#0D47A1;text-align:center">جيزي: التحويل فوري ونهائي عند ردّ الشبكة. ردّ غير معروف يبقى «قيد المراجعة» حتى تقرأه.</div>'
  : p.startsWith('05')
    ? '<div style="margin-top:8px;padding:8px;border-radius:8px;background:#FCE4EC;color:#880E4F;text-align:center">أوريدو: الشحن فوري ونهائي عند ردّ الشبكة برقم العملية. ردّ غير معروف يبقى «قيد المراجعة» حتى تقرأه.</div>'
    : ''

function pressSend () {
  if (!creditOk.value) return Notify.create({ message: 'قريبًا: الإرسال إلى هذا المتعامل غير متوفر بعد.', timeout: 2500 })
  if (busy.value) return
  const v = value.value
  const p = digits.value
  const last = repeatOf(p, { amount: v })
  Dialog.create({
    title: last ? 'نفس آخر عملية' : 'تأكيد الإرسال',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      <div style="text-align:center">يصل للزبون: <b>${money(v)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>${djezzyLine(p)}${repeatLine(last)}`,
    cancel: 'رجوع',
    ok: last ? 'نعم، أرسل مرة ثانية' : 'نعم، أرسل'
  }).onOk(async () => {
    const r = await run(() => keyed('630:' + p + ':' + v, (key) => props.send(p, v, { wait: (text) => { waiting.value = text }, key })))
    waiting.value = ''
    if (!r) return
    phone.value = ''
    emit('sent', r)
  })
}

const sendOffer = (p, label) => keyed('offer:' + p + ':' + label, (key) => props.sendOffer(p, label, key))
// An offer of the typed number still running (the automix screen holds until it ends)
const offerRunning = computed(() => (props.rows || []).some((j) => j.kind === 'offer' && j.running && j.phone === digits.value))
function sentOffer (e) {
  // The automix keeps the number and the offers tab while it runs (owner 2026-10-29): its result decides
  if (e.auto) { emit('sent', e); return }
  phone.value = ''
  // Back to ordinary credit, ready for the next customer (owner 2026-10-26)
  tab.value = '630'
  emit('sent', e)
}
</script>

<style scoped>
.tabs { background: #E4E6EC; border-radius: 12px; }
.amounts { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
.chip { min-height: 40px; font-weight: 700; border-radius: 10px; }
.carrier { font-size: 12px; font-weight: 700; padding: 2px 8px; border-radius: 6px; color: #fff; }
.carrier.mobilis { background: #4CAF50; }
.carrier.djezzy { background: #E53935; }
.carrier.ooredoo { background: #E30613; }
.op-row { width: 100%; border: 0; background: transparent; text-align: right; padding: 10px 14px; border-bottom: 1px solid #ECEEF3;
  display: flex; flex-direction: column; gap: 4px; font: inherit; color: inherit; cursor: pointer; }
.op-row:last-child { border-bottom: 0; }
.moved { color: #BF360C; }
.details { margin-top: 6px; padding: 8px; border: 1px solid #E4E6EC; border-radius: 8px; background: #F8F9FB; }
.reply { white-space: normal; word-break: break-word; }
:deep(.phone) { font-size: 1.4rem; letter-spacing: 1px; }
</style>
