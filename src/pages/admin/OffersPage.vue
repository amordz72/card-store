<template>
  <!-- The offers screen (Flexy Core 0060, owner 2026-10-28 night): every offer the network showed, by operator
       and group (the line type the carrier names: GOLD, Dima…). «جديدة» = waiting for the owner; «النشطة» = decided.
       One control per offer: مغلق (nobody) / للإدارة (the owner) / للكل (the owner and the shops). -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <div class="row q-gutter-xs">
      <q-btn v-for="o in OPERATORS" :key="o.key" dense no-caps rounded :unelevated="operator === o.key" :outline="operator !== o.key"
        :color="operator === o.key ? 'primary' : 'grey-7'" :label="o.label" @click="operator = o.key" />
    </div>
    <div v-if="groups.length > 1" class="row q-gutter-xs">
      <q-btn v-for="g in ['', ...groups]" :key="g || 'all'" dense no-caps rounded size="sm" :unelevated="group === g" :outline="group !== g"
        :color="group === g ? 'deep-orange' : 'grey-7'" :label="g || 'الكل'" @click="group = g" />
    </div>
    <q-tabs v-model="tab" dense no-caps align="justify" class="text-primary">
      <q-tab name="new" :label="`جديدة (${counts.new})`" />
      <q-tab name="active" :label="`النشطة (${counts.active})`" />
    </q-tabs>
    <div v-if="error" class="small text-negative">{{ error }}</div>
    <div v-if="loading" class="row justify-center q-pa-lg"><q-spinner color="primary" size="28px" /></div>
    <div v-else-if="!shown.length" class="card text-center muted q-pa-lg">
      {{ operator !== 'ooredoo' ? 'عروض هذا المتعامل تُضاف لاحقًا بنفس الطريقة.' : tab === 'new' ? 'لا عروض جديدة تنتظرك.' : 'لا عروض نشطة بعد.' }}
    </div>
    <div v-for="(list, g) in byGroup" :key="g" class="card q-pa-none">
      <!-- The group: its state, what a sudden change does, freeze / approve, and its archived versions -->
      <div class="grp column q-gutter-xs">
        <div class="row items-center q-gutter-xs">
          <span>{{ g }}</span>
          <q-badge :color="STATE[info(g).state]?.color || 'grey'" :label="(STATE[info(g).state]?.label || '') + (info(g).state === 'active' ? ' · النسخة ' + info(g).version : '')" />
          <q-badge v-if="info(g).blocked" color="negative" label="موقوفة كلها: تغيّر في الشبكة" />
          <q-space />
          <q-btn v-if="info(g).blocked" dense flat no-caps size="sm" color="primary" label="فك الإيقاف" @click="act(g, 'unblock')" />
          <q-btn v-if="info(g).state !== 'active'" dense unelevated no-caps size="sm" color="positive" label="اعتمد النسخة" @click="act(g, 'approve')" />
          <q-btn v-if="info(g).state !== 'frozen'" dense outline no-caps size="sm" color="deep-orange" label="جمّد واستكشف من جديد" @click="freeze(g)" />
        </div>
        <div class="row items-center q-gutter-xs small">
          <span class="muted">عند تغيّر من الشبكة:</span>
          <q-btn-toggle :model-value="info(g).on_change || 'offer'" dense no-caps unelevated size="sm" toggle-color="primary"
            :options="[{ label: 'أوقف العرض المتغيّر فقط', value: 'offer' }, { label: 'جمّد المجموعة كلها', value: 'group' }]"
            @update:model-value="(v) => act(g, 'on_change', v)" />
        </div>
        <div v-if="info(g).state === 'frozen'" class="small text-deep-orange">
          مجمّدة: لا يُباع منها شيء. افتح رقمًا من هذه المجموعة في «إرسال فليكسي» لتُبنى النسخة الجديدة، ثم «اعتمد النسخة».
          <span v-if="info(g).gone?.length"> اختفى من النسخة السابقة: {{ info(g).gone.join('، ') }}</span>
        </div>
        <div v-if="info(g).versions?.length" class="row items-center q-gutter-xs small">
          <span class="muted">النسخ المحفوظة:</span>
          <q-btn v-for="v in info(g).versions" :key="v.version" dense flat no-caps size="sm" color="primary"
            :label="'النسخة ' + v.version + ' (' + v.count + ')'" @click="restore(g, v)" />
        </div>
      </div>
      <div v-for="o in list" :key="o.id" class="offer" :class="{ off: o.status === 'doubt' }">
        <div class="col">
          <div class="nm">{{ o.nameDisplay }}<span v-if="o.nameDisplay !== o.nameNetwork" class="muted small"> · {{ o.nameNetwork }}</span></div>
          <div class="meta">
            رمز {{ o.code }} · {{ where(o) }} ·
            <span :class="o.price ? '' : 'text-negative'">{{ o.price ? money(o.price) : 'بلا سعر' }}</span>
            <span v-if="o.price"> ({{ PRICE[o.priceSource] || '—' }})</span>
            <span v-if="o.category === 'internet'"> · إنترنت</span>
          </div>
          <div class="meta">
            <span v-if="o.status === 'doubt'" class="text-negative">الرمز ظهر مرتين في القائمة: لا يُرسل · </span>
            <span v-else-if="o.status === 'tested'">مجرّب ✓ · </span>
            وجدته {{ o.foundSim || '—' }} · {{ who(o.foundBy) }} · رآه {{ o.seenCount }} مرة · آخرها {{ clock(o.lastSeenAt) }}
            <span v-if="o.lastOp"> · آخر بيع: {{ OP[o.lastOp.status] || o.lastOp.status }}</span>
          </div>
          <!-- A sudden change: the stable version beside what the network shows now (owner 2026-10-28) -->
          <div v-if="o.drift" class="drift">
            <div>⚠️ {{ DRIFT[o.drift.kind] || 'تغيّر' }}: أُوقف حتى تقرر</div>
            <div>في النسخة المستقرة: رمز {{ o.drift.from.code }} · {{ pageOf(o.drift.from) }} · {{ o.drift.from.price ? money(o.drift.from.price) : 'بلا سعر' }}</div>
            <div v-if="o.drift.to.missing">الآن: لم يعد في صفحته من القائمة</div>
            <div v-else>الآن:
              <span v-if="o.drift.to.code">رمز {{ o.drift.to.code }} · {{ pageOf(o.drift.to) }}</span>
              <span v-if="o.drift.to.price"> · الشبكة قالت {{ money(o.drift.to.price) }}</span>
            </div>
            <div class="row q-gutter-xs q-mt-xs">
              <q-btn v-if="!o.drift.to.missing" dense unelevated no-caps size="sm" color="positive" label="اعتمد التغيير" @click="drift(o, true)" />
              <q-btn dense outline no-caps size="sm" color="negative" label="أبقه موقوفًا" @click="drift(o, false)" />
            </div>
          </div>
        </div>
        <div class="column items-end q-gutter-xs">
          <q-btn-toggle :model-value="o.visibility" dense no-caps unelevated toggle-color="primary" size="sm" :disable="busy === o.id"
            :options="VIS" @update:model-value="(v) => setVisibility(o, v)" />
          <q-btn flat dense no-caps size="sm" icon="edit" label="السعر" @click="editPrice(o)" />
        </div>
      </div>
    </div>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'

const OPERATORS = [{ key: 'mobilis', label: 'موبيليس' }, { key: 'djezzy', label: 'جيزي' }, { key: 'ooredoo', label: 'أوريدو' }]
const VIS = [{ label: 'مغلق', value: 'closed' }, { label: 'للإدارة', value: 'admin' }, { label: 'للكل', value: 'all' }]
const PRICE = { name: 'من الاسم', network: 'من الشبكة', owner: 'كتبته أنت' }
const STATE = { new: { label: 'جديدة', color: 'purple-6' }, active: { label: 'نشطة', color: 'positive' }, frozen: { label: 'مجمّدة', color: 'deep-orange' } }
const DRIFT = { moved: 'تغيّر الرمز أو المكان', missing: 'اختفى من القائمة', price: 'تغيّر السعر', rebuilt: 'تغيّر عن النسخة السابقة' }
const OP = { success: 'ناجح', accepted: 'قبلته الشبكة', failed: 'فاشل', review: 'مراجعة', not_sent: 'لم يُرسل', running: 'جارٍ' }
const ERRORS = {
  CATALOG_PRICE_REQUIRED: 'اكتب سعر العرض أولًا، ثم افتحه.',
  CATALOG_OFFER_IN_DOUBT: 'رمز هذا العرض ظهر مرتين في القائمة: لا يُفتح حتى نفهمه.',
  CATALOG_NOT_FOUND: 'العرض لم يعد موجودًا: حدّث الصفحة.',
  GROUP_ALREADY_FROZEN: 'المجموعة مجمّدة أصلًا.',
  GROUP_ALREADY_ACTIVE: 'المجموعة نشطة أصلًا.',
  VERSION_NOT_FOUND: 'النسخة غير موجودة.'
}

const operator = ref('ooredoo')
const group = ref('')
const tab = ref('new')
const rows = ref([])
const loading = ref(false)
const busy = ref(null)
const error = ref('')

const groups = computed(() => [...new Set(rows.value.map((o) => o.group))])
const inGroup = computed(() => rows.value.filter((o) => !group.value || o.group === group.value))
// «جديدة»: in review, or changed by the network (waiting for the owner); «النشطة»: decided and unchanged
const waiting = (o) => o.review || Boolean(o.drift)
const counts = computed(() => ({ new: inGroup.value.filter(waiting).length, active: inGroup.value.filter((o) => !waiting(o)).length }))
const shown = computed(() => inGroup.value.filter((o) => (tab.value === 'new' ? waiting(o) : !waiting(o))))
const byGroup = computed(() => shown.value.reduce((acc, o) => ({ ...acc, [o.group]: [...(acc[o.group] || []), o] }), {}))
const groupInfo = ref([])
const info = (g) => groupInfo.value.find((x) => x.grp === g) || {}
const pageOf = (x) => (x.path?.length ? `الصفحة ${x.page} (${x.path.map((p) => (p === '0' ? 'المزيد' : p)).join(' ثم ')})` : `الصفحة ${x.page ?? 1}`)
const where = (o) => (o.execPath?.length ? `الصفحة ${o.page} (${o.execPath.map((p) => (p === '0' ? 'المزيد' : p)).join(' ثم ')} ثم ${o.code})` : `الصفحة ${o.page}`)
const who = (v) => (v === 'owner-console' ? 'الإدارة' : v === 'owner-lab' ? 'تجربتك' : v || '—')
const clock = (v) => (v ? new Date(v).toLocaleString('ar-DZ') : '—')

async function load () {
  loading.value = true
  error.value = ''
  try {
    const [r, gr] = await Promise.all([flexy.ownerOfferCatalog(operator.value), flexy.ownerOfferGroups(operator.value)])
    if (r.status !== 200 || !r.body?.ok) throw new Error(r.body?.error || 'FLEXY_CORE')
    rows.value = r.body.offers || []
    groupInfo.value = gr.body?.groups || []
    if (group.value && !groups.value.includes(group.value)) group.value = ''
  } catch (e) {
    error.value = 'تعذّرت قراءة العروض: ' + (e.message || '')
  } finally {
    loading.value = false
  }
}

async function save (o, patch) {
  busy.value = o.id
  try {
    const r = await flexy.ownerOfferCatalogSet(o.id, patch)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
    rows.value = rows.value.map((x) => (x.id === o.id ? r.body.offer : x))
    return true
  } catch (e) {
    Notify.create({ message: e.message, color: 'negative', position: 'top' })
    return false
  } finally {
    busy.value = null
  }
}

const setVisibility = (o, v) => save(o, { visibility: v })

async function act (g, action, value = null) {
  try {
    const r = await flexy.ownerOfferGroupAction(operator.value, g, action, value)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
    await load()
  } catch (e) {
    Notify.create({ message: e.message, color: 'negative', position: 'top' })
  }
}
function freeze (g) {
  Dialog.create({
    title: 'تجميد ' + g,
    message: 'تُحفظ النسخة الحالية كاملة في الأرشيف، ولا يُباع شيء من هذه المجموعة حتى تعتمد نسخة جديدة. أول رقم من هذه المجموعة تفتحه يبني النسخة الجديدة، وتنتقل إليها قراراتك (سعرك، اسمك، اختيارك) لما لم يتغير.',
    cancel: 'رجوع',
    ok: 'جمّد'
  }).onOk(() => act(g, 'freeze'))
}
function restore (g, v) {
  Dialog.create({
    title: 'استعادة النسخة ' + v.version + ' من ' + g,
    message: 'تُحفظ النسخة الحالية في الأرشيف، وتعود النسخة ' + v.version + ' كما كانت (' + v.count + ' عرضًا) وتصير هي النشطة.',
    cancel: 'رجوع',
    ok: 'استعد'
  }).onOk(() => act(g, 'restore', String(v.version)))
}
async function drift (o, accept) {
  busy.value = o.id
  try {
    const r = await flexy.ownerOfferDrift(o.id, accept)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
    await load()
  } catch (e) {
    Notify.create({ message: e.message, color: 'negative', position: 'top' })
  } finally {
    busy.value = null
  }
}

function editPrice (o) {
  Dialog.create({
    title: o.nameDisplay,
    message: 'سعر العرض بالدينار (ما يُخصم من رصيد الشريحة). الـPIN لا يُرسل إلا إذا قالت الشبكة نفس السعر.',
    prompt: { model: o.price ? String(o.price) : '', type: 'number', inputmode: 'numeric' },
    cancel: 'رجوع',
    ok: 'حفظ'
  }).onOk((v) => {
    const price = Number(v)
    if (!Number.isInteger(price) || price <= 0) return Notify.create({ message: 'سعر غير صحيح', color: 'negative', position: 'top' })
    save(o, { price })
  })
}

watch(operator, () => { group.value = ''; load() })
onMounted(load)
</script>

<style scoped>
.page { max-width: 760px; margin: 0 auto; }
.card { background: #fff; border: 1px solid #ECEEF3; border-radius: 12px; overflow: hidden; }
.grp { padding: 8px 14px; font-weight: 800; background: #F8FAFC; border-bottom: 1px solid #ECEEF3; }
.offer { display: flex; gap: 8px; align-items: center; padding: 10px 14px; border-top: 1px solid #ECEEF3; }
.offer:first-of-type { border-top: 0; }
.offer.off { opacity: 0.6; }
.drift { margin-top: 6px; background: #FFF7ED; border: 1px solid #FDBA74; border-radius: 8px; padding: 6px 8px; font-size: 12px; color: #9A3412; }
.nm { font-weight: 700; }
.meta { font-size: 11.5px; color: #6B7280; margin-top: 2px; }
.small { font-size: 12px; }
.muted { color: #6B7280; }
</style>
