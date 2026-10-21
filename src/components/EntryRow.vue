<template>
  <div class="q-pa-sm column q-gutter-xs" :style="{ borderTop: '1px solid #EEF0F5', opacity: e.reversed ? 0.75 : 1, background: e.reversed ? '#F7F8FB' : '#FFFFFF' }">
    <div class="row justify-between items-center">
      <span class="badge" :style="{ background: kind.color }">{{ kind.label }}</span>
      <span v-if="e.customer_name" class="q-px-sm rounded-borders small text-weight-medium" style="background:#EEF0FF;color:#3730A3">{{ e.customer_name }}</span>
      <span class="text-weight-bold">{{ mask(money(e.amount)) }}</span>
    </div>
    <div class="small" style="color:#374151">{{ hide ? '••••' : effectText(e.d_balance, e.d_debt) }}</div>
    <div v-if="e.note" class="small muted">{{ e.note }}</div>
    <div class="row justify-between items-center small muted">
      <span>{{ dateTime(e.created_at) }} · {{ e.reversed ? 'تم استردادها' : e.reverses_id ? 'استرداد لحركة سابقة' : 'سارية' }}</span>
      <q-btn v-if="canReverse" dense outline color="info" :label="e.kind === 'purchase' ? 'استرجاع' : 'استرداد'" @click="$emit('reverse')" />
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { money, dateTime, effectText, KINDS } from 'src/api/format'

const props = defineProps({ e: { type: Object, required: true }, admin: Boolean, hide: Boolean })
defineEmits(['reverse'])

const kind = computed(() => KINDS[props.e.kind] || { label: props.e.kind, color: '#374151' })
const canReverse = computed(() => props.admin && !props.e.reversed && !props.e.kind.endsWith('_refund'))
const mask = (s) => (props.hide ? '••••' : s)
</script>
