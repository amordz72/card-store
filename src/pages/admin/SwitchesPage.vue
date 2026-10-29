<template>
  <!-- «المفاتيح» (owner 2026-10-29): the money switches, moved out of «إرسال فليكسي» so that page starts at the
       number. Set once and kept for days; the send page shows one line only when one of them is closed. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
    <div v-if="forcedOff" class="card text-negative text-weight-bold">🔴 الإرسال موقوف من الخادم (طوارئ): لا يُفتح من هنا.</div>
    <div class="card row items-center q-gutter-sm">
      <q-toggle :model-value="switchOn" :disable="switchOn === null || busy === 'main' || forcedOff" color="positive"
        :label="switchOn ? 'الإرسال الحقيقي مفتوح' : 'الإرسال الحقيقي مقفل'" @update:model-value="flip" />
      <q-spinner v-if="busy === 'main'" size="16px" />
      <div class="col-12 small muted">كل «إرسال» يُخرج رصيدًا حقيقيًا من الشريحة. مقفل = لا يُرسل شيء.</div>
    </div>
    <!-- Djezzy (*760*, owner 2026-10-27): its own switch in Flexy Core -->
    <div class="card row items-center q-gutter-sm">
      <q-toggle :model-value="djezzyOn" :disable="djezzyOn === null || busy === 'djezzy' || forcedOff" color="positive"
        :label="djezzyOn ? 'إرسال جيزي (07) مفتوح' : 'إرسال جيزي (07) مقفل'" @update:model-value="flipDjezzy" />
      <q-spinner v-if="busy === 'djezzy'" size="16px" />
      <div class="col-12 small muted">جيزي (<bdi dir="ltr">*760*</bdi>): تأكيد ثم تحويل فوري، والنجاح يظهر من نص الشبكة. ردّ غير معروف يبقى «قيد المراجعة» حتى تقرأه.</div>
    </div>
    <!-- Ooredoo (*590*, owner 2026-10-27): its own switch in Flexy Core, never Djezzy's -->
    <div class="card row items-center q-gutter-sm">
      <q-toggle :model-value="ooredooOn" :disable="ooredooOn === null || busy === 'ooredoo' || forcedOff" color="positive"
        :label="ooredooOn ? 'إرسال أوريدو (05) مفتوح' : 'إرسال أوريدو (05) مقفل'" @update:model-value="flipOoredoo" />
      <q-spinner v-if="busy === 'ooredoo'" size="16px" />
      <div class="col-12 small muted">أوريدو (<bdi dir="ltr">*590*</bdi>): تأكيد ثم شحن فوري برقم عملية، والنجاح يظهر من نص الشبكة.</div>
    </div>
    <!-- «عروض سما» (owner 2026-10-27): for every send, his and the shops'. Off = Arsselli only. -->
    <div class="card row items-center q-gutter-sm">
      <q-toggle :model-value="samaOn" :disable="samaOn === null || busy === 'sama'" color="primary"
        :label="samaOn ? 'عروض سما مفعّلة' : 'عروض سما ملغاة: العروض من أرسلي فقط'" @update:model-value="flipSama" />
      <q-spinner v-if="busy === 'sama'" size="16px" />
      <div class="col-12 small muted">أقل من 500 دج: أرسلي أولًا وسما عند الضرورة. 500 فما فوق: سما أولًا وأرسلي عند الضرورة.</div>
    </div>

    <!-- «المهام الآلية» (owner 2026-10-29, Flexy Core 0076): what the program does by itself, one switch each,
         what it did last; then everything it did, and every switch change -->
    <div class="section-title q-mt-md">المهام الآلية · ما يفعله البرنامج وحده</div>
    <div v-if="autoError" class="card small text-negative">{{ autoError }}</div>
    <div v-for="t in tasks" :key="t.key" class="card column q-gutter-xs">
      <div class="row items-center no-wrap">
        <span class="col text-weight-bold">{{ t.name }}</span>
        <q-toggle v-if="t.switchable" :model-value="t.on" dense color="positive" :disable="busy === t.key" @update:model-value="(v) => flipTask(t, v)" />
        <span v-else class="small muted">يعمل دائمًا</span>
      </div>
      <div class="small muted">{{ t.what }} · {{ t.every }}</div>
      <div v-if="t.last" class="small">آخر مرة: {{ when(t.last.at) }} · {{ t.last.target }}<template v-if="t.last.reason"> · {{ REASONS[t.last.reason] || t.last.reason }}</template></div>
    </div>
    <q-expansion-item v-if="actions.length" dense class="card q-pa-none" label="آخر ما فعله البرنامج وحده" header-class="text-weight-bold">
      <div v-for="(a, i) in actions" :key="i" class="row small q-px-md q-py-xs line">
        <span class="col-4 muted">{{ when(a.at) }}</span><span class="col">{{ TASKS[a.task] || a.task }} · {{ a.target }}<template v-if="a.reason"> · {{ REASONS[a.reason] || a.reason }}</template></span>
      </div>
    </q-expansion-item>
    <q-expansion-item v-if="changes.length" dense class="card q-pa-none" label="تغييرات المفاتيح" header-class="text-weight-bold">
      <div v-for="(c, i) in changes" :key="i" class="row small q-px-md q-py-xs line">
        <span class="col-4 muted">{{ when(c.at) }}</span><span class="col">{{ KEYS[c.key] || c.key }}: {{ shown(c.before) }} ← {{ shown(c.after) }}</span>
      </div>
    </q-expansion-item>
  </q-page>
</template>

<script setup>
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import { onMounted, ref } from 'vue'
import { useQuasar } from 'quasar'
import * as flexy from 'src/api/flexy'

const $q = useQuasar()
const switchOn = ref(null)
const forcedOff = ref(false)
const djezzyOn = ref(null)
const ooredooOn = ref(null)
const samaOn = ref(null)
const busy = ref(null)

function show (res) {
  if (res.status === 200) {
    switchOn.value = res.body.send_enabled
    forcedOff.value = res.body.forced_off
    samaOn.value = res.body.sama_offers_enabled !== false
    djezzyOn.value = res.body.djezzy_send_enabled === true
    ooredooOn.value = res.body.ooredoo_send_enabled === true
  } else $q.notify({ type: 'negative', message: res.body?.error || 'تعذّر الاتصال.' })
}
async function run (key, call) {
  busy.value = key
  try { show(await call()) } finally { busy.value = null }
}
// Opening one moves real money from then on: asked once; closing is immediate
function ask (title, message, apply) {
  $q.dialog({ title, message, cancel: 'لا', ok: 'نعم، افتح' }).onOk(apply)
}
function flip (on) {
  const apply = () => run('main', () => flexy.setOwnerSwitch(on))
  if (!on) return apply()
  ask('فتح الإرسال الحقيقي', 'كل «إرسال» بعدها يُخرج رصيدًا حقيقيًا من الشريحة. متأكد؟', apply)
}
function flipDjezzy (on) {
  const apply = () => run('djezzy', () => flexy.setDjezzySwitch(on))
  if (!on) return apply()
  ask('فتح إرسال جيزي الحقيقي', 'كل «إرسال» إلى 07 يُخرج رصيدًا حقيقيًا من شريحة جيزي فورًا عند تأكيد الشبكة. متأكد؟', apply)
}
function flipOoredoo (on) {
  const apply = () => run('ooredoo', () => flexy.setOoredooSwitch(on))
  if (!on) return apply()
  ask('فتح إرسال أوريدو الحقيقي', 'كل «إرسال» إلى 05 يُخرج رصيدًا حقيقيًا من شريحة أوريدو فورًا عند تأكيد الشبكة. متأكد؟', apply)
}
const flipSama = (on) => run('sama', () => flexy.setSamaOffersSwitch(on))

// «المهام الآلية»
const tasks = ref([])
const actions = ref([])
const changes = ref([])
const autoError = ref('')
const TASKS = { 'read:mobilis-sama': 'قراءة رصيد سما', 'read:mobilis-arsselli': 'قراءة رصيد أرسلي', 'read:djezzy-flexy': 'قراءة رصيد جيزي', 'read:ooredoo-flexy': 'قراءة رصيد أوريدو', close_stuck: 'إغلاق عملية عالقة بلا مال' }
const REASONS = { stale: 'قراءتها قديمة', never_read: 'لم تُقرأ قط', sold_half: 'باعت نصف رصيدها' }
const KEYS = {
  'owner.630.send_enabled': 'الإرسال الحقيقي', 'owner.760.send_enabled': 'إرسال جيزي', 'owner.590.send_enabled': 'إرسال أوريدو',
  'offers.sama_enabled': 'عروض سما', 'balance.sama_auto_read': 'قراءة سما الآلية', 'balance.arsselli_auto_read': 'قراءة أرسلي الآلية',
  'balance.djezzy_auto_read': 'قراءة جيزي الآلية', 'balance.ooredoo_auto_read': 'قراءة أوريدو الآلية', 'auto.close_stuck': 'إغلاق العالق',
  'offers.background_discovery': 'الاستكشاف في الخلفية', 'balance.auto_read': 'قراءة أرسلي اليومية'
}
const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '—')
const shown = (v) => (v === true ? 'مفتوح' : v === false ? 'مقفل' : v == null ? '—' : String(v))
function showAuto (res) {
  if (res.status === 200 && res.body?.ok) {
    tasks.value = res.body.tasks || []
    actions.value = res.body.actions || []
    changes.value = res.body.settings || []
    autoError.value = ''
  } else autoError.value = res.body?.error === 'AUTO_LOG_NOT_READY' ? 'المهام الآلية لم تُفعَّل بعد (migration 0076).' : (res.body?.error || 'تعذّر الاتصال.')
}
async function flipTask (t, on) {
  busy.value = t.key
  try { showAuto(await flexy.setAutoTask(t.key, on)) } finally { busy.value = null }
}

onMounted(() => {
  run('load', () => flexy.ownerSwitch())
  flexy.ownerAuto().then(showAuto).catch(() => { autoError.value = 'تعذّر الاتصال.' })
})
</script>

<style scoped>
.page { max-width: 760px; margin: 0 auto; }
.card { background: #fff; border: 1px solid #ECEEF3; border-radius: 12px; padding: 12px; }
.section-title { font-weight: 800; }
.line { border-top: 1px solid #ECEEF3; }
</style>
