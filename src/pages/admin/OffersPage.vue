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
      <div class="grp">{{ g }}</div>
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
const ERRORS = {
  CATALOG_PRICE_REQUIRED: 'اكتب سعر العرض أولًا، ثم افتحه.',
  CATALOG_OFFER_IN_DOUBT: 'رمز هذا العرض ظهر مرتين في القائمة: لا يُفتح حتى نفهمه.',
  CATALOG_NOT_FOUND: 'العرض لم يعد موجودًا: حدّث الصفحة.'
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
const counts = computed(() => ({ new: inGroup.value.filter((o) => o.review).length, active: inGroup.value.filter((o) => !o.review).length }))
const shown = computed(() => inGroup.value.filter((o) => (tab.value === 'new' ? o.review : !o.review)))
const byGroup = computed(() => shown.value.reduce((acc, o) => ({ ...acc, [o.group]: [...(acc[o.group] || []), o] }), {}))
const where = (o) => (o.execPath?.length ? `الصفحة ${o.page} (${o.execPath.map((p) => (p === '0' ? 'المزيد' : p)).join(' ثم ')} ثم ${o.code})` : `الصفحة ${o.page}`)
const who = (v) => (v === 'owner-console' ? 'الإدارة' : v === 'owner-lab' ? 'تجربتك' : v || '—')
const clock = (v) => (v ? new Date(v).toLocaleString('ar-DZ') : '—')

async function load () {
  loading.value = true
  error.value = ''
  try {
    const r = await flexy.ownerOfferCatalog(operator.value)
    if (r.status !== 200 || !r.body?.ok) throw new Error(r.body?.error || 'FLEXY_CORE')
    rows.value = r.body.offers || []
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
.nm { font-weight: 700; }
.meta { font-size: 11.5px; color: #6B7280; margin-top: 2px; }
.small { font-size: 12px; }
.muted { color: #6B7280; }
</style>
