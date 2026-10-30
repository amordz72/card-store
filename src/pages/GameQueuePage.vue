<template>
  <q-page class="page">
    <!-- The one switch: the service is open while at least one operator is «متاح» -->
    <div class="card column q-gutter-sm">
      <div class="row items-center no-wrap q-gutter-sm">
        <div class="col">
          <div class="text-weight-bold">{{ board?.is_open ? '🟢 الشحن بالمعرّف مفتوح للزبائن' : '🔴 الشحن بالمعرّف مغلق' }}</div>
          <div class="small muted">
            {{ board?.available_names?.length ? 'متاح الآن: ' + board.available_names.join('، ') : 'لا أحد متاح الآن' }}
          </div>
        </div>
        <q-btn unelevated size="lg" :color="board?.me_available ? 'positive' : 'grey-7'" :loading="busy && switching"
          :label="board?.me_available ? 'متاح' : 'غير متاح'" :icon="board?.me_available ? 'toggle_on' : 'toggle_off'" @click="toggle" />
      </div>
      <!-- v1.49 (owner 2026-10-30): open always, the order waits in the queue (and the bell) until it is done -->
      <q-toggle v-if="session.isAdmin && alwaysOpen !== null" :model-value="alwaysOpen" label="الطلب مفتوح دائمًا (حتى وأنا غير متاح)"
        @update:model-value="setAlwaysOpen" />
      <div class="help small muted">{{ alwaysOpen ? 'يطلب الزبون في أي وقت، وينتظر طلبه هنا وفي الجرس حتى تنفّذه.' : 'اضغط «غير متاح» عند التوقف. يُغلق تلقائيًا بعد 30 دقيقة إذا أُغلق الموقع.' }}</div>
      <q-btn v-if="board?.url" outline color="primary" icon="open_in_new" label="فتح موقع الشحن" :href="board.url" target="_blank" />
    </div>

    <!-- Owner settings: which cards are topped up by player id, the site link -->
    <!-- v1.50 (owner 2026-10-30): someone asks on WhatsApp → the owner orders FOR him; his short balance becomes debt -->
    <q-expansion-item v-if="session.isAdmin" class="card q-pa-none" icon="person_add" label="اطلب شحنًا باسم زبون" header-class="text-primary text-weight-bold" @show="loadForm">
      <div class="column q-gutter-sm q-pa-md">
        <q-select v-model="form.customer" dense outlined use-input input-debounce="0" emit-value map-options :options="customerOpts"
          label="الزبون" @filter="filterCustomers" />
        <q-input v-model="form.player" dense outlined inputmode="numeric" label="ID اللاعب" input-class="ltr text-left" />
        <div class="row q-gutter-xs">
          <q-btn v-for="p in forCards" :key="p.product_id" dense no-caps :unelevated="form.product === p.product_id" :outline="form.product !== p.product_id"
            color="primary" :label="p.name" @click="form.product = p.product_id; form.units = null; forPlan = null" />
        </div>
        <div v-if="!forCards.length" class="muted small">لا بطاقة ألعاب متوفرة الآن.</div>
        <div class="row q-gutter-sm no-wrap items-start">
          <q-select v-if="splitBrands.length > 1" v-model="form.brand" dense outlined :options="splitBrands.map((b) => b.brand)" label="اللعبة" style="min-width:120px" />
          <q-input v-model.number="form.units" class="col" dense outlined type="number" inputmode="numeric" label="أو كمية (مثلًا 300)"
            @update:model-value="form.product = null; forPlan = null" />
          <q-btn outline color="primary" label="احسب" :disable="!form.customer || !(form.units > 0)" @click="previewFor" />
        </div>
        <div v-if="forPlan" class="small" :class="forPlan.ok ? '' : 'text-negative'">
          <template v-if="forPlan.ok">{{ forPlan.units }} = {{ forPlan.parts.map((x) => x.units).join(' + ') }} · السعر {{ forPlan.total }} دج</template>
          <template v-else>{{ PLAN_WHY[forPlan.reason] || forPlan.reason }}</template>
        </div>
        <div class="help small muted">يُخصم سعره من رصيده، وإن لم يكفِ يُضاف الناقص إلى دينه. ثم يظهر الطلب هنا في الانتظار.</div>
        <q-btn unelevated no-caps color="primary" icon="send" label="أرسل الطلب" :loading="busy && ordering"
          :disable="!form.customer || !(form.product || forPlan?.ok) || !/^[0-9]{5,15}$/.test(form.player.replace(/\s/g, ''))" @click="orderFor" />
      </div>
    </q-expansion-item>

    <q-expansion-item v-if="session.isAdmin" class="card q-pa-none" icon="settings" label="إعدادات الشحن بالمعرّف" @show="loadSettings">
      <div class="column q-gutter-sm q-pa-md">
        <div class="text-weight-bold">البطاقات التي تُشحن بالمعرّف</div>
        <div class="help small muted">تبقى في المتجر لمن يريد شراء الكود، وتظهر أيضًا في صفحة الشحن عند فتح الخدمة.</div>
        <q-toggle v-for="p in gameProducts" :key="p.product_id" :model-value="marked.includes(Number(p.product_id))"
          :label="`${p.brand} · ${p.name} (متوفر ${p.available})`" @update:model-value="(v) => mark(p, v)" />
        <div v-if="!gameProducts.length" class="muted">لا توجد بطاقات ألعاب في المخزن بعد.</div>
        <q-separator />
        <div class="text-weight-bold">التقسيم (كمية من عدة بطاقات)</div>
        <q-toggle v-for="b in splitBrands" :key="b.brand" :model-value="b.split" :label="`${b.brand}: يسمح بالتقسيم`"
          @update:model-value="(v) => setSplit(b, v)" />
        <div class="help small muted">لا يُعرض التقسيم إن كان ربحه أقل من البطاقة الواحدة بنفس الكمية، أو إن بيع جزء منه بأقل من سعر شرائه.</div>
        <q-separator />
        <q-input v-model="url" dense outlined label="رابط موقع الشحن (https://…)" input-class="ltr text-left" />
        <q-btn unelevated color="primary" label="حفظ الرابط" :disable="busy" @click="saveUrl" />
        <div class="help small muted">عامل الشحن: حساب زبون تفعّل له «عامل شحن الألعاب» من صفحة الزبون.</div>
      </div>
    </q-expansion-item>

    <q-tabs v-model="tab" dense align="justify" class="text-primary">
      <q-tab name="open" :label="`في الانتظار (${openRows.length})`" />
      <q-tab name="done" label="المنتهية" />
    </q-tabs>

    <template v-if="tab === 'open'">
      <div v-for="g in openRows" :key="g.game_id" class="card column q-gutter-xs" :class="{ mine: g.mine }">
        <div class="row items-center no-wrap q-gutter-sm">
          <div class="col">
            <div class="text-weight-bold">{{ g.product_name }}</div>
            <div v-if="groups[g.game_id]" class="small text-deep-orange text-weight-bold">مقسّم: {{ groups[g.game_id].units }} = {{ groups[g.game_id].names }} · جزء {{ groups[g.game_id].part }} من {{ groups[g.game_id].parts }}</div>
            <div class="small muted">{{ g.customer_name }} · {{ ago(g.created_at) }}<span v-if="g.cards_used"> · بطاقات مستعملة: {{ g.cards_used }}</span></div>
          </div>
          <q-badge :color="g.status === 'queued' ? 'grey-7' : 'info'">{{ g.status === 'queued' ? 'في الانتظار' : 'يشحنه: ' + (g.taken_by || '') }}</q-badge>
        </div>
        <div class="row items-center no-wrap q-gutter-sm">
          <span class="col player-id ltr text-left">{{ g.player_id }}</span>
          <q-btn flat dense icon="content_copy" aria-label="نسخ المعرّف" @click="copyText(g.player_id)" />
        </div>

        <q-btn v-if="g.status === 'queued'" unelevated color="primary" label="أبدأ" :disable="busy" @click="claim(g, true)" />

        <template v-else-if="g.mine">
          <div class="row items-center no-wrap q-pa-sm code-box">
            <div class="col ltr text-left">
              <div class="text-weight-bold">{{ g.code }}</div>
              <div v-if="g.serial" class="small muted">{{ g.serial }}</div>
            </div>
            <q-btn unelevated color="primary" label="نسخ الكود" @click="copyText(g.code)" />
          </div>
          <div class="grid-2">
            <q-btn unelevated color="positive" label="تمّ الشحن" :disable="busy" @click="done(g)" />
            <q-btn outline color="warning" label="البطاقة مستعملة" :disable="busy" @click="usedCard(g)" />
            <q-btn outline color="negative" label="لم يتم" :disable="busy" @click="failed(g)" />
            <q-btn flat color="grey-8" label="تراجع" :disable="busy" @click="claim(g, false)" />
          </div>
        </template>

        <q-btn v-else-if="session.isAdmin" flat dense color="grey-8" label="إرجاعه إلى الانتظار" class="self-start" :disable="busy" @click="claim(g, false)" />
      </div>
      <div v-if="!busy && !openRows.length" class="card text-center muted q-pa-lg">لا توجد طلبات في الانتظار</div>
    </template>

    <template v-else>
      <div class="card q-pa-none">
        <div v-for="g in doneRows" :key="g.game_id" class="op-row">
          <div class="row items-center no-wrap q-gutter-sm">
            <span class="col"><b>{{ g.product_name }}</b> · <bdi dir="ltr">{{ g.player_id }}</bdi></span>
            <q-badge :color="FINISHED[g.status]?.color || 'grey'">{{ FINISHED[g.status]?.label || g.status }}</q-badge>
          </div>
          <div class="small muted">
            {{ g.customer_name }} · {{ money(g.charged_amount) }} · {{ when(g.finished_at || g.created_at) }}<span v-if="g.taken_by"> · {{ g.taken_by }}</span>
          </div>
          <div v-if="g.txn_ref" class="small">رقم العملية: <bdi dir="ltr">{{ g.txn_ref }}</bdi></div>
          <div v-if="g.reason" class="small text-negative">{{ g.reason }}</div>
        </div>
        <div v-if="!busy && !doneRows.length" class="text-center muted q-pa-lg">لا توجد طلبات منتهية</div>
      </div>
      <LoadMoreBar :total="doneTotal" :shown="doneRows.length" :size="size" :loading="loadingMore" @more="more" />
    </template>
  </q-page>
</template>

<script setup>
import { onMounted, onUnmounted, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import { useSessionStore } from 'stores/session'
import { useRun } from 'src/composables/useRun'
import { useLoadMore } from 'src/composables/useLoadMore'
import { useGameAccess } from 'src/composables/useGameAccess'
import { useBell } from 'src/composables/useBell'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/customer'
import * as adminApi from 'src/api/admin'
import { newRequestId } from 'src/api/rpc'
import { money } from 'src/api/format'
import LoadMoreBar from 'components/LoadMoreBar.vue'

const session = useSessionStore()
const game = useGameAccess()
const { refreshBell } = useBell()
const { busy, run } = useRun()
const tok = () => game.opToken()

const FINISHED = {
  done: { label: 'تم الشحن', color: 'positive' },
  failed: { label: 'لم يتم — أُعيد المبلغ', color: 'orange-8' },
  cancelled: { label: 'ألغاه الزبون', color: 'grey' }
}
const when = (t) => new Date(t).toLocaleString('ar-DZ')
function ago (t) {
  const m = Math.max(0, Math.round((Date.now() - new Date(t).getTime()) / 60000))
  return m < 1 ? 'الآن' : m < 60 ? `منذ ${m} د` : `منذ ${Math.round(m / 60)} سا`
}

const tab = ref('open')
const board = ref(null)
const openRows = ref([])
const switching = ref(false)

async function loadBoard () {
  const b = await run(() => api.gameBoard(tok()))
  if (b) board.value = b
}
async function loadOpen () {
  const data = await run(() => api.gameQueue(tok(), true, 100, 0))
  if (!data) return
  // a new waiting order arrived while the page is open
  const known = new Set(openRows.value.map((g) => g.game_id))
  if (openRows.value.length && data.some((g) => g.status === 'queued' && !known.has(g.game_id))) {
    Notify.create({ type: 'info', message: 'طلب شحن جديد', icon: 'sports_esports' })
  }
  openRows.value = data
  // v1.51: the split parts (before v1.51: none)
  api.gameGroups(tok()).then((m) => { groups.value = m || {} }, () => {})
  if (session.isAdmin) refreshBell()
}
const { rows: doneRows, total: doneTotal, loadingMore, reset: resetDone, more, size } =
  useLoadMore((limit, offset) => run(() => api.gameQueue(tok(), false, limit, offset)), { key: 'game_id' })
watch(tab, (t) => { if (t === 'done') resetDone() })

async function toggle () {
  switching.value = true
  const on = !board.value?.me_available
  const r = await run(() => api.gamePresence(tok(), on))
  switching.value = false
  if (r !== undefined) await loadBoard()
}

async function claim (g, take) {
  await run(() => api.gameClaim(tok(), g.game_id, take))
  await loadOpen()
}

function done (g) {
  Dialog.create({
    title: 'تمّ الشحن',
    message: `${g.product_name} للمعرّف ${g.player_id}. رقم العملية من موقع الشحن (اختياري، يراه الزبون):`,
    prompt: { model: '', type: 'text', inputmode: 'numeric' },
    cancel: 'رجوع',
    ok: 'تمّ'
  }).onOk(async (txn) => {
    if (await run(() => api.gameFinish(tok(), g.game_id, 'done', { txnRef: txn }), { success: 'سُجّل الشحن.' })) loadOpen()
  })
}

function usedCard (g) {
  Dialog.create({
    title: 'البطاقة مستعملة',
    message: 'تُلغى هذه البطاقة (خسارة على المحل) وتظهر بطاقة أخرى من المخزن لنفس الطلب. إن لم توجد بطاقة أخرى يُعاد المبلغ للزبون.',
    cancel: 'رجوع',
    ok: 'بطاقة أخرى'
  }).onOk(async () => {
    const r = await run(() => api.gameFinish(tok(), g.game_id, 'used_card'))
    if (r === 'failed') Notify.create({ type: 'warning', message: 'لا توجد بطاقة أخرى: أُعيد المبلغ للزبون.' })
    loadOpen()
  })
}

function failed (g) {
  // step 1: the reason (owner/worker only, the customer never sees it); step 2: was the card used?
  Dialog.create({
    title: 'لم يتم الشحن',
    message: 'يُعاد المبلغ كاملًا للزبون. السبب (لا يراه الزبون):',
    prompt: { model: '', type: 'text' },
    cancel: 'رجوع',
    ok: 'التالي'
  }).onOk((reason) => {
    Dialog.create({
      title: 'البطاقة',
      message: 'هل أدخلت كود البطاقة في موقع الشحن؟',
      options: {
        type: 'radio',
        model: 'back',
        items: [
          { label: 'لا، لم أستعملها — تعود إلى المخزن', value: 'back' },
          { label: 'نعم أو لا أعرف — تبقى خارج المخزن', value: 'keep' }
        ]
      },
      cancel: 'رجوع',
      ok: 'لم يتم'
    }).onOk(async (card) => {
      if (await run(() => api.gameFinish(tok(), g.game_id, 'failed', { reason, cardBack: card === 'back' }), { success: 'أُعيد المبلغ للزبون.' })) loadOpen()
    })
  })
}

// Owner settings
const gameProducts = ref([])
const marked = ref([])
const url = ref('')
// «اطلب شحنًا باسم زبون» (v1.50)
const form = ref({ customer: null, product: null, player: '', units: null, brand: null })
const groups = ref({})
const splitBrands = ref([])
const forPlan = ref(null)
const PLAN_WHY = { NO_COMBINATION: 'لا يمكن تكوينها من البطاقات المتوفرة', SPLIT_OFF: 'اللعبة لا تسمح بالتقسيم', SPLIT_LESS_PROFIT: 'التقسيم أقل ربحًا من البطاقة الواحدة', SPLIT_NO_PROFIT: 'جزء يُباع بأقل من سعر شرائه' }
const loadSplitBrands = () => adminApi.gameBrands().then((b) => { splitBrands.value = b || []; if (!form.value.brand && b?.length) form.value.brand = b[0].brand }, () => {})
async function setSplit (b, v) {
  if (await run(() => adminApi.setGameSplit(b.brand, v).then(() => true))) loadSplitBrands()
}
async function previewFor () {
  const f = form.value
  const p = await run(() => adminApi.gameSplitPreviewFor(f.customer, f.brand || splitBrands.value[0]?.brand, Math.round(f.units)))
  if (p) forPlan.value = p
}
const allCustomers = ref([])
const customerOpts = ref([])
const forCards = ref([])
const ordering = ref(false)
let orderRequest = newRequestId()
async function loadForm () {
  loadSplitBrands()
  const [cs, stock, ids] = await Promise.all([run(() => adminApi.customers()), run(() => adminApi.stock()), run(() => adminApi.playerTopupProducts())])
  if (cs) allCustomers.value = cs.filter((c) => c.active && !c.is_shop).map((c) => ({ label: `${c.name} · …${String(c.phone).slice(-4)}`, value: c.customer_id, name: c.name }))
  customerOpts.value = allCustomers.value
  const on = (ids || []).map(Number)
  if (stock) forCards.value = stock.filter((p) => on.includes(Number(p.product_id)) && p.active && Number(p.available) > 0)
}
function filterCustomers (val, update) {
  update(() => { customerOpts.value = val ? allCustomers.value.filter((c) => c.label.includes(val)) : allCustomers.value })
}
async function orderFor () {
  const f = form.value
  const who = allCustomers.value.find((c) => c.value === f.customer)?.name || ''
  ordering.value = true
  const player = f.player.replace(/\s/g, '')
  const r = await run(() => (f.product ? adminApi.gameOrderFor(f.customer, f.product, player, orderRequest)
    : adminApi.gameOrderUnitsFor(f.customer, f.brand || splitBrands.value[0]?.brand, forPlan.value.units, player, orderRequest)),
  { success: (x) => `أُرسل طلب ${who}` + (x.debt_added > 0 ? ` · أُضيف ${x.debt_added} دج إلى دينه` : '') })
  ordering.value = false
  if (r) {
    orderRequest = newRequestId()
    form.value = { customer: null, product: null, player: '', units: null, brand: form.value.brand }
    forPlan.value = null
    loadOpen()
  }
}
const alwaysOpen = ref(null)
const loadAlwaysOpen = () => adminApi.gameAlwaysOpen().then((v) => { alwaysOpen.value = v === true }, () => {})
async function setAlwaysOpen (v) {
  const r = await run(() => adminApi.gameAlwaysOpen(v), { success: v ? 'الطلب مفتوح دائمًا.' : 'الطلب مفتوح فقط وأنت «متاح».' })
  if (r !== undefined) { alwaysOpen.value = r === true; loadBoard() }
}
async function loadSettings () {
  loadSplitBrands()
  const [stock, ids] = await Promise.all([run(() => adminApi.stock()), run(() => adminApi.playerTopupProducts())])
  if (stock) gameProducts.value = stock.filter((p) => p.category === 'game' && p.active && p.brand_active)
  if (ids) marked.value = ids.map(Number)
  url.value = board.value?.url || ''
}
async function mark (p, v) {
  if (await run(() => adminApi.setPlayerTopup(p.product_id, v).then(() => true))) loadSettings()
}
async function saveUrl () {
  if (await run(() => adminApi.setGameUrl(url.value.trim()).then(() => true), { success: 'حُفظ الرابط.' })) loadBoard()
}

// Refresh the queue every 15 s; tell the server «I am still here» every minute while the page is open
let timer = null
let tick = 0
onMounted(async () => {
  if (session.isAdmin) loadAlwaysOpen()
  await loadBoard()
  await loadOpen()
  timer = setInterval(async () => {
    // Not while hidden (the database's load, 2026-10-30)
    if (document.visibilityState !== 'visible') return
    tick++
    if (tick % 4 === 0 && board.value?.me_available) api.gamePresence(tok(), null).catch(() => {})
    await loadOpen()
    if (tick % 2 === 0) loadBoard()
  }, 15000)
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.player-id { font-size: 1.6rem; font-weight: 700; letter-spacing: 1px; }
.mine { border-color: #6366F1; }
.code-box { border: 1px dashed #A5A9F0; background: #F5F6FF; border-radius: 12px; }
.op-row { padding: 10px 14px; border-bottom: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
.op-row:last-child { border-bottom: 0; }
</style>
