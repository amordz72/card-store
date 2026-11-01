<template>
  <!-- «رأس المال» (owner 2026-10-31, store v1.60 + Flexy Core 0122): his money now (cards at their cost, SIM balances),
       what it earned in the last 7 or 30 days by operator (his buy rate − the shop's share), and his buy rates. -->
  <div class="column q-gutter-sm">
    <div class="row q-gutter-xs">
      <q-btn v-for="d in [7, 30]" :key="d" rounded dense no-caps :unelevated="days === d" :outline="days !== d" color="primary"
        :label="'آخر ' + d + ' يومًا'" @click="days = d" />
    </div>

    <div class="card column q-gutter-xs">
      <div class="text-weight-bold">مالك الآن</div>
      <div class="row justify-between"><span>البطاقات ({{ cardsLeft }} بطاقة{{ suspect ? ' سليمة' : '' }} بسعر شرائها)</span><b>{{ money(cardsTotal) }}</b></div>
      <div v-for="o in simOps" :key="o.name" class="row justify-between"><span>رصيد شرائح {{ o.name }}</span><b>{{ money(o.total) }}</b></div>
      <div v-if="simError" class="small muted">{{ simError }}</div>
      <div class="row justify-between total"><span>المجموع</span><b>{{ money(cardsTotal + simTotal) }}</b></div>
      <!-- s173 (owner 2026-11-01): the suspect cards apart, out of the total, at their purchase price -->
      <div v-if="suspect && suspect.n > 0" class="row justify-between small text-deep-orange q-mt-xs">
        <span>مشكوك فيها: {{ suspect.n }} بطاقة (خارج المجموع)</span><b>{{ money(suspect.capital) }}</b></div>
    </div>

    <div class="card column q-gutter-xs">
      <div class="text-weight-bold">ربحك في آخر {{ days }} يومًا</div>
      <div v-for="r in profitRows" :key="r.key" class="column line">
        <div class="row justify-between"><span class="text-weight-bold">{{ r.name }}</span><b :class="r.net >= 0 ? 'amount-pos' : 'amount-neg'">{{ money(Math.round(r.net)) }}</b></div>
        <div class="small muted">{{ r.detail }}</div>
      </div>
      <div v-if="!profitRows.length" class="muted small">لا عمليات في هذه المدة.</div>
      <div class="row justify-between total"><span>المجموع</span><b>{{ money(Math.round(profitTotal)) }}</b></div>
      <div v-if="flexyError" class="small text-negative">{{ flexyError }}</div>
      <div class="small muted">الفليكسي: المبلغ × نسبة شرائك − رسوم موبيليس (سما) − نسبة المحل. البطاقات: ما دفعه المحل − سعر شرائها.</div>
    </div>

    <div class="card column q-gutter-xs">
      <div class="text-weight-bold">رأس المال في كل بطاقة</div>
      <div v-for="b in brands" :key="b.name" class="column line">
        <div class="row justify-between"><span class="text-weight-bold">{{ b.name }}</span><b>{{ money(b.capital) }}</b></div>
        <div v-for="p in b.items" :key="p.product_id" class="row justify-between small">
          <span>{{ p.name }} <span class="muted">· {{ p.left }} × {{ money(Math.round(p.capital / p.left)) }}</span></span><span>{{ money(p.capital) }}</span>
        </div>
      </div>
    </div>

    <div class="card column q-gutter-xs">
      <div class="text-weight-bold">نسب الشراء</div>
      <div class="small muted">ما تربحه من كل متعامل قبل نسبة المحل. التغيير يسري من الآن، والعمليات السابقة تبقى بنسبتها.</div>
      <div v-for="r in rates" :key="r.route" class="row items-center justify-between line">
        <span>{{ ROUTES[r.route] }}</span>
        <span class="row items-center q-gutter-xs">
          <b>{{ Number(r.rate) }}%</b><span v-if="Number(r.fee)" class="small">+ {{ money(Number(r.fee)) }} للعملية</span>
          <q-btn flat dense no-caps size="sm" color="primary" label="غيّر" @click="editRate(r)" />
        </span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import * as api from 'src/api/admin'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import { useRun } from 'src/composables/useRun'

const ROUTES = { arsselli: 'أرسلي (موبيليس)', sama: 'سما (عروض موبيليس)', djezzy: 'جازي', ooredoo: 'أوريدو' }
// The shops' share by the same names: Mobilis credit is Arsselli; Mobilis offers go by Sama or Arsselli (one share for both)
const { run } = useRun()
const days = ref(30)
const store = ref({ cards: [], cards_profit: [], flexy_shops: [] })
const suspect = ref(null)
const fx = ref({ rates: { now: [] }, routes: [] })
const simOps = ref([])
const flexyError = ref('')
const simError = ref('')

const num = (v) => Number(v) || 0
const cardsTotal = computed(() => store.value.cards.reduce((a, p) => a + num(p.capital), 0))
const cardsLeft = computed(() => store.value.cards.reduce((a, p) => a + num(p.left), 0))
const simTotal = computed(() => simOps.value.reduce((a, o) => a + num(o.total), 0))
const brands = computed(() => {
  const out = []
  for (const p of store.value.cards) {
    let b = out.find((x) => x.name === p.brand)
    if (!b) out.push(b = { name: p.brand, capital: 0, items: [] })
    b.capital += num(p.capital)
    b.items.push(p)
  }
  return out.sort((a, b) => b.capital - a.capital)
})
const rates = computed(() => fx.value.rates?.now || [])

// One row per flexy route (margin, owner's and shops') and one for the cards; the shops' share is taken off its operator
const profitRows = computed(() => {
  const rows = []
  const share = (op) => store.value.flexy_shops.filter((s) => s.operator === op).reduce((a, s) => a + num(s.share), 0)
  const by = (route) => fx.value.routes.filter((r) => r.route === route)
  const mobilisShare = share('mobilis')
  const mobilisRoutes = ['arsselli', 'sama'].filter((r) => by(r).length)
  for (const route of ['arsselli', 'sama', 'djezzy', 'ooredoo']) {
    const list = by(route)
    if (!list.length) continue
    const margin = list.reduce((a, r) => a + num(r.margin), 0)
    const amount = list.reduce((a, r) => a + num(r.amount), 0)
    const n = list.reduce((a, r) => a + num(r.n), 0)
    // Mobilis: the shops' share split by what each route sent for the shops
    let shops = 0
    if (route === 'djezzy' || route === 'ooredoo') shops = share(route)
    else {
      const shopAmt = (r) => by(r).filter((x) => x.who === 'shop').reduce((a, x) => a + num(x.amount), 0)
      const all = mobilisRoutes.reduce((a, r) => a + shopAmt(r), 0)
      shops = all > 0 ? mobilisShare * shopAmt(route) / all : (route === mobilisRoutes[0] ? mobilisShare : 0)
    }
    rows.push({ key: route, name: ROUTES[route], net: margin - shops,
      detail: `${n} عملية · ${money(amount)} · هامش ${money(Math.round(margin))}` + (shops ? ` − للمحلات ${money(Math.round(shops))}` : '') })
  }
  const cp = store.value.cards_profit
  if (cp.length) {
    const profit = cp.reduce((a, b) => a + num(b.profit), 0)
    rows.push({ key: 'cards', name: 'البطاقات', net: profit,
      detail: cp.map((b) => `${b.brand} ${money(num(b.profit))}`).join(' · ') })
  }
  return rows.sort((a, b) => b.net - a.net)
})
const profitTotal = computed(() => profitRows.value.reduce((a, r) => a + r.net, 0))

async function load () {
  const [s, p, m] = await Promise.all([
    api.capitalV2(days.value).catch(() => api.capital(days.value)).catch(() => null),
    flexy.ownerProfit(days.value).catch(() => null),
    flexy.ownerMonitor().catch(() => null)
  ])
  if (s) store.value = { cards: s.cards || [], cards_profit: s.cards_profit || [], flexy_shops: s.flexy_shops || [] }
  suspect.value = s?.suspect || null
  if (p?.status === 200 && p.body?.ok) { fx.value = { rates: p.body.rates || { now: [] }, routes: p.body.routes || [] }; flexyError.value = '' }
  else flexyError.value = p?.body?.error === 'MIGRATION_0122' ? 'طبّق 0122 من «ينتظر تطبيقك» ليُحسب ربح الفليكسي.' : 'تعذّر حساب ربح الفليكسي الآن.'
  if (m?.status === 200 && m.body?.ok) { simOps.value = (m.body.operators || []).map((o) => ({ name: o.name, total: num(o.total) })); simError.value = '' }
  else simError.value = 'أرصدة الشرائح غير متاحة الآن.'
}
watch(days, load)
onMounted(load)

function editRate (r) {
  const sama = r.route === 'sama'
  Dialog.create({
    title: 'نسبة شراء ' + ROUTES[r.route],
    message: sama ? 'النسبة % ثم رسوم كل عملية بالدينار، مثل: 9.5 10' : 'النسبة %، مثل: 4',
    prompt: { model: sama ? `${Number(r.rate)} ${Number(r.fee)}` : String(Number(r.rate)), type: 'text',
      isValid: (v) => /^\s*\d+(\.\d+)?(\s+\d+(\.\d+)?)?\s*$/.test(v) },
    cancel: 'رجوع',
    ok: 'حفظ'
  }).onOk(async (v) => {
    const [rate, fee] = v.trim().split(/\s+/).map(Number)
    const ok = await run(async () => {
      const res = await flexy.ownerBuyRate(r.route, rate, sama ? (fee ?? Number(r.fee)) : 0)
      if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'RATE_INVALID' ? 'نسبة غير صحيحة.' : res.body?.error || 'FLEXY_CORE')
      return true
    }, { success: 'حُفظت: تسري من الآن.' })
    if (ok) load()
  })
}
</script>

<style scoped>
.line { border-top: 1px solid #EEF0F5; padding-top: 6px; }
.total { border-top: 2px solid #C7CBD6; padding-top: 6px; font-size: 16px; }
</style>
