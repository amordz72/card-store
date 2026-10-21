<template>
  <q-page class="page">
    <q-btn flat dense no-caps color="primary" icon="arrow_forward" label="رجوع للزبائن" to="/customers" class="self-start" />
    <template v-if="c">
      <div class="card column q-gutter-sm">
        <div class="row justify-between items-center">
          <div>
            <div class="text-h6 text-weight-bold">{{ c.name }}</div>
            <div class="small muted ltr text-right">{{ c.phone }}</div>
          </div>
          <q-badge v-if="!c.active" color="grey" label="موقوف" />
        </div>
        <div class="grid-2">
          <div class="q-pa-sm rounded-borders column" style="background:#ECFDF3"><span class="small" style="color:#166534">الرصيد</span><b class="amount-pos" style="font-size:17px">{{ money(c.balance) }}</b></div>
          <div class="q-pa-sm rounded-borders column" style="background:#F7F8FB"><span class="small">{{ debt.label }} (الحد {{ money(c.debt_limit) }})</span><b :class="debt.cls" style="font-size:17px">{{ debt.text }}</b></div>
        </div>
        <div class="row q-gutter-sm items-start">
          <q-input v-model.number="limitDraft" class="col" dense outlined type="number" stack-label label="حد الدين (دج)" hint="يمنع الشحن الذاتي فقط؛ لا يمنعك أنت" />
          <q-btn outline color="primary" label="حفظ" @click="save({ debtLimit: limitDraft }, 'حُفظ حد الدين')" />
        </div>
        <q-toggle :model-value="c.self_topup" label="السماح بالشحن الذاتي (للزبون الموثوق)" color="warning"
          @update:model-value="(v) => save({ selfTopup: v }, v ? 'فُعّل الشحن الذاتي' : 'أُوقف الشحن الذاتي')" />
      </div>

      <div class="card column q-gutter-sm">
        <div class="text-weight-bold">تحويل جديد</div>
        <div class="grid-3">
          <q-btn v-for="k in manualKinds" :key="k" no-caps :unelevated="kind === k" :outline="kind !== k"
            :style="kind === k ? { background: KINDS[k].color, color: '#fff' } : {}" :label="KINDS[k].label" @click="kind = k" />
        </div>
        <div class="small q-pa-sm rounded-borders" style="background:#F7F8FB">{{ KINDS[kind].label }}: {{ KINDS[kind].help }}</div>
        <q-input v-model.number="amount" dense outlined type="number" inputmode="numeric" label="المبلغ (دج)" />
        <q-input v-model="note" dense outlined label="ملاحظة (اختيارية)" placeholder="مثال: دفع في المحل" />
        <div v-if="preview" class="small q-pa-sm rounded-borders" style="border:1px dashed #A5A9F0">{{ preview }}</div>
        <q-btn unelevated color="primary" size="lg" label="تسجيل التحويل" :loading="busy" :disable="!(amount > 0)" @click="doTransfer" />
      </div>

      <div class="section-title">كشف الحساب</div>
      <div class="card q-pa-none" style="overflow:hidden">
        <EntryRow v-for="e in entries" :key="e.entry_id" :e="e" admin @reverse="openReverse(e)" />
        <div v-if="!entries.length" class="text-center muted q-pa-lg">لا توجد حركات</div>
      </div>
      <PagerBar v-model:page="page" v-model:size="size" :total="total" :shown="entries.length" />

      <div class="section-title">إدارة الحساب</div>
      <div class="card column q-gutter-sm">
        <q-toggle :model-value="c.active" label="الحساب مفعّل" color="positive"
          @update:model-value="(v) => save({ active: v }, v ? 'فُعّل الحساب' : 'أُوقف الحساب وأُخرج من كل الأجهزة')" />
        <div class="row q-gutter-sm items-start">
          <q-input v-model="newPw" class="col" dense outlined label="كلمة سر جديدة (8 أحرف على الأقل)" input-class="ltr text-right" />
          <q-btn outline color="primary" label="تعيين" :disable="newPw.length < 8" @click="setPw" />
        </div>
        <q-btn flat color="negative" icon="devices" label="إخراجه من كل الأجهزة" @click="revoke" />
      </div>
    </template>
    <q-inner-loading :showing="!c" />

    <q-dialog v-model="revOpen">
      <q-card v-if="revEntry" style="width:100%;max-width:460px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold" style="color:#155E75">{{ revTitle }}</div>
          <div class="small" style="color:#164E63">لا تُحذف الحركة الأصلية؛ تُضاف حركة معاكسة بنفس المبلغ.{{ revEntry.kind === 'purchase' ? ' وتُلغى أكواد هذا الطلب (لا تعود للبيع لأن الزبون رآها).' : '' }}</div>
          <q-input v-model="revNote" dense outlined label="السبب (اختياري)" />
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat label="إلغاء" v-close-popup />
          <q-btn unelevated color="info" label="تأكيد الاسترداد" :loading="busy" @click="doReverse" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { newRequestId } from 'src/api/rpc'
import { money, debtView, KINDS } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import PagerBar from 'components/PagerBar.vue'

const props = defineProps({ id: { type: String, required: true } })
const cid = computed(() => Number(props.id))
const { busy, run } = useRun()

const c = ref(null)
const debt = computed(() => debtView(c.value?.debt || 0, false))
const limitDraft = ref(0)

async function loadCustomer () {
  const list = await run(() => api.customers())
  c.value = list?.find((x) => Number(x.customer_id) === cid.value) || null
  if (c.value) limitDraft.value = Number(c.value.debt_limit)
}

const entries = ref([])
const total = ref(0)
const page = ref(1)
const size = ref(10)
async function loadEntries () {
  const data = await run(() => api.entries({ customerId: cid.value, limit: size.value, offset: (page.value - 1) * size.value }))
  if (!data) return
  entries.value = data
  total.value = data.length ? Number(data[0].total_count) : 0
}
watch(page, loadEntries)
watch(size, () => { page.value === 1 ? loadEntries() : (page.value = 1) })

async function reloadAll () {
  await loadCustomer()
  await loadEntries()
}
onMounted(reloadAll)

// --- transfers
const manualKinds = ['debt', 'cash', 'pay', 'debt_refund', 'cash_refund', 'pay_refund']
const EFFECT = { debt: [1, 1], debt_refund: [-1, -1], cash: [1, 0], cash_refund: [-1, 0], pay: [0, -1], pay_refund: [0, 1] }
const kind = ref('debt')
const amount = ref(null)
const note = ref('')
let transferRequest = null
watch([kind, amount, note], () => { transferRequest = null })

const preview = computed(() => {
  if (!c.value || !(amount.value > 0)) return ''
  const [b, d] = EFFECT[kind.value]
  const nb = Number(c.value.balance) + b * amount.value
  const nd = Number(c.value.debt) + d * amount.value
  const dv = debtView(nd, false)
  let s = `بعد التسجيل: الرصيد ${money(nb)}${nb < 0 ? ' (غير مسموح)' : ''} · ${dv.label} ${dv.text}`
  if (d > 0 && nd > Number(c.value.debt_limit)) s += ` — تنبيه: فوق حد الدين (${money(c.value.debt_limit)})، مسموح لك كمدير`
  return s
})

async function doTransfer () {
  transferRequest = transferRequest || newRequestId()
  const res = await run(() => api.transfer(cid.value, kind.value, amount.value, note.value, transferRequest),
    { success: (r) => `سُجّل: ${KINDS[kind.value].label} ${money(amount.value)}${r.over_limit ? ' — فوق حد الدين' : ''}` })
  if (!res) return
  amount.value = null
  note.value = ''
  transferRequest = null
  page.value = 1
  await reloadAll()
}

// --- reverse
const revOpen = ref(false)
const revEntry = ref(null)
const revNote = ref('')
let reverseRequest = null
const revTitle = computed(() => revEntry.value ? `استرداد: ${KINDS[revEntry.value.kind].label} ${money(revEntry.value.amount)}` : '')

function openReverse (e) {
  revEntry.value = e
  revNote.value = ''
  reverseRequest = newRequestId()
  revOpen.value = true
}

async function doReverse () {
  const res = await run(() => api.reverse(revEntry.value.entry_id, revNote.value, reverseRequest), { success: 'تم الاسترداد.' })
  if (!res) return
  revOpen.value = false
  await reloadAll()
}

// --- settings
async function save (patch, msg) {
  const ok = await run(() => api.updateCustomer(cid.value, patch).then(() => true), { success: msg })
  if (ok) loadCustomer()
}

const newPw = ref('')
async function setPw () {
  const ok = await run(() => api.setPassword(cid.value, newPw.value).then(() => true),
    { success: 'تم تعيين كلمة السر وأُخرج الزبون من كل الأجهزة.' })
  if (ok) newPw.value = ''
}

function revoke () {
  run(() => api.revokeSessions(cid.value), { success: (n) => `أُلغيت ${n} جلسة.` })
}
</script>
