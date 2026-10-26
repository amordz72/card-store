<template>
  <!-- Modem page (owner, 2026-10-26): what the modem's own page shows, from the stations page.
       Read-only status, a message reader, and a USSD lab where no code is blocked; a code
       carrying a PIN waits 60 s and its reply. «{PIN}» is filled in by the server. -->
  <div class="column q-gutter-sm">
    <q-tabs v-model="tab" dense no-caps align="justify" class="text-primary">
      <q-tab name="status" label="حالة المودم" />
      <q-tab name="sms" label="الرسائل" />
      <q-tab name="ussd" label="تجربة USSD" />
    </q-tabs>
    <div v-if="error" class="small text-negative">{{ error }}</div>
    <div v-if="page && page.same_ip_modems > 0" class="small text-deep-orange">
      يوجد {{ page.same_ip_modems }} مودم آخر في نفس الكمبيوتر بنفس العنوان <bdi class="ltr">{{ page.modem_ip }}</bdi> خلال آخر 5 أيام
    </div>
    <div v-if="page && !page.ready" class="small muted">الشريحة أو المودم أو الكمبيوتر غير متصل الآن: القراءة والإرسال غير متاحين</div>

    <!-- Status -->
    <template v-if="tab === 'status'">
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
    <template v-if="tab === 'sms'">
      <div v-if="store" class="small" :class="(store.local_inbox || 0) >= 0.8 * (store.local_max || 500) ? 'text-negative' : 'muted'">
        مخزن المودم: {{ store.local_inbox ?? '—' }} من {{ store.local_max ?? '—' }}. إذا امتلأ لا تصل رسائل جديدة.
      </div>
      <div class="small muted">قراءة فقط: لا حذف ولا إرسال.</div>
      <div v-if="!messages.length" class="small muted">لا رسائل مقروءة بعد.</div>
      <div v-for="(m, i) in messages" :key="m.index || i" class="sms">
        <div class="row justify-between small muted"><bdi class="ltr">{{ m.sender || '—' }}</bdi><bdi class="ltr">{{ m.date }}</bdi></div>
        <div dir="auto" class="pre">{{ m.content }}</div>
      </div>
      <q-btn outline no-caps color="primary" label="اقرأ آخر 20 رسالة" :loading="busy" :disable="!page?.ready" @click="readSms" />
    </template>

    <!-- USSD lab -->
    <template v-if="tab === 'ussd'">
      <div class="small muted">كل الأكواد مسموحة على مسؤولية الإدارة. اكتب {PIN} ليضع الخادم الـPIN المحفوظ دون أن يظهر. الكود الذي فيه PIN لا يتكرر قبل 60 ثانية ووصول رده.</div>
      <div class="console ltr">
        <div v-if="!steps.length" class="muted">—</div>
        <div v-for="s in steps" :key="s.sequence">
          <div v-if="s.action !== 'ussd_release'"><b>Sent:</b> {{ s.value }}</div>
          <div v-else class="muted">— انتهت الجلسة —</div>
          <div v-if="waiting(s) && s.action !== 'ussd_release'" class="muted">… بانتظار الرد</div>
          <div v-if="s.reply" dir="auto" class="text-primary"><b>Received:</b> {{ s.reply }}</div>
          <div v-if="s.status !== 'success' && !waiting(s)" class="text-negative">{{ s.error_code || s.status }}</div>
        </div>
      </div>
      <template v-if="!sessionOpen">
        <q-input v-model="code" dense outlined class="ltr" placeholder="*101#" @keyup.enter="start">
          <template #append><q-btn flat dense no-caps size="sm" label="PIN" :disable="!page?.has_pin" @click="code = addPin(code, true)" /></template>
        </q-input>
        <q-btn unelevated no-caps color="primary" :loading="busy" :disable="!page?.ready || !code.trim() || (lab.pin_wait_seconds > 0 && pinLike(code))"
          :label="lab.pin_wait_seconds > 0 && pinLike(code) ? 'انتظر ' + lab.pin_wait_seconds + ' ث' : 'أرسل'" @click="start" />
      </template>
      <template v-else>
        <q-input v-model="reply" dense outlined class="ltr" placeholder="1" :disable="anyWaiting || !lastOk" @keyup.enter="answer">
          <template #append><q-btn flat dense no-caps size="sm" label="PIN" :disable="!page?.has_pin || anyWaiting" @click="reply = addPin(reply, false)" /></template>
        </q-input>
        <div class="row q-gutter-sm">
          <q-btn class="col" unelevated no-caps color="primary" :loading="busy && !anyWaiting" :disable="anyWaiting || !lastOk || !reply.trim() || (lab.pin_wait_seconds > 0 && pinLike(reply))"
            :label="lab.pin_wait_seconds > 0 && pinLike(reply) ? 'انتظر ' + lab.pin_wait_seconds + ' ث' : 'رد'" @click="answer" />
          <q-btn class="col" outline no-caps color="negative" label="أنهِ الجلسة" :disable="lab.status === 'closing'" @click="end" />
        </div>
      </template>
    </template>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { supabase } from 'boot/supabase'

const props = defineProps({ simUuid: { type: String, required: true } })

const tab = ref('status')
const page = ref(null)
const lab = ref({ pin_wait_seconds: 0 })
const messages = ref([])
const store = ref(null)
const code = ref('')
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
  ADMIN_REQUIRED: 'هذا الحساب ليس مديرًا'
}
const reason = (e) => {
  const text = String(e?.message || e)
  const wait = text.match(/LAB_PIN_COOLDOWN_(\d+)/)
  if (wait) return 'كود فيه PIN: انتظر ' + wait[1] + ' ثانية'
  const key = Object.keys(KNOWN).find((k) => text.includes(k))
  return key ? KNOWN[key] : text
}
const call = async (fn, args) => {
  const { data, error: e } = await supabase.rpc(fn, args)
  if (e) throw e
  return data
}
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

async function loadPage () { page.value = await call('station_connect_admin_modem_page', { p_sim_uuid: props.simUuid }) }
async function loadLab () { lab.value = await call('station_connect_admin_ussd_lab_state', { p_sim_uuid: props.simUuid }) || { pin_wait_seconds: 0 } }
async function loadSms () {
  const rows = await call('station_connect_admin_sms_inbox_history', { p_sim_uuid: props.simUuid }) || []
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
  await call('station_connect_admin_modem_status_queue', { p_sim_uuid: props.simUuid })
  for (let i = 0; i < 20 && alive; i++) {
    await sleep(2500); await loadPage()
    if (page.value?.status && !busyStatus(page.value.status.command_status)) break
  }
})
const readSms = () => run(async () => {
  await call('station_connect_admin_queue_sms_inbox', { p_sim_uuid: props.simUuid, p_limit: 20, p_source_job_uuid: null })
  for (let i = 0; i < 15 && alive; i++) {
    await sleep(2000)
    if (!busyStatus(await loadSms())) break
  }
})
async function follow () {
  await loadLab()
  for (let i = 0; i < 40 && alive && anyWaiting.value; i++) { await sleep(2000); await loadLab() }
}
const start = () => { if (!code.value.trim() || busy.value) return; return run(async () => { await call('station_connect_admin_ussd_lab_start', { p_sim_uuid: props.simUuid, p_code: code.value.trim() }); await follow() }) }
const answer = () => { if (!reply.value.trim() || busy.value) return; return run(async () => { await call('station_connect_admin_ussd_lab_reply', { p_session_uuid: lab.value.session_uuid, p_value: reply.value.trim() }); reply.value = ''; await follow() }) }
const end = () => run(async () => { await call('station_connect_admin_ussd_lab_release', { p_session_uuid: lab.value.session_uuid }); await follow() })

// The PIN wait counts down locally, without asking the server every second.
watch(() => lab.value.pin_wait_seconds, (s) => {
  clearTimeout(timer)
  if (s > 0) timer = setTimeout(() => { lab.value = { ...lab.value, pin_wait_seconds: Math.max(0, s - 1) } }, 1000)
})
async function loadAll () {
  error.value = ''
  try { await Promise.all([loadPage(), loadLab(), loadSms()]) } catch (e) { error.value = reason(e) }
}
watch(() => props.simUuid, loadAll)
onMounted(loadAll)
onBeforeUnmount(() => { alive = false; clearTimeout(timer) })
</script>

<style scoped>
.kv { display: grid; grid-template-columns: auto 1fr; gap: 4px 12px; }
.ltr { direction: ltr; unicode-bidi: isolate; }
.small { font-size: 12px; }
.muted { color: #777; }
.sms { border-bottom: 1px solid #eee; padding: 4px 0; }
.pre { white-space: pre-wrap; }
.console { background: #f6f6f6; border-radius: 6px; padding: 8px; min-height: 56px; white-space: pre-wrap; font-family: monospace; font-size: 13px; }
</style>
