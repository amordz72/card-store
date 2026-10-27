<template>
  <!-- A new station computer, no key in any file (owner 2026-10-27; Flexy Core 0041).
       The computer shows a number: tap the same one here. Or type on it the code shown here.
       Or carry the quick installer (works once). The page approves the computer by itself after. -->
  <div class="card column q-gutter-sm">
    <div class="row items-center q-gutter-sm">
      <q-icon name="add_to_queue" color="primary" size="22px" />
      <div class="col text-weight-bold">إضافة كمبيوتر</div>
      <q-btn flat dense no-caps color="primary" :label="open ? 'إخفاء' : 'فتح'" @click="toggle" />
    </div>

    <!-- Requests waiting: always shown, even closed, so a number is never missed -->
    <div v-for="p in live" :key="p.pairing_id" class="req column q-gutter-xs">
      <div class="row items-center">
        <div class="col"><b class="ltr">{{ p.computer_name }}</b> <span class="small muted">· {{ STATE[p.state] || p.state }}</span></div>
      </div>
      <template v-if="p.state === 'waiting' && p.choices">
        <div class="small">اضغط الرقم الظاهر على شاشة هذا الكمبيوتر:</div>
        <div class="row q-gutter-sm">
          <q-btn v-for="n in p.choices" :key="n" unelevated no-caps color="primary" class="num" :label="String(n)"
            :loading="busy === p.pairing_id + ':' + n" :disable="!!busy" @click="choose(p, n)" />
        </div>
        <div v-if="p.wrong" class="small text-deep-orange">أخطاء: {{ p.wrong }} من {{ settings.max_wrong }}</div>
      </template>
      <template v-else-if="p.state === 'blocked'">
        <div class="small text-negative">محظور بعد {{ p.wrong }} أخطاء حتى {{ clock(p.blocked_until) }}. اسمح له فقط إن كان هذا كمبيوترك الآن.</div>
        <q-btn outline dense no-caps color="negative" label="السماح له" :loading="busy === p.pairing_id" :disable="!!busy" @click="unblock(p)" />
      </template>
    </div>
    <div v-if="message" class="small" :class="messageBad ? 'text-negative' : 'text-positive'">{{ message }}</div>

    <template v-if="open">
      <!-- The GitHub key: pasted once; never shown again -->
      <div class="small">
        مفتاح GitHub (قراءة فقط):
        <b v-if="repoKey.saved" class="text-positive">محفوظ</b><span v-if="repoKey.saved" class="muted"> منذ {{ clock(repoKey.saved_at) }}</span>
        <b v-else class="text-negative">غير محفوظ</b>
      </div>
      <!-- Where the key is made (owner 2026-10-27: «ضع الروابط في الصفحة، لماذا نرجع دائمًا إلى المحادثة»).
           GitHub fills what it understands from the link and ignores the rest; the repository is chosen by hand. -->
      <div class="small column q-gutter-xs help">
        <div>
          <a :href="GITHUB_NEW_KEY" target="_blank" rel="noopener noreferrer">صنع مفتاح جديد على GitHub ↗</a>
          · <a :href="GITHUB_KEYS" target="_blank" rel="noopener noreferrer">مفاتيحي ↗</a>
        </div>
        <div class="muted">في الصفحة: Resource owner = <b class="ltr">amordz72</b> ← Only select repositories = <b class="ltr">station-connect</b> وحده
          ← Repository permissions ← Contents = <b class="ltr">Read-only</b> ← Generate token ← انسخ المفتاح والصقه هنا.
          إن ظهرت الصفحة ناقصة في الهاتف: «موقع سطح المكتب» من قائمة المتصفح.</div>
        <div class="muted">المفتاح يظهر مرة واحدة فقط. إن لم تنسخه، أو انتهى، أو ضاع: «مفاتيحي» ← اسم المفتاح ← <b class="ltr">Regenerate token</b> ← انسخه
          (ضغط مطوّل على النص إن غاب زر النسخ) والصقه هنا. وللمفتاح الضائع: <b class="ltr">Delete</b>.</div>
      </div>
      <div class="row items-center q-gutter-sm">
        <q-input v-model="keyText" dense outlined class="col" type="password" autocomplete="off"
          :label="repoKey.saved ? 'مفتاح جديد (يستبدل القديم في كل الكمبيوترات)' : 'الصق المفتاح github_pat_…'" />
        <q-btn unelevated no-caps color="primary" label="حفظ" :disable="!keyText.trim()" :loading="busy === 'key'" @click="saveKey" />
      </div>

      <template v-if="repoKey.saved">
        <div class="row q-gutter-sm">
          <q-btn outline no-caps color="primary" icon="download" label="ملف التثبيت" :loading="busy === 'bat'" @click="download(false)" />
          <q-btn outline no-caps color="deep-orange" icon="bolt" label="ملف سريع (مرة واحدة)" :loading="busy === 'quick'" @click="download(true)" />
        </div>
        <div class="small muted">
          ملف التثبيت واحد لكل الكمبيوترات ولا سرّ فيه: شغّله، ثم اضغط هنا الرقم الذي يظهر على شاشته.
          الملف السريع يدخل وحده بلا رقم، مرة واحدة خلال {{ settings.invite_minutes }} دقيقة؛ ملف أحدث يُميت السابق.
          <span v-if="inviteOpenUntil" class="text-deep-orange">ملف سريع مفتوح حتى {{ clock(inviteOpenUntil) }}.</span>
        </div>
        <div class="row items-center q-gutter-sm">
          <q-btn flat no-caps color="primary" icon="pin" label="رمز للكتابة على الكمبيوتر" :loading="busy === 'code'" @click="newCode" />
          <div v-if="code" class="code ltr">{{ code.code.slice(0, 3) }} {{ code.code.slice(3) }}</div>
          <div v-if="code" class="small muted">حتى {{ clock(code.expires_at) }}، مرة واحدة</div>
        </div>
      </template>

      <div v-for="p in done" :key="p.pairing_id" class="small muted">
        <span class="ltr">{{ p.computer_name }}</span> · {{ STATE[p.state] || p.state }} · {{ clock(p.created_at) }}
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import * as flexy from 'src/api/flexy'

const emit = defineEmits(['approved'])

// GitHub's fine-grained key page; the query fills the name, owner, a year and Contents: read when GitHub supports it
const GITHUB_NEW_KEY = 'https://github.com/settings/personal-access-tokens/new?name=stations&description=Read+station-connect+for+new+station+computers&target_name=amordz72&expires_in=365&contents=read'
const GITHUB_KEYS = 'https://github.com/settings/personal-access-tokens'

const STATE = {
  waiting: 'ينتظر موافقتك',
  blocked: 'محظور',
  confirmed: 'وافقت، يستلم المفتاح',
  installing: 'يثبّت البرنامج…',
  bound: 'ثُبّت، يُعتمد الآن',
  approved: '✅ معتمد',
  expired: 'انتهى الوقت'
}
const ERRORS = {
  REPO_KEY_INVALID: 'هذا ليس مفتاح GitHub (يبدأ بـ github_pat_).',
  REPO_KEY_REFUSED_BY_GITHUB: 'GitHub رفض المفتاح: يجب أن يقرأ station-connect (Contents: Read-only) وألا يكون منتهيًا.',
  GITHUB_UNREACHABLE: 'لم نصل إلى GitHub الآن، أعد المحاولة.',
  NO_REPO_KEY: 'احفظ مفتاح GitHub أولًا.',
  WRONG_NUMBER: 'رقم خاطئ: ظهر رقم جديد على الكمبيوتر.',
  BLOCKED: 'محظور بعد الأخطاء.',
  EXPIRED: 'انتهى وقت هذا الطلب: شغّل الملف من جديد.'
}

const open = ref(false)
const repoKey = ref({ saved: false })
const pairings = ref([])
const code = ref(null)
const inviteOpenUntil = ref(null)
const settings = ref({ max_wrong: 3, invite_minutes: 60 })
const keyText = ref('')
const busy = ref('')
const message = ref('')
const messageBad = ref(false)

const live = computed(() => pairings.value.filter((p) => p.state === 'waiting' || p.state === 'blocked'))
const done = computed(() => pairings.value.filter((p) => p.state !== 'waiting' && p.state !== 'blocked'))
const moving = computed(() => pairings.value.some((p) => ['waiting', 'confirmed', 'installing', 'bound'].includes(p.state)))

const clock = (t) => (t ? new Date(t).toLocaleTimeString('ar-DZ', { hour: '2-digit', minute: '2-digit' }) : '—')
function say (text, bad = false) { message.value = text; messageBad.value = bad }
const reason = (res) => ERRORS[res.body?.error] || res.body?.error || 'FLEXY_CORE'

let lastApproved = 0
async function load () {
  const res = await flexy.ownerPairing()
  if (res.status !== 200 || !res.body?.ok) return
  repoKey.value = res.body.repo_key || { saved: false }
  pairings.value = res.body.pairings || []
  code.value = res.body.code || null
  inviteOpenUntil.value = res.body.invite_open_until || null
  if (res.body.settings) settings.value = res.body.settings
  // A computer approved by this load: the devices list should show it
  const n = pairings.value.filter((p) => p.state === 'approved').length
  if (n > lastApproved) emit('approved')
  lastApproved = n
}

async function act (tag, body, ok) {
  busy.value = tag
  say('')
  try {
    const res = await flexy.ownerPairingAction(body)
    if (res.status === 200 && res.body?.ok) { if (ok) ok(res.body) } else say(reason(res), true)
  } finally {
    busy.value = ''
  }
  await load()
}

const toggle = () => { open.value = !open.value; if (open.value) load() }
const saveKey = () => act('key', { action: 'save_key', key: keyText.value.trim() }, () => { keyText.value = ''; say('حُفظ المفتاح مشفّرًا في السيرفر.') })
const choose = (p, n) => act(p.pairing_id + ':' + n, { action: 'choose', pairing_id: p.pairing_id, number: n },
  (b) => say(b.done ? `قُبل ${p.computer_name}: يثبّت الآن ثم يُعتمد وحده.` : 'صحيح: رقم آخر للتأكيد على الشاشة.'))
const unblock = (p) => act(p.pairing_id, { action: 'unblock', pairing_id: p.pairing_id }, () => say('رُفع الحظر: رقم جديد على الكمبيوتر.'))
const newCode = () => act('code', { action: 'new_code' }, (b) => { code.value = b.code })

function download (quick) {
  return act(quick ? 'quick' : 'bat', { action: 'installer', quick }, (b) => {
    const url = URL.createObjectURL(new Blob([b.content], { type: 'application/octet-stream' }))
    const a = document.createElement('a')
    a.href = url
    a.download = b.file_name
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 10000)
    say(quick ? `نُزّل الملف السريع: يعمل مرة واحدة حتى ${clock(b.expires_at)}.` : 'نُزّل ملف التثبيت.')
  })
}

// Every 3 seconds while a computer is on its way, every 30 otherwise; never in the background
let timer = null
let ticks = 0
function tick () {
  if (document.hidden) return
  ticks++
  if (moving.value || ticks % 10 === 0) load()
}
onMounted(() => { load(); timer = setInterval(tick, 3000) })
onBeforeUnmount(() => clearInterval(timer))
</script>

<style scoped>
.req { border: 1px solid #E4E6EC; border-radius: 10px; padding: 8px; }
.num { min-width: 56px; font-size: 20px; font-weight: 700; }
.code { font-size: 26px; font-weight: 700; letter-spacing: 3px; }
.ltr { direction: ltr; unicode-bidi: isolate; }
.help a { font-weight: 600; }
</style>
