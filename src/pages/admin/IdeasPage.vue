<template>
  <!-- «أفكار وأوامر» (owner 2026-10-30, Flexy Core 0089): the owner writes or dictates (the phone keyboard's mic) any
       time; Claude reads them at the start of a session and answers (proposed / building / done / review / impossible).
       Nothing is built before his «نفّذ» on a proposal. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />

    <div class="card column q-gutter-sm">
      <div class="row q-gutter-xs">
        <q-btn v-for="k in KINDS" :key="k.id" rounded dense no-caps :unelevated="kind === k.id" :outline="kind !== k.id"
          :color="kind === k.id ? 'primary' : 'grey-8'" :icon="k.icon" :label="k.label" @click="kind = k.id" />
      </div>
      <q-input v-model="text" type="textarea" outlined autogrow :placeholder="'اكتب أو أملِ بالصوت (زر الميكروفون في لوحة المفاتيح)…'" />
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
      <div class="idea-text">{{ i.text }}</div>
      <div v-if="i.reply" class="reply">
        <div class="small text-weight-bold">رد Claude</div>
        <div class="idea-text">{{ i.reply.reply }}</div>
        <a v-if="i.reply.link" :href="i.reply.link" target="_blank" rel="noopener noreferrer" class="small">الرابط ↗</a>
      </div>
      <div class="row q-gutter-sm">
        <q-btn v-if="statusOf(i) === 'proposed'" unelevated dense no-caps color="positive" icon="check" label="نفّذ"
          :loading="busy === 'a' + i.id" @click="mark(i, 'approve')" />
        <q-btn flat dense no-caps color="grey-7" icon="visibility_off" label="أخفِ" :loading="busy === 'h' + i.id" @click="mark(i, 'hide')" />
      </div>
    </div>
    <div v-if="!busy && !shown.length && !error" class="muted text-center q-pa-md">لا شيء هنا</div>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
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
    if (res.status !== 200 || !res.body?.ok) {
      throw new Error(res.body?.error === 'IDEAS_NOT_READY' ? 'طبّق 0089 أولًا من «الإحصائيات و SQL»' : (res.body?.error || 'FLEXY_CORE'))
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
async function add () {
  if (await call('add', () => flexy.addIdea(text.value.trim(), kind.value))) text.value = ''
}
const mark = (i, action) => call((action === 'approve' ? 'a' : 'h') + i.id, () => flexy.markIdea(i.id, action))
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '')
onMounted(() => call('load', () => flexy.ownerIdeas()))
</script>

<style scoped>
.idea-text { white-space: pre-wrap; word-break: break-word; }
.reply { background: rgba(40, 53, 147, 0.06); border-radius: 8px; padding: 8px 10px; }
</style>
