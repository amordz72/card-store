<template>
  <!-- «لوحة المراقبة» (owner 2026-11-01: «لوحة كاملة لمراقبة الشرائح والسيرفرات»): every computer and phone as a tile with
       its SIMs inside, what needs him now, and the cards running out. One screen, refreshed every 20 s. -->
  <q-page class="q-pa-md column q-gutter-md watch-page">
    <div class="row items-center q-gutter-sm">
      <div class="text-h6 col">لوحة المراقبة</div>
      <span class="small muted">{{ w.at.value ? 'حُدّثت ' + clock(w.at.value) : '' }}</span>
      <q-btn flat round dense icon="refresh" :loading="w.loading.value" aria-label="تحديث" @click="w.load" />
    </div>
    <div v-if="w.speed.value?.level" class="small text-weight-bold" :class="w.speed.value.level === 'server' ? 'text-deep-orange-9' : 'text-blue-grey-8'">
      {{ w.speed.value.level === 'server' ? '🐢 الخادم بطيء الآن (القاعدة ترد في ' + (w.speed.value.db / 1000).toFixed(1) + ' ث والموقع سريع): ليس إنترنتك' : '📶 الإنترنت عندك بطيء الآن (الموقع والقاعدة كلاهما بطيء)' }}</div>
    <div v-if="w.error.value" class="small text-negative">تعذّرت القراءة الآن ({{ w.error.value }}): تُعرض آخر حالة.</div>

    <!-- The numbers -->
    <div class="kpis">
      <div class="kpi"><div class="n">{{ w.counts.value.pcOn }}<span>/{{ w.counts.value.pcAll }}</span></div><div>💻 متصل</div></div>
      <div class="kpi"><div class="n">{{ w.counts.value.simReady }}<span>/{{ w.counts.value.simAll }}</span></div><div>📶 جاهزة</div></div>
      <div class="kpi" :class="{ bad: w.counts.value.lowBal }"><div class="n">{{ w.counts.value.lowBal }}</div><div>💰 تحت الحد</div></div>
      <div class="kpi" :class="{ bad: w.counts.value.lowStock }"><div class="n">{{ w.counts.value.lowStock }}</div><div>🃏 تنفد</div></div>
    </div>
    <div v-if="w.counts.value.byType.length" class="bytype">
      <span v-for="x in w.counts.value.byType" :key="x.t" class="chip" :class="{ bad: x.ready < x.all }">
        {{ x.name }} <b>{{ x.ready }}/{{ x.all }}</b><template v-if="x.low"> · 💰{{ x.low }}</template></span>
    </div>

    <div class="layout">
      <!-- The devices -->
      <div class="tiles">
        <div v-for="s in w.stations.value" :key="s.st.station_uuid" class="tile" :class="{ off: s.off }">
          <div class="tile-head">
            <span class="dot" :class="s.off ? 'red' : 'green'"></span>
            <span class="big">{{ s.phone ? '📱' : '💻' }}</span>
            <span class="no" :class="{ struck: s.off }">{{ stNo(s.st) }}</span>
            <span class="small" :class="s.off ? 'text-negative' : 'text-positive'">{{ s.off ? 'مطفأ' : 'متصل' }}</span>
            <q-space />
            <span class="tiny muted">{{ s.sims.length ? s.sims.length + ' شريحة' : 'لا شريحة' }}</span>
          </div>
          <button v-for="x in s.sims" :key="x.sim.sim_uuid" type="button" class="chip" :class="[x.ready ? 'ok' : 'bad', { picked: picked === x.sim.sim_uuid }]"
            @click="pick(x)">
            <span class="ltr">{{ x.slot }} · {{ x.sim.code || 'sim' }}</span>
            <span class="bal" :class="x.sim.balance == null ? 'unread' : x.lowBal ? 'low' : 'good'">{{ x.sim.balance == null ? '؟' : Math.round(x.sim.balance).toLocaleString('en-US') }}</span>
          </button>
          <!-- A SIM opened: its buttons here -->
          <template v-for="x in s.sims" :key="'p' + x.sim.sim_uuid">
            <div v-if="picked === x.sim.sim_uuid" class="sim-open column q-gutter-xs">
              <div class="small"><b>{{ x.sim.code }}</b><span v-if="x.sim.label"> · {{ x.sim.label }}</span> · <bdi class="ltr">{{ x.sim.msisdn || '—' }}</bdi></div>
              <div v-if="x.why" class="small text-negative">{{ x.why }}</div>
              <div class="row q-gutter-xs">
                <q-btn dense outline no-caps size="sm" color="primary" :label="s.phone ? 'اكتشاف الرصيد' : 'الرصيد'" :loading="reading" @click="readBalance(x.sim)" />
                <q-btn dense outline no-caps size="sm" color="primary" label="رقمي" @click="myNumber(x.sim)" />
                <q-btn dense :outline="!ussd" :unelevated="ussd" no-caps size="sm" color="primary" label="USSD" @click="code = ''; ussd = !ussd" />
                <q-btn dense flat no-caps size="sm" color="grey-8" icon="settings" label="إعدادات" :to="'/flexy/devices?sim=' + encodeURIComponent(x.sim.code || '')" />
              </div>
              <div v-if="note" class="small muted">{{ note }}</div>
              <ModemPanel v-if="ussd" :key="x.sim.sim_uuid + code" inline :start-code="code" :sim-uuid="x.sim.sim_uuid" :sim-type="x.sim.sim_type" :phone="s.phone" :sim-name="x.sim.code || ''" />
            </div>
          </template>
        </div>
        <div v-if="!w.stations.value.length && !w.loading.value" class="muted">لا أجهزة بعد.</div>
      </div>

      <!-- What needs him, and the stock -->
      <div class="side column q-gutter-sm">
        <!-- 2. Operations that need him (owner 2026-11-01: «فصل ما يحتاج المراقبة عن الاستعمال») -->
        <div class="panel">
          <div class="panel-title">عمليات تحتاجك ({{ opsTotal }})</div>
          <div v-if="!opsTotal" class="text-positive small q-pa-sm">✓ لا عملية تنتظرك</div>
          <router-link v-for="o in ops.filter((x) => x.n)" :key="o.label" :to="o.to" class="prob row items-center no-wrap op">
            <span class="col">{{ o.label }}</span><b class="text-negative">{{ o.n }}</b>
          </router-link>
        </div>
        <div class="panel">
          <div class="panel-title">الأجهزة والشرائح: يحتاجك ({{ w.problems.value.filter((p) => !p.key.startsWith('stock:')).length }})</div>
          <div v-if="!w.problems.value.filter((p) => !p.key.startsWith('stock:')).length" class="text-positive small q-pa-sm">✓ كل شيء يعمل</div>
          <div v-for="p in w.problems.value.filter((x) => !x.key.startsWith('stock:'))" :key="p.key" class="prob row items-center no-wrap">
            <router-link :to="p.to" class="col" :class="p.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ p.text }}</router-link>
            <q-btn flat dense no-caps size="sm" color="grey-7" label="أخفِ">
              <q-menu auto-close><q-list dense>
                <q-item clickable @click="w.hide(p.key, 60)"><q-item-section>ساعة</q-item-section></q-item>
                <q-item clickable @click="w.hide(p.key, 240)"><q-item-section>4 ساعات</q-item-section></q-item>
                <q-item clickable @click="w.hide(p.key, 1440)"><q-item-section>حتى الغد</q-item-section></q-item>
              </q-list></q-menu>
            </q-btn>
          </div>
        </div>
        <!-- «تغذية سما» here too (owner 2026-11-01: «لا أدري أين التغذية»): manual «اشحنها» and the automatic feeding -->
        <div id="feed" class="panel"><SamaFeed :active="true" /></div>
        <!-- 3. The card stock: healthy / suspect per card (s181), the ones running out first -->
        <div class="panel">
          <div class="panel-title row items-center">مخزون البطاقات<q-space /><router-link to="/stock?tab=ledger" class="small">الدفتر</router-link></div>
          <div v-for="r in ledger" :key="r.product_id" class="prob row items-center no-wrap">
            <span class="col ellipsis">{{ r.brand }} · {{ r.name }}</span>
            <b :class="r.low ? 'text-negative' : 'text-positive'">{{ r.healthy }}</b>
            <span v-if="r.suspect" class="tiny text-deep-orange q-ml-xs">+{{ r.suspect }} مشكوك</span>
          </div>
          <div v-if="!ledger.length" class="small muted q-pa-sm">طبّق s181 لترى المخزون هنا.</div>
        </div>
        <div class="panel">
          <div class="panel-title row items-center">البطاقات التي تنفد ({{ w.lowItems.value.length }})<q-space /><router-link to="/stock?tab=low" class="small">المخزن</router-link></div>
          <div v-if="!w.lowItems.value.length" class="text-positive small q-pa-sm">✓ المخزون كافٍ</div>
          <div v-for="it in w.lowItems.value" :key="it.product_id" class="prob row items-center no-wrap">
            <span class="col">{{ it.brand }} · {{ it.name }}</span>
            <b :class="it.left === 0 ? 'text-negative' : 'text-deep-orange'">{{ it.left }}</b>
            <span v-if="it.days_left != null" class="tiny muted q-ml-xs">~{{ it.days_left }} يوم</span>
          </div>
        </div>
      </div>
    </div>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { useBell } from 'src/composables/useBell'
import { stockLedger } from 'src/api/admin'
import { useWatch, stNo } from 'src/composables/useWatch'
import * as flexy from 'src/api/flexy'
import ModemPanel from 'src/components/ModemPanel.vue'
import SamaFeed from 'src/components/SamaFeed.vue'

const w = useWatch(20000)
const bell = useBell()
// What waits for his decision, each to its page
const ops = computed(() => [
  { label: 'فليكسي المحلات: حكمك', n: Number(bell.flexyReview.value) || 0, to: '/flexy/shops' },
  { label: 'فشل لم يُرجع مبلغه', n: Number(bell.flexyUnrefunded.value) || 0, to: '/flexy/shops' },
  { label: 'مراجعة وفشل (المراقبة)', n: (Number(bell.reviewWaiting.value) || 0) + (Number(bell.failuresOpen.value) || 0), to: '/flexy/monitor?tab=judge' },
  { label: 'تعبئة إيدوم: مراجعة', n: Number(bell.idoomReview.value) || 0, to: '/idoom' },
  { label: 'شحن الألعاب ينتظر', n: Number(bell.gameWaiting.value) || 0, to: '/game' },
  { label: 'الخدمات تنتظر', n: Number(bell.serviceWaiting.value) || 0, to: '/services' },
  { label: 'بلاغات البطاقات', n: Number(bell.openReports.value) || 0, to: '/reports' },
  { label: 'SQL ينتظر تطبيقك', n: Number(bell.sqlPending.value) || 0, to: '/flexy/monitor?tab=db' }
])
const opsTotal = computed(() => ops.value.reduce((a, o) => a + o.n, 0))
// The stock per card, the fewest healthy first (s181)
const ledger = ref([])
const lowIds = computed(() => new Set(w.lowItems.value.map((x) => x.product_id)))
async function loadLedger () {
  const rows = await stockLedger().catch(() => null)
  if (rows) ledger.value = rows.filter((r) => Number(r.healthy) + Number(r.suspect) > 0 || lowIds.value.has(r.product_id))
    .map((r) => ({ ...r, healthy: Number(r.healthy), suspect: Number(r.suspect), low: lowIds.value.has(r.product_id) }))
    .sort((a, b) => (b.low - a.low) || a.healthy - b.healthy)
}
onMounted(() => { loadLedger(); bell.refreshBell?.() })
const clock = (t) => new Date(t).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit', timeZone: 'Africa/Algiers' })
const picked = ref(null)
const ussd = ref(false)
const code = ref('')
const note = ref('')
const reading = ref(false)
function pick (x) {
  picked.value = picked.value === x.sim.sim_uuid ? null : x.sim.sim_uuid
  ussd.value = false
  code.value = ''
  note.value = ''
}
async function readBalance (sim) {
  reading.value = true
  try {
    const res = await flexy.readSimBalance(sim.sim_uuid)
    note.value = res.status === 200 && res.body?.ok ? (res.body.sent ? 'أُرسل كود الرصيد، والرد خلال دقيقة' : 'سيُرسل عند اتصال الشريحة') : 'لم يُرسل: ' + (res.body?.error || 'FLEXY_CORE')
    setTimeout(w.load, 20000)
  } finally {
    reading.value = false
  }
}
// «رقمي»: Sama *222# known; others from ⚙️ (0139)
const NUMBER_CODES = { 'mobilis-sama': '*222#' }
function myNumber (sim) {
  const c = w.tree.value?.sim_limits?.number_codes?.[sim.sim_type] || NUMBER_CODES[sim.sim_type] || ''
  if (!c) { note.value = 'اكتب كود «رقمي» لهذا النوع مرة في إعدادات الشريحة (⚙️).'; return }
  code.value = c
  ussd.value = true
}
</script>

<style scoped>
.watch-page { max-width: 1400px; margin: 0 auto; }
.kpis { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px; }
.kpi { background: #fff; border: 1px solid #E3E6EC; border-radius: 12px; padding: 8px; text-align: center; font-size: 12px; }
.kpi .n { font-size: 22px; font-weight: 800; }
.kpi .n span { font-size: 14px; color: #6B7280; font-weight: 600; }
.kpi.bad { background: #FEF2F2; border-color: #FCA5A5; color: #B91C1C; }
.bytype { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
.bytype .chip { background: #fff; border: 1px solid #E3E6EC; border-radius: 999px; padding: 3px 10px; font-size: 12px; }
.bytype .chip.bad { border-color: #FCA5A5; color: #B91C1C; }
.layout { display: grid; grid-template-columns: minmax(0, 1fr); gap: 12px; }
@media (min-width: 1000px) { .layout { grid-template-columns: minmax(0, 2fr) minmax(0, 1fr); } }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; align-content: start; }
.tile { background: #fff; border: 1px solid #E3E6EC; border-radius: 14px; padding: 10px; display: flex; flex-direction: column; gap: 6px; }
.tile.off { opacity: 0.6; border-color: #FCA5A5; }
.tile-head { display: flex; align-items: center; gap: 6px; }
.tile-head .big { font-size: 24px; }
.tile-head .no { font-size: 22px; font-weight: 800; }
.tile-head .no.struck { text-decoration: line-through; color: #C62828; }
.dot { width: 12px; height: 12px; border-radius: 50%; display: inline-block; }
.dot.green { background: #2FAE1E; box-shadow: 0 0 6px #2FAE1E; }
.dot.red { background: #D32F2F; }
.chip { display: flex; align-items: center; justify-content: space-between; gap: 6px; border-radius: 10px; padding: 5px 8px; border: 1px solid; font: inherit; font-size: 13px; cursor: pointer; text-align: left; }
.chip.ok { background: #F0FDF4; border-color: #86EFAC; }
.chip.bad { background: #FEF2F2; border-color: #FCA5A5; }
.chip.picked { outline: 2px solid var(--q-primary); }
.bal { font-weight: 700; padding: 1px 6px; border-radius: 6px; color: #fff; font-size: 12px; }
.bal.good { background: #16A34A; }
.bal.low { background: #DC2626; }
.bal.unread { background: #F59E0B; }
.sim-open { background: #F7F8FB; border-radius: 10px; padding: 8px; }
.panel { background: #fff; border: 1px solid #E3E6EC; border-radius: 14px; padding: 8px; }
.panel-title { font-weight: 700; padding: 2px 4px 6px; }
.prob { font-size: 13px; border-top: 1px solid #EEF0F4; padding: 3px 4px; gap: 4px; }
.prob a { text-decoration: none; }
.op { text-decoration: none; color: inherit; }
.tiny { font-size: 11px; }
</style>
