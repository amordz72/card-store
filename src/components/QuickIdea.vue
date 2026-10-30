<template>
  <!-- 💡 (owner 2026-10-30: «زر عائم: أجمع أفكاري بسرعة بدل مقاطعتك كل مرة»): on every owner page, an idea in two
       taps, saved in «أفكار وأوامر» (Flexy Core 0089/0090). «أرفق هذه الشاشة» keeps the page as a text file with it,
       with each card's technical data, so Claude reads it at «اقرأ الأفكار» without asking. -->
  <q-page-sticky position="bottom-right" :offset="[16, 96]">
    <q-btn fab-mini color="amber-8" text-color="dark" icon="lightbulb" aria-label="فكرة سريعة" @click="open = true" />
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
        <q-toggle v-model="withScreen" dense :label="`أرفق هذه الشاشة (${pageTitle})`" />
        <div v-if="error" class="small text-negative">{{ error }}</div>
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
import { Notify } from 'quasar'
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

async function save () {
  busy.value = true
  error.value = ''
  try {
    const file = withScreen.value ? { name: 'شاشة ' + (props.pageTitle || '') + '.txt', text: props.screenText().slice(0, 900000) } : null
    const r = await flexy.addIdea(text.value.trim(), kind.value, file)
    if (r.status !== 200 || r.body?.ok === false) {
      throw new Error(r.body?.error === 'IDEAS_NOT_READY' ? 'طبّق 0089 و0090 أولًا' : (r.body?.error || 'FLEXY_CORE'))
    }
    text.value = ''
    open.value = false
    Notify.create({ type: 'positive', message: '💡 حُفظت في «أفكار وأوامر»', position: 'top', timeout: 1200 })
  } catch (e) {
    error.value = 'لم تُحفظ: ' + (e.message || '')
  } finally {
    busy.value = false
  }
}
</script>
