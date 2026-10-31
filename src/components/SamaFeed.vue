<template>
  <!-- «تغذية سما من المخزون» (owner 2026-10-31, «نفذ المنفصلة»; Flexy Core 0125 + store v1.61). One press = one Mobilis 1000
       card moved from the sale to the feeding place and sent to that SIM at its next quiet moment (never beside a flexy);
       the network's reply decides. What needs the owner: a new reply to judge, a card the network refused (its supplier and
       batch shown: «صحّح الرمز» → back to feeding, «مستعملة» → never fed). Design: developer SAMA-TOPUP-CYCLE-2026-10-31.md. -->
  <div class="card column q-gutter-xs q-mt-sm">
    <div class="row items-center">
      <div class="text-weight-bold col">تغذية سما من المخزون</div>
      <q-btn flat dense round icon="refresh" :loading="busy" @click="load" />
    </div>
    <div class="help small muted">«اشحنها 1000» تأخذ أقدم بطاقة Mobilis 1000 من المخزون (تخرج من البيع) وترسلها إلى الشريحة حين تكون هادئة، ولا تقطع أي بيع. ردّ موبيليس يحسم: نجحت فيُضاف المبلغ لرصيدها، أو رفضتها الشبكة فتظهر هنا مع مورّدها. البطاقة لا تُرسل مرتين.</div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <div v-for="s in sims" :key="s.sim_uuid" class="feed-row">
      <span class="column">
        <b>{{ s.label || 'شريحة سما' }}</b>
        <span v-if="s.feed" class="tiny" :class="tone(s.feed)">{{ stateText(s.feed) }}</span>
        <span v-else class="tiny muted">لم تُغذَّ من المخزون بعد</span>
      </span>
      <q-btn v-if="!running(s.feed)" dense unelevated no-caps color="primary" label="اشحنها 1000" :loading="starting === s.sim_uuid" @click="ask(s)" />
      <q-btn v-else dense outline no-caps disable color="grey-7" label="تعبئة جارية" />
    </div>
    <div v-if="loaded && !sims.length" class="small muted">لا شريحة سما.</div>

    <template v-if="reviews.length">
      <div class="text-weight-bold q-mt-sm text-deep-orange-9">تحتاج حكمك ({{ reviews.length }})</div>
      <div v-for="f in reviews" :key="f.feed_id" class="attention column q-gutter-xs">
        <div class="small"><b>{{ f.sim_label }}</b> · {{ when(f.decided_at || f.queued_at) }} · {{ REASON[reasonKey(f.reason)] || f.reason }}</div>
        <div v-if="f.reply" class="reply small">«{{ f.reply }}»</div>
        <div class="row q-gutter-xs">
          <q-btn dense unelevated no-caps color="positive" label="نجحت (وصلت 1000)" :loading="judging === f.feed_id" @click="judge(f, 'success')" />
          <q-btn dense outline no-caps color="negative" label="رفضتها الشبكة" :loading="judging === f.feed_id" @click="judge(f, 'refused')" />
        </div>
        <div class="help tiny muted">حكمك على ردّ جديد يحفظه البرنامج، فيحكم وحده إن تكرّر.</div>
      </div>
    </template>

    <template v-if="refused.length">
      <div class="text-weight-bold q-mt-sm text-negative">رفضتها الشبكة ({{ refused.length }})</div>
      <div v-for="c in refused" :key="c.card_id" class="attention column q-gutter-xs">
        <div class="small"><b>{{ c.product }}</b> · ينتهي بـ {{ c.code_end }} · {{ c.sim || '' }} · {{ when(c.state_at) }}</div>
        <div class="tiny muted">المورّد: {{ c.supplier || '—' }}<template v-if="c.batch_at"> · دفعة {{ when(c.batch_at) }}</template><template v-if="c.cost"> · بسعر {{ money(c.cost) }}</template><template v-if="c.tries > 1"> · جُرّبت {{ c.tries }} مرات</template></div>
        <div v-if="replyOf(c.card_id)" class="reply small">«{{ replyOf(c.card_id) }}»</div>
        <div class="row q-gutter-xs">
          <q-btn dense unelevated no-caps color="primary" label="صحّح الرمز" @click="openFix(c)" />
          <q-btn dense outline no-caps color="grey-8" label="مستعملة" :loading="usedBusy === c.card_id" @click="markUsed(c)" />
        </div>
      </div>
    </template>
    <div v-if="settled.length" class="tiny muted q-mt-xs">
      رجعت للتغذية: {{ settled.filter((c) => c.state === 'ready').length }} · مستعملة: {{ settled.filter((c) => c.state === 'used').length }} (آخر 30 يومًا)
    </div>

    <q-dialog v-model="confirmOpen">
      <q-card v-if="target" style="min-width: 280px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">اشحن {{ target.label }} ببطاقة 1000؟</div>
          <div class="small">تخرج أقدم بطاقة Mobilis 1000 من المخزون (لا تُباع بعدها)، وتُرسل إلى الشريحة في أول لحظة هادئة.</div>
        </q-card-section>
        <q-card-actions align="left">
          <q-btn unelevated no-caps color="primary" label="نعم، اشحنها" @click="start" />
          <q-btn flat no-caps label="لا" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog v-model="fixOpen">
      <q-card v-if="fixing" style="min-width: 280px">
        <q-card-section class="column q-gutter-sm">
          <div class="text-weight-bold">الرمز الصحيح للبطاقة المنتهية بـ {{ fixing.code_end }}</div>
          <div class="small muted">من المورّد ({{ fixing.supplier || '—' }}). ترجع إلى التغذية، لا إلى البيع.</div>
          <q-input v-model="fixCode" outlined dense inputmode="numeric" label="الرمز" autofocus />
          <div v-if="fixError" class="small text-negative">{{ fixError }}</div>
        </q-card-section>
        <q-card-actions align="left">
          <q-btn unelevated no-caps color="primary" label="احفظ" :loading="fixBusy" :disable="!fixCode.trim()" @click="saveFix" />
          <q-btn flat no-caps label="إلغاء" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import * as admin from 'src/api/admin'
import { money } from 'src/api/format'

const props = defineProps({ active: { type: Boolean, default: true } })

const REASON = {
  NO_REPLY: 'لا ردّ من موبيليس خلال 3 دقائق',
  NO_REPORT: 'برنامج المحطة لم يقل هل أرسلها',
  NEW_REPLY: 'ردّ لم يُرَ من قبل',
  SEND_FAILED: 'المودم قال: لم تُرسل',
  SEND_UNCLEAR: 'لا يُعرف هل أُرسلت',
  CODE_INVALID: 'رمز البطاقة ليس أرقامًا صالحة',
  NO_QUIET_MOMENT: 'لم تأتِ لحظة هادئة في 15 دقيقة؛ رجعت البطاقة للتغذية',
  LATE_REPLY: 'ردّ متأخر'
}
const ERRORS = {
  FEED_NO_CARD: 'لا بطاقة Mobilis 1000 متاحة في المخزون.',
  FEED_BUSY: 'تعبئة جارية على هذه الشريحة.',
  FEED_SIM_NOT_SAMA: 'هذه ليست شريحة سما.',
  FEED_SIM_NOT_FOUND: 'الشريحة غير موجودة.',
  FEED_NOT_IN_REVIEW: 'حُسمت من قبل.',
  MIGRATION_0125: 'طبّق 0125 ثم s161 من «ينتظر تطبيقك» أولًا.',
  OWNER_REQUIRED: 'للمالك فقط.',
  SERVER_BUSY: 'الخادم لا يرد الآن، أعد بعد قليل.',
  NETWORK: 'لا إنترنت.'
}
const say = (res) => ERRORS[res.body?.error] || (res.status === 0 ? 'لا إنترنت أو الخادم لا يرد.' : `تعذّر (${res.body?.error || res.status})`)

const view = ref(null)
const cards = ref([])
const loaded = ref(false)
const busy = ref(false)
const error = ref('')
const starting = ref(null)
const judging = ref(null)
const usedBusy = ref(null)
const confirmOpen = ref(false)
const target = ref(null)
const fixOpen = ref(false)
const fixing = ref(null)
const fixCode = ref('')
const fixBusy = ref(false)
const fixError = ref('')

const sims = computed(() => view.value?.sims || [])
const reviews = computed(() => (view.value?.feeds || []).filter((f) => f.status === 'review'))
const refused = computed(() => cards.value.filter((c) => c.state === 'refused'))
const settled = computed(() => cards.value.filter((c) => c.state === 'ready' || c.state === 'used'))
const running = (f) => f && ['queued', 'claimed', 'sent'].includes(f.status)
const reasonKey = (r) => String(r || '').split(':')[0]
const replyOf = (cardId) => (view.value?.feeds || []).find((f) => f.card_id === cardId && f.reply)?.reply || ''

function ago (t) {
  const min = Math.max(0, Math.floor((Date.now() - Date.parse(t)) / 60000))
  if (min < 1) return 'الآن'
  if (min < 60) return `منذ ${min} د`
  if (min < 48 * 60) return `منذ ${Math.floor(min / 60)} س`
  return `منذ ${Math.floor(min / 1440)} ي`
}
function when (t) {
  if (!t) return ''
  const d = new Date(t)
  const today = new Date()
  const y = new Date(today.getTime() - 86400000)
  const hm = d.toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' })
  if (d.toDateString() === today.toDateString()) return 'اليوم ' + hm
  if (d.toDateString() === y.toDateString()) return 'أمس ' + hm
  return d.toLocaleDateString('ar-DZ', { day: 'numeric', month: 'numeric' }) + ' ' + hm
}
function stateText (f) {
  switch (f.status) {
    case 'queued': return `تنتظر لحظة هادئة على الشريحة (${ago(f.queued_at)})`
    case 'claimed': return `تُرسل الآن (${ago(f.claimed_at)})`
    case 'sent': return `أُرسلت، ننتظر ردّ موبيليس (${ago(f.sent_at)})`
    case 'success': return `✓ شُحنت +${money(Number(f.amount) || 1000)} · ${when(f.reply_at || f.decided_at)}`
    case 'refused': return `رفضتها الشبكة · ${when(f.decided_at)}`
    case 'review': return `تحتاج حكمك: ${REASON[reasonKey(f.reason)] || f.reason}`
    case 'not_sent': return `لم تُرسل · ${REASON[reasonKey(f.reason)] || f.reason} · ${when(f.decided_at)}`
    default: return f.status
  }
}
const tone = (f) => (f.status === 'success' ? 'text-positive' : f.status === 'refused' ? 'text-negative' : f.status === 'review' ? 'text-deep-orange-9' : 'muted')

async function load () {
  busy.value = true
  try {
    const [res, list] = await Promise.all([flexy.ownerFeed(), admin.feedCards().catch((e) => { error.value = e.message || 'تعذّرت قراءة البطاقات'; return null })])
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      if (list) error.value = ''
    } else {
      error.value = say(res)
    }
    if (Array.isArray(list)) cards.value = list
    loaded.value = true
  } finally {
    busy.value = false
  }
  schedule()
}

function ask (s) {
  target.value = s
  confirmOpen.value = true
}
async function start () {
  const s = target.value
  confirmOpen.value = false
  starting.value = s.sim_uuid
  try {
    const res = await flexy.ownerFeedStart(s.sim_uuid)
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      Notify.create({ type: 'positive', message: res.body.started?.quiet ? `تُرسل بطاقة إلى ${s.label} الآن` : `${s.label} مشغولة: تُرسل حين تهدأ` })
    } else {
      Notify.create({ type: 'negative', message: say(res) })
    }
  } finally {
    starting.value = null
  }
  schedule()
}
async function judge (f, verdict) {
  judging.value = f.feed_id
  try {
    const res = await flexy.ownerFeedJudge(f.feed_id, verdict)
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      cards.value = await admin.feedCards().catch(() => cards.value)
    } else {
      Notify.create({ type: 'negative', message: say(res) })
    }
  } finally {
    judging.value = null
  }
}
function openFix (c) {
  fixing.value = c
  fixCode.value = ''
  fixError.value = ''
  fixOpen.value = true
}
async function saveFix () {
  fixBusy.value = true
  fixError.value = ''
  try {
    await admin.feedFix(fixing.value.card_id, fixCode.value)
    fixOpen.value = false
    Notify.create({ type: 'positive', message: 'رجعت إلى التغذية' })
    cards.value = await admin.feedCards().catch(() => cards.value)
  } catch (e) {
    fixError.value = e.message || 'تعذّر الحفظ'
  } finally {
    fixBusy.value = false
  }
}
async function markUsed (c) {
  usedBusy.value = c.card_id
  try {
    await admin.feedUsed(c.card_id)
    cards.value = await admin.feedCards().catch(() => cards.value)
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message || 'تعذّر الحفظ' })
  } finally {
    usedBusy.value = null
  }
}

// Asked again every 5 s only while a feed runs and the page is shown (each one ends on the server: 15 min / 3 min)
let timer = null
function schedule () {
  clearTimeout(timer)
  if (!sims.value.some((s) => running(s.feed))) return
  timer = setTimeout(() => {
    if (document.visibilityState === 'visible' && props.active) load()
    else schedule()
  }, 5000)
}
watch(() => props.active, (a) => { if (a) load() })
onMounted(load)
onBeforeUnmount(() => clearTimeout(timer))
</script>

<style scoped>
.feed-row { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 6px 0; border-top: 1px solid #EEF0F3; }
.attention { border: 1px solid #FED7AA; background: #FFF7ED; border-radius: 8px; padding: 8px; }
.reply { background: #F3F4F6; border-radius: 6px; padding: 4px 6px; word-break: break-word; }
.tiny { font-size: 11px; }
</style>
