<template>
  <div style="border-top:1px solid #EEF0F5">
    <q-item clickable class="q-px-sm" @click="tap">
      <q-item-section avatar>
        <div class="brand-tile" style="width:44px;height:44px;font-size:10px;line-height:1.1" :style="{ background: brandColor(op.brand) }">{{ op.brand }}</div>
      </q-item-section>
      <q-item-section>
        <q-item-label class="text-weight-medium">{{ title }}</q-item-label>
        <q-item-label v-if="op.phone" caption><bdi dir="ltr">{{ op.phone }}</bdi></q-item-label>
        <!-- s168: an Idoom top-up shows its line, a game top-up its player -->
        <q-item-label v-if="op.kind === 'idoom' && op.target" caption>الخط <bdi dir="ltr">{{ op.target }}</bdi></q-item-label>
        <q-item-label v-if="op.kind === 'game' && op.target" caption>المعرّف <bdi dir="ltr">{{ op.target }}</bdi></q-item-label>
        <!-- 📱 a phone / 💻 a computer (owner 2026-11-01: «كيف أعرف أن هذه الشريحة هاتف») -->
        <q-item-label v-if="lastSim" caption>الشريحة: <q-icon :name="onPhone(lastSim) ? 'smartphone' : 'computer'" :color="onPhone(lastSim) ? 'deep-purple' : 'blue-grey'" size="16px" class="q-mx-xs" :title="onPhone(lastSim) ? 'هاتف' : 'كمبيوتر'" /><bdi dir="ltr">{{ simLine(lastSim) }}</bdi></q-item-label>
        <q-item-label v-if="before" caption>رصيد الشريحة قبل: {{ before }}</q-item-label>
        <q-item-label v-if="op.customer_name && !shop" caption><span class="q-px-sm rounded-borders" style="background:var(--brand-soft, #FFF1E8);color:var(--brand-deep, #9A3412)">{{ op.customer_name }}</span></q-item-label>
        <q-item-label caption>{{ dateTime(op.created_at) }}<span v-if="op.source !== 'core'"> · رقم {{ op.op_id }}</span></q-item-label>
      </q-item-section>
      <q-item-section side top class="items-end q-gutter-xs">
        <span class="text-weight-bold text-dark">{{ money(op.base_amount) }}</span>
        <span class="badge" :style="{ background: badge.color }">{{ badge.label }}</span>
      </q-item-section>
    </q-item>
    <div v-if="isCard" class="grid-3 q-px-md q-pb-sm small muted">
      <span>{{ isShop ? 'سعر الشراء' : 'المقتطع' }}<br><b style="color:#B45309">{{ mask(money(op.charged_amount)) }}</b></span>
      <span v-if="isShop">ربحي<br><b :class="profitClass">{{ mask(profitText) }}</b></span>
      <span v-else>{{ admin ? 'ربح الزبون' : 'ربحك' }}<br><b :class="op.base_amount - op.charged_amount >= 0 ? 'amount-info' : 'amount-neg'">{{ mask(signed(op.base_amount - op.charged_amount)) }}</b></span>
      <span>الرصيد بعد<br><b class="text-dark">{{ mask(money(op.balance_after)) }}</b></span>
      <span v-if="admin && !isShop">ربحي<br><b :class="profitClass">{{ profitText }}</b></span>
    </div>
    <div v-else-if="op.source === 'flexy'" class="grid-3 q-px-md q-pb-sm small muted">
      <span>المقتطع<br><b style="color:#B45309">{{ mask(money(op.charged_amount)) }}</b></span>
      <span>الرصيد بعد<br><b class="text-dark">{{ mask(money(op.balance_after)) }}</b></span>
    </div>
    <!-- A Flexy row opens in place: what happened, the network's reply, and (owner's own) the SIM -->
    <div v-if="opened" class="q-px-md q-pb-sm column q-gutter-xs small">
      <div v-if="op.kind !== 'idoom' && op.kind !== 'game'" class="text-weight-bold">{{ explain(op.outcome_code, op.status) }}</div>
      <!-- the raw reply: the owner only (owner 2026-11-01) -->
      <template v-if="op.network_reply && admin">
        <div>رد الشبكة:</div>
        <div class="muted ltr text-right" style="white-space:pre-wrap">{{ op.network_reply }}</div>
      </template>
      <template v-if="op.sims && op.sims.length">
        <div v-for="(w, i) in op.sims.slice(0, -1)" :key="i" class="muted">
          تحوّلت من <q-icon :name="onPhone(w) ? 'smartphone' : 'computer'" size="14px" class="q-mx-xs" /><bdi dir="ltr">{{ simLine(w) }}</bdi>: {{ movedWhy(op.sims[i + 1].moved_because) }}
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { money, dateTime, brandColor } from 'src/api/format'
import { algeriaTime, explain, movedWhy, simLine } from 'src/api/flexyExplain'

const props = defineProps({ op: { type: Object, required: true }, admin: Boolean, shop: Boolean, hide: Boolean })
const emit = defineEmits(['open'])
const mask = (s) => (props.hide ? '••••' : s)
const isCard = computed(() => (props.op.source || 'card') === 'card')
// s168: a top-up (Idoom, game) is judged by its own state, not by its card order
const TOPUP = {
  success: { label: 'تمت', color: '#15803D' }, done: { label: 'تمت', color: '#15803D' },
  likely_success: { label: 'تمت على الأرجح', color: '#0F766E' },
  queued: { label: 'تنتظر', color: '#6B7280' }, claimed: { label: 'جارية', color: '#2563EB' },
  review: { label: 'مراجعة', color: '#C2410C' },
  failed: { label: 'لم تتم', color: '#B91C1C' }, used_card: { label: 'لم تتم', color: '#B91C1C' },
  cancelled: { label: 'أُلغيت', color: '#6B7280' }
}
const isShop = computed(() => props.shop || !!props.op.is_shop)
const signed = (n) => (n < 0 ? '−' : '') + money(Math.abs(n))
// Shop orders: selling price − purchase cost. Customer orders (admin view): amount charged − purchase cost.
const profitText = computed(() => (props.op.profit == null ? 'غير معروف' : signed(Number(props.op.profit))))
const profitClass = computed(() => (props.op.profit == null ? '' : props.op.profit >= 0 ? 'amount-info' : 'amount-neg'))

const title = computed(() => {
  const o = props.op
  if (o.kind === 'idoom') return 'تعبئة إيدوم · ' + o.product_name
  if (o.kind === 'game') return 'شحن لعبة · ' + o.product_name
  if (isCard.value) return o.product_name + (o.qty > 1 ? ' × ' + o.qty : '')
  return o.category === 'offer' ? 'عرض ' + (o.offer_label || '') : 'فليكسي'
})

// Cards: done or refunded. Flexy (the shop's job, or the owner's in Flexy Core): the send's state.
const FLEXY = {
  success: { label: 'ناجحة', color: '#15803D' },
  accepted: { label: 'قبلتها الشبكة', color: '#15803D' },
  failed: { label: 'فاشلة', color: '#B91C1C' },
  rejected: { label: 'رفضتها الشبكة', color: '#B91C1C' },
  not_sent: { label: 'لم تُرسل', color: '#6B7280' },
  review: { label: 'قيد المراجعة', color: '#C2410C' }
}
const badge = computed(() => {
  if ((props.op.kind === 'idoom' || props.op.kind === 'game') && TOPUP[props.op.job_status]) return TOPUP[props.op.job_status]
  if (isCard.value) return props.op.status === 'done' ? { label: 'ناجحة', color: '#15803D' } : { label: 'مسترجعة', color: '#6B7280' }
  return FLEXY[props.op.status] || { label: 'جارية', color: '#2563EB' }
})

// The owner only: the SIM that ran a Flexy row (its own, or a shop's from Flexy Core)
// a phone station is named «هاتف الإدارة · <model>» (agent phone-*); a computer by its Windows name
const onPhone = (w) => /هاتف|phone/i.test(String(w?.computer_name || ''))
const lastSim = computed(() => (props.op.sims?.length ? props.op.sims[props.op.sims.length - 1] : null))

// The owner only: the SIM's estimated balance before it (SHOP-OPS-SIM-AND-BALANCE step 2): the last
// real reading minus what ran since. Arsselli names the account.
const before = computed(() => {
  const b = props.op.balance_before
  if (!b) return null
  if (b.amount == null) return 'غير معروف: لم يُقرأ رصيدها بعد'
  return money(b.amount) + ' (تقديري' + (b.account ? '، الحساب ' + b.account : '') +
    (b.reading_at ? '، آخر قراءة ' + algeriaTime(b.reading_at) : '') + (b.ambiguous ? '، فيه عملية غير محسومة' : '') + ')'
})

const opened = ref(false)
function tap () {
  if (isCard.value) emit('open')
  else opened.value = !opened.value
}
</script>
