<template>
  <!-- 💡 (owner 2026-10-30: «زر عائم: أجمع أفكاري بسرعة بدل مقاطعتك كل مرة»): on every owner page, an idea in two
       taps, saved in «أفكار وأوامر» (Flexy Core 0089/0090). «أرفق هذه الشاشة» keeps the page as a text file with it,
       with each card's technical data, so Claude reads it at «اقرأ الأفكار» without asking. -->
  <q-page-sticky position="bottom-right" :offset="[16, 96]">
    <q-btn fab-mini color="amber-8" text-color="dark" icon="lightbulb" aria-label="فكرة سريعة" @click="open = true">
      <q-badge v-if="notes.length" floating color="negative" :label="notes.length" />
    </q-btn>
  </q-page-sticky>
  <q-dialog v-model="open" position="bottom">
    <q-card style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
      <q-card-section class="column q-gutter-sm">
        <div class="text-weight-bold">💡 فكرة سريعة</div>
        <div class="row q-gutter-xs">
          <q-btn v-for="k in KINDS" :key="k.id" rounded dense no-caps size="sm" :unelevated="kind === k.id" :outline="kind !== k.id"
            :color="kind === k.id ? 'primary' : 'grey-8'" :label="k.label" @click="kind = k.id" />
        </div>
        <q-input v-model="text" type="textarea" outlined autogrow autofocus placeholder="اكتب أو أملِ بالصوت…" />
        <q-toggle v-model="withScreen" dense :label="`أرفق نسخة من الصفحة التي أنت فيها الآن: ${pageTitle}`" />
        <div v-if="error" class="small text-negative">{{ error }}</div>
        <!-- Notes taken while Claude works (owner 2026-10-30: «أسجّل أثناء عملك، ثم أنسخها كلها مرة واحدة») -->
        <div v-if="notes.length" class="notes column q-gutter-xs">
          <div class="row items-center">
            <div class="col text-weight-bold small">ملاحظاتي السريعة ({{ notes.length }})</div>
            <q-btn unelevated dense no-caps size="sm" color="primary" icon="content_copy" label="انسخها كلها" @click="copyAll" />
            <q-btn flat dense no-caps size="sm" color="grey-7" label="امسحها" @click="clearNotes" />
          </div>
          <div v-for="(n, i) in notes" :key="i" class="small note">{{ i + 1 }}. {{ n.text }} <span class="muted">· {{ n.page }}</span></div>
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
import { ref } from 'vue'
import { copyToClipboard, Dialog, LocalStorage, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'

const props = defineProps({
  // The page as «نسخ الشاشة» gives it (AppLayout), and its title
  screenText: { type: Function, required: true },
  pageTitle: { type: String, default: '' }
})
const KINDS = [{ id: 'idea', label: 'فكرة' }, { id: 'order', label: 'أمر' }, { id: 'problem', label: 'مشكلة' }, { id: 'brainstorm', label: 'عصف ذهني' }]
const open = ref(false)
const text = ref('')
const kind = ref('idea')
const withScreen = ref(true)
const busy = ref(false)
const error = ref('')
// Kept on this phone too: a note is never lost (no network, or before 0090), and all can be copied at once
const NOTES_KEY = 'cs_quick_notes'
const readNotes = () => { try { return LocalStorage.getItem(NOTES_KEY) || [] } catch { return [] } }
const notes = ref(readNotes())
const keepNotes = () => { try { LocalStorage.set(NOTES_KEY, notes.value) } catch { /* private mode */ } }
async function copyAll () {
  const t = 'ملاحظاتي السريعة:\n' + notes.value.map((n, i) => `${i + 1}. ${n.text} (${n.page})`).join('\n')
  await copyToClipboard(t)
  Notify.create({ type: 'positive', message: 'نُسخت كلها: الصقها في المحادثة', position: 'top', timeout: 1500 })
}
function clearNotes () {
  Dialog.create({ title: 'امسح الملاحظات السريعة؟', message: 'تبقى المحفوظة منها في «أفكار وأوامر».', cancel: 'لا', ok: 'امسح' })
    .onOk(() => { notes.value = []; keepNotes() })
}

async function save () {
  busy.value = true
  error.value = ''
  // On this phone first: whatever happens next, the note stays
  notes.value.push({ text: text.value.trim(), page: props.pageTitle, at: new Date().toISOString() })
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
.notes { border-top: 1px solid rgba(0, 0, 0, 0.08); padding-top: 6px; max-height: 220px; overflow-y: auto; }
.note { overflow-wrap: anywhere; }
</style>
