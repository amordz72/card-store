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

    <div class="row q-gutter-xs">
      <q-btn v-for="g in GROUPS" :key="g.id" rounded no-caps :unelevated="group === g.id" :outline="group !== g.id"
        :color="group === g.id ? g.color : 'grey-8'" :label="`${g.label} (${count(g.id)})`" @click="group = g.id" />
    </div>
    <div class="card q-pa-none">
      <div v-if="!rows.length && !busy" class="muted q-pa-md text-center">لا محلات هنا</div>
      <div v-for="s in rows" :key="s.id" class="line row items-center no-wrap q-gutter-sm">
        <div class="col text-weight-bold">{{ s.name }}
          <div class="small muted">{{ s.last_at ? 'آخر دخول ' + ago(s.last_at) : 'لم يدخل' }}</div></div>
        <div class="small text-right">{{ money(s.prev) }} ← <b>{{ money(s.cur) }}</b></div>
        <q-badge :color="GROUPS.find((g) => g.id === s.grp)?.color || 'grey-6'" :label="s.change === null ? '—' : (s.change > 0 ? '+' : '') + s.change + '%'" />
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
.line { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 8px 12px; }
</style>
