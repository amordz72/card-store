<template>
  <!-- «تحتاج حكمك» (owner 2026-10-30, Flexy Core 0092): operations whose outcome is unknown (review, or accepted and not
       settled). Money may have left: the program never decides; the owner does, with the evidence (the SIM's messages
       after the operation, its balance), through the settle path that already exists. Hidden when nothing waits. -->
  <div v-if="ops.length || state === 'failed'" class="card column gap-sm review">
    <div class="row items-center">
      <q-icon name="gavel" color="deep-orange" size="22px" class="q-mr-sm" />
      <div class="col text-weight-bold">تحتاج حكمك ({{ ops.length }})</div>
      <q-btn flat round dense icon="smart_toy" aria-label="نسخ الكل لـClaude" @click="copyForClaude('تحتاج حكمك', ops.map(forClaude))" />
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="state === 'busy'" @click="load" />
    </div>
    <div v-if="state === 'failed'" class="small text-negative">لم تصل · <a href="#" @click.prevent="load">أعد المحاولة</a> (طبّق 0092 إن لم تفعل)</div>
    <!-- Newest first; each one a timeline: the operation, its messages (marked: this number or another), then «اليوم» -->
    <div v-for="o in ops" :key="o.id" class="op column gap-xs">
      <div class="row items-center no-wrap gap-sm">
        <span class="col text-weight-bold ltr phone">{{ o.phone || '—' }}</span>
        <q-badge v-if="ageDays(o.at) >= 1" color="grey-7" :label="'⏳ ' + (ageDays(o.at) === 1 ? 'عملية الأمس' : 'قبل ' + ageDays(o.at) + ' أيام')" />
        <q-btn v-if="o.phone" flat round dense size="sm" icon="content_copy" aria-label="نسخ الرقم" @click="copy(o.phone)" />
        <q-btn flat round dense size="sm" icon="smart_toy" aria-label="نسخ لـClaude" @click="copyForClaude('تحتاج حكمك', forClaude(o))" />
      </div>
      <div class="small">{{ o.offer || (o.amount ? o.amount + ' دج' : '') }} · {{ WAYS[o.way] || o.way }} · {{ o.shop ? 'المحل: ' + o.shop : (o.app === 'owner-console' ? 'صفحتك أو المختبر' : o.app) }}</div>
      <div v-if="o.later_success_at" class="small text-positive text-weight-bold">✅ نجحت لهذا الرقم عملية لاحقة ({{ when(o.later_success_at) }}): الأرجح أن هذه قديمة وحُلّت أو لم تصل</div>

      <div class="tl">
        <div class="tl-item"><span class="dot" /> <b>{{ when(o.at) }}</b> · أُرسلت من {{ o.sim || 'شريحة ؟' }} · صارت «{{ o.status === 'review' ? 'مراجعة' : 'مقبولة' }}»<span v-if="o.code" class="tiny muted ltr"> {{ o.code }}</span></div>
        <div v-if="!(o.messages || []).length" class="tl-item small muted"><span class="dot" /> لا رسالة على الشريحة في الساعتين بعدها</div>
        <div v-for="(m, i) in o.messages || []" :key="i" class="tl-item small">
          <span class="dot" :class="mineOf(o, m)" /> <b>{{ when(m.at) }}</b> · {{ m.from }}
          <q-badge v-if="mineOf(o, m) === 'mine'" color="positive" label="رقم هذه العملية" />
          <q-badge v-else-if="mineOf(o, m) === 'other'" color="grey-6" :label="'رقم آخر: …' + otherNumber(m.text)" />
          <div class="msg">{{ m.text }}</div>
          <div v-if="mobilisArabic(m.text)" class="text-weight-bold arabic">↲ {{ mobilisArabic(m.text) }}</div>
        </div>
        <div v-if="o.sim_balance !== null && o.sim_balance !== undefined" class="tl-item small today">
          <span class="dot now" /> <b>اليوم</b> · رصيد {{ o.sim }} الآن <b>{{ o.sim_balance }}</b> دج (قُرئ {{ when(o.sim_balance_at) }})
        </div>
      </div>
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
import { copyForClaude, registerForClaude } from 'src/composables/useClaudeCopy'
import { WAYS } from 'src/api/ways'
import { when } from 'src/api/when'
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
  // Newest first (owner 2026-10-30), whatever order the server sent
  if (r?.status === 200 && r.body?.ok) { ops.value = (r.body.rows?.[0]?.rows || []).sort((a, b) => Date.parse(b.at) - Date.parse(a.at)); state.value = '' } else state.value = 'failed'
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
// A message names a number (…vers le 672498437): this operation's, or another one's
const digits = (t) => (String(t || '').match(/(?:vers le|au|à)\s*(\d{8,10})/i) || [])[1] || ''
const otherNumber = (t) => digits(t).slice(-4)
function mineOf (o, m) {
  const d = digits(m.text)
  if (!d) return ''
  return String(o.phone || '').replace(/\D/g, '').endsWith(d.slice(-8)) ? 'mine' : 'other'
}
const ageDays = (t) => { const a = new Date(t); const b = new Date(); a.setHours(0, 0, 0, 0); b.setHours(0, 0, 0, 0); return Math.round((b - a) / 86400000) }
const forClaude = (o) => ({ id: o.id, at: o.at, op: o.op, way: o.way, status: o.status, code: o.code, phone: o.phone, offer: o.offer, amount: o.amount,
  app: o.app, shop: o.shop, sim: o.sim, later_success_at: o.later_success_at, balance_now: o.sim_balance, balance_at: o.sim_balance_at,
  messages: (o.messages || []).map((m) => m.at + ' ' + m.text) })
registerForClaude('تحتاج حكمك', () => ops.value.map(forClaude))
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
.tl { border-right: 2px solid rgba(0, 0, 0, 0.12); padding-right: 10px; margin: 4px 0; }
.tl-item { position: relative; padding: 3px 0; overflow-wrap: anywhere; }
.dot { display: inline-block; width: 8px; height: 8px; border-radius: 4px; background: #9e9e9e; margin-left: 4px; }
.dot.mine { background: #2e7d32; }
.dot.other { background: #bdbdbd; }
.dot.now { background: #1565c0; }
.today { border-top: 1px dashed rgba(0, 0, 0, 0.2); margin-top: 4px; padding-top: 6px; color: #1565c0; }
.tiny { font-size: 10px; }
.msg { border-right: 3px solid rgba(0, 0, 0, 0.1); padding: 2px 8px; margin: 4px 0; overflow-wrap: anywhere; }
</style>
