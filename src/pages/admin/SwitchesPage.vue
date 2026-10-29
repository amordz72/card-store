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

onMounted(() => run('load', () => flexy.ownerSwitch()))
</script>

<style scoped>
.page { max-width: 760px; margin: 0 auto; }
.card { background: #fff; border: 1px solid #ECEEF3; border-radius: 12px; padding: 12px; }
</style>
