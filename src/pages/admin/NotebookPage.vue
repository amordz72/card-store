<template>
  <!-- «دفتر البرنامج» (owner 2026-10-30, Flexy Core 0106): what the program knows (codes it sends, codes known but not
       programmed, network texts it understands and what it does with each), what the owner found (saved, never sent or
       used by the program), and the plan of what is to be built. A search says: used / known / understood / unknown. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
    <q-btn-toggle v-model="tab" spread unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
      :options="[{ label: 'ما يعرفه', value: 'know' }, { label: `ما سجّلتُه (${mine.length})`, value: 'mine' }, { label: `الخطة (${plan.length})`, value: 'plan' }]" />
    <div v-if="error" class="small text-negative">{{ error }}</div>
    <div v-if="pending" class="small text-deep-orange">طبّق {{ pending }} من «ينتظر تطبيقك» لتحفظ ما تسجّله والخطة.</div>

    <!-- Search: a code or a text -->
    <div class="card column q-gutter-sm">
      <div class="row q-gutter-sm items-center no-wrap">
        <q-input v-model="query" dense outlined class="col" placeholder="الصق كودًا أو رسالة: هل يعرفه البرنامج؟" @keyup.enter="search" />
        <q-btn unelevated no-caps color="primary" icon="search" :loading="busy === 'search'" :disable="!query.trim()" @click="search" />
      </div>
      <template v-if="found">
        <div class="text-weight-bold" :class="FOUND[found.verdict.found].cls">{{ FOUND[found.verdict.found].icon }} {{ FOUND[found.verdict.found].label }}: {{ found.verdict.text }}</div>
        <div v-if="found.verdict.code" class="small muted">{{ found.verdict.code.money ? 'فيه مال' : 'بلا مال' }} · {{ found.verdict.code.when }}</div>
        <div v-for="m in found.mine" :key="m.id" class="small">📝 سجّلتَه: {{ m.text }}<template v-if="m.meaning"> — {{ m.meaning }}</template></div>
        <q-btn v-if="found.verdict.found === 'unknown' && !found.mine.length" flat dense no-caps color="primary" icon="add" label="سجّله في «ما سجّلتُه»"
          class="self-start" @click="startMine(query)" />
      </template>
    </div>

    <template v-if="tab === 'know'">
      <div class="card column gap-xs">
        <div class="text-weight-bold">الأكواد التي يرسلها البرنامج</div>
        <div v-for="(c, n) in used" :key="'u' + n" class="row-line">
          <div class="ltr code">{{ c.code }}</div>
          <div class="small">{{ c.operator }} · {{ c.what }} · <b :class="c.money ? 'text-deep-orange' : 'text-positive'">{{ c.money ? 'فيه مال' : 'بلا مال' }}</b></div>
          <div class="small muted">{{ c.when }}</div>
        </div>
      </div>
      <div class="card column gap-xs">
        <div class="text-weight-bold">ردود الشبكة التي يفهمها</div>
        <div v-for="(t, n) in texts" :key="'t' + n" class="row-line">
          <div class="small muted">{{ t.source === 'sms' ? 'رسالة' : 'USSD' }} · {{ t.operator }}</div>
          <div class="ltr small code">{{ t.example }}</div>
          <div class="small"><b>{{ t.meaning }}</b> ← {{ t.action }}</div>
        </div>
      </div>
      <div class="card column gap-xs">
        <div class="text-weight-bold">معروفة ولا يستعملها بعد</div>
        <div v-for="(c, n) in known" :key="'k' + n" class="row-line">
          <div class="ltr code">{{ c.code }}</div>
          <div class="small">{{ c.operator }} · {{ c.what }}</div>
        </div>
      </div>
    </template>

    <template v-else-if="tab === 'mine'">
      <div class="card column q-gutter-sm">
        <div class="help small muted">ما تجده من أكواد أو رسائل أو ملاحظات. يُحفظ ولا يرسله البرنامج ولا يعمل به؛ Claude يقرؤه كل جلسة ويقترح برمجته.</div>
        <q-btn-toggle v-model="draft.kind" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: 'كود', value: 'code' }, { label: 'رسالة', value: 'message' }, { label: 'ملاحظة', value: 'note' }]" />
        <q-select v-model="draft.operator" dense outlined emit-value map-options :options="OPERATORS" label="المتعامل" clearable />
        <q-input v-model="draft.text" dense outlined autogrow :label="draft.kind === 'code' ? 'الكود' : draft.kind === 'message' ? 'نص الرسالة' : 'الملاحظة'" />
        <q-input v-model="draft.meaning" dense outlined autogrow label="معناه (ما تعرفه عنه)" />
        <div class="row q-gutter-sm">
          <q-btn unelevated no-caps color="primary" icon="save" :label="draft.id ? 'احفظ التعديل' : 'سجّل'" :loading="busy === 'save'"
            :disable="!draft.text.trim()" @click="save('mine')" />
          <q-btn v-if="draft.id" flat no-caps label="إلغاء" @click="resetDraft" />
        </div>
      </div>
      <div v-for="l in mine" :key="l.id" class="card column gap-xs">
        <div class="small muted">{{ KIND[l.kind] || l.kind }}<template v-if="l.operator"> · {{ l.operator }}</template> · {{ when(l.updated_at) }}</div>
        <div class="ltr code">{{ l.text }}</div>
        <div v-if="l.meaning" class="small">{{ l.meaning }}</div>
        <div class="row q-gutter-sm">
          <q-btn flat dense no-caps color="primary" icon="edit" label="عدّل" @click="editLine(l)" />
          <q-btn flat dense no-caps color="grey-7" icon="delete" label="احذف" :loading="busy === 'h' + l.id" @click="hide(l)" />
        </div>
      </div>
    </template>

    <template v-else>
      <div class="card column q-gutter-sm">
        <q-input v-model="draft.text" dense outlined autogrow label="خدمة أو فكرة" />
        <q-btn-toggle v-model="draft.status" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="STATUS_OPTIONS" />
        <q-input v-model="draft.note" dense outlined autogrow label="ملاحظة" />
        <div class="row q-gutter-sm">
          <q-btn unelevated no-caps color="primary" icon="save" :label="draft.id ? 'احفظ التعديل' : 'أضف إلى الخطة'" :loading="busy === 'save'"
            :disable="!draft.text.trim()" @click="save('plan')" />
          <q-btn v-if="draft.id" flat no-caps label="إلغاء" @click="resetDraft" />
        </div>
      </div>
      <div v-for="l in plan" :key="l.id" class="card column gap-xs">
        <div class="row items-center no-wrap q-gutter-sm">
          <span>{{ STATUS[l.status]?.icon || '•' }}</span>
          <span class="col text-weight-medium">{{ l.text }}</span>
          <span class="small muted">{{ STATUS[l.status]?.label }}</span>
        </div>
        <div v-if="l.note" class="small muted">{{ l.note }}</div>
        <div class="row q-gutter-sm">
          <q-btn flat dense no-caps color="primary" icon="arrow_upward" label="أهم" @click="bump(l, 1)" />
          <q-btn flat dense no-caps color="primary" icon="edit" label="عدّل" @click="editLine(l)" />
          <q-btn flat dense no-caps color="grey-7" icon="delete" label="احذف" :loading="busy === 'h' + l.id" @click="hide(l)" />
        </div>
      </div>
    </template>
  </q-page>
</template>

<script setup>
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import { computed, onMounted, ref } from 'vue'
import { Dialog } from 'quasar'
import * as flexy from 'src/api/flexy'

const FOUND = {
  used: { icon: '✅', label: 'يُستعمل', cls: 'text-positive' },
  known: { icon: '🟡', label: 'معروف ولا يُستعمل', cls: 'text-amber-9' },
  understood: { icon: '✅', label: 'يفهمه', cls: 'text-positive' },
  unknown: { icon: '❌', label: 'لا يعرفه', cls: 'text-negative' }
}
const STATUS = {
  done: { icon: '✅', label: 'موجود' }, partial: { icon: '🟡', label: 'جزئي' }, planned: { icon: '📋', label: 'مخطط' }, idea: { icon: '💭', label: 'فكرة' }
}
const STATUS_OPTIONS = Object.entries(STATUS).map(([value, s]) => ({ label: s.icon + ' ' + s.label, value }))
const KIND = { code: 'كود', message: 'رسالة', note: 'ملاحظة', service: 'خدمة' }
const OPERATORS = ['موبيليس أرسلي', 'موبيليس سما', 'موبيليس', 'جيزي', 'أوريدو', 'أخرى'].map((o) => ({ label: o, value: o }))

const tab = ref('know')
const busy = ref('')
const error = ref('')
const pending = ref('')
const codes = ref([])
const texts = ref([])
const mine = ref([])
const plan = ref([])
const used = computed(() => codes.value.filter((c) => c.status === 'used'))
const known = computed(() => codes.value.filter((c) => c.status === 'known'))
const query = ref('')
const found = ref(null)
const blank = () => ({ id: null, kind: 'code', operator: null, text: '', meaning: '', status: 'idea', note: '', priority: 0 })
const draft = ref(blank())
const resetDraft = () => { draft.value = blank() }

async function call (key, fn) {
  busy.value = key
  error.value = ''
  try {
    const r = await fn()
    if (r.status !== 200 || !r.body?.ok) throw new Error(r.body?.error || 'FLEXY_CORE')
    return r.body
  } catch (e) {
    error.value = e.message || 'FLEXY_CORE'
    return null
  } finally {
    busy.value = ''
  }
}
function take (b) {
  if (!b || b.verdict) return
  codes.value = b.codes || []
  texts.value = b.texts || []
  mine.value = b.mine || []
  plan.value = b.plan || []
  pending.value = b.pending || ''
}
async function search () {
  const b = await call('search', () => flexy.notebookSearch(query.value.trim()))
  if (b) found.value = { verdict: b.verdict, mine: b.mine || [] }
}
function startMine (text) {
  tab.value = 'mine'
  draft.value = { ...blank(), kind: /^[*#0-9\s]+$/.test(text) ? 'code' : 'message', text }
}
async function save (section) {
  const d = draft.value
  const line = { section, kind: section === 'plan' ? 'service' : d.kind, operator: d.operator, text: d.text.trim(), meaning: d.meaning,
    status: section === 'plan' ? d.status : null, note: d.note, priority: d.priority, ...(d.id ? { id: d.id } : {}) }
  const b = await call('save', () => flexy.notebookSave(line))
  if (b) { take(b); resetDraft() }
}
function editLine (l) {
  draft.value = { ...blank(), ...l, meaning: l.meaning || '', note: l.note || '' }
  window.scrollTo({ top: 0, behavior: 'smooth' })
}
async function bump (l, by) {
  take(await call('b' + l.id, () => flexy.notebookSave({ ...l, priority: (l.priority || 0) + by })))
}
function hide (l) {
  Dialog.create({ title: 'احذف من الدفتر؟', message: l.text.slice(0, 120), cancel: 'إلغاء', ok: 'احذف' })
    .onOk(async () => take(await call('h' + l.id, () => flexy.notebookHide(l.id))))
}
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers', dateStyle: 'short', timeStyle: 'short' }) : '')
onMounted(async () => take(await call('load', () => flexy.ownerNotebook())))
</script>

<style scoped>
.row-line { padding: 6px 2px; border-top: 1px solid rgba(0, 0, 0, 0.06); }
.code { font-family: monospace; word-break: break-all; }
.ltr { direction: ltr; text-align: left; }
.gap-xs { gap: 4px; }
</style>
