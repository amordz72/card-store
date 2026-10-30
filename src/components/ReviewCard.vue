<template>
  <!-- «تحتاج حكمك» (owner 2026-10-30, Flexy Core 0092/0095): operations whose outcome is unknown (review, or accepted and not
       settled). The clear ones the program closes itself (rejudge, every 10 minutes); here each says its evidence and
       which way it points («موافق»), the shop is asked first; otherwise the owner decides, with the evidence (the SIM's messages
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
      <!-- The evidence, and what it says (owner 2026-10-30: «قل لي كيف أحكم، لا تطلب حكمي فقط») -->
      <div class="evidence column gap-xs">
        <div v-for="(e, i) in evidenceOf(o)" :key="i" class="small" :class="e.cls">{{ e.text }}</div>
      </div>

      <div class="tl">
        <div class="tl-item"><span class="dot" /> <b>{{ when(o.at) }}</b> · أُرسلت من {{ o.sim || 'شريحة ؟' }} · صارت «{{ o.status === 'review' ? 'مراجعة' : 'مقبولة' }}»<span v-if="CODES[o.code]" class="muted">: {{ CODES[o.code] }}</span></div>
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
        <q-btn :unelevated="suggest(o) !== 'failed'" :outline="suggest(o) === 'failed'" dense no-caps color="positive" icon="check"
          :label="suggest(o) === 'success' ? 'موافق: وصلت' : 'وصلت'" :loading="busy === o.id + 's'" @click="settle(o, 'success')" />
        <q-btn :unelevated="suggest(o) !== 'success'" :outline="suggest(o) === 'success'" dense no-caps color="negative" icon="close"
          :label="suggest(o) === 'failed' ? 'موافق: لم تصل' : 'لم تصل'" :loading="busy === o.id + 'f'" @click="settle(o, 'failed')" />
        <!-- «لا أدري» (owner 2026-10-30): no answer from him; the program reads the SIM's balance and does the sum -->
        <q-btn v-if="!o.unknown_at" flat dense no-caps color="grey-8" icon="help_outline" label="لا أدري" :loading="busy === o.id + 'u'" @click="unknown(o)" />
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
async function unknown (o) {
  busy.value = o.id + 'u'
  try {
    const r = await flexy.ownerUnknown(o.id)
    if (r.status !== 200 || r.body?.ok === false) throw new Error(r.body?.error === 'UNKNOWN_NOT_READY' ? 'طبّق 0097 أولًا' : (r.body?.error || 'FLEXY_CORE'))
    // The SIM's balance asked once more (the same read as its button: no money)
    let read = ''
    if (r.body.sim_uuid) {
      const b = await flexy.readSimBalance(r.body.sim_uuid).catch(() => null)
      read = b?.status === 200 && b.body?.ok !== false ? ' طلبنا قراءة رصيد الشريحة.' : ' لم تُطلب قراءة الرصيد الآن (' + (b?.body?.error || 'الشريحة مشغولة') + '): تكفي آخر قراءة إن وُجدت.'
    }
    Notify.create({ type: 'info', message: 'البرنامج يحاول.' + read, position: 'top', timeout: 4000 })
    await load()
  } catch (e) {
    Notify.create({ type: 'negative', message: 'لم يُسجَّل: ' + (e.message || ''), position: 'top' })
  } finally {
    busy.value = ''
  }
}
// What the sum says (Flexy Core fc_balance_guess)
function guessLine (o) {
  const g = o.guess || {}
  const nums = g.before !== undefined && g.after !== null && g.after !== undefined
    ? `الرصيد ${g.before} (${when(g.before_at)}) ← ${g.after} (${when(g.after_at)})، والناجحة بينهما ${g.others_success ?? 0} دج` : ''
  switch (g.verdict) {
    case 'arrived': return { cls: 'text-positive text-weight-bold', text: `🤖 ${nums}: الباقي ${g.rest} = مبلغها: وصلت.` }
    case 'not_arrived': return { cls: 'text-negative text-weight-bold', text: `🤖 ${nums}: لا باقي: لم تصل.` }
    // No read before it can never come later: said plainly, not «waiting»
    case 'no_reading': return g.before_at
      ? { cls: 'text-primary', text: '🤖 البرنامج يحاول: ينتظر قراءة رصيد الشريحة بعد العملية…' }
      : { cls: 'muted', text: '🤖 لا قراءة لرصيد الشريحة قبل هذه العملية: الرصيد لا يحسمها، احكم بالأدلة الأخرى.' }
    case 'others_open': return { cls: 'text-deep-orange', text: `🤖 ${nums}: على الشريحة ${g.others_open} عمليات أخرى غير محسومة: لا يُحسم الآن.` }
    case 'amount_unknown': return { cls: 'text-deep-orange', text: '🤖 بين القراءتين عملية بلا مبلغ معروف: لا يُحسم بالرصيد.' }
    case 'unclear': return { cls: 'text-deep-orange', text: `🤖 ${nums}: الباقي ${g.rest} لا يساوي مبلغها ولا صفرًا (شحن أو عملية أخرى): لا يُحسم.` }
    case 'no_sim': return { cls: 'muted', text: '🤖 لا نعرف الشريحة التي أرسلتها: لا يُحسم بالرصيد.' }
    default: return { cls: 'text-primary', text: '🤖 البرنامج يحاول…' }
  }
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
// Why it is in review, in words (never the code)
const CODES = { '630_FAILURE_SMS_SEEN': 'رأى رسالة «فشلت»', '630_SMS_AMBIGUOUS': 'رسالة تحتمل عمليتين', '630_NO_FINAL_SMS': 'لم تصل رسالة في الوقت' }
const sms = (t) => String(t || '')
const isSuccess = (t) => /Vous avez rech?arg/i.test(sms(t))
const isFailure = (t) => /échou|insuffisant|incorrect/i.test(sms(t))
const SLACK = 30000
// Each line: what a proof says (the program closes the clear ones itself every 10 minutes, Flexy Core rejudge)
function evidenceOf (o) {
  const sent = Date.parse(o.at)
  const out = []
  const msgs = o.messages || []
  const mineOk = msgs.find((m) => isSuccess(m.text) && mineOf(o, m) === 'mine' && Date.parse(m.at) >= sent - SLACK)
  const failBefore = msgs.find((m) => isFailure(m.text) && Date.parse(m.at) < sent - SLACK)
  const failAfter = msgs.find((m) => isFailure(m.text) && Date.parse(m.at) >= sent - SLACK)
  if (mineOk) out.push({ cls: 'text-positive text-weight-bold', text: '✅ رسالة نجاح لرقمها بعد الإرسال برقم معاملة: وصلت. اضغط «موافق: وصلت».' })
  if (failBefore) out.push({ cls: 'muted', text: `• رسالة «فشلت» ${when(failBefore.at)} جاءت قبل الإرسال: تخص عملية سابقة، لا هذه.` })
  if (failAfter && !mineOk) out.push({ cls: 'text-negative', text: `• رسالة «فشلت» بعد الإرسال (${when(failAfter.at)}): قد تكون لهذه أو لعملية أخرى على نفس الشريحة.` })
  // Our SIM's balance around the send (0095): did the money leave our SIM?
  const b = o.balance
  if (b && b.before !== null && b.after !== null) {
    const drop = Number(b.drop)
    const line = `رصيد ${o.sim || 'الشريحة'}: ${b.before} (${when(b.before_at)}) ← ${b.after} (${when(b.after_at)})`
    if (drop === 0) out.push({ cls: 'text-negative', text: `• ${line}: لم ينقص، فلم يخرج المال: الأرجح لم تصل.` })
    else if (Number(b.sessions) <= 1 && drop === Number(o.amount)) out.push({ cls: 'text-positive', text: `• ${line}: نقص ${drop} دج = هذه وحدها: خرج المال.` })
    else out.push({ cls: 'muted', text: `• ${line}: نقص ${drop} دج مع ${b.sessions} عمليات: لا يكفي وحده.` })
  } else {
    out.push({ cls: 'muted', text: '• لا قراءة لرصيد الشريحة بعد هذه العملية: الرصيد لا يحسمها.' })
  }
  // The shop knows its customer: asked first (card-store v1.47)
  if (o.shop) {
    const said = { arrived: 'وصلت', not_arrived: 'لم تصل', unknown: 'لا يعرف' }[o.shop_answer]
    out.push(said ? { cls: 'text-weight-bold', text: `• المحل ${o.shop} قال: ${said} (${when(o.shop_answer_at)}).` }
      : { cls: 'muted', text: `• المحل ${o.shop} لم يجب بعد (يُسأل في تطبيقه «هل وصل للزبون؟» بعد تطبيق s147).` })
  }
  // A later success proves the number accepts it, never that this one arrived
  if (o.unknown_at) out.push(guessLine(o))
  if (o.later_success_at) {
    out.push({ cls: 'muted', text: `• نجحت لنفس الرقم عملية لاحقة ${when(o.later_success_at)} (${o.later_app === 'owner-console' ? 'من المختبر أو صفحتك' : 'من محل'}): الرقم يقبل العرض فقط، ولا يثبت هذه.` })
  }
  if (!mineOk && !(b && b.before !== null && b.after !== null) && !(o.shop && o.shop_answer)) {
    out.push({ cls: 'text-deep-orange', text: o.shop ? 'لا دليل بعد: انتظر جواب المحل، أو اسأل الزبون.' : 'لا دليل: احكم أنت (مثلًا من هاتف الزبون).' })
  }
  return out
}
function suggest (o) {
  if (o.guess?.verdict === 'arrived') return 'success'
  if (o.guess?.verdict === 'not_arrived') return 'failed'
  const sent = Date.parse(o.at)
  if ((o.messages || []).some((m) => isSuccess(m.text) && mineOf(o, m) === 'mine' && Date.parse(m.at) >= sent - SLACK)) return 'success'
  const b = o.balance
  if (b && b.before !== null && b.after !== null) {
    if (Number(b.drop) === 0) return 'failed'
    if (Number(b.sessions) <= 1 && Number(b.drop) === Number(o.amount)) return 'success'
  }
  if (o.shop_answer === 'arrived') return 'success'
  if (o.shop_answer === 'not_arrived') return 'failed'
  return ''
}
const ageDays = (t) => { const a = new Date(t); const b = new Date(); a.setHours(0, 0, 0, 0); b.setHours(0, 0, 0, 0); return Math.round((b - a) / 86400000) }
const forClaude = (o) => ({ id: o.id, at: o.at, op: o.op, way: o.way, status: o.status, code: o.code, phone: o.phone, offer: o.offer, amount: o.amount,
  app: o.app, shop: o.shop, sim: o.sim, later_success_at: o.later_success_at, later_app: o.later_app, shop_answer: o.shop_answer, balance: o.balance,
  evidence: evidenceOf(o).map((e) => e.text), suggest: suggest(o), balance_now: o.sim_balance, balance_at: o.sim_balance_at,
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
