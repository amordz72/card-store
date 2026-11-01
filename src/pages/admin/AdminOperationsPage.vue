<template>
  <q-page class="page">
    <OpsFilters v-model="f" scopes feeds :customers="customers" />
    <div class="card q-pa-none" style="overflow:hidden">
      <OperationRow v-for="op in rows" :key="op.key" :op="withSims(op)" admin @open="openCodes(op)" />
      <div v-if="!loading && !rows.length" class="text-center muted q-pa-lg">لا توجد عمليات</div>
    </div>
    <div v-if="coreFailed" class="text-center small text-deep-orange q-pa-sm">تعذّرت قراءة عمليات الفليكسي الخاصة بك من النواة الآن.</div>
    <LoadMoreBar :total="total" :shown="rows.length" :size="size" :has-more="hasMore" :loading="loadingMore" @more="more" />
    <q-inner-loading :showing="loading" />
    <CodesDialog v-model="codesOpen" :title="codesTitle" :subtitle="codesSub" :codes="codes" :order-id="lastOrderId"
      :mark-copied="markCopied" />
  </q-page>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import { useOpsFeed, offsetSource } from 'src/composables/useOpsFeed'
import { useSavedFilter, rangeDates } from 'src/composables/useSavedFilter'
import { copyText } from 'src/composables/useCopy'
import { askCardFailed } from 'src/composables/useCardFailed'
import * as api from 'src/api/admin'
import * as flexy from 'src/api/flexy'
import OpsFilters from 'components/OpsFilters.vue'
import OperationRow from 'components/OperationRow.vue'
import LoadMoreBar from 'components/LoadMoreBar.vue'
import CodesDialog from 'components/CodesDialog.vue'

const { run } = useRun()
const customers = ref([])
// One list like Hani Rohek (owner 2026-10-26): «الكل/أنا/زبائني»، النوع، الزبون، التاريخ، kept as last left
const f = useSavedFilter('card-store:ops-filter:admin',
  { scope: 'shop', customerId: null, type: null, range: 'all', from: '', to: '', query: '' }, { skip: ['query'] })

const cardKey = (r) => ({ ...r, key: r.source + ':' + r.op_id })
const dbSource = () => offsetSource((limit, offset) => run(() => api.ops({ ...f.value, ...rangeDates(f.value), limit, offset })), cardKey)

// The owner's own Flexy sends live in Flexy Core («إرسال فليكسي»): read page by page and filtered
// here by type, dates and search, since that list has no filters of its own.
const OFFER_KEYS = ['mobilis.sama.offer.665', 'mobilis.arsselli.offer.696', 'djezzy.flexy.offer.760', 'ooredoo.flexy.offer.585']
// The carrier by the number (owner 2026-10-29: an Ooredoo offer showed «Mobilis»)
const BRAND = { '05': 'Ooredoo', '06': 'Mobilis', '07': 'Djezzy' }
const coreFailed = ref(false)
function coreSource () {
  const { from, to } = rangeDates(f.value)
  const day = (t) => new Date(t).toLocaleDateString('en-CA', { timeZone: 'Africa/Algiers' })
  const q = (f.value.query || '').trim()
  const keep = (o) => (!f.value.type || f.value.type === o.category) && (!to || day(o.created_at) <= to) &&
    (!q || (o.phone || '').includes(q) || (o.offer_label || '').toLowerCase().includes(q.toLowerCase()))
  return async (limit, before) => {
    const n = Math.min(limit, 50)
    const res = await flexy.ownerOperations(n, before).catch(() => null)
    if (!res || res.status !== 200) { coreFailed.value = true; return undefined }
    const list = res.body.operations || []
    const last = list[list.length - 1]
    const older = from && last && day(last.created_at) < from
    const rows = list.filter((o) => !from || day(o.created_at) >= from).map((o) => ({
      key: 'core:' + o.idempotency_key, source: 'core', op_id: o.idempotency_key, brand: BRAND[(o.phone || '').slice(0, 2)] || 'Mobilis', is_shop: true,
      category: OFFER_KEYS.includes(o.operation_key) ? 'offer' : 'flexy', offer_label: o.offer, phone: o.phone,
      base_amount: o.amount, status: o.status, network_reply: o.network_reply, outcome_code: o.outcome_code,
      sims: o.sims || [], balance_before: o.balance_before || null, created_at: o.created_at
    })).filter(keep)
    return { rows, state: last?.created_at ?? before, done: list.length < n || Boolean(older) }
  }
}

// «تغذية الشرائح» (s186, owner 2026-11-01): which SIM, the card, the state and the network's reply. Shown under
// «الكل» (the owner's own scope) and under its own chip; filtered here by dates and search, like Flexy Core's list.
function feedSource () {
  const { from, to } = rangeDates(f.value)
  const day = (t) => new Date(t).toLocaleDateString('en-CA', { timeZone: 'Africa/Algiers' })
  const q = (f.value.query || '').trim().toLowerCase()
  return async (limit, before) => {
    const n = Math.min(limit, 50)
    const list = await api.simFeeds(n, before).catch(() => null)
    if (!list) return undefined
    const last = list[list.length - 1]
    const older = from && last && day(last.queued_at) < from
    const rows = list.filter((x) => (!from || day(x.queued_at) >= from) && (!to || day(x.queued_at) <= to) &&
      (!q || [x.sim_label, x.sim_code, x.card_supplier].some((v) => String(v || '').toLowerCase().includes(q))))
      .map((x) => ({ ...x, key: 'feed:' + x.feed_id, source: 'feed', kind: 'feed', op_id: x.feed_id, brand: 'Sama',
        base_amount: x.card_face, network_reply: x.reply, created_at: x.queued_at }))
    return { rows, state: last?.feed_id ?? before, done: list.length < n || Boolean(older) }
  }
}

function sources () {
  coreFailed.value = false
  const v = f.value
  if (v.type === 'feed') return [feedSource()]
  const withCore = v.scope !== 'customers' && !v.customerId && (!v.type || v.type === 'flexy' || v.type === 'offer')
  const withFeeds = v.scope !== 'customers' && !v.customerId && !v.type
  return [dbSource(), ...(withCore ? [coreSource()] : []), ...(withFeeds ? [feedSource()] : [])]
}
const { rows, total, hasMore, loading, loadingMore, reset, more, size } = useOpsFeed(sources, { size: 20 })
// The SIM that ran each shop Flexy row (owner 2026-10-26, SHOP-OPS-SIM-AND-BALANCE step 1): the rows'
// keys from the store, then Flexy Core says each one's SIMs. Read once per row; a failure leaves it out.
const simsOf = ref({})
const withSims = (op) => (op.source === 'flexy' && simsOf.value[op.op_id]
  ? { ...op, sims: simsOf.value[op.op_id].sims, outcome_code: simsOf.value[op.op_id].outcome_code, balance_before: simsOf.value[op.op_id].balance_before }
  : op)
watch(rows, async (list) => {
  const ids = list.filter((r) => r.source === 'flexy' && !(r.op_id in simsOf.value)).map((r) => r.op_id).slice(0, 50)
  if (!ids.length) return
  for (const id of ids) simsOf.value[id] = null
  const keys = await api.flexyKeys(ids).catch(() => [])
  if (!keys?.length) return
  const res = await flexy.ownerAppOperations('card-store', keys.map((k) => k.core_key)).catch(() => null)
  if (res?.status !== 200) return
  const byKey = new Map((res.body.operations || []).map((o) => [o.idempotency_key, o]))
  for (const k of keys) if (byKey.has(k.core_key)) simsOf.value[k.job_id] = byKey.get(k.core_key)
})

// «أنا» are the owner's own operations, so a customer filter makes no sense there
watch(() => f.value.scope, (s) => { if (s === 'shop') f.value.customerId = null })
watch(f, () => reset(), { deep: true })
onMounted(async () => {
  customers.value = (await run(() => api.customers())) || []
  // a saved customer that no longer exists is dropped
  if (f.value.customerId && !customers.value.some((c) => c.customer_id === f.value.customerId)) f.value.customerId = null
  reset()
})

// Codes are masked for the admin; each reveal is logged in the database
const lastOrderId = ref(null)
const codesOpen = ref(false)
const codes = ref([])
const codesTitle = ref('')
const codesSub = ref('')
// The owner saves copies of the shop's own cards only; a customer's copy is shown, never set, here
const markCopied = ref(null)

function codeItem (c, copiedAt) {
  return {
    badge: copiedAt ? { label: 'نسخها الزبون', color: 'grey-7' } : null,
    code: c.masked_code,
    serial: c.serial,
    status: c.status,
    actionLabel: 'كشف',
    action: async () => {
      const full = await run(() => api.revealCode(c.code_id))
      if (!full) return
      const i = codes.value.findIndex((x) => x.id === c.code_id)
      codes.value[i] = { ...codes.value[i], code: full, actionLabel: 'نسخ', action: () => copyText(full) }
    },
    id: c.code_id
  }
}

async function openCodes (op) {
  lastOrderId.value = op.op_id
  const [data, copies] = await Promise.all([
    run(() => api.orderCodes(op.op_id)),
    api.orderCopies(op.op_id).catch(() => [])
  ])
  if (!data) return
  const copiedAt = new Map(copies.map((x) => [x.code_id, x.copied_at]))
  markCopied.value = op.is_shop ? api.markCopied : null
  const refunded = op.status !== 'done'
  codesTitle.value = refunded ? 'عملية مسترجعة' : 'أكواد العملية'
  codesSub.value = `${op.product_name} × ${op.qty} · رقم ${op.op_id}` + (op.is_shop ? ' — من حساب المحل' : ' — الأكواد مخفية؛ «كشف» يُسجَّل')
  // the shop's own codes come back in full; customers' codes are masked with a logged reveal
  codes.value = op.is_shop
    ? data.map((c) => ({ id: c.code_id, code: c.masked_code, serial: c.serial, status: c.status, copiedAt: copiedAt.get(c.code_id) || null, actionLabel: 'نسخ', action: refunded ? null : () => copyText(c.masked_code),
        help: !refunded && c.status === 'sold' ? () => askCardFailed(run, { id: c.code_id, code: c.masked_code }, () => openCodes(op)) : null,
        helpLabel: 'لم تعمل' }))
    : data.map((c) => codeItem(c, copiedAt.get(c.code_id)))
  codesOpen.value = true
}
</script>
