<template>
  <!-- «صفحة الكمبيوتر الجديد» (owner 2026-10-30, Flexy Core 0117): opened on a computer, trusted once from the owner's phone
       (the same 4 digits on both screens), until he revokes it. Then everything that computer needs: the installer ready,
       downloads, the commands to copy, the links, and what each installation did. No login, no store, nothing else. -->
  <div class="newpc" dir="rtl">
    <h1>Flexy · كمبيوتر جديد</h1>
    <div v-if="error" class="box bad">{{ error }}</div>

    <div v-if="state === 'unknown' || state === 'revoked'" class="box">
      <p v-if="state === 'revoked'" class="bad">أُلغيت الثقة بهذا الكمبيوتر. اطلبها من جديد إن أردت.</p>
      <p>هذا الكمبيوتر غير موثوق بعد. اضغط، ثم وافق من هاتفك.</p>
      <button class="big" :disabled="busy" @click="ask">اطلب الدخول كجهاز جديد</button>
    </div>

    <div v-else-if="state === 'waiting'" class="box">
      <p>على هاتفك: <b>إضافة كمبيوتر ← الأجهزة الموثوقة</b>، وتأكّد أن الأرقام نفسها، ثم <b>«اعطه الصلاحية»</b>.</p>
      <div class="number">{{ number }}</div>
      <p class="muted">تفتح هذه الصفحة وحدها بعد موافقتك.</p>
    </div>

    <template v-else-if="state === 'trusted'">
      <!-- «شات» (owner 2026-10-30, Flexy Core 0118): paste here, it shows on the owner's phone; his answer shows here -->
      <div class="box chat">
        <h2>رسائل مع هاتفك</h2>
        <div class="msgs">
          <div v-if="!page.messages?.length" class="muted">الصق هنا أي شيء (رمز، خطأ، سطر) فيظهر على هاتفك. وما ترسله من هاتفك يظهر هنا بزر «انسخ».</div>
          <div v-for="m in page.messages" :key="m.id" class="msg" :class="m.sender">
            <div class="who muted">{{ m.sender === 'pc' ? 'من هذا الكمبيوتر' : 'من هاتفك' }} · {{ when(m.at) }}</div>
            <pre class="ltr">{{ m.text }}</pre>
            <button v-if="m.sender === 'owner'" @click="copy(m.text, 'm' + m.id)">{{ copied === 'm' + m.id ? 'نُسخ ✓' : 'انسخ' }}</button>
          </div>
        </div>
        <textarea v-model="draft" rows="3" class="ltr" placeholder="الصق هنا (Ctrl+V أو زر أيمن ← Paste)"></textarea>
        <button class="big" :disabled="busy || !draft.trim()" @click="say">أرسل إلى هاتفي</button>
      </div>

      <div class="box">
        <h2>1. ملف التثبيت</h2>
        <p class="muted">جاهز ومعتمد مسبقًا: شغّله فيثبّت كل شيء ويربط الكمبيوتر وحده، بلا موافقة ثانية.</p>
        <button class="big" :disabled="busy" @click="installer">نزّل ملف التثبيت وشغّله</button>
        <p v-if="saved" class="ok">نُزّل: {{ saved }} ← افتحه من شريط التنزيلات.</p>
      </div>

      <div class="box">
        <h2>2. ماذا فعل التثبيت <span class="muted">(يتحدّث وحده)</span></h2>
        <div v-if="!page.installs?.length" class="muted">لا تثبيت بعد.</div>
        <div v-for="i in page.installs" :key="i.started_at + i.computer_name" class="install">
          <div><b>{{ i.computer_name }}</b> · الخطوة {{ i.step }} من {{ i.total }} ·
            <span :class="i.ok === false ? 'bad' : i.ok === true && i.step === i.total ? 'ok' : ''">{{ i.ok === false ? '✗ ' : i.ok === true && i.step === i.total ? '✓ ' : '⏳ ' }}{{ i.text }}</span>
            <span class="muted"> · {{ when(i.updated_at) }}</span></div>
          <details><summary class="muted">كل الخطوات</summary>
            <div v-for="(l, n) in i.log" :key="n" class="small"><span class="muted ltr">{{ when(l.at) }}</span> · {{ l.ok === false ? '✗' : l.ok === true ? '✓' : '·' }} {{ l.step }}. {{ l.text }}</div>
          </details>
        </div>
      </div>

      <div class="box">
        <h2>3. الأوامر <span class="muted">(انسخ والصق في cmd)</span></h2>
        <div v-for="(c, n) in page.commands" :key="n" class="cmd">
          <div class="label">{{ c.label }}</div>
          <div class="row"><code class="ltr">{{ c.text }}</code><button @click="copy(c.text, n)">{{ copied === n ? 'نُسخ ✓' : 'انسخ' }}</button></div>
        </div>
      </div>

      <div class="box">
        <h2>4. تنزيلات</h2>
        <a v-for="d in page.downloads" :key="d.url" class="link" :href="d.url" target="_blank" rel="noopener noreferrer">{{ d.label }}<span class="ltr">{{ d.url }}</span></a>
      </div>

      <div class="box">
        <h2>5. روابط مفيدة</h2>
        <a v-for="l in page.links" :key="l.url" class="link" :href="l.url" target="_blank" rel="noopener noreferrer">{{ l.label }}<span class="ltr">{{ l.url }}</span></a>
      </div>
      <p class="muted center">موثوق: {{ page.label }} · حتى تلغيه من هاتفك</p>
    </template>
    <div v-else class="box muted">…</div>
  </div>
</template>

<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { supabase } from 'boot/supabase'

const KEY = 'flexy.newpc.token'
const state = ref('')
const number = ref('')
const page = ref({})
const busy = ref(false)
const error = ref('')
const saved = ref('')
const copied = ref(null)
const draft = ref('')
let timer = null

function token () {
  let t = null
  try { t = localStorage.getItem(KEY) } catch { /* private window */ }
  if (!t || !/^[0-9a-f]{64}$/.test(t)) {
    const b = new Uint8Array(32)
    crypto.getRandomValues(b)
    t = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
    try { localStorage.setItem(KEY, t) } catch { /* kept for this visit only */ }
  }
  return t
}
async function call (path, body) {
  const { data, error: e } = await supabase.functions.invoke('flexy-api/v1/newpc/' + path, { method: 'POST', body: { token: token(), ...body } })
  if (!e) return data
  let b = null
  try { b = await e.context?.json() } catch { b = null }
  throw new Error(b?.error || e.message || 'NETWORK')
}
async function load () {
  try {
    const r = await call('state')
    state.value = r.state
    number.value = r.number || ''
    if (r.state === 'trusted') page.value = r
    error.value = ''
  } catch (e) {
    error.value = 'تعذّر الاتصال بالخادم: ' + e.message
  }
}
async function ask () {
  busy.value = true
  try {
    const label = (navigator.userAgentData?.platform || navigator.platform || 'كمبيوتر') + ' · ' + new Date().toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers', dateStyle: 'short', timeStyle: 'short' })
    const r = await call('open', { label })
    state.value = r.state
    number.value = r.number || ''
  } catch (e) {
    error.value = e.message === 'TOO_MANY_WAITING' ? 'طلبات كثيرة تنتظر: وافق أو انتظر 15 دقيقة.' : 'لم يُرسل الطلب: ' + e.message
  } finally {
    busy.value = false
  }
}
async function installer () {
  busy.value = true
  try {
    const r = await call('installer')
    const d = new Date()
    const p2 = (x) => String(x).padStart(2, '0')
    const name = `Flexy-install-station-quick-${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}_${p2(d.getHours())}-${p2(d.getMinutes())}.bat`
    const url = URL.createObjectURL(new Blob([r.content], { type: 'application/octet-stream' }))
    const a = document.createElement('a')
    a.href = url
    a.download = name
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 10000)
    saved.value = name
  } catch (e) {
    error.value = 'لم يُنزّل: ' + e.message
  } finally {
    busy.value = false
  }
}
async function say () {
  busy.value = true
  try {
    await call('say', { text: draft.value })
    draft.value = ''
    await load()
  } catch (e) {
    error.value = 'لم تُرسل: ' + e.message
  } finally {
    busy.value = false
  }
}
async function copy (text, n) {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    const t = document.createElement('textarea')
    t.value = text
    document.body.appendChild(t)
    t.select()
    document.execCommand('copy')
    t.remove()
  }
  copied.value = n
  setTimeout(() => { if (copied.value === n) copied.value = null }, 1500)
}
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers', dateStyle: 'short', timeStyle: 'medium' }) : '')
onMounted(() => {
  load()
  timer = setInterval(() => { if (document.visibilityState === 'visible') load() }, 4000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<style scoped>
.newpc { max-width: 760px; margin: 0 auto; padding: 16px; font-family: system-ui, 'Segoe UI', Tahoma, sans-serif; background: #f6f7f9; min-height: 100vh; }
h1 { font-size: 22px; margin: 0 0 12px; }
h2 { font-size: 17px; margin: 0 0 8px; }
.box { background: #fff; border: 1px solid #e4e6ec; border-radius: 12px; padding: 14px; margin-bottom: 12px; }
.big { font: inherit; font-size: 17px; padding: 12px 18px; border: 0; border-radius: 10px; background: #c2410c; color: #fff; cursor: pointer; }
.big[disabled] { opacity: .5; }
.number { font-size: 56px; font-weight: 800; letter-spacing: 12px; text-align: center; color: #c2410c; margin: 8px 0; direction: ltr; }
.muted { color: #6b7280; font-size: 13px; }
.ok { color: #15803d; font-weight: 700; }
.bad { color: #b91c1c; font-weight: 700; }
.ltr { direction: ltr; unicode-bidi: embed; }
.install { padding: 8px 0; border-top: 1px solid #eef0f4; }
.small { font-size: 13px; }
.cmd { padding: 8px 0; border-top: 1px solid #eef0f4; }
.cmd .label { font-weight: 700; margin-bottom: 4px; }
.cmd .row { display: flex; gap: 8px; align-items: center; }
.cmd code { flex: 1; background: #0f172a; color: #e2e8f0; padding: 8px; border-radius: 8px; font-size: 13px; overflow-x: auto; white-space: nowrap; text-align: left; }
.cmd button { font: inherit; padding: 8px 12px; border: 1px solid #c2410c; color: #c2410c; background: #fff; border-radius: 8px; cursor: pointer; }
.link { display: block; padding: 10px; border-top: 1px solid #eef0f4; color: #1565c0; text-decoration: none; font-weight: 700; }
.link span { display: block; color: #6b7280; font-weight: 400; font-size: 12px; text-align: left; }
.center { text-align: center; }
.chat textarea { width: 100%; box-sizing: border-box; font: inherit; font-size: 14px; padding: 8px; border: 1px solid #d1d5db; border-radius: 8px; margin: 8px 0; text-align: left; }
.msgs { max-height: 320px; overflow-y: auto; }
.msg { padding: 8px; border-radius: 10px; margin: 6px 0; }
.msg.pc { background: #fff7ed; }
.msg.owner { background: #ecfdf5; }
.msg pre { white-space: pre-wrap; word-break: break-all; margin: 4px 0; font-size: 14px; text-align: left; }
.msg button { font: inherit; padding: 6px 12px; border: 1px solid #15803d; color: #15803d; background: #fff; border-radius: 8px; cursor: pointer; }
</style>
