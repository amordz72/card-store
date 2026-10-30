<template>
  <!-- 💡 (owner 2026-10-30: «زر عائم: أجمع أفكاري بسرعة بدل مقاطعتك كل مرة»): on every owner page, an idea in two
       taps, saved in «أفكار وأوامر» (Flexy Core 0089/0090). «أرفق هذه الشاشة» keeps the page as a text file with it,
       with each card's technical data, so Claude reads it at «اقرأ الأفكار» without asking. -->
  <!-- Moved with a finger, kept where it was put, on this device (owner 2026-10-30: «زر أنقله ويُحفظ مكانه»);
       a tap opens it, a drag moves it -->
  <div class="qi-fab" :style="{ left: pos.x + 'px', top: pos.y + 'px' }" @pointerdown="dragStart">
    <q-btn :fab-mini="!pos.big" :fab="pos.big" color="amber-8" text-color="dark" icon="lightbulb" aria-label="فكرة سريعة" @click="tapOpen">
      <!-- Red: not sent to Claude yet; green: done by Claude, waiting for your ✓ (owner N6: «يظهر 4 رغم أنه تمت») -->
      <q-badge v-if="toSend.length" floating color="negative" :label="toSend.length" />
      <q-badge v-else-if="doneCount" floating color="positive" :label="'✓' + doneCount" />
    </q-btn>
  </div>
  <!-- At the top (owner ideas #3, #4): the phone keyboard opens under it, never over it -->
  <q-dialog v-model="open" position="top">
    <q-card style="width:100%;max-width:560px;border-radius:0 0 20px 20px">
      <q-card-section class="column q-gutter-sm">
        <div class="text-weight-bold">💡 فكرة سريعة</div>
        <div class="row q-gutter-xs">
          <q-btn v-for="k in KINDS" :key="k.id" rounded dense no-caps size="sm" :unelevated="kind === k.id" :outline="kind !== k.id"
            :color="kind === k.id ? 'primary' : 'grey-8'" :label="k.label" @click="kind = k.id" />
        </div>
        <q-input v-model="text" type="textarea" outlined autogrow autofocus placeholder="اكتب أو أملِ بالصوت…" />
        <div class="row items-center q-gutter-xs small muted">
          <span>الزر:</span>
          <q-btn flat dense no-caps size="sm" :label="pos.big ? 'صغّره' : 'كبّره'" @click="pos.big = !pos.big; keepPos()" />
          <q-btn flat dense no-caps size="sm" label="أعِده لمكانه" @click="resetPos" />
          <span>(اسحبه بإصبعك لتنقله)</span>
        </div>
        <q-toggle v-model="withScreen" dense :label="`أرفق نسخة من الصفحة التي أنت فيها الآن: ${pageTitle}`" />
        <div v-if="error" class="small text-negative">{{ error }}</div>

        <!-- Notes between the owner and Claude (owner 2026-10-30): each has a number; «انسخ ما لم يصل» copies only
             what Claude has not answered; Claude ends his reply with «FLEXY N1=تمت N2=وصلت»; «الصق رد Claude» reads
             that line and moves them; the owner closes ✓ or reopens ↺. Kept on this phone. -->
        <div v-if="notes.length" class="notes column q-gutter-xs">
          <div class="row items-center q-gutter-xs">
            <q-btn unelevated dense no-caps size="sm" color="primary" icon="content_copy" :label="`انسخ ما لم يصل (${toSend.length})`"
              :disable="!toSend.length" @click="copyToSend" />
            <q-btn outline dense no-caps size="sm" color="primary" icon="content_paste" label="الصق رد Claude" @click="pasteReply" />
          </div>
          <div v-if="pasteBox" class="column q-gutter-xs">
            <q-input v-model="pasted" type="textarea" outlined dense autogrow autofocus placeholder="الصق هنا رد Claude (أو سطر FLEXY وحده)" input-class="ltr" />
            <q-btn unelevated dense no-caps size="sm" color="primary" label="اقرأه" class="self-start" :disable="!pasted.trim()" @click="applyReply(pasted)" />
          </div>
          <div v-for="g in groups" :key="g.key" class="column q-gutter-xs">
            <div class="small text-weight-bold" :class="g.cls">{{ g.label }} ({{ g.list.length }})</div>
            <div v-for="n in g.list" :key="n.id" class="row items-center no-wrap small note">
              <div class="col"><b>N{{ n.id }}</b><span v-if="n.state === 'reopen'" class="text-deep-orange"> (أُعيدت)</span> {{ n.text }}
                <span class="muted">· {{ n.page }}<span v-if="n.state === 'new' && n.copiedAt"> · نُسخت ولم يصل رد</span></span></div>
              <template v-if="n.state === 'done'">
                <q-btn flat round dense size="sm" color="positive" icon="check" aria-label="أغلقها" @click="setState(n, 'closed')" />
                <q-btn flat round dense size="sm" color="deep-orange" icon="undo" aria-label="أعد فتحها" @click="setState(n, 'reopen')" />
              </template>
            </div>
          </div>
          <q-expansion-item v-if="closed.length" dense dense-toggle switch-toggle-side :label="`المغلقة (${closed.length})`" header-class="small text-grey-8 q-px-none">
            <div v-for="n in closed" :key="n.id" class="row items-center no-wrap small note muted">
              <div class="col"><b>N{{ n.id }}</b> {{ n.text }}</div>
              <q-btn flat round dense size="sm" icon="undo" aria-label="أعد فتحها" @click="setState(n, 'reopen')" />
            </div>
            <q-btn flat dense no-caps size="sm" color="grey-7" label="امسح المغلقة" @click="clearClosed" />
          </q-expansion-item>
        </div>
      </q-card-section>
      <q-card-actions align="right">
        <q-btn flat no-caps label="إلغاء" v-close-popup />
        <q-btn unelevated no-caps color="primary" icon="send" label="احفظ" :loading="busy" :disable="!text.trim()" @click="save" />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { computed, ref } from 'vue'
import { copyToClipboard, Dialog, LocalStorage, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'

const props = defineProps({
  // The page as «نسخ الشاشة» gives it (AppLayout), and its title
  screenText: { type: Function, required: true },
  pageTitle: { type: String, default: '' }
})
// Where the button is: {x, y, big}, from the top-left, kept per device; at the top by default
const POS_KEY = 'cs_quick_pos'
const defaultPos = () => ({ x: 12, y: 120, big: false })
function readPos () {
  try { return { ...defaultPos(), ...(JSON.parse(localStorage.getItem(POS_KEY) || 'null') || {}) } } catch { return defaultPos() }
}
const pos = ref(readPos())
const keepPos = () => { try { localStorage.setItem(POS_KEY, JSON.stringify(pos.value)) } catch { /* private mode */ } }
const clamp = () => {
  const size = pos.value.big ? 56 : 40
  pos.value.x = Math.min(Math.max(pos.value.x, 0), window.innerWidth - size)
  pos.value.y = Math.min(Math.max(pos.value.y, 0), window.innerHeight - size)
}
clamp()
function resetPos () { pos.value = defaultPos(); keepPos() }
let drag = null
let moved = false
function dragStart (e) {
  drag = { sx: e.clientX, sy: e.clientY, x: pos.value.x, y: pos.value.y }
  moved = false
  window.addEventListener('pointermove', dragMove)
  window.addEventListener('pointerup', dragEnd, { once: true })
}
function dragMove (e) {
  if (!drag) return
  const dx = e.clientX - drag.sx
  const dy = e.clientY - drag.sy
  if (!moved && Math.abs(dx) + Math.abs(dy) < 8) return
  moved = true
  pos.value.x = drag.x + dx
  pos.value.y = drag.y + dy
  clamp()
}
function dragEnd () {
  window.removeEventListener('pointermove', dragMove)
  drag = null
  if (moved) keepPos()
}
// A drag that ends on the button is not a tap
function tapOpen () { if (!moved) open.value = true; moved = false }
const KINDS = [{ id: 'idea', label: 'فكرة' }, { id: 'order', label: 'أمر' }, { id: 'problem', label: 'مشكلة' }, { id: 'brainstorm', label: 'عصف ذهني' }]
const open = ref(false)
const text = ref('')
const kind = ref('idea')
const withScreen = ref(true)
const busy = ref(false)
const error = ref('')

// States: new (Claude has not answered it) → got («وصلت») → done («تمت» مبدئيًا) → closed by the owner, or reopen
const NOTES_KEY = 'cs_quick_notes'
function readNotes () {
  let list = []
  try { list = LocalStorage.getItem(NOTES_KEY) || [] } catch { /* private mode */ }
  // Notes kept before the numbers: numbered now, in their order
  let seq = list.reduce((m, n) => Math.max(m, n.id || 0), 0)
  return list.map((n) => (n.id ? n : { ...n, id: ++seq, state: 'new' }))
}
const notes = ref(readNotes())
const keepNotes = () => { try { LocalStorage.set(NOTES_KEY, notes.value) } catch { /* private mode */ } }
const nextId = () => notes.value.reduce((m, n) => Math.max(m, n.id), 0) + 1

const toSend = computed(() => notes.value.filter((n) => n.state === 'new' || n.state === 'reopen'))
const closed = computed(() => notes.value.filter((n) => n.state === 'closed'))
const groups = computed(() => [
  { key: 'done', label: 'تمت مبدئيًا: أغلقها ✓ أو أعد فتحها ↺', cls: 'text-positive', list: notes.value.filter((n) => n.state === 'done') },
  { key: 'send', label: 'لم تصل Claude', cls: 'text-deep-orange', list: toSend.value },
  { key: 'got', label: 'وصلت Claude: يعمل عليها', cls: 'text-primary', list: notes.value.filter((n) => n.state === 'got') }
].filter((g) => g.list.length))
const doneCount = computed(() => notes.value.filter((n) => n.state === 'done').length)

function setState (n, state) {
  n.state = state
  keepNotes()
}
async function copyToSend () {
  const t = 'ملاحظاتي السريعة (Flexy). ضع في آخر ردك سطرًا: FLEXY N1=تمت N2=وصلت\n' +
    toSend.value.map((n) => `N${n.id}${n.state === 'reopen' ? ' (أُعيدت)' : ''}. ${n.text} (${n.page})`).join('\n')
  try {
    await copyToClipboard(t)
    // Copied is not received: they stay «لم تصل» until Claude's FLEXY line says so
    const at = new Date().toISOString()
    toSend.value.forEach((n) => { n.copiedAt = at })
    keepNotes()
    Notify.create({ type: 'positive', message: 'نُسخت: الصقها في المحادثة', position: 'top', timeout: 1500 })
  } catch {
    Notify.create({ type: 'negative', message: 'تعذّر النسخ', position: 'top' })
  }
}

// «الصق رد Claude»: the clipboard read directly (the browser asks once); refused → a box to paste in
const pasteBox = ref(false)
const pasted = ref('')
async function pasteReply () {
  try {
    const t = await navigator.clipboard.readText()
    if (applyReply(t)) return
  } catch { /* not allowed here */ }
  pasteBox.value = true
}
const STATES = { تمت: 'done', وصلت: 'got', مفتوحة: 'got' }
function applyReply (t) {
  const lines = String(t || '').split('\n').filter((l) => /FLEXY/i.test(l))
  let changed = 0
  for (const l of lines) {
    for (const m of l.matchAll(/N\s*(\d+)\s*=\s*(تمت|وصلت|مفتوحة)/gi)) {
      const n = notes.value.find((x) => x.id === Number(m[1]))
      // A closed note stays closed; «وصلت» never takes back a «تمت»
      if (!n || n.state === 'closed' || (n.state === 'done' && STATES[m[2]] === 'got')) continue
      if (n.state !== STATES[m[2]]) { n.state = STATES[m[2]]; changed++ }
    }
  }
  if (!lines.length) {
    Notify.create({ type: 'warning', message: 'لا يوجد سطر FLEXY في المنسوخ', position: 'top' })
    return false
  }
  keepNotes()
  pasteBox.value = false
  pasted.value = ''
  Notify.create({ type: 'positive', message: changed ? `تحدّثت ${changed} ملاحظة` : 'لا جديد في الرد', position: 'top', timeout: 1500 })
  return true
}
function clearClosed () {
  Dialog.create({ title: 'امسح المغلقة؟', message: 'تبقى المحفوظة منها في «أفكار وأوامر».', cancel: 'لا', ok: 'امسح' })
    .onOk(() => { notes.value = notes.value.filter((n) => n.state !== 'closed'); keepNotes() })
}

async function save () {
  busy.value = true
  error.value = ''
  // On this phone first: whatever happens next, the note stays
  notes.value.push({ id: nextId(), state: 'new', text: text.value.trim(), page: props.pageTitle, at: new Date().toISOString() })
  keepNotes()
  try {
    const file = withScreen.value ? { name: 'شاشة ' + (props.pageTitle || '') + '.txt', text: props.screenText().slice(0, 900000) } : null
    const r = await flexy.addIdea(text.value.trim(), kind.value, file)
    if (r.status !== 200 || r.body?.ok === false) {
      throw new Error(r.body?.error === 'IDEAS_NOT_READY' ? 'طبّق 0089 و0090 أولًا' : (r.body?.error || 'FLEXY_CORE'))
    }
    text.value = ''
    Notify.create({ type: 'positive', message: '💡 حُفظت (هنا وفي «أفكار وأوامر»)', position: 'top', timeout: 1200 })
  } catch (e) {
    text.value = ''
    error.value = 'حُفظت على هاتفك فقط (' + (e.message || '') + ')'
  } finally {
    busy.value = false
  }
}
</script>

<style scoped>
.qi-fab { position: fixed; z-index: 2000; touch-action: none; }
.notes { border-top: 1px solid rgba(0, 0, 0, 0.08); padding-top: 6px; max-height: 300px; overflow-y: auto; }
.note { overflow-wrap: anywhere; }
</style>
