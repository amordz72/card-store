<template>
  <!-- «تحتاج حكمك» (owner 2026-10-30, Flexy Core 0092): operations whose outcome is unknown (review, or accepted and not
       settled). Money may have left: the program never decides; the owner does, with the evidence (the SIM's messages
       after the operation, its balance), through the settle path that already exists. Hidden when nothing waits. -->
  <div v-if="ops.length || state === 'failed'" class="card column gap-sm review">
    <div class="row items-center">
      <q-icon name="gavel" color="deep-orange" size="22px" class="q-mr-sm" />
      <div class="col text-weight-bold">تحتاج حكمك ({{ ops.length }})</div>
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="state === 'busy'" @click="load" />
    </div>
    <div v-if="state === 'failed'" class="small text-negative">لم تصل · <a href="#" @click.prevent="load">أعد المحاولة</a> (طبّق 0092 إن لم تفعل)</div>
    <div v-for="o in ops" :key="o.id" class="op column gap-xs">
      <div class="row items-center no-wrap gap-sm">
        <span class="col text-weight-bold ltr phone">{{ o.phone || '—' }}</span>
        <q-btn v-if="o.phone" flat round dense size="sm" icon="content_copy" aria-label="نسخ الرقم" @click="copy(o.phone)" />
      </div>
      <div class="small">{{ o.offer || (o.amount ? o.amount + ' دج' : '') }} · {{ o.sim || 'شريحة ؟' }} · {{ o.op }}</div>
      <div class="small muted">{{ o.status === 'review' ? 'مراجعة' : 'مقبولة لم تُحسم' }} منذ {{ when(o.at) }}<span v-if="o.code"> · {{ o.code }}</span></div>
      <div v-if="o.sim_balance !== null && o.sim_balance !== undefined" class="small">رصيد {{ o.sim }} الآن: <b>{{ o.sim_balance }}</b> دج (قُرئ {{ when(o.sim_balance_at) }})</div>
      <q-expansion-item dense dense-toggle switch-toggle-side :label="`رسائل الشريحة بعدها (${(o.messages || []).length})`" header-class="small text-grey-8 q-px-none">
        <div v-if="!(o.messages || []).length" class="small muted">لا رسالة على الشريحة في الساعتين بعد العملية.</div>
        <div v-for="(m, i) in o.messages || []" :key="i" class="small msg"><span class="muted">{{ when(m.at) }} · {{ m.from }}</span><div>{{ m.text }}</div>
          <div v-if="mobilisArabic(m.text)" class="text-weight-bold arabic">↲ {{ mobilisArabic(m.text) }}</div></div>
      </q-expansion-item>
      <div class="row gap-sm">
        <q-btn unelevated dense no-caps color="positive" icon="check" label="وصلت" :loading="busy === o.id + 's'" @click="settle(o, 'success')" />
        <q-btn unelevated dense no-caps color="negative" icon="close" label="لم تصل" :loading="busy === o.id + 'f'" @click="settle(o, 'failed')" />
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { copyToClipboard, Dialog, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { mobilisArabic } from 'src/api/mobilisText'
import { useBell } from 'src/composables/useBell'

const { refreshBell } = useBell()
const ops = ref([])
const state = ref('')
const busy = ref('')

const withLimit = (p, ms = 15000) => Promise.race([p, new Promise((resolve) => setTimeout(() => resolve(null), ms))])
async function load () {
  if (state.value === 'busy') return
  state.value = 'busy'
  const r = await withLimit(flexy.runReady('review_ops')).catch(() => null)
  if (r?.status === 200 && r.body?.ok) { ops.value = r.body.rows?.[0]?.rows || []; state.value = '' } else state.value = 'failed'
}
function settle (o, to) {
  const yes = to === 'success'
  Dialog.create({
    title: yes ? 'وصلت للزبون؟' : 'لم تصل للزبون؟',
    message: (yes ? 'تُحسب ناجحة.' : 'تُحسب فاشلة، ويُعاد المال إن كانت من محل.') + ' اكتب دليلك (اختياري):',
    prompt: { model: '', type: 'text' }, cancel: 'إلغاء', ok: yes ? 'نعم، وصلت' : 'نعم، لم تصل'
  }).onOk(async (note) => {
    busy.value = o.id + (yes ? 's' : 'f')
    try {
      const res = await flexy.ownerSettle(o.id, to, (note || '').trim() || (yes ? 'المالك: وصلت' : 'المالك: لم تصل'))
      if (res.status !== 200 || res.body?.ok === false) throw new Error(res.body?.error || 'FLEXY_CORE')
      Notify.create({ type: 'positive', message: yes ? '✓ حُسبت ناجحة' : '✓ حُسبت فاشلة', position: 'top' })
      await load()
      refreshBell()
    } catch (e) {
      Notify.create({ type: 'negative', message: 'لم تُحسم: ' + (e.message || ''), position: 'top', timeout: 6000 })
    } finally {
      busy.value = ''
    }
  })
}
const when = (t) => { if (!t) return '—'; const d = new Date(t); const today = new Date().toDateString() === d.toDateString(); return (today ? '' : d.toLocaleDateString('ar-DZ', { day: '2-digit', month: '2-digit' }) + ' ') + d.toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' }) }
async function copy (p) { await copyToClipboard(p); Notify.create({ message: 'نُسخ الرقم', color: 'positive', position: 'top', timeout: 1000 }) }
onMounted(load)
</script>

<style scoped>
.review { border: 2px solid #e64a19; }
.gap-sm { gap: 8px; }
.gap-xs { gap: 4px; }
.op { border-top: 1px solid rgba(0, 0, 0, 0.08); padding: 8px 0; min-width: 0; }
.ltr { direction: ltr; text-align: right; }
.phone { font-size: 16px; }
.arabic { color: #2e7d32; }
.msg { border-right: 3px solid rgba(0, 0, 0, 0.1); padding: 2px 8px; margin: 4px 0; overflow-wrap: anywhere; }
</style>
