<template>
  <q-page class="page">
    <!-- Review first: these hold a shop's money until the owner decides -->
    <div v-if="reviews.length" class="card column q-gutter-sm">
      <div class="row items-center">
        <div class="col section-title">تحتاج حكمك</div>
        <q-badge color="deep-orange" :label="reviews.length" />
      </div>
      <div v-for="j in reviews" :key="j.job_id" class="review column q-gutter-xs">
        <div class="text-weight-bold"><bdi dir="ltr">{{ j.phone }}</bdi> · {{ money(j.amount) }}</div>
        <div class="small muted">{{ j.customer_name }} · خُصم {{ money(j.charged) }} · {{ when(j.created_at) }}</div>
        <div class="small muted ltr text-right">{{ j.network_reply || 'لا رد مفهوم من الشبكة.' }}</div>
        <div class="grid-2">
          <q-btn unelevated no-caps color="positive" label="تم الإرسال" :loading="busy" @click="resolve(j, true)" />
          <q-btn outline no-caps color="negative" label="فشل، أرجع المبلغ" :loading="busy" @click="resolve(j, false)" />
        </div>
      </div>
    </div>

    <div class="card column q-gutter-sm">
      <div class="section-title">لكل المحلات</div>
      <q-toggle :model-value="isOpen" color="primary" :disable="busy || core.apps === null || core.forcedOff"
        :label="isOpen ? 'فليكسي المحلات مفتوح' : 'فليكسي المحلات مقفل'" @update:model-value="setOpen" />
      <div v-if="core.forcedOff" class="small text-negative">الإرسال موقوف من الخادم (طوارئ).</div>
      <div v-else-if="core.apps === null" class="small text-negative">تعذّرت قراءة مفتاح Flexy Core.</div>
      <div v-else-if="settings.open !== core.apps" class="small text-deep-orange">نصف مفتوح: المتجر {{ settings.open ? 'مفتوح' : 'مقفل' }} وFlexy Core {{ core.apps ? 'مفتوح' : 'مقفل' }}. أعد الضغط لتوحيدهما.</div>
      <div class="small muted">إقفاله يوقف إرسال كل المحلات فورًا. إرسالك أنت من «إرسال فليكسي» له مفتاحه الخاص.</div>
      <div class="grid-3">
        <q-input v-model.number="defaults.rate630" dense outlined type="number" step="0.25" label="نسبة العادي %" />
        <q-input v-model.number="defaults.rateOffer" dense outlined type="number" step="0.25" label="نسبة العروض %" />
        <q-input v-model.number="defaults.max" dense outlined type="number" label="أكبر مبلغ" />
      </div>
      <div class="small muted">الافتراضية تُنسخ مرة واحدة عند تفعيل محل. تغييرها لاحقًا لا يغيّر المحلات المفعّلة.</div>
      <q-btn flat no-caps color="primary" label="حفظ الافتراضية" :loading="busy" @click="saveDefaults" />
    </div>

    <div class="card column q-gutter-sm">
      <div class="row items-center q-gutter-sm">
        <div class="col section-title">نسب المحلات</div>
        <q-select v-model="roleFilter" dense outlined emit-value map-options :options="ROLE_FILTER" style="min-width: 130px" />
      </div>
      <q-input v-model="search" dense outlined clearable placeholder="بحث بالاسم" />
      <div class="shop-head small muted">
        <span>المحل</span><span>عادي</span><span>عروض</span><span>الحد</span>
      </div>
      <button v-for="c in shown" :key="c.customer_id" type="button" class="shop-row" @click="edit(c)">
        <span class="column items-start">
          <span>{{ c.name }}</span>
          <span class="row q-gutter-xs">
            <q-badge :color="c.role === 'wholesale' ? 'info' : 'positive'" :label="ROLES[c.role]" />
            <q-badge v-if="!c.enabled" color="grey-6" label="غير مفعّل" />
          </span>
        </span>
        <span><span v-if="c.rate_630 != null" class="rate">{{ c.rate_630 }}%</span></span>
        <span><span v-if="c.rate_offer != null" class="rate">{{ c.rate_offer }}%</span></span>
        <span class="small">{{ c.max_amount ? money(c.max_amount) : '—' }}</span>
      </button>
      <div v-if="!shown.length" class="text-center muted q-pa-md">لا محلات</div>
    </div>

    <div class="card q-pa-none">
      <div class="section-title q-pa-sm">آخر عمليات المحلات</div>
      <div v-for="j in jobs" :key="j.job_id" class="op-row">
        <div class="row items-center no-wrap q-gutter-sm">
          <span class="col text-weight-bold"><bdi dir="ltr">{{ j.phone }}</bdi> · {{ money(j.amount) }}</span>
          <q-badge :color="STATUS[j.status]?.color || 'grey'" :label="STATUS[j.status]?.label || j.status" />
        </div>
        <div class="small muted">{{ j.customer_name }} · خُصم {{ money(j.charged) }} · {{ when(j.created_at) }}</div>
      </div>
      <div v-if="!jobs.length" class="text-center muted q-pa-lg">لا عمليات بعد</div>
    </div>

    <q-dialog v-model="editing">
      <q-card v-if="form" style="min-width: 300px">
        <q-card-section class="text-weight-bold">{{ form.name }}</q-card-section>
        <q-card-section class="column q-gutter-sm">
          <q-toggle v-model="form.enabled" label="تفعيل الفليكسي" />
          <q-select v-model="form.role" dense outlined emit-value map-options label="الدور" :options="ROLE_OPTIONS" />
          <q-input v-model.number="form.rate630" dense outlined type="number" step="0.25" label="نسبة العادي %" />
          <q-input v-model.number="form.rateOffer" dense outlined type="number" step="0.25" label="نسبة العروض %" />
          <q-input v-model.number="form.max" dense outlined type="number" label="أكبر مبلغ للعملية" />
          <div class="small muted">المحل لا يرى نسبته ولا دوره.</div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat no-caps label="إلغاء" v-close-popup />
          <q-btn unelevated no-caps color="primary" label="حفظ" :loading="busy" @click="saveShop" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { Dialog } from 'quasar'
import * as api from 'src/api/admin'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'
import { useRun } from 'src/composables/useRun'
import { useBell } from 'src/composables/useBell'

const { busy, run } = useRun()
const { refreshBell } = useBell()
const ROLES = { trader: 'تاجر', wholesale: 'تاجر الجملة' }
const ROLE_OPTIONS = [{ label: 'تاجر', value: 'trader' }, { label: 'تاجر الجملة', value: 'wholesale' }]
const ROLE_FILTER = [{ label: 'الكل', value: null }, ...ROLE_OPTIONS]
const STATUS = {
  queued: { label: 'في الطريق', color: 'grey-7' },
  sent: { label: 'جارٍ', color: 'info' },
  success: { label: 'ناجحة', color: 'positive' },
  failed: { label: 'فاشلة · أُعيد', color: 'negative' },
  not_sent: { label: 'لم تُرسل · أُعيد', color: 'grey-7' },
  review: { label: 'مراجعة', color: 'deep-orange' }
}
const when = (t) => new Date(t).toLocaleString('ar-DZ')

const settings = reactive({ open: false })
// Shops send only when both are on: the store's switch and Flexy Core's apps switch.
const core = reactive({ apps: null, forcedOff: false })
const isOpen = computed(() => settings.open && core.apps === true && !core.forcedOff)
function showCore (res) {
  if (res.status !== 200) throw new Error('تعذّر الوصول إلى مفتاح Flexy Core (' + (res.body?.error || 'FLEXY_CORE') + ').')
  core.apps = res.body.apps_send_enabled === true
  core.forcedOff = res.body.forced_off === true
}
const defaults = reactive({ rate630: null, rateOffer: null, max: null })
const shops = ref([])
const jobs = ref([])
const reviews = ref([])
const roleFilter = ref(null)
const search = ref('')
const shown = computed(() => shops.value.filter((c) => (!roleFilter.value || c.role === roleFilter.value) &&
  (!search.value || c.name.includes(search.value))))

async function load () {
  const [s, c, j, r, k] = await Promise.all([api.flexySettings(), api.flexyCustomers(), api.flexyJobs(null, 20), api.flexyJobs('review', 50), flexy.ownerSwitch()])
  try { showCore(k) } catch { core.apps = null }
  if (s) {
    settings.open = s.open
    defaults.rate630 = Number(s.default_rate_630)
    defaults.rateOffer = s.default_rate_offer == null ? null : Number(s.default_rate_offer)
    defaults.max = s.default_max
  }
  shops.value = c
  jobs.value = j
  reviews.value = r
}

// One toggle for both switches. Opening: Flexy Core first, then the store; closing: the store first.
async function setOpen (on) {
  const apply = async () => {
    const ok = await run(async () => {
      if (on) showCore(await flexy.setAppsSwitch(true))
      await api.setFlexySettings(on, null, null, null)
      settings.open = on
      if (!on) showCore(await flexy.setAppsSwitch(false))
      return true
    })
    if (!ok) load()
  }
  if (!on) return apply()
  Dialog.create({ title: 'فتح فليكسي المحلات', message: 'كل «أرسل» من محل مفعّل يُخرج رصيدًا حقيقيًا من الشريحة. متأكد؟', cancel: 'لا', ok: 'نعم، افتح' }).onOk(apply)
}
async function saveDefaults () {
  if (await run(() => api.setFlexySettings(null, defaults.rate630, defaults.rateOffer, defaults.max).then(() => true), { success: 'حُفظت الافتراضية.' })) load()
}

const editing = ref(false)
const form = ref(null)
function edit (c) {
  form.value = { id: c.customer_id, name: c.name, enabled: c.enabled, role: c.role, rate630: c.rate_630 == null ? null : Number(c.rate_630), rateOffer: c.rate_offer == null ? null : Number(c.rate_offer), max: c.max_amount }
  editing.value = true
}
async function saveShop () {
  const f = form.value
  const ok = await run(() => api.setCustomerFlexy(f.id, { enabled: f.enabled, role: f.role, rate630: f.rate630, rateOffer: f.rateOffer, max: f.max }).then(() => true), { success: 'حُفظ.' })
  if (ok) { editing.value = false; load() }
}

function resolve (j, done) {
  Dialog.create({
    title: done ? 'تم الإرسال؟' : 'لم يُرسل؟',
    message: done ? 'يبقى المبلغ مخصومًا من المحل.' : `يُعاد ${money(j.charged)} إلى رصيد المحل.`,
    cancel: 'رجوع',
    ok: 'تأكيد'
  }).onOk(async () => {
    if (await run(() => api.flexyResolve(j.job_id, done))) { load(); refreshBell() }
  })
}

onMounted(() => run(load))
</script>

<style scoped>
.review { border: 1px solid #F3D9B8; background: #FFF8EE; border-radius: 12px; padding: 10px; }
.shop-head, .shop-row { display: grid; grid-template-columns: 2fr 1fr 1fr 1fr; gap: 6px; align-items: center; }
.shop-row { width: 100%; border: 0; border-top: 1px solid #EEF0F4; background: transparent; padding: 8px 0; text-align: right; font: inherit; color: inherit; cursor: pointer; }
.rate { background: #1E293B; color: #FFF; border-radius: 6px; padding: 2px 8px; font-weight: 700; }
.op-row { padding: 10px 14px; border-top: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
</style>
