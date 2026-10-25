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
      <div class="card column q-gutter-sm">
        <div class="amounts">
          <q-btn v-for="a in amounts" :key="a" dense unelevated no-caps class="chip"
            :outline="amount !== a" :color="amount === a ? 'primary' : 'grey-7'" :label="money(a)" @click="pick(a)" />
        </div>
        <q-input v-model.number="other" dense outlined type="number" inputmode="numeric"
          :label="`أو اكتب مبلغًا (40 إلى ${money(maxAmount)})`" @update:model-value="amount = null" />
      </div>
      <div v-if="note" class="small muted">{{ note }}</div>
      <q-btn unelevated color="primary" size="lg" icon="send" label="إرسال" :loading="busy"
        :disable="!canSend" @click="pressSend" />
      <div v-if="waiting" class="small muted text-center">{{ waiting }}</div>
    </template>
    <div v-else-if="!offers" class="card text-center muted q-pa-lg">العروض غير مفعّلة لحسابك.</div>
    <div v-else-if="phoneFull && !phoneOk" class="card text-center muted q-pa-lg">قريبًا: عروض هذا المتعامل غير متوفرة بعد.</div>
    <FlexyOffers v-else :phone="digits" :phone-ok="phoneOk" :active="tab === 'offer'" :max-amount="maxAmount"
      :lookup="lookup" :send="sendOffer" :repeat-of="repeatOf" @sent="sentOffer" />

    <div>
      <div class="row items-center justify-between">
        <div class="text-weight-bold">آخر العمليات</div>
        <q-btn flat dense icon="refresh" aria-label="تحديث" :loading="refreshing" @click="emit('refresh')" />
      </div>
      <div class="card q-pa-none q-mt-sm">
        <button v-for="j in rows" :key="j.id" type="button" class="op-row" :aria-expanded="opened === j.id"
          @click="opened = opened === j.id ? null : j.id">
          <div class="row items-center no-wrap q-gutter-sm">
            <span class="col text-weight-bold">{{ j.title }}</span>
            <q-badge :color="j.badge.color" class="q-pa-xs">{{ j.badge.label }}</q-badge>
          </div>
          <div class="small muted ltr text-right">{{ spaced(j.phone) }}</div>
          <div v-if="opened === j.id" class="details column q-gutter-xs">
            <div class="small">التاريخ: <bdi dir="ltr">{{ when(j.at) }}</bdi></div>
            <div class="small">رد الشبكة:</div>
            <div class="small muted ltr text-right reply">{{ j.reply || '—' }}</div>
          </div>
        </button>
        <div v-if="!rows.length" class="text-center muted q-pa-lg">لا توجد عمليات بعد</div>
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
//   rows: [{ id, title, phone, kind: '630' | 'offer', amount, offer, badge: { label, color }, at, reply }], newest first.
//
// Two guards before money leaves (owner 2026-10-25):
//   * one key per press, kept while its answer is lost: pressing again re-asks the same request, never a
//     second send. A definite answer (sent or refused) frees it.
//   * the last operation of this shop (or of the owner) to the same number with the same amount or offer
//     asks «أرسل مرة ثانية؟» first. Nothing is blocked.
import { computed, ref } from 'vue'
import { Dialog, Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import FlexyOffers from 'src/components/FlexyOffers.vue'

const props = defineProps({
  open: { type: Boolean, required: true },
  maxAmount: { type: Number, required: true },
  offers: { type: Boolean, default: true },
  note: { type: String, default: '' },
  send: { type: Function, required: true },
  lookup: { type: Function, required: true },
  sendOffer: { type: Function, required: true },
  rows: { type: Array, required: true },
  hasMore: { type: Boolean, default: false },
  loadingMore: { type: Boolean, default: false },
  refreshing: { type: Boolean, default: false }
})
const emit = defineEmits(['sent', 'refresh', 'more'])
const { busy, run } = useRun()

const tab = ref('630')
const phone = ref('')
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
const phoneOk = computed(() => /^06\d{8}$/.test(digits.value))
const CARRIERS = { 5: { name: 'Ooredoo', cls: 'ooredoo' }, 6: { name: 'Mobilis', cls: 'mobilis' }, 7: { name: 'Djezzy', cls: 'djezzy' } }
const carrier = computed(() => (/^0[567]/.test(digits.value) ? CARRIERS[digits.value[1]] : null))
const amounts = computed(() => [40, 50, 100, 200, 500, 1000, 2000, 5000].filter((a) => a <= props.maxAmount))
const value = computed(() => amount.value || Number(other.value) || 0)
const canSend = computed(() => props.open && phoneFull.value && value.value >= 40 && value.value <= props.maxAmount)
const spaced = (d) => (d || '').replace(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/, '$1 $2 $3 $4 $5')
const when = (t) => new Date(t).toLocaleString('ar-DZ')
function pick (a) { amount.value = a; other.value = null }

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

function pressSend () {
  if (!phoneOk.value) return Notify.create({ message: 'قريبًا: الإرسال إلى هذا المتعامل غير متوفر بعد.', timeout: 2500 })
  if (busy.value) return
  const v = value.value
  const p = digits.value
  const last = repeatOf(p, { amount: v })
  Dialog.create({
    title: last ? 'نفس آخر عملية' : 'تأكيد الإرسال',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      <div style="text-align:center">يصل للزبون: <b>${money(v)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>${repeatLine(last)}`,
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
function sentOffer (e) {
  phone.value = ''
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
.details { margin-top: 6px; padding: 8px; border: 1px solid #E4E6EC; border-radius: 8px; background: #F8F9FB; }
.reply { white-space: normal; word-break: break-word; }
:deep(.phone) { font-size: 1.4rem; letter-spacing: 1px; }
</style>
