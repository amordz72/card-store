<template>
  <!-- «الأجهزة الموثوقة» (owner 2026-10-30, Flexy Core 0117): a computer that opened the site's /new page asks; the same
       4 digits on both screens, «اعطه الصلاحية», trusted until «ألغِ». What its page shows (links, commands) is edited here. -->
  <div class="column q-gutter-xs">
    <div v-for="b in waiting" :key="b.id" class="req row items-center q-gutter-sm">
      <div class="col"><b>كمبيوتر يطلب الدخول</b> <span class="small muted">· {{ b.label }}</span>
        <div class="small">على شاشته الأرقام: <b class="ltr digits">{{ b.number }}</b></div></div>
      <q-btn unelevated no-caps color="primary" label="اعطه الصلاحية" :loading="busy === 'a' + b.id" @click="set({ approve: b.id }, 'a' + b.id)" />
    </div>
    <!-- Always in sight (owner 2026-10-30: «أين زر تحميلها؟»): the page file to carry by cable -->
    <q-btn unelevated no-caps color="primary" icon="computer" class="self-start" label="ملف صفحة الكمبيوتر الجديد (للنقل بالكابل)" @click="shortcut" />
    <q-expansion-item v-model="expanded" dense icon="verified_user" :label="`الأجهزة الموثوقة (${trusted.length}) · الرسائل · الأوامر والروابط`" header-class="small text-weight-bold">
      <div class="column q-gutter-sm q-pa-sm">
        <div class="small muted">على أي كمبيوتر افتح <b class="ltr">{{ newUrl }}</b>
          <q-btn flat dense no-caps size="sm" color="primary" icon="content_copy" label="انسخ الرابط" @click="copy(newUrl)" /></div>
        <div v-for="b in trusted" :key="b.id" class="column q-gutter-xs line">
          <div class="row items-center q-gutter-sm">
            <div class="col small"><b>{{ b.label }}</b> · وُثق {{ when(b.approved_at) }}<span v-if="b.last_seen_at"> · آخر فتح {{ when(b.last_seen_at) }}</span></div>
            <q-btn flat dense no-caps size="sm" color="negative" label="ألغِ" :loading="busy === 'r' + b.id" @click="set({ revoke: b.id }, 'r' + b.id)" />
          </div>
          <!-- «شات» with this computer (Flexy Core 0118) -->
          <div v-for="m in chatOf(b.id)" :key="m.id" class="msg" :class="m.sender">
            <div class="small muted">{{ m.sender === 'pc' ? 'من الكمبيوتر' : 'منك' }} · {{ when(m.at) }}</div>
            <div class="ltr text-left msg-text">{{ m.text }}</div>
            <q-btn v-if="m.sender === 'pc'" flat dense no-caps size="sm" color="primary" icon="content_copy" label="انسخ" @click="copy(m.text)" />
          </div>
          <div class="row q-gutter-xs no-wrap">
            <q-input v-model="drafts[b.id]" dense outlined autogrow class="col" input-class="ltr text-left" placeholder="أرسل للكمبيوتر (يظهر بزر «انسخ»)" />
            <q-btn unelevated dense no-caps color="primary" icon="send" :loading="busy === 's' + b.id" :disable="!(drafts[b.id] || '').trim()"
              @click="set({ say: { id: b.id, text: drafts[b.id] } }, 's' + b.id).then(() => { drafts[b.id] = '' })" />
          </div>
        </div>
        <div v-if="installs.length" class="column q-gutter-xs">
          <div class="text-weight-bold small">آخر التثبيتات</div>
          <div v-for="i in installs" :key="i.started_at + i.computer_name" class="small">
            <b class="ltr">{{ i.computer_name }}</b> · {{ i.step }}/{{ i.total }} ·
            <span :class="i.ok === false ? 'text-negative' : ''">{{ i.ok === false ? '✗ ' : '' }}{{ i.text }}</span> <span class="muted">· {{ when(i.updated_at) }}</span>
          </div>
        </div>
        <div class="text-weight-bold small">الأوامر <span class="muted">(سطر لكل أمر: الاسم | الأمر)</span></div>
        <q-input v-model="commandsText" type="textarea" outlined dense autogrow input-class="ltr text-left small" />
        <q-btn outline dense no-caps color="primary" class="self-start" label="احفظ الأوامر" :loading="busy === 'c'" @click="saveCommands" />
        <div class="text-weight-bold small">روابطك <span class="muted">(سطر لكل رابط: الاسم | https://…)</span></div>
        <q-input v-model="linksText" type="textarea" outlined dense autogrow input-class="ltr text-left small" />
        <q-btn outline dense no-caps color="primary" class="self-start" label="احفظ الروابط" :loading="busy === 'l'" @click="saveLinks" />
        <div v-if="error" class="small text-negative">{{ error }}</div>
      </div>
    </q-expansion-item>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Notify } from 'quasar'
import * as flexy from 'src/api/flexy'

const data = ref({ browsers: [], commands: [], own_links: [], installs: [], messages: [] })
const drafts = ref({})
// Open by itself (owner 2026-10-30: «أين الزر؟»): the chat and the computers in sight
const expanded = ref(true)
const chatOf = (id) => (data.value.messages || []).filter((m) => m.browser_id === id).slice(-10)
const busy = ref('')
const error = ref('')
const commandsText = ref('')
const linksText = ref('')
const waiting = computed(() => data.value.browsers.filter((b) => b.state === 'waiting'))
const trusted = computed(() => data.value.browsers.filter((b) => b.state === 'trusted'))
const installs = computed(() => (data.value.installs || []).slice(0, 5))
const newUrl = location.origin + location.pathname + '#/new'
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '')
const ERRORS = { MIGRATION: 'طبّق 0117 من «ينتظر تطبيقك» أولًا.', NOT_WAITING: 'انتهى الطلب (15 دقيقة): اطلبه من جديد على الكمبيوتر.', LINKS_INVALID: 'رابط غير صحيح: كل سطر «الاسم | https://…».', COMMANDS_INVALID: 'أمر غير صحيح.' }

function take (b, edit) {
  data.value = { browsers: b.browsers || [], commands: b.commands || [], own_links: b.own_links || [], installs: b.installs || [], messages: b.messages || [] }
  if (edit) {
    commandsText.value = data.value.commands.map((c) => `${c.label} | ${c.text}`).join('\n')
    linksText.value = data.value.own_links.map((l) => `${l.label} | ${l.url}`).join('\n')
  }
}
async function load (edit = false) {
  const r = await flexy.ownerTrusted(null).catch(() => null)
  if (r?.status === 200 && r.body?.ok) { take(r.body, edit); error.value = '' } else if (r && r.status === 500) error.value = ERRORS.MIGRATION
}
async function set (body, tag) {
  busy.value = tag
  try {
    const r = await flexy.ownerTrusted(body)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
    take(r.body, body.links !== undefined || body.commands !== undefined)
    if (!body.say) Notify.create({ type: 'positive', message: body.approve ? 'وُثق: صفحته تفتح الآن على الكمبيوتر.' : body.revoke ? 'أُلغيت الثقة.' : 'حُفظ.' })
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = ''
  }
}
const lines = (t) => t.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => { const i = l.indexOf('|'); return i < 0 ? [l, l] : [l.slice(0, i).trim(), l.slice(i + 1).trim()] })
const saveCommands = () => set({ commands: lines(commandsText.value).map(([label, text]) => ({ label, text })) }, 'c')
const saveLinks = () => set({ links: lines(linksText.value).map(([label, url]) => ({ label, url })) }, 'l')
async function copy (t) {
  try { await navigator.clipboard.writeText(t) } catch { /* shown anyway */ }
  Notify.create({ type: 'positive', message: 'نُسخ الرابط.' })
}
// A file to carry by cable (owner 2026-10-30): double-clicked on the new computer, it opens its page in the browser
function shortcut () {
  // Plain HTML that Internet Explorer opens too (owner 2026-10-30: a fresh Windows with IE only, the site never loaded):
  // IE gets «نزّل Chrome» first (the direct installer), any other browser goes straight to the page
  const chrome = 'https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe'
  const html = `<!doctype html><html dir="rtl"><head><meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge"><title>Flexy كمبيوتر جديد</title>
<style>body{font-family:Tahoma,sans-serif;background:#f6f7f9;padding:24px;font-size:18px}a.b{display:inline-block;background:#c2410c;color:#fff;padding:14px 20px;border-radius:10px;text-decoration:none;margin:8px 0;font-weight:bold}.k{color:#555;font-size:15px}</style></head><body>
<h2>Flexy · كمبيوتر جديد</h2>
<div id="ie" style="display:none"><p><b>هذا Internet Explorer: موقعك لا يعمل عليه.</b></p>
<p>1. <a class="b" href="${chrome}">نزّل Chrome وثبّته</a></p>
<p class="k">2. بعد التثبيت: اضغط هذا الملف بالزر الأيمن ← Open with ← Google Chrome.</p></div>
<div id="go"><p><a class="b" href="${newUrl}">افتح صفحة الكمبيوتر الجديد</a></p></div>
<script>if (document.documentMode) { document.getElementById('ie').style.display = 'block'; document.getElementById('go').style.display = 'none' } else { location.replace('${newUrl}') }</` + `script></body></html>`
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([html], { type: 'text/html' }))
  a.download = 'Flexy-كمبيوتر-جديد.html'
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 10000)
  Notify.create({ type: 'positive', message: 'نُزّل Flexy-كمبيوتر-جديد.html: انقله بالكابل وافتحه على الكمبيوتر الجديد.' })
}
let timer = null
onMounted(() => {
  load(true)
  // Every 4 seconds while a computer asks, every 30 otherwise; never in the background
  let n = 0
  timer = setInterval(() => { if (!document.hidden && (waiting.value.length || trusted.value.length || ++n % 8 === 0)) load() }, 4000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<style scoped>
.req { border: 2px solid #c2410c; border-radius: 10px; padding: 8px; }
.digits { font-size: 22px; letter-spacing: 4px; color: #c2410c; }
.line { border-top: 1px solid #EEF0F5; padding-top: 4px; }
.msg { border-radius: 8px; padding: 6px 8px; }
.msg.pc { background: #FFF7ED; }
.msg.owner { background: #ECFDF5; }
.msg-text { white-space: pre-wrap; word-break: break-all; font-size: 13px; }
</style>
