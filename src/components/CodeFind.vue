<template>
  <!-- «الصق كودًا» (owner 2026-11-01, s167): a whole code, or its last 4–8 characters → its batch, state and buyer -->
  <div class="card column q-gutter-sm">
    <div class="row items-center no-wrap q-gutter-sm">
      <q-input v-model="text" class="col" dense outlined clearable label="الصق كودًا أو آخر 4 أرقام منه" input-class="ltr"
        @keyup.enter="find" @clear="results = []" />
      <q-btn unelevated dense no-caps color="primary" icon="search" label="ابحث" :loading="busy" :disable="clean.length < 4" @click="find" />
    </div>
    <div v-if="searched && !results.length" class="small muted">لا يوجد هذا الكود في المخزن.</div>
    <div v-for="c in results" :key="c.code_id" class="found column q-gutter-xs">
      <div class="row items-center no-wrap q-gutter-sm">
        <bdi class="col ltr text-right text-weight-bold">{{ c.shown_code }}</bdi>
        <q-badge :color="codeWord(c).color" :label="codeWord(c).label" />
      </div>
      <div class="small muted">{{ c.product_name }} · دفعة <b><bdi dir="ltr">{{ codes[c.batch_id] || '#' + c.batch_id }}</bdi></b> · {{ c.supplier }}
        <span v-if="c.customer_name"> · بيع لـ<b>{{ c.customer_name }}</b> (طلب {{ c.order_id }}) · {{ dateTime(c.sold_at) }}</span>
        <span v-if="c.void_reason && c.status === 'void'"> · {{ c.void_reason }}</span></div>
      <div class="row q-gutter-xs">
        <q-btn v-for="s in CODE_STATES" :key="s.state" dense outline no-caps size="sm" :color="s.color" :label="s.label" :disable="busy"
          @click="setState(c, s.state)" />
        <q-btn dense flat no-caps size="sm" color="primary" icon="inventory_2" :label="'الدفعة ' + (codes[c.batch_id] || '#' + c.batch_id)" @click="emit('batch', c.batch_id)" />
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { dateTime } from 'src/api/format'
import { CODE_STATES, codeWord } from 'src/api/codeStates'

const emit = defineEmits(['batch', 'changed'])
const { busy, run } = useRun()
const text = ref('')
const results = ref([])
const searched = ref(false)
const codes = ref({})
const clean = computed(() => String(text.value || '').replace(/[\s-]/g, ''))

async function find () {
  if (clean.value.length < 4) return
  const r = await run(() => api.codeFind(text.value))
  if (r) {
    results.value = r
    searched.value = true
    codes.value = await api.batchCodeMap([...new Set(r.map((x) => x.batch_id))])
  }
}
async function setState (c, state) {
  const n = await run(() => api.codesState([c.code_id], state), { success: (n) => (n ? 'تغيّرت الحالة.' : 'لم يتغيّر شيء.') })
  if (n !== undefined) { await find(); emit('changed') }
}
</script>

<style scoped>
.found { border-top: 1px solid #EEF0F4; padding-top: 8px; }
</style>
