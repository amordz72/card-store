<template>
  <q-page class="page">
    <q-badge :color="game.isOpen.value ? 'positive' : 'negative'" class="q-pa-sm self-start">
      {{ game.isOpen.value ? '🟢 الشحن بالمعرّف متاح الآن' : '🔴 الشحن بالمعرّف متوقف الآن' }}
    </q-badge>

    <!-- Closed: the same cards are still for sale in the store (owner decision) -->
    <div v-if="!game.isOpen.value" class="card column q-gutter-sm">
      <div>يمكنك شراء البطاقة من المتجر وشحنها بنفسك، أو العودة بعد قليل.</div>
      <q-btn unelevated color="primary" label="البطاقات في المتجر" to="/store" />
    </div>

    <template v-else>
      <div class="card column q-gutter-sm">
        <div class="player-id text-center" dir="ltr">{{ digits || '— — —' }}</div>
        <q-input v-model="playerId" dense outlined label="معرّف اللاعب (Player ID)" inputmode="numeric" maxlength="20"
          input-class="ltr text-right" :error="!!playerId && !idOk" error-message="أرقام فقط، من 5 إلى 15 رقمًا" />
        <div v-if="recent.length" class="row q-gutter-xs items-center">
          <span class="small muted">معرّفاتك السابقة:</span>
          <q-chip v-for="r in recent" :key="r" clickable dense outline color="primary" class="ltr" @click="playerId = r">{{ r }}</q-chip>
        </div>
        <div class="small muted">يُخصم ثمن البطاقة من رصيدك عند الطلب. إن لم يتم الشحن يُعاد المبلغ كاملًا.</div>
      </div>

      <div v-if="idOk" class="card column q-gutter-sm">
        <div class="text-weight-bold">اختر الكمية</div>
        <div v-if="cards.length" class="row q-col-gutter-sm">
          <div v-for="c in cards" :key="c.product_id" class="col-6">
            <q-btn unelevated color="primary" class="full-width q-py-md" :disable="busy" @click="confirmOrder(c)">
              <div class="column items-center">
                <span class="text-subtitle1 text-weight-bold">{{ c.name }}</span>
                <span class="small">{{ c.brand }} · {{ money(c.base_price) }}</span>
              </div>
            </q-btn>
          </div>
        </div>
        <div v-else class="muted">لا توجد بطاقات متوفرة للشحن الآن</div>
      </div>

      <!-- v1.51 (owner 2026-10-30): any amount from several cards (300 = 200 + 100), its price the sum of the cards -->
      <div v-if="idOk && brands.length" class="card column q-gutter-sm">
        <div class="text-weight-bold">كمية أخرى</div>
        <div v-if="brands.length > 1" class="row q-gutter-xs">
          <q-btn v-for="b in brands" :key="b" dense no-caps :unelevated="brand === b" :outline="brand !== b" color="primary" :label="b"
            @click="brand = b; plan = null" />
        </div>
        <div class="row q-gutter-sm no-wrap items-start">
          <q-input v-model.number="units" class="col" dense outlined type="number" inputmode="numeric" label="الكمية (مثلًا 300)"
            @update:model-value="plan = null" />
          <q-btn unelevated color="primary" label="احسب" :disable="!(units > 0) || busy" @click="preview" />
        </div>
        <template v-if="plan">
          <div v-if="plan.ok" class="column q-gutter-xs">
            <div><b>{{ plan.units }}</b> = {{ plan.parts.map((x) => x.units).join(' + ') }}<span v-if="plan.split" class="small muted"> ({{ plan.parts.length }} بطاقات)</span></div>
            <div>السعر: <b>{{ money(plan.total) }}</b></div>
            <q-btn unelevated color="positive" icon="bolt" label="اشحن" :disable="busy" @click="confirmUnits" />
          </div>
          <div v-else class="text-negative small">{{ PLAN_WHY[plan.reason] || 'هذه الكمية غير متاحة الآن.' }}</div>
        </template>
      </div>
    </template>

    <div class="row items-center justify-between q-mt-md">
      <div class="text-weight-bold">طلبات الشحن</div>
      <q-btn flat dense icon="refresh" aria-label="تحديث" @click="reloadAll" />
    </div>
    <div class="card q-pa-none">
      <div v-for="g in rows" :key="g.game_id" class="op-row">
        <div class="row items-center no-wrap q-gutter-sm">
          <span dir="ltr" class="text-weight-bold col">{{ g.player_id }}</span>
          <q-badge :color="view(g).color" class="q-pa-xs">{{ view(g).label }}</q-badge>
        </div>
        <div class="small muted">{{ g.product_name }} · {{ money(g.charged_amount) }} · {{ when(g.created_at) }}</div>
        <div v-if="g.txn_ref" class="small">رقم العملية: <bdi dir="ltr">{{ g.txn_ref }}</bdi></div>
        <q-btn v-if="g.status === 'queued'" flat dense size="sm" color="negative" label="إلغاء الطلب" class="self-start"
          :disable="busy" @click="cancel(g)" />
      </div>
      <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد طلبات بعد</div>
    </div>
    <LoadMoreBar :total="total" :shown="rows.length" :size="size" :loading="loadingMore" @more="more" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { Dialog } from 'quasar'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { useLoadMore } from 'src/composables/useLoadMore'
import { useGameAccess } from 'src/composables/useGameAccess'
import * as api from 'src/api/customer'
import { money } from 'src/api/format'
import LoadMoreBar from 'components/LoadMoreBar.vue'

const customer = useCustomerStore()
const buyer = useBuyer()
const game = useGameAccess()
const { busy, run } = useRun()

// What the customer sees (the reason of a failure is for the operator only)
function view (g) {
  if (g.status === 'done') return { label: 'تم الشحن', color: 'positive' }
  if (g.status === 'queued') return { label: 'في الانتظار', color: 'grey-7' }
  if (g.status === 'claimed') return { label: 'قيد الشحن', color: 'info' }
  if (g.status === 'cancelled') return { label: 'أُلغي — أُعيد المبلغ', color: 'grey' }
  if (g.status === 'failed') return { label: 'لم يتم — أُعيد المبلغ', color: 'orange-8' }
  return { label: g.status, color: 'grey' }
}

const playerId = ref('')
const digits = computed(() => playerId.value.replace(/\s/g, ''))
const idOk = computed(() => /^[0-9]{5,15}$/.test(digits.value))
const when = (t) => new Date(t).toLocaleString('ar-DZ')

// The cards the owner marked «يُشحن بالمعرّف», in stock
const catalog = ref([])
const gameIds = ref([])
const cards = computed(() => catalog.value.filter((p) => p.available && gameIds.value.includes(Number(p.product_id))))
const recent = ref([])
// «كمية أخرى» (v1.51)
const brands = computed(() => [...new Set(catalog.value.filter((p) => gameIds.value.includes(Number(p.product_id))).map((p) => p.brand))])
const brand = ref(null)
const units = ref(null)
const plan = ref(null)
const PLAN_WHY = { NO_COMBINATION: 'لا يمكن تكوين هذه الكمية من البطاقات المتوفرة الآن.', SPLIT_OFF: 'هذه اللعبة لا تقبل التقسيم: اختر كمية من البطاقات.' }
async function preview () {
  if (!brand.value) brand.value = brands.value[0]
  const p = await run(() => api.gameSplitPreview(customer.token, brand.value, Math.round(units.value)))
  if (p) plan.value = p
}
function confirmUnits () {
  const p = plan.value
  Dialog.create({
    title: 'تأكيد الشحن',
    html: true,
    message: `شحن <b>${p.units}</b> (${p.parts.map((x) => x.units).join(' + ')}) للمعرّف <b dir="ltr">${digits.value}</b><br>تأكد من المعرّف: الشحن لا يُسترجع بعد تنفيذه.<br>يُخصم من رصيدك <b>${money(p.total)}</b>.`,
    cancel: 'إلغاء',
    ok: 'نعم، اشحن'
  }).onOk(async () => {
    const r = await run(() => api.gameCreateUnits(customer.token, brand.value, p.units, digits.value, crypto.randomUUID()),
      { success: 'أُرسل الطلب. تابع حالته في «طلبات الشحن».' })
    if (r) { plan.value = null; units.value = null; buyer.refresh(); reset(); loadCards() }
  })
}

const { rows, total, loadingMore, reset, refresh, more, size } =
  useLoadMore((limit, offset) => run(() => api.gameOrders(customer.token, limit, offset)), { key: 'game_id' })
const open = computed(() => rows.value.some((g) => ['queued', 'claimed'].includes(g.status)))

async function loadCards () {
  const [cat, ids, rec] = await Promise.all([
    run(() => buyer.catalog()), run(() => api.gameCards(customer.token)), run(() => api.gameRecentIds(customer.token))
  ])
  if (cat) catalog.value = cat
  if (ids) gameIds.value = ids.map(Number)
  if (rec) recent.value = rec
}

async function reloadAll () {
  await game.refresh()
  await refresh()
}

function confirmOrder (c) {
  Dialog.create({
    title: 'تأكيد الشحن',
    html: true,
    message: `شحن <b>${c.name}</b> للمعرّف <b dir="ltr">${digits.value}</b><br>تأكد من المعرّف: الشحن لا يُسترجع بعد تنفيذه.<br>يُخصم من رصيدك ثمن البطاقة.`,
    cancel: 'إلغاء',
    ok: 'نعم، اشحن'
  }).onOk(async () => {
    const r = await run(() => api.gameCreate(customer.token, c.product_id, digits.value, crypto.randomUUID()),
      { success: 'أُرسل الطلب. تابع حالته في «طلبات الشحن».' })
    if (r) { buyer.refresh(); reset(); loadCards() }
  })
}

function cancel (g) {
  Dialog.create({ title: 'إلغاء الطلب', message: 'يُعاد المبلغ إلى رصيدك.', cancel: 'رجوع', ok: 'إلغاء الطلب' })
    .onOk(async () => {
      if (await run(() => api.gameCancel(customer.token, g.game_id).then(() => true), { success: 'أُلغي الطلب وأُعيد المبلغ.' })) {
        buyer.refresh()
        refresh()
      }
    })
}

// While an order waits or runs, follow it every 10 s (and the service state every 30 s)
let timer = null
let tick = 0
onMounted(async () => {
  await game.refresh()
  await loadCards()
  reset()
  timer = setInterval(async () => {
    // Not while hidden (the database's load, 2026-10-30)
    if (document.visibilityState !== 'visible') return
    tick++
    if (tick % 3 === 0) game.refresh()
    if (open.value) {
      const wasOpen = rows.value.filter((g) => ['queued', 'claimed'].includes(g.status)).length
      await refresh()
      // an order just finished: a refund changes the balance
      if (rows.value.filter((g) => ['queued', 'claimed'].includes(g.status)).length < wasOpen) buyer.refresh()
    }
  }, 10000)
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.player-id { font-size: 2rem; font-weight: 700; letter-spacing: 2px; }
.op-row { padding: 10px 14px; border-bottom: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
.op-row:last-child { border-bottom: 0; }
</style>
