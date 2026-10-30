<template>
  <!-- «ذاكرة الأرقام» (owner 2026-10-29, Flexy Core 0073): what the program remembers about a customer number
       (Mobilis group, Ooredoo group, Djezzy family, the discovery card), and «انسَ» so the next send discovers
       it again. Or forget everything learned in the last 30 days, after seeing how many numbers.
       No money and no USSD here; what is forgotten is archived in Flexy Core, never lost. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />

    <div class="card column q-gutter-sm">
      <div class="text-subtitle1 text-weight-bold">رقم واحد</div>
      <div class="row q-gutter-sm items-center no-wrap">
        <q-input v-model="phone" dense outlined class="col" inputmode="tel" placeholder="06XXXXXXXX" maxlength="16"
          @keyup.enter="look" />
        <q-btn unelevated no-caps color="primary" label="ابحث" :loading="busy === 'look'" @click="look" />
      </div>
      <div v-if="error" class="small text-negative">{{ error }}</div>

      <template v-if="mem">
        <div v-if="!known.length" class="muted">لا يتذكر البرنامج شيئًا عن هذا الرقم: سيُستكشف عند أول إرسال.</div>
        <div v-for="k in known" :key="k.key" class="kv row no-wrap">
          <div class="col-5 muted">{{ k.label }}</div>
          <div class="col">{{ k.value }}<div v-if="k.when" class="small muted">{{ k.when }}</div></div>
        </div>
        <div v-if="mem.forgotten?.length" class="small muted">
          نُسي من قبل: {{ mem.forgotten.map((f) => SOURCES[f.source] + ' (' + when(f.forgot_at) + ')').join('، ') }}
        </div>
        <q-btn v-if="known.length" unelevated no-caps color="deep-orange" icon="restart_alt" label="انسَ هذا الرقم"
          :loading="busy === 'forget'" @click="forgetOne" />
      </template>
    </div>

    <div class="card column q-gutter-sm">
      <div class="text-subtitle1 text-weight-bold">كل ما عُرف في آخر 30 يومًا</div>
      <div class="small muted">
        كل رقم عُرفت مجموعته أو عائلته أو بدأ استكشافه خلال 30 يومًا يُنسى، فيُستكشف من جديد عند إرساله القادم.
        يظهر العدد قبل التأكيد.
      </div>
      <q-btn outline no-caps color="deep-orange" icon="person" label="انسَ الأرقام التي أرسلتُ لها أنا"
        :loading="busy === 'mine'" @click="forgetMany('mine')" />
      <div class="help small muted">من شاشتك أو من هاتف الإدارة، في آخر 30 يومًا. أرقام المحلات لا تُمسّ.</div>
      <q-btn outline no-caps color="negative" icon="delete_sweep" label="انسَ آخر 30 يومًا (كل الأرقام)"
        :loading="busy === 'recent'" @click="forgetMany('recent')" />
    </div>
  </q-page>
</template>

<script setup>
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import { computed, ref } from 'vue'
import { Dialog, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'

const SOURCES = { mobilis: 'موبيليس', discovery: 'الاستكشاف', djezzy: 'جازي', ooredoo: 'أوريدو' }
const ERRORS = {
  PHONE_INVALID: 'رقم غير صحيح: 10 أرقام يبدأ بـ 05 أو 06 أو 07.',
  DAYS_INVALID: 'عدد الأيام غير صحيح.',
  NUMBER_MEMORY_NOT_READY: 'ذاكرة الأرقام لم تُفعَّل بعد (migration 0073 و0074).',
  OWNER_REQUIRED: 'للمالك فقط.'
}

const phone = ref('')
const mem = ref(null)
const busy = ref(null)
const error = ref('')

const when = (t) => (t ? new Date(t).toLocaleString('ar-DZ', { dateStyle: 'short', timeStyle: 'short' }) : '')

const known = computed(() => {
  const m = mem.value
  if (!m) return []
  const out = []
  if (m.mobilis) out.push({ key: 'm', label: 'مجموعة موبيليس', value: m.mobilis.line_group, when: 'عُرفت ' + when(m.mobilis.confirmed_at) })
  if (m.ooredoo) out.push({ key: 'o', label: 'مجموعة أوريدو', value: m.ooredoo.grp || '—', when: 'عُرفت ' + when(m.ooredoo.confirmed_at) })
  if (m.djezzy) out.push({ key: 'd', label: 'عائلة جازي', value: m.djezzy.family || '—', when: 'عُرفت ' + when(m.djezzy.confirmed_at) })
  if (m.discovery) {
    const d = m.discovery
    out.push({ key: 'n', label: 'بطاقة الاستكشاف', value: d.released_at ? 'انتهى' : 'جارٍ', when: 'بدأ ' + when(d.started_at) })
  }
  return out
})

async function call (fn) {
  const r = await fn()
  if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'تعذّر الاتصال.')
  return r.body
}

async function look () {
  error.value = ''
  busy.value = 'look'
  try {
    mem.value = (await call(() => flexy.numberMemory(phone.value))).memory
  } catch (e) {
    mem.value = null
    error.value = e.message
  } finally {
    busy.value = null
  }
}

function forgetOne () {
  const p = mem.value?.phone
  Dialog.create({ title: 'انسَ هذا الرقم', message: 'سيُنسى ما عُرف عن ' + p + ' ويُستكشف عند إرساله القادم. لا مال ولا USSD الآن.', cancel: 'إلغاء', ok: 'انسَ' })
    .onOk(async () => {
      busy.value = 'forget'
      try {
        await call(() => flexy.numberForget(p))
        Notify.create({ message: 'نُسي الرقم.', color: 'positive', position: 'top' })
        await look()
      } catch (e) {
        Notify.create({ message: e.message, color: 'negative', position: 'top' })
      } finally {
        busy.value = null
      }
    })
}

async function forgetMany (kind) {
  const fn = kind === 'mine' ? flexy.numberForgetMine : flexy.numberForgetRecent
  const title = kind === 'mine' ? 'انسَ الأرقام التي أرسلتُ لها أنا' : 'انسَ آخر 30 يومًا'
  busy.value = kind
  let n = 0
  try {
    n = (await call(() => fn(30, false))).preview?.numbers ?? 0
  } catch (e) {
    Notify.create({ message: e.message, color: 'negative', position: 'top' })
    return
  } finally {
    busy.value = null
  }
  if (!n) {
    Notify.create({ message: 'لا شيء عُرف في آخر 30 يومًا.', color: 'info', position: 'top' })
    return
  }
  Dialog.create({ title, message: 'سيُنسى ' + n + ' رقمًا ويُستكشف كل منها عند إرساله القادم. متأكد؟', cancel: 'إلغاء', ok: 'انسَ ' + n })
    .onOk(async () => {
      busy.value = kind
      try {
        await call(() => fn(30, true))
        Notify.create({ message: 'نُسي ' + n + ' رقمًا.', color: 'positive', position: 'top' })
        if (mem.value) await look()
      } catch (e) {
        Notify.create({ message: e.message, color: 'negative', position: 'top' })
      } finally {
        busy.value = null
      }
    })
}
</script>

<style scoped>
.kv { border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding: 4px 0; }
</style>
