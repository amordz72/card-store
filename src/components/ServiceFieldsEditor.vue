<template>
  <!-- The fields a customer fills for one service (owner 2026-10-31): name, kind, required or not, the choices -->
  <div class="column q-gutter-sm">
    <div v-for="(f, i) in rows" :key="f._id" class="field-row column q-gutter-xs">
      <div class="row items-center no-wrap q-gutter-xs">
        <q-input v-model="f.label" class="col" dense outlined label="اسم الخانة (مثلًا: ID اللاعب)" maxlength="60" />
        <q-btn flat round dense icon="arrow_upward" aria-label="أعلى" :disable="i === 0" @click="move(i, -1)" />
        <q-btn flat round dense icon="delete" color="negative" aria-label="حذف" @click="rows.splice(i, 1)" />
      </div>
      <div class="row items-center q-gutter-sm">
        <q-select v-model="f.type" class="col" dense outlined emit-value map-options :options="TYPES" label="نوعها" />
        <q-toggle v-model="f.required" dense label="إجبارية" />
      </div>
      <q-input v-if="f.type === 'choice'" v-model="f.optionsText" dense outlined autogrow type="textarea"
        label="الخيارات: خيار في كل سطر (مثلًا PUBG ثم Free Fire)" />
    </div>
    <div class="row q-gutter-xs">
      <q-btn outline dense no-caps color="primary" icon="add" label="خانة" @click="add()" />
      <q-btn v-if="!rows.some((x) => x.label.trim() === 'بيانات الشحن')" flat dense no-caps color="primary" label="+ بيانات الشحن"
        @click="add('بيانات الشحن', 'long', true)" />
    </div>
    <div v-if="!rows.length" class="small muted">بلا خانات: يكتب الزبون العدد والملاحظة فقط.</div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'

// v-model: the list as the database keeps it [{key,label,type,required,options}]
const props = defineProps({ modelValue: { type: Array, default: () => [] } })
const emit = defineEmits(['update:modelValue'])

const TYPES = [
  { value: 'text', label: 'نص قصير' },
  { value: 'long', label: 'نص طويل' },
  { value: 'number', label: 'رقم' },
  { value: 'phone', label: 'رقم هاتف' },
  { value: 'link', label: 'رابط' },
  { value: 'choice', label: 'اختيار من قائمة' }
]
let seq = 0
const toRow = (f) => ({ _id: ++seq, key: f.key || null, label: f.label || '', type: f.type || 'text', required: !!f.required,
  optionsText: (f.options || []).join('\n') })
const rows = ref((props.modelValue || []).map(toRow))
watch(() => props.modelValue, (v) => { if (JSON.stringify(v) !== JSON.stringify(out())) rows.value = (v || []).map(toRow) })

// Keys stay the same for a kept field (old orders keep their own labels anyway); new fields get f1, f2…
function out () {
  const used = new Set(rows.value.map((f) => f.key).filter(Boolean))
  let n = 1
  return rows.value.filter((f) => f.label.trim()).map((f) => {
    let key = f.key
    if (!key) { while (used.has('f' + n)) n++; key = 'f' + n; used.add(key) }
    return { key, label: f.label.trim(), type: f.type, required: f.required,
      options: f.type === 'choice' ? f.optionsText.split('\n').map((x) => x.trim()).filter(Boolean) : [] }
  })
}
watch(rows, () => emit('update:modelValue', out()), { deep: true })

function add (label = '', type = 'text', required = false) { rows.value.push(toRow({ label, type, required })) }
function move (i, d) { const [x] = rows.value.splice(i, 1); rows.value.splice(i + d, 0, x) }
</script>

<style scoped>
.field-row { border: 1px solid #E5E7EB; border-radius: 12px; padding: 8px; }
</style>
