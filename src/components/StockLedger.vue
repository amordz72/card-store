<template>
  <!-- «دفتر المخزون» (owner 2026-11-01, s181): the stock as a statement — per card: in, sold, voided, fed, and what is left
       healthy / suspect with its value; a tap opens its movements, newest first, each with the count left after it.
       A batch code opens that batch's own life. -->
  <div class="column q-gutter-sm">
    <div v-if="missing" class="small text-negative">طبّق s181 من «ينتظر تطبيقك» أولًا.</div>
    <template v-else>
      <div class="totals">
        <div><b>{{ totals.healthy }}</b><span>سليمة</span><small>{{ money(totals.healthyValue) }}</small></div>
        <div class="sus"><b>{{ totals.suspect }}</b><span>مشكوك فيها</span><small>{{ money(totals.suspectValue) }}</small></div>
        <div><b>{{ totals.healthy + totals.suspect + totals.frozen }}</b><span>المجموع</span><small>{{ money(totals.healthyValue + totals.suspectValue) }}</small></div>
      </div>
      <q-input v-model="q" dense outlined clearable placeholder="ابحث عن بطاقة (mobilis، 1000…)" />
      <div class="table">
        <div class="tr th"><span class="name">البطاقة</span><span>دخلت</span><span>بيعت</span><span>أُلغيت</span><span>غُذّيت</span><span>سليمة</span><span>مشكوك</span></div>
        <template v-for="r in shown" :key="r.product_id">
          <button type="button" class="tr" :class="{ open: openId === r.product_id }" @click="toggle(r)">
            <span class="name">{{ r.brand === r.name.split(' ')[0] ? r.name : r.brand + ' · ' + r.name }}</span>
            <span>{{ r.added }}</span><span>{{ r.sold }}</span><span>{{ r.voided }}</span><span>{{ r.fed }}</span>
            <span class="ok">{{ r.healthy }}</span><span :class="{ sus: r.suspect }">{{ r.suspect }}</span>
          </button>
          <div v-if="openId === r.product_id" class="moves">
            <div class="row items-center q-gutter-xs">
              <span class="small text-weight-bold col">الحركة{{ batch ? ' · الدفعة ' + batch.code : '' }}</span>
              <q-btn v-if="batch" flat dense no-caps size="sm" color="primary" label="كل الدفعات" @click="pickBatch(r, null)" />
            </div>
            <q-inner-loading :showing="loadingMoves" />
            <div v-for="(m, i) in moves" :key="i" class="mv">
              <span class="d">{{ whenText(m.at) }}</span>
              <span class="col">{{ m.label }}
                <button v-if="m.batch && !batch" type="button" class="bchip" @click="pickBatch(r, m)">{{ m.batch }}</button></span>
              <b :class="m.delta > 0 ? 'text-positive' : 'text-negative'">{{ m.delta > 0 ? '+' : '' }}{{ m.delta }}</b>
              <span class="left">= {{ m.left }}</span>
            </div>
            <div v-if="!loadingMoves && !moves.length" class="small muted">لا حركة.</div>
          </div>
        </template>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import * as api from 'src/api/admin'
import { money, whenText } from 'src/api/format'

const rows = ref([])
const missing = ref(false)
const q = ref('')
const openId = ref(null)
const moves = ref([])
const loadingMoves = ref(false)
const batch = ref(null)

const shown = computed(() => {
  const t = String(q.value || '').trim().toLowerCase()
  return rows.value.filter((r) => !t || (r.brand + ' ' + r.name).toLowerCase().includes(t))
})
const totals = computed(() => shown.value.reduce((a, r) => ({
  healthy: a.healthy + Number(r.healthy), suspect: a.suspect + Number(r.suspect), frozen: a.frozen + Number(r.frozen),
  healthyValue: a.healthyValue + Number(r.healthy_value), suspectValue: a.suspectValue + Number(r.suspect_value)
}), { healthy: 0, suspect: 0, frozen: 0, healthyValue: 0, suspectValue: 0 }))

async function load () {
  try {
    rows.value = (await api.stockLedger()) || []
  } catch (e) {
    missing.value = /store_admin_stock_ledger/.test(e?.message || '')
  }
}
async function loadMoves (r) {
  loadingMoves.value = true
  try { moves.value = (await api.stockMoves(r.product_id, 200, batch.value?.id ?? null)) || [] } catch { moves.value = [] } finally { loadingMoves.value = false }
}
function toggle (r) {
  if (openId.value === r.product_id) { openId.value = null; return }
  openId.value = r.product_id
  batch.value = null
  loadMoves(r)
}
// A batch's own life: in, sold, voided, fed — by its code (the id is looked up from the batches list)
async function pickBatch (r, m) {
  if (!m) { batch.value = null; return loadMoves(r) }
  const found = await api.batchFind(m.batch).catch(() => [])
  const b = (found || []).find((x) => x.code === m.batch) || (found || [])[0]
  if (!b) return
  batch.value = { id: b.batch_id, code: m.batch }
  loadMoves(r)
}
onMounted(load)
defineExpose({ load })
</script>

<style scoped>
.totals { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
.totals > div { border: 1px solid #E3E6EC; border-radius: 12px; padding: 8px; text-align: center; display: flex; flex-direction: column; }
.totals b { font-size: 22px; } .totals span { font-size: 12px; color: #6B7280; } .totals small { font-size: 11px; color: #6B7280; }
.totals .sus { background: #FFF7ED; border-color: #FDBA74; }
.table { border: 1px solid #E3E6EC; border-radius: 12px; overflow: hidden; contain: inline-size; }
.tr { display: grid; grid-template-columns: minmax(0, 2.4fr) repeat(6, minmax(0, 1fr)); gap: 2px; align-items: center; width: 100%; padding: 7px 8px;
  border: 0; border-top: 1px solid #EEF0F4; background: #fff; font: inherit; font-size: 13px; text-align: center; color: inherit; cursor: pointer; }
.tr.th { background: #F7F8FB; font-size: 11px; color: #6B7280; cursor: default; border-top: 0; }
.tr.open { background: #EEF2FF; }
.tr .name { text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600; }
.ok { color: #15803D; font-weight: 700; } .sus { color: #C2410C; font-weight: 700; }
.moves { background: #FAFBFD; padding: 6px 10px; position: relative; min-height: 40px; }
.mv { display: flex; align-items: center; gap: 6px; font-size: 13px; padding: 4px 0; border-top: 1px solid #EEF0F4; min-width: 0; }
.mv .d { color: #6B7280; font-size: 12px; white-space: nowrap; } .mv .col { min-width: 0; }
.mv .left { color: #6B7280; font-size: 12px; white-space: nowrap; }
.bchip { border: 1px solid #C7D2FE; background: #EEF2FF; color: #3730A3; border-radius: 6px; font-size: 11px; padding: 0 5px; margin-inline-start: 4px; cursor: pointer; }
</style>
