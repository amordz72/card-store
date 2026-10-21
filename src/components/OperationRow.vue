<template>
  <div style="border-top:1px solid #EEF0F5">
    <q-item clickable class="q-px-sm" @click="$emit('open')">
      <q-item-section avatar>
        <div class="brand-tile" style="width:44px;height:44px;font-size:10px;line-height:1.1" :style="{ background: brandColor(op.brand) }">{{ op.brand }}</div>
      </q-item-section>
      <q-item-section>
        <q-item-label class="text-weight-medium">{{ op.product_name }}{{ op.qty > 1 ? ' × ' + op.qty : '' }}</q-item-label>
        <q-item-label v-if="op.customer_name && !shop" caption><span class="q-px-sm rounded-borders" style="background:#EEF0FF;color:#3730A3">{{ op.customer_name }}</span></q-item-label>
        <q-item-label caption>{{ dateTime(op.created_at) }} · رقم {{ op.order_id }}</q-item-label>
      </q-item-section>
      <q-item-section side top class="items-end q-gutter-xs">
        <span class="text-weight-bold text-dark">{{ money(op.base_amount) }}</span>
        <span class="badge" :style="{ background: op.status === 'done' ? '#15803D' : '#6B7280' }">{{ op.status === 'done' ? 'ناجحة' : 'مسترجعة' }}</span>
      </q-item-section>
    </q-item>
    <div class="grid-3 q-px-md q-pb-sm small muted">
      <span>المقتطع<br><b style="color:#B45309">{{ mask(money(op.charged_amount)) }}</b></span>
      <span>{{ admin ? (op.is_shop ? 'ربحي حسب نسبتي' : 'خصم الزبون') : shop ? 'ربحي حسب نسبتي' : 'ربحك' }}<br><b class="amount-info">{{ mask(money(op.base_amount - op.charged_amount)) }}</b></span>
      <span>الرصيد بعد<br><b class="text-dark">{{ mask(money(op.balance_after)) }}</b></span>
      <span v-if="admin || shop">{{ op.is_shop ? 'الربح الحقيقي' : 'ربحي' }}<br><b :class="op.profit == null ? '' : op.profit >= 0 ? 'amount-info' : 'amount-neg'">{{ op.profit == null ? 'غير معروف' : (op.profit < 0 ? '−' : '') + money(op.profit) }}</b></span>
    </div>
  </div>
</template>

<script setup>
import { money, dateTime, brandColor } from 'src/api/format'

const props = defineProps({ op: { type: Object, required: true }, admin: Boolean, shop: Boolean, hide: Boolean })
defineEmits(['open'])
const mask = (s) => (props.hide ? '••••' : s)
</script>
