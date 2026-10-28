<template>
  <div class="column q-gutter-sm">
    <!-- The line's group (kept, or discovered without money), then its offers: name and price -->
    <div v-if="!phoneOk" class="card text-center muted q-pa-lg">اكتب رقم الزبون لتظهر عروضه.</div>
    <div v-else-if="loading" class="card column items-center q-gutter-sm q-pa-lg">
      <q-spinner color="primary" size="32px" />
      <div class="small muted">جارٍ معرفة نوع خط الزبون… قد يأخذ حتى دقيقة.</div>
    </div>
    <div v-else-if="error" class="card column items-center q-gutter-sm q-pa-lg">
      <div class="small text-negative text-center">{{ error }}</div>
      <q-btn flat no-caps color="primary" icon="refresh" label="أعد المحاولة" @click="load({ retry: true })" />
    </div>
    <!-- Sections come from the offers themselves (owner 2026-10-28): each offer's category (bundle /
         internet); no category = bundle, so an operator without categories (Sama) looks as before. -->
    <template v-else-if="families.length || internet.length">
      <div v-if="families.length" class="card q-pa-none">
        <q-expansion-item v-for="f in families" :key="f.name" :label="f.name" :default-opened="families.length === 1"
          group="families" header-class="family" expand-separator>
          <div v-for="o in f.offers" :key="o.label" class="offer-row" :class="{ busy }" role="button" tabindex="0"
            :aria-disabled="busy" @click="confirm(o)" @keyup.enter="confirm(o)">
            <span class="text-weight-bold">{{ o.label }}<q-badge v-if="o.review" class="q-ml-xs" color="purple-6" label="جديد" /><q-badge v-else-if="o.visibility === 'admin'" class="q-ml-xs" color="amber-8" label="للإدارة" /></span>
            <span class="row items-center no-wrap q-gutter-xs">
              <q-btn v-if="detailOf(o)" flat round dense size="sm" icon="info_outline" aria-label="التفاصيل"
                @click.stop="details(o)" />
              <span class="price">{{ money(o.amount) }}</span>
            </span>
          </div>
        </q-expansion-item>
      </div>
      <div v-if="internet.length" class="card q-pa-none net-card">
        <div class="net-head"><q-icon name="swap_vert" size="18px" /> إنترنت فقط</div>
        <div v-for="o in internet" :key="o.label" class="offer-row net" :class="{ busy }" role="button" tabindex="0"
          :aria-disabled="busy" @click="confirm(o)" @keyup.enter="confirm(o)">
          <span class="column">
            <span class="text-weight-bold">{{ o.label }}</span>
            <span v-if="detailOf(o)" class="small muted">{{ detailOf(o) }}</span>
          </span>
          <span class="price net-price">{{ money(o.amount) }}</span>
        </div>
      </div>
    </template>
    <div v-else-if="looked && !newGroup" class="card text-center muted q-pa-lg">لا توجد عروض متاحة لهذا الرقم الآن.</div>
    <!-- A group none of whose offers is decided yet (Ooredoo, Flexy Core 0060): its offers show above, sellable by the
         owner; the live menu opens by itself below to move through the next pages, each one recorded. -->
    <div v-if="newGroup && !loading" class="card column q-gutter-sm live">
      <div class="text-weight-bold">{{ newGroup.frozen ? '❄️ مجموعة مجمّدة' : '⚡ مجموعة جديدة' }}: {{ newGroup.group || 'غير معروفة' }} · الصفحات التالية</div>
      <div v-if="newGroup.frozen" class="small text-deep-orange">لا يُباع منها شيء حتى تعتمد نسختها الجديدة في شاشة العروض. تنقّل في الصفحات لتُسجَّل.</div>
      <ModemPanel v-if="newGroup.sim" :sim-uuid="newGroup.sim" sim-type="ooredoo-flexy" ussd-only :start-code="'*585*' + phone + '#'" />
      <q-btn flat no-caps color="primary" icon="local_offer" label="شاشة العروض" to="/flexy/offers" />
    </div>
  </div>
</template>

<script setup>
// The offers of one number, shared by the shop page and the owner's page (one UI, two callers):
// `lookup(phone)` answers { status: 'ready' | 'discovering' | …, offers: [{ label, family, amount, available? }] },
// `send(phone, label)` sends one offer and resolves to something truthy when it was accepted for sending;
// `repeatOf(phone, { offer })` names the last operation when it was this same offer to this number.
import { computed, defineAsyncComponent, ref, watch } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'

const props = defineProps({
  phone: { type: String, required: true },
  phoneOk: { type: Boolean, required: true },
  active: { type: Boolean, default: true },
  maxAmount: { type: Number, default: Infinity },
  lookup: { type: Function, required: true },
  send: { type: Function, required: true },
  repeatOf: { type: Function, default: () => null }
})
const emit = defineEmits(['sent'])
// The lab, only for the owner's live session on a new group (never loaded on a shop's page)
const ModemPanel = defineAsyncComponent(() => import('src/components/ModemPanel.vue'))
const newGroup = ref(null)
const { busy, run } = useRun()

// What the customer gets for each offer (shown from «i»). The price is the number in the name.
const DETAILS = {
  'Sama Mix 100': '500Mo — يوم واحد', 'Sama Mix 500': '5Go — 15 يومًا', 'Sama Mix 1000': '15Go — 30 يومًا',
  'Sama Mix 1500': '30Go — 30 يومًا', 'Sama Mix 2000': '50Go — 30 يومًا',
  'Sama Talk 500': '500Mo — 15 يومًا', 'Sama Talk 1000': '2Go — 30 يومًا', 'Sama Talk 1500': '3Go — 30 يومًا',
  'Sama Talk 2000': '4Go — 30 يومًا',
  'Sama Net 500': '10Go — 15 يومًا', 'Sama Net 1000': '30Go — 30 يومًا', 'Sama Net 1500': '60Go — 30 يومًا',
  'Sama Net 2000': '90Go — 30 يومًا',
  'PixX 50': '500Mo — يوم واحد', 'PixX 100': '1Go — يوم واحد', 'PixX 500': '5Go — 15 يومًا',
  'PixX 1000': '13Go — 30 يومًا', 'PixX 2000': '30Go',
  // Djezzy (owner's market screenshots 2026-10-27, «حسب السوق»)
  'LEGEND 50': '24 ساعة · 60 دقيقة نحو جيزي · 10 دقائق نحو الكل'
}
const spaced = (d) => (d || '').replace(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/, '$1 $2 $3 $4 $5')

const loading = ref(false)
const looked = ref(false)
const error = ref('')
const offers = ref([])
let loadedFor = ''
let runId = 0
const group = ref('')

// Prices rising; the catalog's order only between equal prices (owner 2026-10-28: by amount by default)
const byPrice = (a, b) => a.amount - b.amount || (a.order ?? 0) - (b.order ?? 0)
const shown = computed(() => offers.value.filter((x) => x.available !== false && x.amount <= props.maxAmount))
// Bundles: by family in the catalog's order (Mix, Talk, Net…). An offer without a category is a bundle.
const families = computed(() => {
  const out = []
  for (const o of shown.value.filter((x) => x.category !== 'internet')) {
    let f = out.find((x) => x.name === o.family)
    if (!f) out.push(f = { name: o.family, offers: [] })
    f.offers.push(o)
  }
  for (const f of out) f.offers.sort(byPrice)
  return out
})
// Internet only: its own section and colour, never beside a bundle of the same price
const internet = computed(() => shown.value.filter((x) => x.category === 'internet').sort(byPrice))
const detailOf = (o) => DETAILS[o.label] || o.details || ''

// One request; while the core discovers the line, ask again every 3 s (at most 90 s).
// `retry` («أعد المحاولة») asks the core for a new discovery when the last one ended.
let loadingFor = ''
let shownFor = ''
async function load ({ retry = false } = {}) {
  const p = props.phone
  const mine = ++runId
  loadingFor = p
  offers.value = []
  error.value = ''
  looked.value = false
  newGroup.value = null
  loading.value = true
  try {
    let r = await props.lookup(p, { retry })
    for (let i = 0; r?.status === 'discovering' && i < 30 && mine === runId; i++) {
      await new Promise((resolve) => setTimeout(resolve, 3000))
      r = await props.lookup(p)
    }
    if (mine !== runId) return
    if (r?.status === 'ready') {
      loadedFor = p
      offers.value = r.offers || []
      looked.value = true
      group.value = r.group || ''
    } else if (r?.status === 'new_group') {
      loadedFor = p
      looked.value = true
      offers.value = r.offers || []
      group.value = r.group || ''
      newGroup.value = { group: r.group || '', sim: r.sim_uuid || '', frozen: r.frozen === true }
    } else if (r?.status === 'no_offers') {
      // The network said the number takes no offers now: the empty list says it, no error (owner 2026-10-26)
      loadedFor = p
      offers.value = []
      looked.value = true
      group.value = ''
    } else {
      error.value = r?.status === 'discovering' ? 'لم تردّ الشبكة. أعد المحاولة.' : (r?.message || 'تعذّر معرفة نوع خط الزبون الآن.')
    }
  } catch (e) {
    if (mine === runId) error.value = e?.message || 'تعذّر جلب العروض الآن.'
  } finally {
    if (mine === runId) { loading.value = false; loadingFor = ''; shownFor = p }
  }
}

// Opening the tab, or a new number, loads that number's offers. Back on the tab with the same number
// (owner 2026-10-26): a wait still running goes on, an answer or an error stays (its own button retries).
watch(() => [props.active, props.phone, props.phoneOk], () => {
  if (!props.active) return
  if (!props.phoneOk) { runId++; loading.value = false; loadingFor = ''; shownFor = ''; offers.value = []; looked.value = false; error.value = ''; newGroup.value = null; return }
  if (loading.value && loadingFor === props.phone) return
  if (shownFor === props.phone && (looked.value || error.value)) return
  load()
}, { immediate: true })

// After an offer of this number stopped: read its offers again. True when the line's group changed
// (the sale stopped before buying and the core kept the new group): the new offers are now shown.
async function recheck (p) {
  if (p !== props.phone || !props.phoneOk) return false
  const before = group.value
  await load()
  return Boolean(before && group.value && before !== group.value)
}
defineExpose({ recheck })

function details (o) {
  Dialog.create({ title: o.label, message: detailOf(o), ok: 'حسنًا', position: 'bottom' })
}

// One offer at a time: a tap while one is being sent opens nothing
let asking = false
function confirm (o) {
  const p = props.phone
  if (busy.value || asking) return
  if (p !== loadedFor) { load(); return }
  const last = props.repeatOf(p, { offer: o.label })
  asking = true
  Dialog.create({
    title: last ? 'نفس آخر عملية' : 'تأكيد العرض',
    html: true,
    message: `<div dir="ltr" style="font-size:1.6rem;font-weight:700;text-align:center">${spaced(p)}</div>
      ${o.category === 'internet' ? '<div style="text-align:center;margin:4px 0"><span style="background:#ECFEFF;color:#0E7490;border-radius:6px;padding:2px 8px;font-weight:700">إنترنت فقط</span></div>' : ''}
      <div style="text-align:center${o.category === 'internet' ? ';color:#0E7490' : ''}"><b>${o.label}</b>${detailOf(o) ? ' — ' + detailOf(o) : ''}</div>
      <div style="text-align:center">السعر: <b>${money(o.amount)}</b></div>
      <div style="font-size:12px;color:#5B6170;text-align:center">تأكد من الرقم. بعد الإرسال لا يمكن الإلغاء.</div>${last
        ? `<div style="margin-top:8px;padding:8px;border-radius:8px;background:#FFF3E0;color:#BF360C;text-align:center">
            آخر عملية كانت نفس العرض لنفس الرقم (${last.badge.label}).<br><b>أرسل مرة ثانية؟</b></div>`
        : ''}`,
    cancel: 'رجوع',
    ok: last ? 'نعم، أرسل مرة ثانية' : 'نعم، أرسل'
  }).onDismiss(() => { asking = false }).onOk(async () => {
    const r = await run(() => props.send(p, o.label))
    if (r) emit('sent', { phone: p, offer: o, result: r })
  })
}
</script>

<style scoped>
.offer-row { border-top: 1px solid #ECEEF3; padding: 10px 14px; cursor: pointer;
  display: flex; align-items: center; justify-content: space-between; gap: 8px; text-align: right; }
:deep(.family) { font-weight: 700; }
.price { font-weight: 700; white-space: nowrap; }
.offer-row.busy { opacity: 0.5; cursor: default; }
.net-card { border-inline-start: 4px solid #0E7490; }
.net-head { display: flex; align-items: center; gap: 6px; padding: 10px 14px; font-weight: 700; color: #0E7490; }
.net-price { color: #0E7490; }
.live { border: 2px solid #0E7490; padding: 12px; }
</style>
