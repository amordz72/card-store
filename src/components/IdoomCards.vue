<template>
  <!-- An Idoom line typed in «تعبئة» (owner 2026-11-01): its cards in short rows, in the same place as the number -->
  <div v-if="isIdoom" class="card column q-gutter-sm">
    <div class="row items-center q-gutter-sm">
      <q-badge :color="is4g ? 'indigo' : 'purple'" class="q-pa-xs">{{ is4g ? 'إيدوم · 4G LTE' : 'إيدوم · ADSL / FTTH' }}</q-badge>
      <q-badge v-if="known" color="primary" class="q-pa-xs"><bdi dir="ltr">{{ known.offer }}</bdi></q-badge>
      <q-space />
      <span v-if="access.enabled.value && !access.phoneOnline.value" class="small text-negative">🔴 متوقفة الآن</span>
    </div>
    <div v-if="!access.enabled.value" class="muted text-center q-pa-sm">تعبئة إيدوم غير مفعّلة لحسابك. اطلب من المحل تفعيلها.</div>
    <template v-else>
      <!-- s170 (owner 2026-11-01): the owner may top up from a suspect card; the line's answer judges it -->
      <q-toggle v-if="owner && suspectTotal" v-model="fromSuspect" color="deep-orange" :label="'من المشكوك فيها (' + suspectTotal + ')'" />
      <button v-for="c in shownCards" :key="c.product_id" type="button" class="idoom-row" :disabled="busy || !access.phoneOnline.value" @click="confirmCharge(c)">
        <span class="col">{{ c.name }}<span v-if="fromSuspect" class="small text-deep-orange"> · مشكوك فيها {{ suspectOf(c) }}</span></span>
        <span class="price">{{ money(c.base_price) }}</span>
      </button>
      <div v-if="!shownCards.length" class="muted text-center q-pa-sm">لا توجد بطاقات {{ is4g ? 'Idoom 4G' : 'Idoom ADSL' }} متوفرة الآن</div>
      <div class="small muted">يُخصم ثمن البطاقة من رصيدك. إن لم تتم التعبئة يُعاد المبلغ تلقائيًا.</div>
    </template>
  </div>
</template>

<script setup>
// The Idoom part of «تعبئة» (owner 2026-11-01, «فليكسي وإيدوم مع بعض»): the same order as «تعبئة إيدوم»
// (store_idoom_create, the same money rule), only shown where the shop types the number. «تعبئة إيدوم» stays
// until the owner has tried this.
//   raw: the digits typed. A fixed line is 9 digits from 01–04 (05–07 is a mobile still being typed);
//   4G is 213 + 9 digits not starting 5–7 (213 6… is a mobile in international form).
import { computed, onMounted, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import { useCustomerStore } from 'stores/customer'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { useIdoomAccess } from 'src/composables/useIdoomAccess'
import * as api from 'src/api/customer'
import * as adminApi from 'src/api/admin'
import { money } from 'src/api/format'

// owner: the owner's own page («تعبئة» for the owner, 2026-11-01): his API, always enabled, the phone's state from its executors
const props = defineProps({ raw: { type: String, default: '' }, owner: { type: Boolean, default: false } })
const emit = defineEmits(['sent'])

const customer = useCustomerStore()
const buyer = useBuyer()
const shopAccess = useIdoomAccess()
const ownerOnline = ref(false)
const access = props.owner
  ? { enabled: ref(true), phoneOnline: ownerOnline, refresh: async () => {
      const list = await adminApi.executors().catch(() => [])
      ownerOnline.value = (list || []).some((p) => p.active && p.last_seen_at && Date.now() - Date.parse(p.last_seen_at) <= 60_000)
    } }
  : shopAccess
const { busy, run } = useRun()

const is4g = computed(() => /^213[0-489]\d{8}$/.test(props.raw))
const isIdoom = computed(() => /^0[1-4]\d{7}$/.test(props.raw) || is4g.value)
const spaced = (d) => (d || '').replace(/^(\d{3})(\d{3})(\d{3})(\d{3})?$/, (m, a, b, c, e) => [a, b, c, e].filter(Boolean).join(' '))

const catalog = ref([])
const cards = computed(() => catalog.value.filter((p) => p.category === 'net' && p.available &&
  /idoom/i.test(p.brand) && /4g|lte/i.test(p.brand + ' ' + p.name) === is4g.value))

// s170: suspect cards per Idoom product (the owner only); empty before s170
const suspectCounts = ref({})
const fromSuspect = ref(false)
const suspectOf = (c) => Number(suspectCounts.value?.[String(c.product_id)] || 0)
const idoomAll = computed(() => catalog.value.filter((p) => p.category === 'net' &&
  /idoom/i.test(p.brand) && /4g|lte/i.test(p.brand + ' ' + p.name) === is4g.value))
const suspectTotal = computed(() => idoomAll.value.reduce((n, c) => n + suspectOf(c), 0))
const shownCards = computed(() => (fromSuspect.value ? idoomAll.value.filter((c) => suspectOf(c) > 0) : cards.value))

const known = ref(null)
watch(() => props.raw, async (want) => {
  known.value = null
  if (!isIdoom.value) return
  const r = await (props.owner ? adminApi.idoomLineInfo(want) : api.idoomLineInfo(customer.token, want)).catch(() => null)
  if (want === props.raw) known.value = r
})

function loadSuspect () { adminApi.suspectCounts().then((v) => { suspectCounts.value = v || {} }).catch(() => { suspectCounts.value = {} }) }
function confirmCharge (c) {
  const line = props.raw
  Dialog.create({
    title: 'تأكيد التعبئة',
    html: true,
    message: `تعبئة الخط <b dir="ltr">${spaced(line)}</b><br>البطاقة: <b>${c.name}</b>${fromSuspect.value ? ' <b style="color:#E65100">من المشكوك فيها</b><br>إن كانت مستعملة تُحسب خاطئة في دفعتها.' : '<br>يُخصم من رصيدك ثمن هذه البطاقة.'}`,
    cancel: 'إلغاء',
    ok: 'نعم، عبّئ'
  }).onOk(async () => {
    const suspect = props.owner && fromSuspect.value
    const r = await run(() => (suspect ? adminApi.idoomCreateSuspect(c.product_id, line, crypto.randomUUID())
      : props.owner ? adminApi.idoomCreate(c.product_id, line, crypto.randomUUID())
        : api.idoomCreate(customer.token, c.product_id, line, crypto.randomUUID())))
    if (r && suspect) loadSuspect()
    if (r) {
      if (!props.owner) buyer.refresh()
      Notify.create({ type: 'positive', message: 'أُرسل الطلب. تابع حالته في «آخر العمليات».', position: 'top' })
      emit('sent')
    }
  })
}

onMounted(async () => {
  await access.refresh()
  if (!access.enabled.value) return
  const data = await (props.owner ? adminApi.shopCatalog() : buyer.catalog()).catch(() => null)
  if (data) catalog.value = data
  if (props.owner) loadSuspect()
})
</script>

<style scoped>
.idoom-row { display: flex; align-items: center; gap: 8px; width: 100%; padding: 6px 12px; border: 1px solid #E3E6EC; border-radius: 10px;
  background: #fff; font: inherit; color: inherit; text-align: right; cursor: pointer; }
.idoom-row:disabled { opacity: 0.5; cursor: default; }
.idoom-row .price { background: var(--q-primary); color: #fff; border-radius: 8px; padding: 3px 8px; font-weight: 700; white-space: nowrap;
  min-width: 76px; text-align: center; }
</style>
