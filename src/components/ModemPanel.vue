<template>
  <!-- Modem page (owner, 2026-10-26): what the modem's own page shows, from the stations page.
       Read-only status, a message reader, and a USSD lab where no code is blocked; a code
       carrying a PIN waits 60 s and its reply. «{PIN}» is filled in by the server. -->
  <div class="column q-gutter-sm" style="min-width: 0; max-width: 100%">
    <q-tabs v-if="!ussdOnly" v-model="tab" dense no-caps align="justify" mobile-arrows outside-arrows class="text-primary">
      <!-- The admin phone (agent «phone-*») has no HiLink modem and no SMS reader: only the USSD lab works there -->
      <q-tab v-if="!phone" name="status" label="حالة المودم" />
      <q-tab v-if="!phone" name="sms" label="الرسائل" />
      <q-tab name="ussd" label="تجربة USSD" />
      <q-tab name="ledger" label="سجل الرصيد" />
    </q-tabs>
    <div v-if="error" class="small text-negative">{{ error }}</div>
    <div v-if="page && page.same_ip_modems > 0" class="small text-deep-orange">
      يوجد {{ page.same_ip_modems }} مودم آخر في نفس الكمبيوتر بنفس العنوان <bdi class="ltr">{{ page.modem_ip }}</bdi> خلال آخر 5 أيام
    </div>
    <div v-if="page && !page.ready" class="small muted">الشريحة أو المودم أو الكمبيوتر غير متصل الآن: القراءة والإرسال غير متاحين</div>

    <!-- Status -->
    <template v-if="tab === 'status' && !phone">
      <div v-if="unsupported" class="small text-deep-orange">قراءة حالة المودم تحتاج Agent 0.6.5 أو أحدث: اضغط «حدّث» لهذا الكمبيوتر.</div>
      <div class="kv">
        <span class="muted">الإشارة</span>
        <span v-if="status?.network">{{ bars }} {{ netType }}<span v-if="status.signal?.rsrp" class="muted"> · <bdi class="ltr">RSRP {{ status.signal.rsrp }}</bdi></span></span><span v-else>—</span>
        <span class="muted">الشبكة</span><span>{{ status?.plmn?.name || status?.plmn?.short_name || '—' }}</span>
        <span class="muted">حالة الشريحة</span><span>{{ simState }}</span>
        <span class="muted">مخزن الرسائل</span>
        <span v-if="count" :class="fullness >= 80 ? 'text-negative' : ''">{{ count.local_inbox ?? '—' }} من {{ count.local_max ?? '—' }} · الشريحة {{ count.sim_inbox ?? '—' }} من {{ count.sim_max ?? '—' }}</span><span v-else>—</span>
        <span class="muted">مركز الرسائل</span><bdi class="ltr">{{ status?.sms_config?.smsc || '—' }}</bdi>
        <span class="muted">IMEI</span><bdi class="ltr">{{ tail(status?.device?.imei) }}</bdi>
        <span class="muted">آخر قراءة</span><span>{{ page?.status ? clock(status?.read_at || page.status.completed_at || page.status.created_at) : 'لم تُقرأ بعد' }}</span>
      </div>
      <div v-if="status?.errors && Object.keys(status.errors).length" class="small muted">لم يجب المودم عن: {{ Object.keys(status.errors).join('، ') }}</div>
      <q-btn outline no-caps color="primary" label="اقرأ حالة المودم" :loading="busy" :disable="!page?.ready" @click="readStatus" />
    </template>

    <!-- Messages -->
    <template v-if="tab === 'sms' && !phone">
      <div v-if="store" class="small" :class="(store.local_inbox || 0) >= 0.8 * (store.local_max || 500) ? 'text-negative' : 'muted'">
        مخزن المودم: {{ store.local_inbox ?? '—' }} من {{ store.local_max ?? '—' }}. إذا امتلأ لا تصل رسائل جديدة.
      </div>
      <!-- «أرسل رسالة» (owner 2026-10-31, Flexy Core 0123, Agent 0.9.9): one SMS from THIS SIM, never retried;
           a Mobilis card to 111 recharges the SIM that sent it. The reply shows below by itself. -->
      <div class="send column q-gutter-xs">
        <div class="text-weight-bold">أرسل رسالة <span class="small muted">من: {{ simName || 'هذه الشريحة' }}</span></div>
        <q-input v-model="smsTo" dense outlined label="المستلم" placeholder="111" inputmode="numeric" input-class="ltr text-left" maxlength="15" />
        <q-input v-model="smsText" dense outlined autogrow label="المحتوى" input-class="ltr text-left" :counter="true" maxlength="160" />
        <q-btn unelevated no-caps color="primary" icon="send" label="أرسل" :loading="sending" :disable="busy || sending || !page?.ready || !/^[0-9]{3,15}$/.test(smsTo.trim()) || !smsText.trim()" @click="sendSms" />
        <div v-if="smsResult" class="small" :class="smsResult.cls">{{ smsResult.text }}</div>
        <div class="small muted">رسالة واحدة في كل ضغطة، ولا تُعاد وحدها. المحتوى يبقى في سجل الأوامر.</div>
      </div>
      <div class="small muted">القراءة لا تحذف شيئًا.</div>
      <div v-if="!messages.length" class="small muted">لا رسائل مقروءة بعد.</div>
      <div v-for="(m, i) in messages" :key="m.index || i" class="sms">
        <div class="row justify-between small muted"><bdi class="ltr">{{ m.sender || '—' }}</bdi><bdi class="ltr">{{ m.date }}</bdi></div>
        <div dir="auto" class="pre">{{ m.content }}</div>
      </div>
      <q-btn outline no-caps color="primary" label="اقرأ آخر 20 رسالة" :loading="busy" :disable="!page?.ready" @click="readSms" />
    </template>

    <!-- USSD lab -->
    <!-- Exploring a new group (owner 2026-10-29, «ارسم»→«نفّذ»): every page read, gathered; moving below it -->
    <template v-if="tab === 'ussd' && explore">
      <template v-if="startedHere || sessionOpen">
        <div v-for="p in explored.pages" :key="p.key" class="xpage">
          <div class="xpg" :class="{ cur: sessionOpen && p.key === explored.current }" role="button" tabindex="0" @click="toggle(p.key)">
            <span>{{ pageLabel(p.path) }}<span v-if="sessionOpen && p.key === explored.current && !hasNext && !asked.pin"> · الأخيرة</span></span>
            <span>{{ offersCount(p.items.length) }}<span v-if="!isOpen(p.key)"> ▾</span></span>
          </div>
          <template v-if="isOpen(p.key)">
            <div v-for="o in p.items" :key="o.value + o.label" class="xrow" :class="{ picked: probeCode === o.value && p.key === explored.current }"
              role="button" tabindex="0" @click="pick(o, p)">
              <span class="xr"><span class="xc ltr">{{ o.value }}</span><bdi dir="auto">{{ o.label }}</bdi></span>
              <span class="xok">سُجّل ✓</span>
            </div>
          </template>
        </div>
        <!-- «اكشف»: the price the network names for the code sent, beside the page's offers holding that code -->
        <div v-if="explored.price" class="xcmp">
          <div class="text-weight-bold">الرمز <span class="ltr">{{ explored.price.code }}</span> ← الشبكة قالت {{ explored.price.amount }} دج</div>
          <div v-for="c in comparison" :key="c.label" :class="c.match ? 'text-positive' : 'text-negative'">
            {{ c.match ? '✓ يطابق' : '✗ لا يطابق' }}: <bdi dir="auto">{{ c.label }}</bdi> ({{ c.price ?? '—' }})
          </div>
          <div v-if="comparison.length > 1" class="small muted">الرمز مكرر في القائمة: يُحفظ هذا كدليل، ويبقى العرضان «مشكوكين» لا يُباعان.</div>
          <div class="small text-deep-orange">الشبكة تطلب الـPIN الآن: الاستكشاف لا يشتري، أنهِ الجلسة. لكشف رمز آخر افتح القائمة من جديد.</div>
        </div>
        <div v-if="anyWaiting" class="small muted q-px-sm">… بانتظار رد الشبكة</div>
        <div v-else-if="steps.length && !lastOk" class="small text-negative q-px-sm">لم تردّ الشبكة على آخر خطوة. أنهِ الجلسة وافتحها من جديد.</div>
        <template v-if="sessionOpen">
          <div class="row no-wrap q-gutter-xs">
            <q-btn class="col" unelevated no-caps color="cyan-9" label="التالية" icon-right="chevron_left" :disable="!canMove || !hasNext" :loading="busy && !anyWaiting" @click="move(nextOpt?.value)" />
            <q-btn class="col" outline no-caps color="cyan-9" icon="chevron_right" label="رجوع" :disable="!canMove || !backOpt" @click="move(backOpt?.value)" />
            <q-btn class="col" outline no-caps color="negative" label="أنهِ" :disable="lab.status === 'closing' || moving" @click="end" />
          </div>
          <!-- «اكشف»: a tap on an offer copies its code here; only «أرسل» sends it (never a PIN) -->
          <div class="row no-wrap items-center q-gutter-xs">
            <q-input v-model="probeCode" dense outlined class="col ltr" mask="###" inputmode="numeric" placeholder="رمز العرض" :disable="!canMove || asked.pin" />
            <q-btn unelevated no-caps color="deep-orange" label="اكشف السعر" :disable="!canMove || asked.pin || !/^\d{1,3}$/.test(probeCode || '')" @click="move(probeCode)" />
          </div>
        </template>
        <template v-else-if="explored.pages.length">
          <div class="xdone">✓ سُجّلت {{ explored.pages.length }} {{ explored.pages.length > 2 ? 'صفحات' : explored.pages.length === 2 ? 'صفحتان' : 'صفحة' }} و{{ explored.total }} عرضًا في «جديدة»</div>
        </template>
        <q-expansion-item dense dense-toggle label="التفاصيل (ما أُرسل وما رُدّ)" header-class="small text-cyan-9">
          <div class="console ltr">
            <div v-for="(s, i) in steps" :key="s.sequence">
              <div v-if="s.action !== 'ussd_release'"><b>Sent:</b> {{ sentText(s, i) }}</div>
              <div v-else class="muted">— انتهت الجلسة —</div>
              <div v-if="s.reply" dir="auto" class="text-primary"><b>Received:</b> {{ s.reply }}</div>
              <div v-if="s.status !== 'success' && !waiting(s)" class="text-negative">{{ s.error_code || s.status }}</div>
            </div>
          </div>
        </q-expansion-item>
      </template>
      <q-btn v-if="!sessionOpen" outline no-caps color="primary" icon="refresh" :loading="busy" :disable="!page?.ready || !startCode"
        label="افتح القائمة من جديد" @click="code = startCode; start()" />
    </template>
    <template v-else-if="tab === 'ussd'">
      <div class="small muted">كل الأكواد مسموحة على مسؤولية الإدارة. اكتب {PIN} ليضع الخادم الـPIN المحفوظ دون أن يظهر. الكود الذي فيه PIN لا يتكرر قبل 60 ثانية ووصول رده.</div>
      <!-- The offers tab's live session shows only the session started here, never an older one -->
      <div v-if="!ussdOnly || startedHere || sessionOpen" class="console ltr">
        <div v-if="!steps.length" class="muted">—</div>
        <div v-for="(s, i) in steps" :key="s.sequence">
          <div v-if="s.action !== 'ussd_release'"><b>Sent:</b> {{ sentText(s, i) }}</div>
          <div v-else class="muted">— انتهت الجلسة —</div>
          <div v-if="waiting(s) && s.action !== 'ussd_release'" class="muted">… بانتظار الرد</div>
          <div v-if="s.reply" dir="auto" class="text-primary"><b>Received:</b> {{ s.reply }}</div>
          <div v-if="s.status !== 'success' && !waiting(s)" class="text-negative">{{ s.error_code || s.status }}</div>
        </div>
      </div>
      <!-- The offers tab's live session opens by itself; once ended, one button opens it again -->
      <template v-if="!sessionOpen && ussdOnly">
        <q-btn outline no-caps color="primary" icon="refresh" :loading="busy" :disable="!page?.ready || !startCode"
          label="افتح القائمة من جديد" @click="code = startCode; start()" />
      </template>
      <template v-else-if="!sessionOpen">
        <div v-if="quick.length" class="row q-gutter-xs">
          <q-btn v-for="[label, c] in quick" :key="c" outline dense no-caps size="sm" color="primary" :label="label"
            :disable="busy || !page?.ready || (pinLike(c) && (!page?.has_pin || lab.pin_wait_seconds > 0))" @click="code = c; start()" />
        </div>
        <q-input v-model="code" dense outlined class="ltr" placeholder="*101#" @keyup.enter="start">
          <template #append><q-btn flat dense no-caps size="sm" label="PIN" :disable="!page?.has_pin" @click="code = addPin(code, true)" /></template>
        </q-input>
        <q-btn unelevated no-caps color="primary" :loading="busy" :disable="!page?.ready || !code.trim() || (lab.pin_wait_seconds > 0 && pinLike(code))"
          :label="lab.pin_wait_seconds > 0 && pinLike(code) ? 'انتظر ' + lab.pin_wait_seconds + ' ث' : 'أرسل'" @click="start" />
      </template>
      <template v-else>
        <!-- What the last reply asks for, as buttons (owner 2026-10-28); the box stays for anything else -->
        <template v-if="lastOk && !anyWaiting">
          <div v-if="asked.pin && explore" class="small text-deep-orange">هذا سعر العرض كما تقوله الشبكة (سُجّل). الاستكشاف لا يشتري: أنهِ الجلسة (أي رد هنا تأخذه الشبكة كـPIN)، والبيع من القائمة فوق.</div>
          <q-btn v-else-if="asked.pin" unelevated no-caps color="deep-orange" icon="lock" :disable="!page?.has_pin"
            :label="page?.has_pin ? 'أرسل الـPIN المحفوظ (من الخادم)' : 'لا يوجد PIN محفوظ لهذه الشريحة'" @click="choose({ value: '{PIN}', label: 'PIN', money: asked.pinIsMoney })" />
          <div v-if="asked.options.length" class="row q-gutter-xs">
            <q-btn v-for="(o, i) in asked.options" :key="i" dense no-caps :outline="!o.money" :unelevated="o.money"
              :color="o.money ? 'deep-orange' : o.duplicate ? 'warning' : 'primary'" @click="choose(o)">
              <span class="ltr">{{ o.value }}</span>&nbsp;·&nbsp;<span dir="auto">{{ o.next ? 'المزيد' : o.label }}</span>
            </q-btn>
          </div>
        </template>
        <q-input v-model="reply" dense outlined class="ltr" :placeholder="explore ? '0' : '1'" :disable="anyWaiting || !lastOk" @keyup.enter="answer">
          <template v-if="!explore" #append><q-btn flat dense no-caps size="sm" label="PIN" :disable="!page?.has_pin || anyWaiting" @click="reply = addPin(reply, false)" /></template>
        </q-input>
        <div class="row q-gutter-sm">
          <q-btn class="col" unelevated no-caps color="primary" :loading="busy && !anyWaiting" :disable="anyWaiting || !lastOk || !reply.trim() || (lab.pin_wait_seconds > 0 && pinLike(reply))"
            :label="lab.pin_wait_seconds > 0 && pinLike(reply) ? 'انتظر ' + lab.pin_wait_seconds + ' ث' : 'رد'" @click="answer" />
          <q-btn class="col" outline no-caps color="negative" label="أنهِ الجلسة" :disable="lab.status === 'closing'" @click="end" />
        </div>
      </template>
    </template>

    <!-- The SIM ledger: what each session did to the balance, and the reads that settle it -->
    <SimLedger v-if="tab === 'ledger'" :sim-uuid="simUuid" />
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { ownerModem } from 'src/api/flexy'
import { readReply, typedPin } from 'src/api/ussdMenu'
import SimLedger from 'src/components/SimLedger.vue'

const props = defineProps({
  simUuid: { type: String, required: true },
  phone: { type: Boolean, default: false },
  simType: { type: String, default: '' },
  // The offers tab's live session on a new group (owner 2026-10-28): the lab alone, its code ready
  ussdOnly: { type: Boolean, default: false },
  startCode: { type: String, default: '' },
  // Shown above «أرسل» (owner 2026-10-31: «أي شريحة»): the SIM the message leaves from
  simName: { type: String, default: '' },
  // Exploring a new group's pages (owner 2026-10-28: no PIN nor «1» in a discovery): moving and reading only,
  // an offer's code shows its price and nothing more
  explore: { type: Boolean, default: false }
})

// One press for what is known (owner 2026-10-26): read-only codes from telecom/TELECOM-SERVICE-CODES.md, by SIM type.
// No money code here; typing stays for anything else.
const QUICK = {
  'mobilis-arsselli': [['الرصيد', '*632*01*{PIN}#'], ['الرقم', '*101#'], ['أرقام فليكسي', '*632*03*{PIN}#']],
  'mobilis-sama': [['الرصيد', '*222#'], ['الرقم', '*101#']],
  'djezzy-flexy': [['الرصيد', '*766#'], ['آخر العمليات', '*762#']],
  'ooredoo-flexy': [['الرصيد', '*200*{PIN}#']]
}
const quick = computed(() => QUICK[props.simType] || [])

const tab = ref(props.phone || props.ussdOnly ? 'ussd' : 'status')
const page = ref(null)
const lab = ref({ pin_wait_seconds: 0 })
const messages = ref([])
const store = ref(null)
const code = ref(props.startCode)
const reply = ref('')
const busy = ref(false)
const error = ref('')
let alive = true
let timer = null

const KNOWN = {
  SIM_NOT_READY: 'الشريحة أو المودم أو الكمبيوتر غير متصل الآن',
  SMS_INBOX_SIM_NOT_READY: 'الشريحة أو المودم أو الكمبيوتر غير متصل الآن',
  LAB_SESSION_OPEN: 'جلسة سابقة ما زالت مفتوحة: أنهِها أولًا',
  LAB_WAITING_REPLY: 'انتظر رد الخطوة السابقة',
  LAB_SESSION_CLOSED: 'الجلسة انتهت: ابدأ كودًا جديدًا',
  LAB_LAST_STEP_NOT_ANSWERED: 'الخطوة السابقة لم يصلها رد: أنهِ الجلسة وابدأ من جديد',
  PIN_NOT_SAVED: 'لا يوجد PIN محفوظ لهذه الشريحة',
  LAB_CODE_CHARACTERS: 'الكود يقبل الأرقام و* و# و+ و{PIN} فقط',
  LAB_CODE_MUST_START_WITH_STAR: 'الكود يبدأ بـ * أو #',
  LAB_CODE_LENGTH: 'الكود فارغ أو طويل جدًا',
  OWNER_REQUIRED: 'هذا الحساب ليس مديرًا',
  STATION_CONNECT_UNREACHABLE: 'تعذّر الوصول إلى المحطات الآن: أعد المحاولة',
  MODEM_BUSY: 'المودم مشغول بعملية أخرى (رصيد أو عرض أو تجربة): أعد المحاولة بعد نصف دقيقة'
}
const reason = (e) => {
  const text = String(e?.message || e)
  const wait = text.match(/LAB_PIN_COOLDOWN_(\d+)/)
  if (wait) return 'كود فيه PIN: انتظر ' + wait[1] + ' ثانية'
  const key = Object.keys(KNOWN).find((k) => text.includes(k))
  return key ? KNOWN[key] : text
}
// Through flexy-api only (AGENTS.md rule 1): Flexy Core calls Station Connect as this session.
const call = async (path, body) => {
  const r = await ownerModem(path, body)
  if (!r.body?.ok) throw new Error(r.body?.error || 'HTTP_' + r.status)
  return r.body.data
}
const q = () => '?sim_uuid=' + encodeURIComponent(props.simUuid)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const busyStatus = (s) => s === 'queued' || s === 'claimed'
const waiting = (s) => busyStatus(s.status)
const clock = (v) => (v ? new Date(v).toLocaleString('ar-DZ') : '—')
const tail = (v) => (v ? '…' + String(v).slice(-6) : '—')
const parse = (raw) => { try { return raw ? JSON.parse(raw) : null } catch { return null } }
const pinLike = (v) => /\{\s*pin\s*\}/i.test(v) || /\*\d{4,8}(?=[*#]|$)/.test(v)
const addPin = (v, isCode) => (isCode ? v.replace(/#$/, '') + (v && !v.replace(/#$/, '').endsWith('*') ? '*' : '') + '{PIN}#' : v + '{PIN}')

const status = computed(() => parse(page.value?.status?.raw_response))
const unsupported = computed(() => page.value?.status?.error_code === 'UNSUPPORTED_COMMAND_ACTION')
const count = computed(() => status.value?.sms_count || null)
const fullness = computed(() => (count.value?.local_max ? Math.round(100 * (count.value.local_inbox || 0) / count.value.local_max) : 0))
const bars = computed(() => {
  const n = Number(status.value?.network?.signal_icon || 0)
  const max = Number(status.value?.network?.max_signal || 5) || 5
  return '▮'.repeat(n) + '▯'.repeat(Math.max(0, max - n))
})
const NET = { 19: '4G', 101: '4G', 1011: '4G+', 1: '2G', 2: '3G', 3: '3G', 4: '3G', 5: '3G', 6: '3G', 7: '3G', 9: '3G', 41: '3G', 46: '3G' }
const netType = computed(() => NET[status.value?.network?.network_type] || status.value?.network?.network_type || '')
const SIM = { 0: 'لا توجد شريحة أو غير صالحة', 1: 'جاهزة', 2: 'غير صالحة', 255: 'لا توجد شريحة', 240: 'PIN الشريحة مطلوب' }
const simState = computed(() => { const s = status.value?.network?.sim_status; return s == null ? '—' : (SIM[s] || s) })
const steps = computed(() => lab.value.steps || [])
const sessionOpen = computed(() => lab.value.status === 'open' || lab.value.status === 'closing')
const anyWaiting = computed(() => steps.value.some(waiting))
const lastOk = computed(() => steps.value.length > 0 && steps.value[steps.value.length - 1].status === 'success')
const asked = computed(() => readReply(steps.value[steps.value.length - 1]?.reply, props.simType))

async function loadPage () { page.value = await call('page' + q()) }
async function loadLab () { lab.value = await call('lab' + q()) || { pin_wait_seconds: 0 } }
async function loadSms () {
  const rows = await call('sms' + q()) || []
  const latest = rows.find((r) => r.command_status === 'success' && r.raw_response) || null
  const body = parse(latest?.raw_response)
  // Entries with no sender, no text and a 1999 date are not shown (the modem's own page hides them too).
  messages.value = (body?.messages || []).filter((m) => m.sender || m.content || !String(m.date || '').startsWith('1999'))
  store.value = body?.sms_count || null
  return rows[0] ? (rows[0].command_status || rows[0].status) : null
}

async function run (fn) {
  busy.value = true; error.value = ''
  try { await fn() } catch (e) { error.value = reason(e) } finally { busy.value = false }
}
const readStatus = () => run(async () => {
  await call('status', { sim_uuid: props.simUuid })
  for (let i = 0; i < 20 && alive; i++) {
    await sleep(2500); await loadPage()
    if (page.value?.status && !busyStatus(page.value.status.command_status)) break
  }
})
const readSms = () => run(async () => {
  await call('sms', { sim_uuid: props.simUuid })
  for (let i = 0; i < 15 && alive; i++) {
    await sleep(2000)
    if (!busyStatus(await loadSms())) break
  }
})
// «أرسل رسالة»: queued for this SIM, followed until the modem says sent / failed; then the inbox is read for the reply
const smsTo = ref('111')
const smsText = ref('')
const sending = ref(false)
const smsResult = ref(null)
const SMS_CODES = { MODEM_BUSY: 'المودم بقي مشغولًا دقيقة: أعد بعد قليل', SMS_SEND_BUSY: 'رسالة سابقة لم تنتهِ بعد', UNSUPPORTED_COMMAND_ACTION: 'برنامج هذا الكمبيوتر قديم: ينتظر التحديث 0.9.9', NO_SEND_STATUS: 'المودم قبلها ولم يقل هل خرجت: انظر الرسائل الواردة' }
async function sendSms () {
  if (sending.value) return
  sending.value = true; smsResult.value = null; error.value = ''
  try {
    const job = await call('sms-send', { sim_uuid: props.simUuid, to: smsTo.value.trim(), text: smsText.value })
    smsResult.value = { cls: 'muted', text: 'في الطريق إلى المودم…' }
    let st = null
    for (let i = 0; i < 60 && alive; i++) {
      await sleep(2000)
      st = await call('sms-send?job_uuid=' + encodeURIComponent(job))
      if (st && !busyStatus(st.status)) break
    }
    if (st?.status === 'success') {
      smsResult.value = { cls: 'text-positive', text: '✓ أُرسلت إلى ' + st.to + '. تُقرأ الرسائل الواردة بعد 20 ثانية…' }
      smsText.value = ''
      await sleep(20000)
      if (alive) await readSms()
      smsResult.value = { cls: 'text-positive', text: '✓ أُرسلت إلى ' + st.to + '. الرد (إن وصل) في الرسائل أدناه.' }
    } else if (st?.status === 'failed' || st?.status === 'review') {
      smsResult.value = { cls: 'text-negative', text: (st.status === 'review' ? '؟ ' : '✗ ') + (SMS_CODES[st.error_code || st.result_code] || st.error_code || st.result_code || 'لم تُرسل') }
    } else {
      smsResult.value = { cls: 'text-deep-orange', text: 'لم يأخذها الكمبيوتر بعد: هل هو متصل؟' }
    }
  } catch (e) {
    smsResult.value = { cls: 'text-negative', text: SMS_CODES[String(e?.message || '')] || reason(e) }
  } finally {
    sending.value = false
  }
}
async function follow () {
  await loadLab()
  for (let i = 0; i < 40 && alive && anyWaiting.value; i++) { await sleep(2000); await loadLab() }
}
// The exploration's pages: each menu the session showed, by the replies that led to it («0» next page,
// «00» back, a code = its sub-menu); the latest reading of a page wins. A PIN prompt names an offer's price.
const BACK = /^(retour|pr[ée]c[ée]dent|back|رجوع)/i
const explored = computed(() => {
  const pages = []
  let path = []
  let current = null
  let price = null
  steps.value.forEach((s, i) => {
    if (s.action === 'ussd_release') return
    if (i > 0) path = String(s.value) === '00' ? path.slice(0, -1) : [...path, String(s.value)]
    if (s.status !== 'success' || !s.reply) return
    const r = readReply(s.reply)
    const items = r.options.filter((o) => !o.next && o.value !== '00' && !BACK.test(o.label))
    if (items.length) {
      const key = path.join(',')
      const p = pages.find((x) => x.key === key)
      if (p) p.items = items
      else pages.push({ key, path: [...path], items })
      current = key
      price = null
    } else if (r.pin) {
      price = { code: path[path.length - 1], pageKey: path.slice(0, -1).join(','), amount: (s.reply.match(/(\d[\d\s.,]*)\s*da/i)?.[1] || '—').trim() }
    }
  })
  return { pages, current, price, total: pages.reduce((n, p) => n + p.items.length, 0) }
})
// The network's price for a code beside the offers of that page holding it (the core's priceFromName, by the name)
const fold = (v) => String(v).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
function namePrice (name) {
  const n = fold(name)
  const m = /(?:^|[^0-9])([0-9]{2,5})\s*da\b/.exec(n) || /(?:^|[a-z+&]\s)([0-9]{2,5})(?![0-9])/.exec(n) || /^([0-9]{2,5})(?![0-9])/.exec(n)
  return m ? Number(m[1]) : null
}
const comparison = computed(() => {
  const pr = explored.value.price
  if (!pr) return []
  const p = explored.value.pages.find((x) => x.key === pr.pageKey)
  return (p?.items || []).filter((o) => o.value === pr.code)
    .map((o) => ({ label: o.label, price: namePrice(o.label), match: namePrice(o.label) === Number(pr.amount) }))
})
// One step at a time: a second tap before the network answers sends nothing (owner 2026-10-29)
const moving = ref(false)
async function move (value) {
  if (moving.value || !canMove.value || !value) return
  moving.value = true
  try { await send(value) } finally { moving.value = false; probeCode.value = '' }
}
const probeCode = ref('')
const pick = (o, p) => { if (canMove.value && !asked.value.pin && p.key === explored.value.current) probeCode.value = o.value }
// «الصفحة 3 (المزيد ثم المزيد)», «قائمة 29», «قائمة 29 · الصفحة 2»
function pageLabel (path) {
  let menu = ''
  let n = 1
  for (const v of path) { if (v === '0') n++; else { menu = menu ? menu + ' › ' + v : v; n = 1 } }
  const more = path.length && path.every((v) => v === '0') ? ' (' + path.map(() => 'المزيد').join(' ثم ') + ')' : ''
  return menu ? 'قائمة ' + menu + (n > 1 ? ' · الصفحة ' + n : '') : 'الصفحة ' + n + more
}
const nextOpt = computed(() => asked.value.options.find((o) => o.next) || null)
const backOpt = computed(() => (asked.value.pin ? null : asked.value.options.find((o) => o.value === '00' || BACK.test(o.label)) || null))
const hasNext = computed(() => Boolean(nextOpt.value) && !asked.value.pin)
const canMove = computed(() => sessionOpen.value && lastOk.value && !anyWaiting.value && !busy.value && !moving.value)
const offersCount = (n) => (n === 1 ? 'عرض واحد' : n === 2 ? 'عرضان' : n <= 10 ? n + ' عروض' : n + ' عرضًا')
// Earlier pages fold; the current one stays open
const opened = ref(new Set())
const isOpen = (key) => (sessionOpen.value && key === explored.value.current) || opened.value.has(key)
const toggle = (key) => { const n = new Set(opened.value); if (n.has(key)) n.delete(key); else n.add(key); opened.value = n }
const startedHere = ref(false)
const start = () => { if (!code.value.trim() || busy.value) return; startedHere.value = true; return run(async () => { await call('lab/start', { sim_uuid: props.simUuid, code: code.value.trim() }); await follow() }) }
// A PIN typed by hand in an older session is never shown again (owner 2026-10-28: «Sent: 3808» on screen)
const sentText = (s, i) => (i > 0 && readReply(steps.value[i - 1]?.reply).pin && /^\s*\d{4,8}\s*$/.test(s.value || '') ? '••••' : s.value)
const send = (value) => run(async () => { await call('lab/reply', { session_uuid: lab.value.session_uuid, value }); reply.value = ''; await follow() })
// A PIN is never typed (owner 2026-10-28: a typed PIN is kept in the station's command log): the server fills {PIN}
const answer = () => {
  if (!reply.value.trim() || busy.value) return
  if (typedPin(reply.value, asked.value.pin)) { error.value = 'لا تكتب الـPIN: اضغط زر «أرسل الـPIN المحفوظ»، فيضعه الخادم دون أن يُحفظ ظاهرًا'; return }
  if (props.explore && (/pin/i.test(reply.value) || asked.value.pin)) { error.value = 'الاستكشاف لا يشتري: لا PIN هنا. البيع من القائمة فوق.'; return }
  return send(reply.value.trim())
}
// A button: the money step (and a code the menu shows twice) is asked first
function choose (o) {
  if (busy.value) return
  if (props.explore && o.money) { error.value = 'الاستكشاف لا يشتري: هذه خطوة المال. البيع من القائمة فوق.'; return }
  const notes = [o.money ? 'هذه خطوة المال: بعدها قد يُخصم الرصيد.' : '', o.duplicate ? 'الرمز ' + o.value + ' مكرر في القائمة: الشبكة قد تختار عرضًا آخر بنفس الرمز.' : ''].filter(Boolean)
  if (!notes.length) return send(o.value)
  Dialog.create({ title: 'تأكيد', message: notes.join(' ') + ' أرسل «' + (o.value === '{PIN}' ? 'PIN' : o.value) + '»؟', cancel: 'رجوع', ok: 'نعم، أرسل' })
    .onOk(() => send(o.value))
}
const end = () => run(async () => { await call('lab/release', { session_uuid: lab.value.session_uuid }); await follow() })

// The PIN wait counts down locally, without asking the server every second.
watch(() => lab.value.pin_wait_seconds, (s) => {
  clearTimeout(timer)
  if (s > 0) timer = setTimeout(() => { lab.value = { ...lab.value, pin_wait_seconds: Math.max(0, s - 1) } }, 1000)
})
async function loadAll () {
  error.value = ''
  try { await Promise.all([loadPage(), loadLab(), props.phone ? null : loadSms()]) } catch (e) { error.value = reason(e) }
}
watch(() => props.simUuid, loadAll)
watch(() => props.phone, (p) => { if (p) tab.value = 'ussd' })
onMounted(async () => {
  await loadAll()
  // The offers tab's live session: no question, the menu opens at once (owner 2026-10-28)
  if (props.ussdOnly && props.startCode && !sessionOpen.value && page.value?.ready) start()
})
onBeforeUnmount(() => { alive = false; clearTimeout(timer) })
</script>

<style scoped>
.kv { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 4px 12px; }
.kv > * { min-width: 0; overflow-wrap: anywhere; }
.ltr { direction: ltr; unicode-bidi: isolate; }
.small { font-size: 12px; }
.muted { color: #777; }
.sms { border-bottom: 1px solid #eee; padding: 4px 0; }
.pre { white-space: pre-wrap; }
.xpage { border: 1px solid #ECEEF3; border-radius: 8px; overflow: hidden; margin-bottom: 4px; }
.xpg { display: flex; justify-content: space-between; padding: 5px 10px; font-size: 12px; color: #6B7280; background: #F8FAFC; cursor: pointer; }
.xpg.cur { background: #ECFEFF; color: #0E7490; font-weight: 800; }
.xrow { display: flex; justify-content: space-between; align-items: center; padding: 5px 10px; border-top: 1px solid #ECEEF3; font-size: 13px; }
.xr { display: flex; align-items: center; gap: 8px; }
.xc { font-weight: 800; color: #0E7490; background: #ECFEFF; border-radius: 5px; min-width: 26px; text-align: center; font-size: 12px; padding: 0 4px; }
.xrow.picked { background: #FFF7ED; }
.xcmp { border: 1px solid #FDBA74; background: #FFF7ED; border-radius: 8px; padding: 8px 10px; font-size: 13px; }
.xok { color: #16A34A; font-size: 11.5px; font-weight: 800; white-space: nowrap; }
.xdone { padding: 9px 10px; font-weight: 800; color: #166534; background: #F0FDF4; border: 1px solid #BBF7D0; border-radius: 8px; }
.console { background: #f6f6f6; border-radius: 6px; padding: 8px; min-height: 56px; white-space: pre-wrap; font-family: monospace; font-size: 13px; }
.send { border: 1px solid #E4E6EC; border-radius: 10px; padding: 10px; }
</style>
