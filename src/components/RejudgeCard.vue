<template>
  <!-- «حُكم عليها: لم تُرسل» (owner 2026-10-30, Flexy Core 0108): operations closed in the last 24 hours on an unclear step
       (the PIN sent and no reply read, a result not known), after they reached the network. The owner may judge one again
       («وصلت» / «لم تصل», with his note); the first verdict is kept. Hidden when there is none. -->
  <div v-if="rows.length" class="card column q-gutter-xs">
    <div class="row items-center">
      <q-icon name="history_edu" color="grey-8" size="22px" class="q-mr-sm" />
      <div class="col text-weight-bold">حُكم عليها «لم تُرسل» بعد خطوة غير واضحة ({{ rows.length }})</div>
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
    </div>
    <div class="help small muted">البرنامج لم يكمل هذه العمليات. إن كنت أكملتها بيدك أو أكّد الزبون أنها وصلت، غيّر الحكم.</div>
    <div v-for="o in rows" :key="o.operation_id" class="line column q-gutter-xs">
      <div class="row items-center no-wrap q-gutter-sm">
        <span class="col"><b>{{ o.offer || (o.amount ? o.amount + ' دج' : '') }}</b> · …{{ o.phone_tail }}<q-badge v-if="o.shop" class="q-ml-xs" color="info" label="محل" /></span>
        <span class="small muted">{{ when(o.created_at) }}</span>
      </div>
      <div class="small muted">{{ WHY[o.code] || o.code }}</div>
      <div class="row q-gutter-xs">
        <q-btn dense outline no-caps size="sm" color="positive" label="وصلت" :loading="busy === o.operation_id" @click="judge(o, 'success')" />
        <q-btn v-if="o.status !== 'failed'" dense outline no-caps size="sm" color="negative" label="لم تصل" :loading="busy === o.operation_id" @click="judge(o, 'failed')" />
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { Dialog, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { when } from 'src/api/when'

const WHY = {
  '665_PIN_NO_RESPONSE': 'أُرسل الـPIN ولم يُقرأ ردّ الشبكة',
  '585_SEND_RESULT_UNKNOWN': 'لا يُعرف ما حدث بعد الإرسال',
  '760O_SEND_RESULT_UNKNOWN': 'لا يُعرف ما حدث بعد الإرسال'
}
const rows = ref([])
const busy = ref(false)
async function load () {
  busy.value = true
  try {
    const r = await flexy.ownerRejudgeable()
    rows.value = r.status === 200 && r.body?.ok ? r.body.operations || [] : []
  } catch {
    // before 0108, or offline: nothing shown
  } finally {
    busy.value = false
  }
}
function judge (o, to) {
  Dialog.create({
    title: 'غيّر الحكم: ' + (to === 'success' ? 'وصلت' : 'لم تصل'),
    message: 'اكتب لماذا (مثلًا: أكملتها بيدي، أو أكّد الزبون). يُحفظ مع الحكم الأول.',
    prompt: { model: '', type: 'text', isValid: (v) => !!String(v).trim() },
    cancel: 'رجوع',
    ok: 'غيّر'
  }).onOk(async (note) => {
    busy.value = o.operation_id
    try {
      const r = await flexy.ownerRejudge(o.operation_id, to, note)
      if (r.status !== 200 || !r.body?.ok) throw new Error(r.body?.error || 'FLEXY_CORE')
      Notify.create({ type: 'positive', message: 'تغيّر الحكم' + (r.body.shop && to === 'success' ? '. عملية محل: أُرجع له المبلغ من قبل، اخصمه من حسابه إن أردت.' : '') })
    } catch (e) {
      Notify.create({ type: 'negative', message: e.message === 'REJUDGE_NOT_ALLOWED' ? 'لا يمكن: مرّ أكثر من 24 ساعة.' : e.message })
    } finally {
      busy.value = false
      load()
    }
  })
}
onMounted(load)
</script>

<style scoped>
.line { padding: 6px 0; border-top: 1px solid #EEF0F5; }
</style>
