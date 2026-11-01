<template>
  <q-page class="page">
    <div v-if="!access.enabled.value" class="card text-center column q-gutter-sm q-pa-lg">
      <q-icon name="wifi_off" size="40px" color="grey-6" class="self-center" />
      <div class="text-weight-bold">تعبئة إيدوم غير مفعّلة لحسابك</div>
      <div class="small muted">اطلب من المحل تفعيلها.</div>
    </div>

    <template v-else>
      <q-badge v-if="!access.phoneOnline.value" color="negative" class="q-pa-sm self-start">🔴 الخدمة متوقفة الآن — حاول بعد قليل</q-badge>

      <div class="card column q-gutter-sm">
        <div v-if="pretty" class="idoom-line text-center" dir="ltr">{{ pretty }}</div>
        <div v-if="lineOk" class="text-center"><q-badge :color="is4g ? 'indigo' : 'purple'">{{ is4g ? '4G LTE' : 'ADSL / FTTH' }}</q-badge></div>
        <div v-if="lineOk && known" class="text-center">
          <q-badge color="primary" class="q-pa-sm text-subtitle2"><bdi dir="ltr">idoom · {{ known.offer }}</bdi></q-badge>
          <div class="small muted q-mt-xs">من آخر تعبئة لك لهذا الخط</div>
        </div>
        <q-input v-model="line" clearable @focus="(e) => e.target.select()" @clear="line = ''" dense outlined label="رقم الخط: ثابت 9 أرقام أو 4G يبدأ بـ 213" inputmode="tel" maxlength="16"
          placeholder="0XXXXXXXX" input-class="ltr text-right" />
        <div class="small muted">يُخصم ثمن البطاقة من رصيدك عند الطلب. إن لم تتم التعبئة يُعاد المبلغ تلقائيًا.</div>
      </div>

      <div v-if="lineOk" class="card column q-gutter-sm">
        <div class="text-weight-bold">اختر البطاقة</div>
        <!-- The same short rows as «تعبئة» (owner 2026-11-01) -->
        <div v-if="lineBusy" class="busy-line">⏳ تعبئة جارية لهذا الخط · منذ {{ busySince }} — انتظر ردها</div>
        <button v-for="c in cards" :key="c.product_id" type="button" class="idoom-row" :disabled="busy || !!lineBusy || !access.phoneOnline.value" @click="confirmCharge(c)">
          <span class="col">{{ c.name }}</span>
          <span class="price">{{ money(c.base_price) }}</span>
        </button>
        <div v-if="!cards.length" class="muted">لا توجد بطاقات {{ is4g ? 'Idoom 4G' : 'Idoom ADSL' }} متوفرة الآن</div>
      </div>

      <div class="row items-center justify-between q-mt-md">
        <div class="text-weight-bold">تعبئاتي</div>
        <q-btn flat dense icon="refresh" aria-label="تحديث" @click="reloadAll" />
      </div>
      <div class="card q-pa-none">
        <div v-for="j in rows" :key="j.job_id" class="op-row">
          <div class="row items-center no-wrap q-gutter-sm">
            <span dir="ltr" class="text-weight-bold col">{{ spaced(j.line) }}</span>
            <q-badge :color="view(j).color" class="q-pa-xs">{{ view(j).label }}</q-badge>
          </div>
          <div class="small muted">
            {{ j.product_name }} · {{ money(j.charged_amount) }} · {{ when(j.created_at) }}
            <span v-if="j.offer"> · <bdi dir="ltr">{{ j.offer }}</bdi></span>
          </div>
          <!-- owner decision: no cancel on the first attempt, only while the automatic second attempt waits -->
          <q-btn v-if="j.status === 'queued' && j.attempt > 1" flat dense size="sm" color="negative" label="إلغاء الطلب" :disable="busy" @click="cancel(j)" />
        </div>
        <div v-if="!busy && !rows.length" class="text-center muted q-pa-lg">لا توجد تعبئات بعد</div>
      </div>
      <LoadMoreBar :total="total" :shown="rows.length" :size="size" :loading="loadingMore" @more="more" />
    </template>
  </q-page>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { useLoadMore } from 'src/composables/useLoadMore'
import { useIdoomAccess } from 'src/composables/useIdoomAccess'
import * as api from 'src/api/customer'
import { money } from 'src/api/format'
import LoadMoreBar from 'components/LoadMoreBar.vue'
import { useLineBusy } from 'src/composables/useLineBusy'

const customer = useCustomerStore()
const buyer = useBuyer()
const access = useIdoomAccess()
const { busy, run } = useRun()

// What the customer sees for each state (the money side is automatic). Short and general on purpose:
// the reason of a failure (e.g. a used card) is for the owner only, in his page.
function view (j) {
  if (j.attempt > 1 && ['queued', 'claimed'].includes(j.status)) return { label: 'فشل الشحن — جاري الإعادة', color: 'warning' }
  if (j.status === 'success') return { label: 'تمت التعبئة', color: 'positive' }
  if (j.status === 'likely_success') return { label: 'تمت على الأرجح', color: 'teal' }
  if (j.status === 'queued') return { label: 'في الانتظار', color: 'grey-7' }
  if (j.status === 'claimed') return { label: 'قيد التنفيذ', color: 'info' }
  if (j.status === 'review') return { label: 'قيد المراجعة من المحل', color: 'deep-orange' }
  if (j.status === 'cancelled') return { label: 'أُلغيت — أُعيد المبلغ', color: 'grey' }
  if (j.status === 'used_card') return { label: 'لم تتم — أُعيد المبلغ', color: 'orange-8' }
  if (j.status === 'failed') return { label: 'لم تتم — أُعيد المبلغ', color: 'orange-8' }
  return { label: j.status, color: 'grey' }
}

const line = ref('')
const digits = computed(() => line.value.replace(/\D/g, ''))
const lineOk = computed(() => /^(0\d{8}|213\d{9})$/.test(digits.value))
const is4g = computed(() => /^213\d{9}$/.test(digits.value))
const spaced = (d) => (d || '').replace(/^(\d{3})(\d{3})(\d{3})(\d{3})?$/, (m, a, b, c, e) => [a, b, c, e].filter(Boolean).join(' '))
const pretty = computed(() => spaced(digits.value))
const when = (t) => new Date(t).toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers' })

// IDOOM cards that fit the line (same rule as the database: "4g"/"lte" in the name marks a 4G card)
const catalog = ref([])
const cards = computed(() => catalog.value.filter((p) => p.category === 'net' && p.available &&
  /idoom/i.test(p.brand) && /4g|lte/i.test(p.brand + ' ' + p.name) === is4g.value))

const known = ref(null)
watch(digits, async () => {
  known.value = null
  if (!lineOk.value) return
  const want = digits.value
  const r = await api.idoomLineInfo(customer.token, want).catch(() => null)
  if (want === digits.value) known.value = r
})

const { rows, total, loadingMore, reset, refresh, more, size } =
  useLoadMore((limit, offset) => run(() => api.idoomJobs(customer.token, limit, offset)), { key: 'job_id' })
const { busyLine: lineBusy, busySince } = useLineBusy(() => rows.value, () => digits.value)
const open = computed(() => rows.value.some((j) => ['queued', 'claimed'].includes(j.status)))

async function reloadAll () {
  await access.refresh()
  if (access.enabled.value) await refresh()
}

function confirmCharge (c) {
  Dialog.create({
    title: 'تأكيد التعبئة',
    html: true,
    message: `تعبئة الخط <b dir="ltr">${pretty.value}</b><br>البطاقة: <b>${c.name}</b><br>يُخصم من رصيدك ثمن هذه البطاقة.`,
    cancel: 'إلغاء',
    ok: 'نعم، عبّئ'
  }).onOk(async () => {
    const r = await run(() => api.idoomCreate(customer.token, c.product_id, digits.value, crypto.randomUUID()),
      { success: 'أُرسل الطلب. تابع حالته في «تعبئاتي».' })
    if (r) { buyer.refresh(); reset() }
  })
}

function cancel (j) {
  Dialog.create({ title: 'إلغاء الطلب', message: 'يُعاد المبلغ إلى رصيدك.', cancel: 'رجوع', ok: 'إلغاء الطلب' })
    .onOk(async () => {
      if (await run(() => api.idoomCancel(customer.token, j.job_id).then(() => true), { success: 'أُلغي الطلب وأُعيد المبلغ.' })) {
        buyer.refresh()
        refresh()
      }
    })
}

// While a top-up is waiting or running, follow it every 5 s (and the phone status every 30 s)
let timer = null
let tick = 0
onMounted(async () => {
  await access.refresh()
  if (!access.enabled.value) return
  const data = await run(() => buyer.catalog())
  if (data) catalog.value = data
  reset()
  timer = setInterval(async () => {
    // Not while hidden (the database's load, 2026-10-30)
    if (document.visibilityState !== 'visible') return
    tick++
    if (tick % 6 === 0) access.refresh()
    if (open.value) {
      const wasOpen = rows.value.filter((j) => ['queued', 'claimed'].includes(j.status)).length
      await refresh()
      // a top-up just finished (or was refunded): the balance changed
      if (rows.value.filter((j) => ['queued', 'claimed'].includes(j.status)).length < wasOpen) buyer.refresh()
    }
  }, 5000)
})
onUnmounted(() => clearInterval(timer))
</script>

<style scoped>
.idoom-line { font-size: 2.2rem; font-weight: 700; letter-spacing: 2px; }
.op-row { padding: 10px 14px; border-bottom: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
.op-row:last-child { border-bottom: 0; }
.idoom-row { display: flex; align-items: center; gap: 8px; width: 100%; padding: 6px 12px; border: 1px solid #E3E6EC; border-radius: 10px;
  background: #fff; font: inherit; color: inherit; text-align: right; cursor: pointer; }
.idoom-row:disabled { opacity: 0.5; cursor: default; }
.idoom-row .price { background: var(--q-primary); color: #fff; border-radius: 8px; padding: 3px 8px; font-weight: 700; white-space: nowrap; min-width: 76px; text-align: center; }
.busy-line { background: #E3F2FD; color: #0D47A1; border-radius: 8px; padding: 6px 10px; font-weight: 600; }
</style>
