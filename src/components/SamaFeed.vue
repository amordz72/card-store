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
    <div class="help small muted">«اشحنها» تأخذ أقدم بطاقة Mobilis بالقيمة المختارة من المخزون (تخرج من البيع) وترسلها إلى الشريحة حين تكون هادئة، ولا تقطع أي بيع. ردّ موبيليس يحسم: نجحت فيُضاف المبلغ لرصيدها، أو رفضتها الشبكة فتظهر هنا مع مورّدها. البطاقة لا تُرسل مرتين.</div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <div v-for="s in sims" :key="s.sim_uuid" class="feed-row">
      <span class="column">
        <b>{{ s.label || 'شريحة سما' }}<span v-if="s.phone" class="tiny muted"> · هاتف الإدارة</span></b>
        <span v-if="s.feed" class="tiny" :class="tone(s.feed)">{{ stateText(s.feed) }}</span>
        <span v-else class="tiny muted">لم تُغذَّ من المخزون بعد</span>
      </span>
      <!-- Owner 2026-10-31: one list of the values in stock and one button, instead of a button per value -->
      <!-- 0129 (owner 2026-10-31): an unavailable SIM (computer or phone off, SIM out) takes no card; the reason and since when
           instead of the button, which comes back by itself once the obstacle is gone -->
      <span v-if="!running(s.feed) && s.ready && s.ready.ok === false" class="tiny text-grey-8 unready">{{ unreadyText(s) }}</span>
      <!-- 0127: a program that cannot feed yet: no card moves, the button says which update it needs -->
      <q-btn v-else-if="!running(s.feed) && s.capable === false" dense outline no-caps disable color="grey-7"
        :label="s.phone ? 'يحتاج تحديث تطبيق الهاتف (0.8.3)' : 'يحتاج تحديث برنامج المحطة (0.9.10)'" />
      <span v-else-if="!running(s.feed) && faces.length" class="row no-wrap items-center q-gutter-xs">
        <q-select v-model="chosen[s.sim_uuid]" :options="faceOptions" emit-value map-options dense outlined options-dense class="face" />
        <q-btn dense unelevated no-caps color="primary" label="اشحنها" :loading="starting === s.sim_uuid" @click="ask(s)" />
      </span>
      <q-btn v-else-if="running(s.feed)" dense outline no-caps disable color="grey-7" label="تعبئة جارية" />
      <span v-else-if="facesLoaded" class="tiny text-negative">لا بطاقات Mobilis في المخزون</span>
    </div>
    <div v-if="loaded && !sims.length" class="small muted">لا شريحة سما.</div>

    <template v-if="reviews.length">
      <div class="text-weight-bold q-mt-sm text-deep-orange-9">تحتاج حكمك ({{ reviews.length }})</div>
      <div v-for="f in reviews" :key="f.feed_id" class="attention column q-gutter-xs">
        <div class="small"><b>{{ f.sim_label }}</b> · {{ when(f.decided_at || f.queued_at) }} · {{ REASON[reasonKey(f.reason)] || f.reason }}</div>
        <div v-if="f.reply" class="reply small">«{{ f.reply }}»</div>
        <div class="row q-gutter-xs">
          <q-btn dense unelevated no-caps color="positive" :label="'نجحت (وصلت ' + money(f.card_face) + ')'" :loading="judging === f.feed_id" @click="judge(f, 'success')" />
          <q-btn dense outline no-caps color="negative" label="رفضتها الشبكة" :loading="judging === f.feed_id" @click="judge(f, 'refused')" />
        </div>
        <div class="help tiny muted">حكمك على ردّ جديد يحفظه البرنامج، فيحكم وحده إن تكرّر.</div>
      </div>
    </template>

    <template v-if="refused.length">
      <div class="text-weight-bold q-mt-sm text-negative">رفضتها الشبكة ({{ refused.length }})</div>
      <div v-for="c in refused" :key="c.card_id" class="attention column q-gutter-xs">
        <div class="small"><b>{{ c.product }}</b> · ينتهي بـ {{ c.code_end }} · {{ c.sim || '' }} · {{ when(c.state_at) }}</div>
        <div class="tiny muted">المورّد: {{ c.supplier || '—' }}<template v-if="batchCodes[c.batch_id]"> · <bdi dir="ltr" class="text-weight-bold">{{ batchCodes[c.batch_id] }}</bdi></template><template v-if="c.batch_at"> · دفعة {{ when(c.batch_at) }}</template><template v-if="c.cost"> · بسعر {{ money(c.cost) }}</template><template v-if="c.tries > 1"> · جُرّبت {{ c.tries }} مرات</template></div>
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
          <div class="text-weight-bold">اشحن {{ target.label }} ببطاقة {{ money(targetFace) }}؟</div>
          <div class="small">تخرج أقدم بطاقة Mobilis {{ targetFace }} من المخزون (لا تُباع بعدها)، وتُرسل إلى الشريحة في أول لحظة هادئة.</div>
          <!-- s170 (owner 2026-11-01): from the suspect stock, on his choice; Mobilis' answer judges the card -->
          <q-toggle v-if="suspectOf(targetFace)" v-model="fromSuspect" color="deep-orange" :label="'من المشكوك فيها (' + suspectOf(targetFace) + ')'" />
          <!-- s172: the owner picks the batch (or the oldest) -->
          <q-select v-if="batchOptions.length > 1" v-model="feedBatch" :options="batchOptions" emit-value map-options dense outlined label="من الدفعة" />
          <div v-if="fromSuspect" class="tiny text-deep-orange">إن رفضتها الشبكة تُحسب خاطئة في دفعتها؛ بطاقتان خاطئتان تجعلان الدفعة مشكوكًا فيها.</div>
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
  FEED_NO_CARD: 'لا بطاقة Mobilis بهذه القيمة متاحة في المخزون.',
  FEED_NO_SUSPECT_CARD: 'لا بطاقة مشكوك فيها بهذه القيمة.',
  MIGRATION_0133: 'طبّق 0133 وs170 من «ينتظر تطبيقك» أولًا.',
  MIGRATION_0134: 'طبّق 0134 وs172 من «ينتظر تطبيقك» أولًا.',
  FEED_BATCH_EMPTY: 'لا بطاقة بهذه القيمة في هذه الدفعة.',
  FEED_FACE_INVALID: 'قيمة البطاقة غير صحيحة.',
  MIGRATION_0126: 'طبّق 0126 أولًا من «ينتظر تطبيقك» (قيم غير 1000).',
  FEED_STATION_OLD: 'برنامج هذه الشريحة لا يعرف التغذية بعد: حدّثه أولًا. لم تُسحب أي بطاقة.',
  FEED_STATION_OFFLINE: 'كمبيوتر أو هاتف هذه الشريحة غير متصل الآن. لم تُسحب أي بطاقة.',
  FEED_MODEM_OFFLINE: 'مودم هذه الشريحة غير متصل الآن. لم تُسحب أي بطاقة.',
  FEED_SIM_OFFLINE: 'هذه الشريحة غير متصلة الآن. لم تُسحب أي بطاقة.',
  FEED_STATION_NOT_APPROVED: 'محطة هذه الشريحة غير معتمدة. لم تُسحب أي بطاقة.',
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
// v1.62: the values in stock, and the one chosen under each SIM (the smallest first, for trying)
const faces = ref([])
const facesLoaded = ref(false)
const chosen = ref({})
const faceOptions = computed(() => faces.value.map((f) => ({ value: f.face, label: f.available + f.ready > 0 ? `${f.face} (${f.available + f.ready} بطاقة)` : String(f.face) })))
const targetFace = computed(() => (target.value ? chosen.value[target.value.sim_uuid] : null))
const target = ref(null)
// s170: suspect cards of each value ({ "1000": 3 }); empty before s170
const suspectFaces = ref({})
// s171: the batch code of each card shown
const batchCodes = ref({})
const feedBatches = ref([])
const feedBatch = ref(null)
const batchOptions = computed(() => [{ label: 'تلقائي (الأقدم)', value: null },
  ...feedBatches.value.map((b) => ({ label: `${b.code || '#' + b.batch_id} · ${b.n} بطاقة`, value: b.batch_id }))])
const loadFeedBatches = () => { feedBatch.value = null; if (targetFace.value) admin.batchesForFace(targetFace.value, fromSuspect.value).then((v) => { feedBatches.value = v || [] }) }
watch(fromSuspect, loadFeedBatches)
const fromSuspect = ref(false)
const suspectOf = (face) => Number(suspectFaces.value?.[String(face)] || 0)
const loadSuspect = () => admin.feedSuspectFaces().then((v) => { suspectFaces.value = v || {} }).catch(() => { suspectFaces.value = {} })
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
  const hm = d.toLocaleTimeString('ar-DZ', { timeZone: 'Africa/Algiers', hour: '2-digit', minute: '2-digit' })
  if (d.toDateString() === today.toDateString()) return 'اليوم ' + hm
  if (d.toDateString() === y.toDateString()) return 'أمس ' + hm
  return d.toLocaleDateString('ar-DZ', { timeZone: 'Africa/Algiers', day: 'numeric', month: 'numeric' }) + ' ' + hm
}
function stateText (f) {
  switch (f.status) {
    case 'queued': return `تنتظر لحظة هادئة على الشريحة (${ago(f.queued_at)})`
    case 'claimed': return `تُرسل الآن (${ago(f.claimed_at)})`
    case 'sent': return `أُرسلت، ننتظر ردّ موبيليس (${ago(f.sent_at)})`
    case 'success': return `✓ شُحنت +${money(Number(f.amount) || f.card_face)} · ${when(f.reply_at || f.decided_at)}`
    case 'refused': return `رفضتها الشبكة · ${when(f.decided_at)}`
    case 'review': return `تحتاج حكمك: ${REASON[reasonKey(f.reason)] || f.reason}`
    case 'not_sent': return `لم تُرسل · ${REASON[reasonKey(f.reason)] || f.reason} · ${when(f.decided_at)}`
    default: return f.status
  }
}
// 0129: why this SIM cannot be fed now, and since when
function unreadyText (s) {
  const since = s.ready.since ? ` ${ago(s.ready.since)}` : ''
  switch (s.ready.reason) {
    case 'STATION_OFFLINE': return (s.phone ? 'الهاتف غير متصل' : 'الكمبيوتر مطفأ أو غير متصل') + since
    case 'MODEM_OFFLINE': return 'المودم غير متصل' + since
    case 'SIM_OFFLINE': return 'الشريحة غير متصلة (منزوعة أو لا ترد)' + since
    case 'STATION_NOT_APPROVED': return 'المحطة غير معتمدة'
    default: return 'غير متاحة الآن'
  }
}
const tone = (f) => (f.status === 'success' ? 'text-positive' : f.status === 'refused' ? 'text-negative' : f.status === 'review' ? 'text-deep-orange-9' : 'muted')

async function load () {
  busy.value = true
  try {
    const [res, list, values] = await Promise.all([flexy.ownerFeed(), admin.feedCards().catch((e) => { error.value = e.message || 'تعذّرت قراءة البطاقات'; return null }),
      admin.feedFaces().catch(() => null)])
    if (Array.isArray(values)) {
      faces.value = values.filter((f) => f.available + f.ready > 0)
      facesLoaded.value = true
      // A value no longer in stock is replaced by the smallest left
      for (const s of res.body?.sims || []) {
        if (!faces.value.some((f) => f.face === chosen.value[s.sim_uuid])) chosen.value[s.sim_uuid] = faces.value[0]?.face ?? null
      }
    } else if (!facesLoaded.value) {
      // Before s162: the value 1000 only, as before
      faces.value = [{ face: 1000, available: 0, ready: 0 }]
      for (const s of res.body?.sims || []) chosen.value[s.sim_uuid] = 1000
    }
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      if (list) error.value = ''
    } else {
      error.value = say(res)
    }
    if (Array.isArray(list)) {
      cards.value = list
      const ids = [...new Set(list.map((c) => c.batch_id).filter(Boolean))]
      if (ids.length) admin.batchCodeMap(ids).then((m) => { batchCodes.value = m || {} })
    }
    loaded.value = true
  } finally {
    busy.value = false
  }
  schedule()
}

function ask (s) {
  fromSuspect.value = false
  loadSuspect()
  target.value = s
  loadFeedBatches()
  confirmOpen.value = true
}
async function start () {
  const s = target.value
  confirmOpen.value = false
  starting.value = s.sim_uuid
  try {
    const res = await flexy.ownerFeedStart(s.sim_uuid, chosen.value[s.sim_uuid] || 1000, fromSuspect.value, feedBatch.value)
    if (res.status === 200 && res.body?.ok) {
      view.value = res.body
      Notify.create({ type: 'positive', message: res.body.started?.quiet ? `تُرسل بطاقة إلى ${s.label} الآن` : `${s.label} مشغولة: تُرسل حين تهدأ` })
      admin.feedFaces().then((v) => { if (Array.isArray(v)) faces.value = v.filter((f) => f.available + f.ready > 0) }).catch(() => {})
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
.face { min-width: 120px; }
</style>
