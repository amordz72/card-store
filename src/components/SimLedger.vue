<template>
  <!-- The SIM ledger (Flexy Core 0052, owner 2026-10-28): every session on this SIM and what it did to the
       balance; every balance read closes the period before it. The read is always the confirmed balance;
       a difference is written beside it, and operations get their verdict only when one explanation exists. -->
  <div class="column q-gutter-sm">
    <div class="row items-center q-gutter-xs">
      <span class="small muted">المدة</span>
      <q-btn v-for="d in [1, 7, 30]" :key="d" dense no-caps size="sm" :outline="days !== d" :unelevated="days === d" color="primary"
        :label="d === 1 ? 'يوم' : d + ' أيام'" @click="days = d" />
      <q-space />
      <q-btn dense flat no-caps size="sm" icon="refresh" :loading="busy" @click="load" />
    </div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <div v-if="summary" class="box column q-gutter-xs">
      <div><span class="muted">الرصيد المؤكد</span> <b>{{ money(summary.confirmed) }}</b>
        <span v-if="summary.confirmed_at" class="muted small"> · قُرئ {{ clock(summary.confirmed_at) }}</span></div>
      <div v-if="summary.deducted_since || summary.pending_count" class="small">
        بعد القراءة: خُصم مؤكد {{ money(summary.deducted_since) }}
        <span v-if="summary.pending_count"> · غير محسوم {{ money(summary.pending_since) }} ({{ summary.pending_count }})</span>
      </div>
      <div v-if="summary.confirmed !== null && (summary.deducted_since || summary.pending_since)" class="small muted">
        المتوقع الآن: {{ money(summary.confirmed - summary.deducted_since - summary.pending_since) }}، حتى القراءة التالية
      </div>
    </div>

    <div v-if="!busy && lines.length === 0 && !error" class="small muted">لا جلسات في هذه المدة</div>

    <div v-for="l in lines" :key="l.job" class="line" :class="lineClass(l)">
      <template v-if="l.kind === 'reading'">
        <div class="row items-center no-wrap">
          <span class="col"><b>قراءة رصيد: {{ money(l.reading) }}</b><span v-if="!l.closes" class="muted small"> · من المختبر</span></span>
          <span class="muted small">{{ clock(l.at) }}</span>
        </div>
        <div v-if="l.close" class="small">
          <span v-if="l.close.prev_amount !== null">{{ money(l.close.prev_amount) }} ← {{ money(l.close.amount) }} · خرج {{ money(l.close.delta) }}</span>
          <span v-if="l.close.explained !== null && l.close.prev_amount !== null"> · مفسّر {{ money(l.close.explained) }}</span>
          <div :class="stateClass(l.close.state)">{{ STATES[l.close.state] }}<span v-if="noteText(l.close.note)"> · {{ noteText(l.close.note) }}</span></div>
          <div v-if="l.close.unexplained" class="text-negative">الفارق غير المفسّر: {{ money(l.close.unexplained) }}</div>
          <div class="muted">أُغلقت الفترة {{ clock(l.close.closed_at) }}<span v-if="l.close.verdicts?.length"> · حسمت {{ l.close.verdicts.length }} عملية</span></div>
        </div>
        <div v-else-if="l.closes" class="small muted">لم تُغلق فترتها بعد (خلال دقيقة)</div>
      </template>
      <template v-else>
        <div class="row items-center no-wrap">
          <span class="col">{{ SOURCES[l.source] }} · {{ KINDS[l.kind] }}<span v-if="l.offer"> {{ l.offer }}</span><span v-if="l.amount !== null"> {{ money(l.amount) }}</span>
            <span v-if="l.phone" class="muted"> · <bdi class="ltr">{{ l.phone }}</bdi></span></span>
          <span class="muted small">{{ clock(l.at) }}</span>
        </div>
        <div class="small row items-center q-gutter-xs">
          <q-badge :color="DEDUCTION[effective(l)].color" :label="DEDUCTION[effective(l)].label" />
          <span class="muted">{{ REASONS[l.reason] || l.reason }}</span>
          <span v-if="l.operation_status" class="muted">· العملية: {{ STATUS[l.operation_status] || l.operation_status }}</span>
        </div>
        <div v-if="l.settled && l.deduction === 'unknown'" class="small" :class="l.settled.deducted === null ? 'text-deep-orange' : 'text-positive'">
          {{ l.settled.deducted === null ? 'بلا حكم في فترة' : 'حُسمت' }} بقراءة {{ clock(l.settled.reading_at) }} · أُغلقت {{ clock(l.settled.closed_at) }}
          <span v-if="l.settled.verdict"> · صارت {{ STATUS[l.settled.verdict] }}</span>
        </div>
        <div v-else-if="!l.settled && l.deduction !== 'no'" class="small muted">تنتظر القراءة التالية</div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import { simLedger } from 'src/api/flexy'

const props = defineProps({ simUuid: { type: String, required: true } })
const days = ref(7)
const busy = ref(false)
const error = ref('')
const lines = ref([])
const summary = ref(null)

const SOURCES = { operation: 'الزر/تطبيق', lab: 'المختبر', system: 'النظام' }
const KINDS = { transfer: 'تحويل', offer: 'عرض', discovery: 'استكشاف', reading: 'قراءة رصيد', read_failed: 'قراءة رصيد فشلت', other: 'جلسة' }
const DEDUCTION = {
  yes: { label: 'خُصم', color: 'negative' },
  no: { label: 'لم يُخصم', color: 'grey-6' },
  unknown: { label: 'غير محسوم', color: 'orange-8' }
}
const STATUS = { success: 'ناجحة', failed: 'فاشلة', not_sent: 'لم تُرسل', rejected: 'مرفوضة', review: 'مراجعة', accepted: 'مقبولة', running: 'جارية', queued: 'في الطابور' }
const STATES = { first: 'أول قراءة', matched: 'مطابق', difference: 'فرق', ambiguous: 'بلا حكم', unreadable: 'قراءة بلا مبلغ' }
const REASONS = {
  READING: '',
  READ_NOT_DELIVERED: 'لم تصل إلى الشبكة',
  READ_UNCLEAR: 'رد بلا مبلغ',
  NO_MONEY_STEP: 'بلا خطوة مال',
  OPERATION_SUCCESS: 'العملية ناجحة',
  OPERATION_NOT_SENT: 'العملية لم تُرسل',
  OPERATION_REJECTED: 'رفضتها الشبكة',
  OPERATION_FAILED: 'العملية فاشلة',
  OPERATION_OPEN: 'العملية بلا حكم بعد',
  NO_CONFIRM_SENT: 'لم يُرسل التأكيد «1»',
  NETWORK_SUCCESS_TEXT: 'ردت الشبكة بنص النجاح',
  CONFIRM_NO_KNOWN_REPLY: 'أُرسل التأكيد ولم يأتِ نص معروف',
  NETWORK_PROCESSING: 'الشبكة: قيد المعالجة',
  OFFER_NOT_IN_CATALOG: 'عرض ليس في القائمة: مبلغه مجهول',
  MENU_ONLY: 'قائمة فقط',
  LAB_UNKNOWN_CODE: 'كود غير معروف مع رد: مبلغه مجهول',
  UNKNOWN_SESSION: 'جلسة غير معروفة: مبلغها مجهول'
}
const NOTES = {
  FIRST_READ: '',
  ALL_EXPLAINED: 'كل ما خرج مفسّر',
  ONE_COMBINATION: 'تفسير واحد، فحُسمت العمليات',
  PATH_NOT_PROVEN: 'مفسّر، لكن المسار لم يثبت خصمه بعد: لا حكم على العمليات',
  DROP_NOT_EXPLAINED: 'نقص لا تفسره الجلسات',
  RISE_NOT_EXPLAINED: 'زيادة لا تفسرها الجلسات (شحن؟)',
  NO_COMBINATION_EXPLAINS: 'لا تركيبة من الجلسات تفسر الفارق',
  SEVERAL_COMBINATIONS: 'أكثر من تفسير ممكن',
  SESSION_RUNNING_DURING_READ: 'جلسة كانت تعمل أثناء القراءة',
  SESSION_AMOUNT_UNKNOWN: 'جلسة مبلغها مجهول',
  DEDUCTION_AMOUNT_UNKNOWN: 'خصم مبلغه مجهول',
  TOO_MANY_OPEN_SESSIONS: 'جلسات غير محسومة كثيرة',
  READ_HAS_NO_AMOUNT: 'قراءة بلا مبلغ'
}
const noteText = (n) => {
  if (!n) return ''
  const wide = n.endsWith('_WITH_PREVIOUS_PERIOD')
  const base = NOTES[wide ? n.slice(0, -'_WITH_PREVIOUS_PERIOD'.length) : n] ?? n
  return wide ? base + '، مع الفترة السابقة' : base
}
const money = (n) => (n === null || n === undefined ? '—' : Number(n).toLocaleString('ar-DZ', { maximumFractionDigits: 2 }) + ' دج')
const clock = (v) => (v ? new Date(v).toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers' }) : '—')
// An unknown session a period settled shows what the period found.
const effective = (l) => (l.deduction === 'unknown' && l.settled?.deducted !== null && l.settled?.deducted !== undefined ? (l.settled.deducted ? 'yes' : 'no') : l.deduction)
const stateClass = (s) => (s === 'matched' || s === 'first' ? 'text-positive' : s === 'difference' ? 'text-negative' : 'text-deep-orange')
const lineClass = (l) => (l.kind === 'reading' ? 'reading' : effective(l) === 'no' ? 'quiet' : '')

async function load () {
  if (!props.simUuid) return
  busy.value = true
  error.value = ''
  try {
    const res = await simLedger(props.simUuid, days.value)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    lines.value = res.body.lines || []
    summary.value = res.body.summary || null
  } catch (e) {
    error.value = 'تعذرت قراءة السجل: ' + (e.message || 'FLEXY_CORE')
  } finally {
    busy.value = false
  }
}

watch(() => [props.simUuid, days.value], load)
onMounted(load)
</script>

<style scoped>
.box { border: 1px solid #E3E6EC; border-radius: 8px; padding: 8px 10px; }
.line { border-top: 1px solid #EEF0F4; padding-top: 6px; }
.line.reading { background: #F6F8FB; border-radius: 6px; padding: 6px 8px; }
.line.quiet { opacity: 0.7; }
.small { font-size: 12px; }
.muted { color: #6B7280; }
.ltr { direction: ltr; unicode-bidi: isolate; }
</style>
