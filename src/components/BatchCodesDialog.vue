<template>
  <!-- «عرض» of a batch (owner 2026-11-01, s167): read first; the whole codes only on «أظهر الأكواد» (stock only, logged) -->
  <q-dialog :model-value="modelValue" @update:model-value="(v) => emit('update:modelValue', v)">
    <q-card class="codes-card">
      <q-card-section class="row items-center no-wrap q-pb-sm">
        <div class="col">
          <div class="text-weight-bold"><bdi v-if="batch?.code" dir="ltr" class="text-primary">{{ batch.code }}</bdi> {{ batch?.product_name }} <span class="small muted">#{{ batch?.batch_id }}</span></div>
          <div class="small muted">{{ batch?.supplier }}</div>
        </div>
        <q-btn flat round dense icon="close" aria-label="إغلاق" @click="emit('update:modelValue', false)" />
      </q-card-section>
      <q-card-section class="row q-gutter-xs q-pt-none">
        <q-btn v-if="!revealed" unelevated dense no-caps color="primary" icon="visibility" label="أظهر الأكواد" :loading="loading" @click="load(true)" />
        <q-btn v-else dense outline no-caps color="grey-8" icon="visibility_off" label="أخفها" @click="load(false)" />
        <q-btn v-if="stockIds.length" dense outline no-caps color="deep-orange" label="اجعل المتوفر مشكوكًا فيه" :loading="busy" @click="setState(stockIds, 'suspect')" />
      </q-card-section>
      <q-card-section class="q-pt-none scroll list">
        <div v-for="c in rows" :key="c.code_id" class="code-row">
          <div class="row items-center no-wrap q-gutter-sm">
            <bdi class="col ltr text-right code" :class="{ full: c.full_shown }">{{ c.shown_code }}</bdi>
            <q-btn v-if="c.full_shown" flat dense round size="sm" icon="content_copy" aria-label="نسخ" @click="copyText(c.shown_code)" />
            <q-badge :color="codeWord(c).color" :label="codeWord(c).label" />
            <q-btn-dropdown flat dense no-caps size="sm" color="primary" label="الحالة" :disable="busy">
              <q-list dense>
                <q-item v-for="s in CODE_STATES" :key="s.state" v-close-popup clickable @click="setState([c.code_id], s.state)">
                  <q-item-section :class="'text-' + s.color">{{ s.label }}</q-item-section>
                </q-item>
              </q-list>
            </q-btn-dropdown>
          </div>
          <div class="small muted">
            <span v-if="c.serial">تسلسلي <bdi dir="ltr">{{ c.serial }}</bdi></span>
            <span v-if="c.customer_name"> · بيع لـ<b>{{ c.customer_name }}</b> (طلب {{ c.order_id }}) · {{ dateTime(c.sold_at) }}</span>
            <span v-if="c.void_reason && c.status === 'void'"> · {{ c.void_reason }}</span>
          </div>
        </div>
        <div v-if="!loading && !rows.length" class="text-center muted q-pa-md">لا أكواد</div>
        <q-inner-loading :showing="loading" />
      </q-card-section>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { Notify } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { copyText } from 'src/composables/useCopy'
import * as api from 'src/api/admin'
import { dateTime } from 'src/api/format'
import { CODE_STATES, codeWord } from 'src/api/codeStates'

const props = defineProps({ modelValue: { type: Boolean, default: false }, batch: { type: Object, default: null } })
const emit = defineEmits(['update:modelValue', 'changed'])
const { busy, run } = useRun()
const rows = ref([])
const loading = ref(false)
const revealed = ref(false)
const stockIds = computed(() => rows.value.filter((c) => c.status === 'available' && !c.suspect).map((c) => c.code_id))

async function load (reveal) {
  if (!props.batch) return
  loading.value = true
  try {
    rows.value = await api.batchCodesV3(props.batch.batch_id, reveal)
    revealed.value = reveal
  } catch (e) {
    Notify.create({ type: 'negative', message: /store_admin_batch_codes_v3/.test(e?.message || '') ? 'طبّق s167 من «ينتظر تطبيقك» أولًا.' : (e?.message || 'خطأ') })
  } finally {
    loading.value = false
  }
}
async function setState (ids, state) {
  const n = await run(() => api.codesState(ids, state), { success: (n) => `تغيّرت ${n} ${n === 1 ? 'بطاقة' : 'بطاقات'}.` })
  if (n !== undefined) { await load(revealed.value); emit('changed') }
}
watch(() => [props.modelValue, props.batch?.batch_id], ([open]) => { if (open) { rows.value = []; load(false) } }, { immediate: true })
</script>

<style scoped>
.codes-card { width: 100%; max-width: 560px; }
.list { max-height: 65vh; }
.code-row { padding: 8px 0; border-bottom: 1px solid #EEF0F4; }
.code-row:last-child { border-bottom: 0; }
.code { font-variant-numeric: tabular-nums; }
.code.full { font-weight: 700; user-select: all; }
</style>
