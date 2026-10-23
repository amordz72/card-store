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
        <q-btn outline dense no-caps color="primary" icon="sell" label="أسعار ونسب هذا الزبون" class="self-start"
          :to="{ path: '/prices', query: { who: id } }" />
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
      <LoadMoreBar :total="total" :shown="entries.length" :size="size" :loading="loadingMore" @more="more" />

      <div class="section-title">إدارة الحساب</div>
      <q-form class="card column q-gutter-sm" @submit.prevent="saveInfo">
        <div class="text-weight-bold">بيانات الزبون</div>
        <q-input v-model="infoDraft.name" dense outlined label="الاسم" />
        <q-input v-model="infoDraft.phone" dense outlined label="رقم الهاتف (يدخل به)" inputmode="tel" input-class="ltr text-right"
          hint="10 أرقام يبدأ بـ 05 أو 06 أو 07، ولا يتكرر لزبونين" />
        <q-btn type="submit" outline color="primary" label="حفظ البيانات" class="self-start" :loading="busy"
          :disable="!infoDraft.name.trim() || !infoDraft.phone.trim() || (infoDraft.name.trim() === c.name && infoDraft.phone.trim() === c.phone)" />
      </q-form>
      <div class="card column q-gutter-sm">
        <q-toggle :model-value="c.active" label="الحساب مفعّل" color="positive"
          @update:model-value="(v) => save({ active: v }, v ? 'فُعّل الحساب' : 'أُوقف الحساب وأُخرج من كل الأجهزة')" />
        <WilayaSelect :model-value="wilaya" @update:model-value="setWilaya" />
        <q-toggle :model-value="idoomOn" label="تعبئة إيدوم (يعبّئ خطوط إيدوم من رصيده)" color="positive" :disable="busy" @update:model-value="setIdoom" />
        <div class="row q-gutter-sm items-start">
          <q-input v-model="newPw" class="col" dense outlined label="كلمة سر جديدة (8 أحرف على الأقل)" input-class="ltr text-right" />
          <q-btn outline color="primary" label="تعيين" :disable="newPw.length < 8" @click="setPw" />
        </div>
        <q-btn flat color="negative" icon="devices" label="إخراجه من كل الأجهزة" @click="revoke" />
        <q-btn flat color="warning" icon="lock_open" label="إيقاف قفل البرنامج (إن نسي رمزه)" @click="lockOff" />
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
import { useLoadMore } from 'src/composables/useLoadMore'
import WilayaSelect from 'components/WilayaSelect.vue'
import * as api from 'src/api/admin'
import { newRequestId } from 'src/api/rpc'
import { money, debtView, KINDS } from 'src/api/format'
import EntryRow from 'components/EntryRow.vue'
import LoadMoreBar from 'components/LoadMoreBar.vue'

const props = defineProps({ id: { type: String, required: true } })
const cid = computed(() => Number(props.id))
const { busy, run } = useRun()

const c = ref(null)
const debt = computed(() => debtView(c.value?.debt || 0, false))
const limitDraft = ref(0)
const infoDraft = ref({ name: '', phone: '' })

async function loadCustomer () {
  const list = await run(() => api.customers())
  c.value = list?.find((x) => Number(x.customer_id) === cid.value) || null
  if (c.value) {
    limitDraft.value = Number(c.value.debt_limit)
    infoDraft.value = { name: c.value.name, phone: c.value.phone }
  }
}

const { rows: entries, total, loadingMore, reset: loadEntries, refresh: refreshEntries, more, size } =
  useLoadMore((limit, offset) => run(() => api.entries({ customerId: cid.value, limit, offset })), { key: 'entry_id' })

// «تعبئة إيدوم» for this customer: off by default, the owner turns it on for customers he trusts
const idoomOn = ref(false)
const wilaya = ref(null)
async function loadIdoom () {
  const ids = await run(() => api.idoomTopupCustomers())
  if (ids) idoomOn.value = ids.map(Number).includes(cid.value)
  const ws = await run(() => api.customerWilayas())
  if (ws) wilaya.value = ws.find((w) => Number(w.customer_id) === cid.value)?.wilaya_code ?? null
}
async function setWilaya (code) {
  if (await run(() => api.setCustomerWilaya(cid.value, code).then(() => true), { success: 'حُفظت الولاية.' })) wilaya.value = code
}
async function setIdoom (v) {
  const ok = await run(() => api.setIdoomTopup(cid.value, v).then(() => true),
    { success: v ? 'فُعّلت تعبئة إيدوم لهذا الزبون.' : 'أُوقفت تعبئة إيدوم لهذا الزبون.' })
  if (ok) idoomOn.value = v
}

async function reloadAll () {
  loadIdoom()
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
  await loadCustomer()
  await refreshEntries()
}

// --- settings
async function save (patch, msg) {
  const ok = await run(() => api.updateCustomer(cid.value, patch).then(() => true), { success: msg })
  if (ok) loadCustomer()
}

// name and phone; the database rejects a phone already used by another customer
function saveInfo () {
  save({ name: infoDraft.value.name.trim(), phone: infoDraft.value.phone.trim() }, 'حُفظت بيانات الزبون.')
}

const newPw = ref('')
async function setPw () {
  const ok = await run(() => api.setPassword(cid.value, newPw.value).then(() => true),
    { success: 'تم تعيين كلمة السر وأُخرج الزبون من كل الأجهزة.' })
  if (ok) newPw.value = ''
}

function lockOff () {
  run(() => api.customerLockOff(cid.value), { success: (had) => (had ? 'أُوقف قفل البرنامج لهذا الزبون.' : 'لم يكن القفل مفعّلًا عنده.') })
}

function revoke () {
  run(() => api.revokeSessions(cid.value), { success: (n) => `أُلغيت ${n} جلسة.` })
}
</script>
