<template>
  <!-- «أفكار وأوامر» (owner 2026-10-30, Flexy Core 0089): the owner writes or dictates (the phone keyboard's mic) any
       time; Claude reads them at the start of a session and answers (proposed / building / done / review / impossible).
       Nothing is built before his «نفّذ» on a proposal. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
    <q-btn-toggle v-model="tab" spread unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
      :options="[{ label: 'أفكاري', value: 'mine' }, { label: `ينتظرك${handover ? ' (' + handover.needs.length + ')' : ''}`, value: 'handover' }]" />

    <!-- «ينتظرك» (owner 2026-10-30): what Claude recorded in developer, from the code (Flexy Core src/data/handover.ts) -->
    <template v-if="tab === 'handover'">
      <div v-if="handover" class="small muted">آخر نقطة توقف: {{ when(handover.at) }} · {{ handover.title }}</div>
      <div v-for="sec in SECTIONS" :key="sec.key" class="card column gap-xs">
        <div class="text-weight-bold">{{ sec.label }} ({{ (handover?.[sec.key] || []).length }})</div>
        <component :is="item.to ? 'router-link' : 'div'" v-for="(item, n) in handover?.[sec.key] || []" :key="n" :to="item.to" class="h-item">
          <span class="col">{{ item.text }}</span>
          <q-icon v-if="item.to" name="chevron_left" color="primary" />
          <span v-if="item.doc" class="small muted ltr">{{ item.doc.split('/').pop() }}</span>
        </component>
      </div>
      <q-expansion-item v-if="history.length" dense icon="history" label="نقاط توقف سابقة" class="card q-pa-none">
        <div v-for="h in history" :key="h.at" class="q-pa-sm">
          <div class="text-weight-bold small">{{ when(h.at) }} · {{ h.title }}</div>
          <div v-for="sec in SECTIONS" :key="sec.key" class="small">
            <template v-if="(h[sec.key] || []).length">{{ sec.label }}: {{ h[sec.key].map((x) => x.text).join(' · ') }}</template>
          </div>
        </div>
      </q-expansion-item>
    </template>

    <template v-else>
    <div class="card column q-gutter-sm">
      <div class="row q-gutter-xs">
        <q-btn v-for="k in KINDS" :key="k.id" rounded dense no-caps :unelevated="kind === k.id" :outline="kind !== k.id"
          :color="kind === k.id ? 'primary' : 'grey-8'" :icon="k.icon" :label="k.label" @click="kind = k.id" />
      </div>
      <q-input v-model="text" type="textarea" outlined autogrow :placeholder="'اكتب أو أملِ بالصوت (زر الميكروفون في لوحة المفاتيح)…'" />
      <!-- A text file with it (Flexy Core 0090): a copied screen, a log, a CSV, a script; up to 1 MB. Pictures stay in the chat. -->
      <q-file v-model="picked" dense outlined clearable accept=".txt,.csv,.sql,.log,.json,.md,text/*" label="أرفق ملفًا نصيًا (اختياري)"
        :max-file-size="1000000" @rejected="error = 'الملف أكبر من 1 ميغابايت أو ليس نصيًا'">
        <template #prepend><q-icon name="attach_file" /></template>
      </q-file>
      <q-btn unelevated no-caps color="primary" icon="send" label="أرسل" class="self-start" :loading="busy === 'add'" :disable="!text.trim()" @click="add" />
    </div>

    <div v-if="error" class="small text-negative">{{ error }}</div>

    <div class="row q-gutter-xs">
      <q-btn v-for="f in FILTERS" :key="f.id" rounded dense no-caps :unelevated="filter === f.id" :outline="filter !== f.id"
        :color="filter === f.id ? 'primary' : 'grey-8'" :label="`${f.label} (${countOf(f.id)})`" @click="filter = f.id" />
    </div>

    <div v-for="i in shown" :key="i.id" class="card column q-gutter-xs">
      <div class="row items-center no-wrap q-gutter-sm">
        <q-icon :name="KINDS.find((k) => k.id === i.kind)?.icon || 'lightbulb'" color="grey-7" />
        <span class="small muted col">#{{ i.id }} · {{ when(i.at) }}</span>
        <q-badge :color="STATUS[statusOf(i)].color" :label="STATUS[statusOf(i)].label" />
      </div>
      <!-- Claude's one-line summary first; the owner's full text folded under it -->
      <template v-if="i.reply?.summary">
        <div class="text-weight-bold">{{ i.reply.summary }}</div>
        <q-expansion-item dense dense-toggle switch-toggle-side label="النص الكامل" header-class="small text-grey-8 q-px-none">
          <div class="idea-text">{{ i.text }}</div>
        </q-expansion-item>
      </template>
      <div v-else class="idea-text">{{ i.text }}</div>
      <div v-if="i.file_name" class="small muted"><q-icon name="attach_file" /> {{ i.file_name }} · {{ Math.ceil((i.file_size || 0) / 1024) }} KB</div>
      <div v-if="i.edited_at" class="small muted">عُدّلت {{ when(i.edited_at) }}</div>
      <div v-if="i.reply" class="reply">
        <div class="small text-weight-bold">رد Claude</div>
        <div class="idea-text">{{ i.reply.reply }}</div>
        <a v-if="i.reply.link" :href="i.reply.link" target="_blank" rel="noopener noreferrer" class="small">الرابط ↗</a>
      </div>
      <div class="row q-gutter-sm">
        <q-btn v-if="statusOf(i) === 'proposed'" unelevated dense no-caps color="positive" icon="check" label="نفّذ"
          :loading="busy === 'a' + i.id" @click="mark(i, 'approve')" />
        <q-btn v-if="!['building', 'done', 'impossible'].includes(statusOf(i))" flat dense no-caps color="primary" icon="edit" label="عدّل"
          :loading="busy === 'e' + i.id" @click="editOne(i)" />
        <q-btn flat dense no-caps color="grey-7" icon="visibility_off" label="أخفِ" :loading="busy === 'h' + i.id" @click="mark(i, 'hide')" />
      </div>
    </div>
    <div v-if="!busy && !shown.length && !error" class="muted text-center q-pa-md">لا شيء هنا</div>
    </template>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { Dialog } from 'quasar'
import { useRoute } from 'vue-router'
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import * as flexy from 'src/api/flexy'

const KINDS = [
  { id: 'idea', label: 'فكرة', icon: 'lightbulb' },
  { id: 'order', label: 'أمر', icon: 'task_alt' },
  { id: 'problem', label: 'مشكلة', icon: 'report_problem' },
  { id: 'brainstorm', label: 'عصف ذهني', icon: 'psychology' }
]
const STATUS = {
  new: { label: '🆕 جديدة', color: 'grey-7' },
  proposed: { label: '💬 اقتراحي جاهز', color: 'indigo-7' },
  approved: { label: '👍 موافَق، ينتظر التنفيذ', color: 'teal-7' },
  building: { label: '🔨 قيد التنفيذ', color: 'orange-8' },
  done: { label: '✅ تم التنفيذ', color: 'positive' },
  review: { label: '🔍 مراجعة', color: 'deep-orange' },
  impossible: { label: '⛔ غير ممكن', color: 'negative' }
}
const FILTERS = [
  { id: 'open', label: 'مفتوحة' }, { id: 'proposed', label: 'تنتظرك' }, { id: 'done', label: 'تمت' }, { id: 'all', label: 'الكل' }
]
const statusOf = (i) => {
  const s = i.reply?.status || 'new'
  return s === 'proposed' && i.approved_at ? 'approved' : s
}
const inFilter = (i, f) => f === 'all' ||
  (f === 'open' && !['done', 'impossible'].includes(statusOf(i))) ||
  (f === 'proposed' && ['proposed', 'review'].includes(statusOf(i))) ||
  (f === 'done' && ['done', 'impossible'].includes(statusOf(i)))

const SECTIONS = [
  { key: 'needs', label: '🔴 تحتاج يدك' },
  { key: 'decide', label: '💬 ينتظر قرارك' },
  { key: 'done', label: '✅ تم مؤخرًا' }
]
// The blue bar opens «ينتظرك» directly (/ideas?tab=handover)
const tab = ref(useRoute().query.tab === 'handover' ? 'handover' : 'mine')
const handover = ref(null)
const history = ref([])
const ideas = ref([])
const kind = ref('idea')
const text = ref('')
const filter = ref('open')
const busy = ref('')
const error = ref('')
const shown = computed(() => ideas.value.filter((i) => inFilter(i, filter.value)))
const countOf = (f) => ideas.value.filter((i) => inFilter(i, f)).length

async function call (key, fn) {
  busy.value = key
  error.value = ''
  try {
    const res = await fn()
    // «ينتظرك» comes with every answer, even before 0089
    if (res.body?.handover) { handover.value = res.body.handover; history.value = res.body.history || [] }
    if (res.status !== 200 || !res.body?.ok) {
      const e = res.body?.error
      throw new Error(e === 'IDEAS_NOT_READY' ? 'طبّق 0089 و0090 أولًا من «الإحصائيات و SQL»'
        : e === 'IDEA_ALREADY_STARTED' ? 'بدأ تنفيذها: اكتب فكرة جديدة بدل التعديل'
          : e === 'IDEA_FILE_TOO_BIG' ? 'الملف أكبر من 1 ميغابايت' : (e || 'FLEXY_CORE'))
    }
    ideas.value = res.body.ideas || []
    return true
  } catch (e) {
    error.value = e.message || 'FLEXY_CORE'
    return false
  } finally {
    busy.value = ''
  }
}
const picked = ref(null)
async function add () {
  let file = null
  if (picked.value) {
    try {
      file = { name: picked.value.name, text: await picked.value.text() }
    } catch {
      error.value = 'تعذّرت قراءة الملف'
      return
    }
  }
  if (await call('add', () => flexy.addIdea(text.value.trim(), kind.value, file))) { text.value = ''; picked.value = null }
}
// His own edit, before Claude starts on it (after, a new idea)
function editOne (i) {
  Dialog.create({ title: 'عدّل #' + i.id, prompt: { model: i.text, type: 'textarea', isValid: (v) => !!String(v).trim() }, cancel: 'إلغاء', ok: 'احفظ' })
    .onOk((v) => call('e' + i.id, () => flexy.editIdea(i.id, String(v).trim())))
}
const mark = (i, action) => call((action === 'approve' ? 'a' : 'h') + i.id, () => flexy.markIdea(i.id, action))
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '')
onMounted(() => call('load', () => flexy.ownerIdeas()))
</script>

<style scoped>
.idea-text { white-space: pre-wrap; word-break: break-word; }
.h-item { display: flex; align-items: center; gap: 8px; padding: 8px 2px; border-top: 1px solid rgba(0, 0, 0, 0.06); color: inherit; text-decoration: none; }
.gap-xs { gap: 4px; }
.ltr { direction: ltr; }
.reply { background: rgba(40, 53, 147, 0.06); border-radius: 8px; padding: 8px 10px; }
</style>
