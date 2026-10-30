<template>
  <!-- «المؤشرات» (owner 2026-10-30, card-store v1.45): each shop's spending (purchases + flexy, less refunds),
       this period against the one before. The two numbers are the owner's (store.settings), never fixed here. -->
  <div class="column q-gutter-sm">
    <div class="card column q-gutter-sm">
      <div class="row q-gutter-xs">
        <q-btn v-for="d in [7, 14, 30]" :key="d" rounded no-caps :unelevated="days === d" :outline="days !== d"
          :color="days === d ? 'primary' : 'grey-8'" :label="d === 7 ? 'أسبوع بأسبوع' : d === 14 ? 'أسبوعان بأسبوعين' : 'شهر بشهر'" @click="days = d" />
      </div>
      <div class="row q-gutter-sm">
        <q-input v-model.number="pct" class="col" dense outlined type="number" inputmode="numeric" stack-label label="تغيّر لا يقل عن" suffix="%" />
        <q-input v-model.number="min" class="col" dense outlined type="number" inputmode="numeric" stack-label label="تجاهل أقل من" suffix="دج" />
        <q-btn unelevated no-caps color="primary" label="حفظ" :loading="saving" :disable="!changed" @click="save" />
      </div>
      <div class="small muted">مصروف المحل = البطاقات + الفليكسي، ناقص ما أُرجع له. يُقارن آخر {{ days }} يومًا بالـ{{ days }} التي قبلها.</div>
      <div v-if="error" class="small text-negative">{{ error }}</div>
    </div>

    <!-- Indicators first (owner 2026-10-30): four tiles that filter, then each shop as two bars, before and now -->
    <div class="tiles">
      <button v-for="g in GROUPS" :key="g.id" type="button" class="tile" :class="[g.id, { picked: group === g.id }]" @click="group = g.id">
        <div class="n">{{ count(g.id) }}</div><div class="small">{{ g.label }}</div>
      </button>
    </div>
    <div class="card column q-gutter-xs">
      <div class="row items-center q-gutter-md small">
        <span><span class="key prev" /> الفترة السابقة</span><span><span class="key cur" /> آخر {{ days }} يومًا</span>
      </div>
      <div v-if="!rows.length && !busy" class="muted q-pa-md text-center">لا محلات هنا</div>
      <div v-for="s in rows" :key="s.id" class="shop">
        <div class="row items-center no-wrap">
          <div class="col text-weight-bold ellipsis">{{ s.name }}</div>
          <q-badge :color="GROUPS.find((g) => g.id === s.grp)?.color || 'grey-6'" :label="s.change === null ? (s.grp === 'new' ? 'جديد' : '—') : (s.change > 0 ? '+' : '') + s.change + '%'" />
        </div>
        <div class="pair">
          <div class="hbar prev" :style="{ width: w(s.prev) }" /><span class="small muted">{{ money(s.prev) }}</span>
        </div>
        <div class="pair">
          <div class="hbar cur" :style="{ width: w(s.cur) }" /><span class="small"><b>{{ money(s.cur) }}</b></span>
        </div>
        <div class="small muted">{{ s.last_at ? 'آخر دخول ' + ago(s.last_at) : 'لم يدخل' }}</div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import * as adminApi from 'src/api/admin'
import { money } from 'src/api/format'

const GROUPS = [
  { id: 'down', label: 'انخفض استهلاكهم', color: 'negative' },
  { id: 'stopped', label: 'توقفوا', color: 'deep-orange' },
  { id: 'up', label: 'في ارتفاع', color: 'positive' },
  { id: 'new', label: 'نشطون جدد', color: 'primary' }
]
const days = ref(7)
const group = ref('down')
const data = ref(null)
const pct = ref(30)
const min = ref(1000)
const busy = ref(false)
const saving = ref(false)
const error = ref('')

const count = (id) => (data.value?.shops || []).filter((s) => s.grp === id).length
const rows = computed(() => (data.value?.shops || []).filter((s) => s.grp === group.value))
// Bars on one scale for the shops shown: the largest amount is the full width
const scale = computed(() => Math.max(1, ...rows.value.flatMap((r) => [r.prev, r.cur])))
const w = (v) => Math.max(1, Math.round((v / scale.value) * 70)) + '%'
const changed = computed(() => data.value && (pct.value !== data.value.change_pct || min.value !== data.value.min_amount))

async function load () {
  busy.value = true
  error.value = ''
  try {
    data.value = await adminApi.indicators(days.value)
    pct.value = data.value.change_pct
    min.value = data.value.min_amount
    // The bell's «انخفض استهلاكهم» is seen for this week (useBell)
    if (days.value === 7) markIndicatorsSeen()
  } catch (e) {
    // Before v1.45 is applied
    error.value = 'لم تُقرأ (' + (e.message || 'STORE') + ').'
  } finally {
    busy.value = false
  }
}
async function save () {
  if (!(pct.value >= 1 && pct.value <= 100) || !(min.value >= 0)) { error.value = 'النسبة من 1 إلى 100، والمبلغ 0 أو أكثر.'; return }
  saving.value = true
  try {
    await adminApi.setIndicators(pct.value, min.value)
    await load()
  } catch (e) {
    error.value = 'لم يُحفظ (' + (e.message || 'STORE') + ').'
  } finally {
    saving.value = false
  }
}
function ago (t) {
  const m = Math.round((Date.now() - Date.parse(t)) / 60000)
  if (m < 60) return 'منذ ' + Math.max(m, 1) + ' دقيقة'
  if (m < 1440) return 'منذ ' + Math.round(m / 60) + ' ساعة'
  return 'منذ ' + Math.round(m / 1440) + ' يوم'
}
watch(days, load)
onMounted(load)
</script>

<script>
import { LocalStorage } from 'quasar'
// The week (Monday) the owner last opened the indicators: the bell shows the drops once a week
export const weekKey = () => { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return d.toISOString().slice(0, 10) }
export function markIndicatorsSeen () { try { LocalStorage.set('cs_indicators_seen', weekKey()) } catch { /* private mode */ } }
export function indicatorsSeenThisWeek () { try { return LocalStorage.getItem('cs_indicators_seen') === weekKey() } catch { return false } }
</script>

<style scoped>
.tiles { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
.tile { border: 2px solid transparent; border-radius: 12px; padding: 8px 10px; text-align: right; background: rgba(0, 0, 0, 0.04); cursor: pointer; font: inherit; color: inherit; }
.tile .n { font-size: 22px; font-weight: 700; }
.tile.down .n { color: var(--q-negative); }
.tile.stopped .n { color: #d84315; }
.tile.up .n { color: var(--q-positive); }
.tile.new .n { color: var(--q-primary); }
.tile.picked { border-color: currentColor; background: rgba(0, 0, 0, 0.07); }
.shop { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 8px 2px; }
.pair { display: flex; align-items: center; gap: 6px; margin-top: 3px; }
.hbar { height: 10px; border-radius: 0 4px 4px 0; }
.hbar.prev, .key.prev { background: #9e9e9e; }
.hbar.cur, .key.cur { background: var(--q-primary); }
.key { display: inline-block; width: 10px; height: 10px; border-radius: 2px; vertical-align: middle; }
body.body--dark .tile { background: rgba(255, 255, 255, 0.06); }
.line { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 8px 12px; }
</style>
