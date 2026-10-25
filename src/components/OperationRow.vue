<template>
  <div style="border-top:1px solid #EEF0F5">
    <q-item clickable class="q-px-sm" @click="$emit('open')">
      <q-item-section avatar>
        <div class="brand-tile" style="width:44px;height:44px;font-size:10px;line-height:1.1" :style="{ background: brandColor(op.brand) }">{{ op.brand }}</div>
      </q-item-section>
      <q-item-section>
        <q-item-label class="text-weight-medium">{{ op.product_name }}{{ op.qty > 1 ? ' × ' + op.qty : '' }}</q-item-label>
        <q-item-label v-if="op.customer_name && !shop" caption><span class="q-px-sm rounded-borders" style="background:#FFF1E8;color:#9A3412">{{ op.customer_name }}</span></q-item-label>
        <q-item-label caption>{{ dateTime(op.created_at) }} · رقم {{ op.order_id }}</q-item-label>
      </q-item-section>
      <q-item-section side top class="items-end q-gutter-xs">
        <span class="text-weight-bold text-dark">{{ money(op.base_amount) }}</span>
        <span class="badge" :style="{ background: op.status === 'done' ? '#15803D' : '#6B7280' }">{{ op.status === 'done' ? 'ناجحة' : 'مسترجعة' }}</span>
      </q-item-section>
    </q-item>
    <div class="grid-3 q-px-md q-pb-sm small muted">
      <span>{{ isShop ? 'سعر الشراء' : 'المقتطع' }}<br><b style="color:#B45309">{{ mask(money(op.charged_amount)) }}</b></span>
      <span v-if="isShop">ربحي<br><b :class="profitClass">{{ mask(profitText) }}</b></span>
      <span v-else>{{ admin ? 'ربح الزبون' : 'ربحك' }}<br><b :class="op.base_amount - op.charged_amount >= 0 ? 'amount-info' : 'amount-neg'">{{ mask(signed(op.base_amount - op.charged_amount)) }}</b></span>
      <span>الرصيد بعد<br><b class="text-dark">{{ mask(money(op.balance_after)) }}</b></span>
      <span v-if="admin && !isShop">ربحي<br><b :class="profitClass">{{ profitText }}</b></span>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { money, dateTime, brandColor } from 'src/api/format'

const props = defineProps({ op: { type: Object, required: true }, admin: Boolean, shop: Boolean, hide: Boolean })
defineEmits(['open'])
const mask = (s) => (props.hide ? '••••' : s)
const isShop = computed(() => props.shop || !!props.op.is_shop)
const signed = (n) => (n < 0 ? '−' : '') + money(Math.abs(n))
// Shop orders: selling price − purchase cost. Customer orders (admin view): amount charged − purchase cost.
const profitText = computed(() => (props.op.profit == null ? 'غير معروف' : signed(Number(props.op.profit))))
const profitClass = computed(() => (props.op.profit == null ? '' : props.op.profit >= 0 ? 'amount-info' : 'amount-neg'))
</script>
