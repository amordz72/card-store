<template>
  <!-- «التقرير اليومي والأرباح» (owner 2026-11-01, «نفذ»; flexy-core s184): day by day what the shops consumed, my own
       account, Flexy, and the profit taken; from a date to a date; and the products sold most in that range. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <div class="row items-center">
      <div class="col section-title">التقرير اليومي والأرباح</div>
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
    </div>
    <div class="row q-gutter-xs">
      <q-btn v-for="r in RANGES" :key="r.id" rounded no-caps size="sm" :unelevated="range === r.id" :outline="range !== r.id"
        :color="range === r.id ? 'primary' : 'grey-8'" :label="r.label" @click="range = r.id" />
    </div>
    <div v-if="range === 'pick'" class="card grid-2">
      <DateField v-model="from" label="من تاريخ" />
      <DateField v-model="to" label="حتى تاريخ" />
    </div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <template v-if="data">
      <div class="small muted">{{ hint }}</div>
      <!-- The whole range -->
      <div class="card column q-gutter-xs">
        <div class="text-weight-bold">المجموع</div>
        <div class="big-number amount-info">{{ signed(total.profit) }} دج</div>
        <div class="small muted">ربحك كله: من المحلات {{ signed(total.shops_profit) }} · من حسابك {{ signed(total.mine_profit) }}</div>
        <q-separator />
        <div class="grid-2">
          <div class="column"><span class="small muted">استهلاك المحلات (بطاقات)</span><b>{{ money(total.shops_charged) }}</b><span class="small muted">{{ total.shops_orders }} عملية</span></div>
          <div class="column"><span class="small muted">مبيعات حسابي</span><b>{{ money(total.mine_sold) }}</b><span class="small muted">{{ total.mine_orders }} عملية</span></div>
          <div class="column"><span class="small muted">فليكسي المحلات (ناجحة)</span><b>{{ money(total.flexy_charged) }}</b><span class="small muted">{{ total.flexy_count }} عملية</span></div>
          <div class="column"><span class="small muted">الإجمالي</span><b>{{ money(total.shops_charged + total.mine_sold + total.flexy_charged) }}</b></div>
        </div>
        <div v-if="total.no_cost" class="small text-warning">{{ total.no_cost }} عملية بلا سعر شراء (ربحها غير محسوب)</div>
      </div>

      <!-- Day by day -->
      <div class="card column q-gutter-xs">
        <div class="text-weight-bold">يومًا بيوم</div>
        <div v-for="d in shownDays" :key="d.day" class="day column">
          <div class="row items-center">
            <span class="col text-weight-medium">{{ dayName(d.day) }}</span>
            <b :class="d.shops_profit + d.mine_profit < 0 ? 'text-negative' : 'text-positive'">{{ signed(d.shops_profit + d.mine_profit) }} دج</b>
          </div>
          <div class="small muted">
            المحلات {{ money(d.shops_charged) }} ({{ d.shops_orders }}) · ربح {{ signed(d.shops_profit) }}
            — حسابي {{ money(d.mine_sold) }} ({{ d.mine_orders }}) · ربح {{ signed(d.mine_profit) }}
            <template v-if="d.flexy_count"> — فليكسي {{ money(d.flexy_charged) }} ({{ d.flexy_count }})</template>
          </div>
        </div>
        <div v-if="!shownDays.length" class="small muted">لا عمليات في هذه الفترة.</div>
        <q-toggle v-model="withEmpty" dense size="sm" label="أظهر الأيام بلا عمليات" class="small" />
      </div>

      <!-- Products sold most -->
      <div class="card column q-gutter-xs">
        <div class="text-weight-bold">الأكثر مبيعًا في الفترة</div>
        <div v-for="(p, i) in data.top" :key="p.product_id" class="row items-center no-wrap top">
          <span class="rank">{{ i + 1 }}</span>
          <span class="col ellipsis">{{ p.brand ? p.brand + ' · ' : '' }}{{ p.name }}</span>
          <span class="small muted q-mx-sm">{{ money(p.charged) }}</span>
          <b class="q-mr-sm">× {{ p.qty }}</b>
          <span class="small" :class="(p.profit || 0) < 0 ? 'text-negative' : 'text-positive'">{{ p.profit == null ? '—' : signed(p.profit) }}</span>
        </div>
        <div v-if="!data.top.length" class="small muted">لم يُبع شيء في هذه الفترة.</div>
        <div class="small muted">الربح = ما دفعه المحل (أو سعر البيع في حسابك) − سعر الشراء. البطاقات المسترجعة مخصومة.</div>
      </div>
    </template>
    <q-inner-loading :showing="busy && !data" />
  </q-page>
</template>

<script setup>
import { computed, ref, watch, onMounted } from 'vue'
import { dailyReport } from 'src/api/admin'
import { money, signed } from 'src/api/format'
import DateField from 'components/DateField.vue'

const RANGES = [
  { id: 'today', label: 'اليوم' }, { id: 'yesterday', label: 'أمس' }, { id: '7', label: '7 أيام' },
  { id: '30', label: '30 يومًا' }, { id: 'pick', label: 'من تاريخ إلى تاريخ' }
]
const range = ref('7')
const from = ref('')
const to = ref('')
const data = ref(null)
const busy = ref(false)
const error = ref('')
const withEmpty = ref(false)

// Today in Algeria, as YYYY-MM-DD
const algeriaDay = (offset = 0) => new Date(Date.now() + offset * 86400000).toLocaleDateString('en-CA', { timeZone: 'Africa/Algiers' })
function bounds () {
  if (range.value === 'today') return [algeriaDay(), algeriaDay()]
  if (range.value === 'yesterday') return [algeriaDay(-1), algeriaDay(-1)]
  if (range.value === 'pick') return [from.value || null, to.value || null]
  return [algeriaDay(-(Number(range.value) - 1)), algeriaDay()]
}

async function load () {
  busy.value = true
  error.value = ''
  try {
    const [f, t] = bounds()
    data.value = await dailyReport(f, t)
  } catch (e) {
    error.value = e?.message || 'تعذّر التحميل'
  } finally {
    busy.value = false
  }
}
watch([range, from, to], load)
onMounted(load)

const sum = (k) => (data.value?.days || []).reduce((a, d) => a + (Number(d[k]) || 0), 0)
const total = computed(() => {
  const t = {}
  for (const k of ['shops_charged', 'shops_profit', 'shops_orders', 'mine_sold', 'mine_profit', 'mine_orders', 'flexy_charged', 'flexy_count', 'no_cost']) t[k] = sum(k)
  t.profit = t.shops_profit + t.mine_profit
  return t
})
const shownDays = computed(() => (data.value?.days || []).filter((d) => withEmpty.value || d.shops_orders || d.mine_orders || d.flexy_count))
const hint = computed(() => data.value ? (data.value.from === data.value.to ? dayName(data.value.from) : 'من ' + data.value.from + ' حتى ' + data.value.to) : '')
function dayName (day) {
  if (day === algeriaDay()) return 'اليوم · ' + day
  if (day === algeriaDay(-1)) return 'أمس · ' + day
  const n = new Date(day + 'T12:00:00Z').toLocaleDateString('ar-DZ', { weekday: 'long', timeZone: 'UTC' })
  return n + ' · ' + day
}
</script>

<style scoped>
.day { border-top: 1px solid #EEF0F4; padding-top: 6px; }
.day:first-of-type { border-top: 0; }
.top { gap: 6px; font-size: 13px; }
.rank { width: 20px; color: #6B7280; font-weight: 700; }
</style>
