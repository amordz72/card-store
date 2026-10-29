<template>
  <!-- Every filter is a button on the screen, no pop-up list (owner 2026-10-26, like Hani Rohek) -->
  <div class="card column q-gutter-sm filters">
    <div v-if="scopes" class="chips">
      <span class="lbl">عمليات</span>
      <q-btn v-for="s in SCOPES" :key="String(s.id)" v-bind="chip(f.scope === s.id)" :label="s.label" @click="f.scope = s.id" />
    </div>
    <div class="chips">
      <span class="lbl">النوع</span>
      <q-btn v-for="t in TYPES" :key="String(t.id)" v-bind="chip(f.type === t.id)" :label="t.label" @click="f.type = t.id" />
    </div>
    <div v-if="customers && f.scope !== 'shop'" class="chips scroll">
      <span class="lbl">الزبون</span>
      <q-btn v-bind="chip(!f.customerId)" label="كل الزبائن" @click="f.customerId = null" />
      <q-btn v-for="c in customers" :key="c.customer_id" v-bind="chip(f.customerId === c.customer_id)" :label="c.name"
        @click="f.customerId = c.customer_id" />
    </div>
    <div class="chips">
      <span class="lbl">التاريخ</span>
      <q-btn v-for="r in RANGES" :key="r.id" v-bind="chip(f.range === r.id)" :label="r.label" @click="f.range = r.id" />
    </div>
    <div v-if="f.range === 'custom'" class="grid-2">
      <DateField v-model="f.from" label="من تاريخ" />
      <DateField v-model="f.to" label="حتى تاريخ" />
    </div>
    <div class="row items-center no-wrap q-gutter-sm">
      <q-input v-model="f.query" dense outlined clearable debounce="400" class="col" placeholder="بحث: بطاقة، رقم، زبون" />
      <q-btn flat dense no-caps color="grey-8" icon="filter_alt_off" label="مسح" @click="clear" />
    </div>
  </div>
</template>

<script setup>
import { CATEGORIES } from 'src/api/format'
import DateField from 'components/DateField.vue'

defineProps({ customers: { type: Array, default: null }, scopes: Boolean })
const f = defineModel({ type: Object, required: true })

const SCOPES = [{ id: null, label: 'الكل' }, { id: 'shop', label: 'أنا' }, { id: 'customers', label: 'زبائني' }]
const TYPES = [{ id: null, label: 'الكل' }, { id: 'flexy', label: 'فليكسي' }, { id: 'offer', label: 'عروض' },
  ...CATEGORIES.map((c) => ({ id: c.id, label: c.label }))]
const RANGES = [{ id: 'today', label: 'اليوم' }, { id: 'yesterday', label: 'أمس' }, { id: '7d', label: '7 أيام' },
  { id: 'all', label: 'الكل' }, { id: 'custom', label: 'تاريخ محدد' }]

const chip = (on) => ({ rounded: true, dense: true, 'no-caps': true, unelevated: on, outline: !on, color: on ? 'primary' : 'grey-8', class: 'q-px-sm' })

function clear () {
  Object.assign(f.value, { customerId: null, type: null, range: 'all', from: '', to: '', query: '' })   // «الكل/أنا/زبائني» stays as chosen
}
</script>

<style scoped>
/* never wider than the screen: a long row scrolls inside (2026-10-29: many customers pushed the page sideways) */
.filters { min-width: 0; max-width: 100%; overflow: hidden; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; min-width: 0; max-width: 100%; }
/* many customers: one line that scrolls sideways */
.chips.scroll { flex-wrap: nowrap; overflow-x: auto; white-space: nowrap; padding-bottom: 2px; }
.chips > * { flex: 0 0 auto; }
.lbl { align-self: center; font-size: 12px; color: #5B6170; min-width: 44px; }
</style>
