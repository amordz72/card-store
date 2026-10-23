<template>
  <q-page class="page">
    <!-- Reminder until the account turns the lock on («لاحقًا» hides it for 7 days on this device) -->
    <div v-if="showLockHint" class="card row items-center no-wrap q-gutter-sm" style="background:#FFFBEB;border-color:#FCD34D">
      <q-icon name="lock_open" size="28px" color="warning" />
      <div class="col small" style="color:#92400E">احمِ حسابك: فعّل قفل البرنامج بالبصمة أو برمز، حتى لا يستعمله غيرك إن تركت جهازك مفتوحًا.</div>
      <div class="column q-gutter-xs">
        <q-btn dense unelevated color="warning" label="تفعيل" to="/account" />
        <q-btn dense flat color="grey-8" label="لاحقًا" @click="snoozeLockHint" />
      </div>
    </div>

    <BannerCarousel :banners="banners" />

    <div v-if="announcement" class="card" style="background:#EEF0FF;border-color:#C7CAF5">
      <div class="small text-weight-bold" style="color:#3730A3">إعلان</div>
      <div class="text-subtitle1 text-weight-medium" style="white-space:pre-line">{{ announcement }}</div>
    </div>

    <!-- Customer -->
    <template v-if="!session.isAdmin && p">
      <div class="card row items-center no-wrap">
        <div class="col">
          <div class="row items-center q-gutter-x-sm muted text-weight-medium"><q-icon name="account_balance_wallet" size="24px" /><span>رصيدي</span></div>
          <div class="big-number amount-pos">{{ shown(p.balance) }}</div>
        </div>
        <q-btn v-if="canTopup" round unelevated color="positive" icon="add" size="md" aria-label="شحن رصيدي" @click="topupOpen = true" />
      </div>
      <div class="card">
        <div class="row items-center q-gutter-x-sm muted text-weight-medium"><q-icon name="bookmark_remove" size="24px" /><span>{{ debt.label }}</span></div>
        <div class="big-number" :class="debt.cls">{{ hide ? '••••••' : debt.text }}</div>
        <div class="small muted">حد الدين: {{ money(p.debt_limit) }}</div>
      </div>
      <div class="card">
        <div class="row items-center q-gutter-x-sm muted text-weight-medium"><q-icon name="bookmark_add" size="24px" /><span>أرباحي</span></div>
        <div class="big-number amount-info">{{ shown(p.profit) }}</div>
        <div class="small muted">الفرق بين سعر البيع وما اقتُطع من رصيدك</div>
      </div>
    </template>

    <!-- Owner: the same cards for «حساب المحل», with a period selector -->
    <template v-if="session.isAdmin && row">
      <div class="card row items-center no-wrap">
        <div class="col">
          <div class="row items-center q-gutter-x-sm muted text-weight-medium"><q-icon name="account_balance_wallet" size="24px" /><span>رصيدي</span></div>
          <div class="big-number amount-pos">{{ shown(row.balance) }}</div>
        </div>
        <q-btn round unelevated color="positive" icon="add" size="md" aria-label="شحن رصيد المحل" @click="topupOpen = true" />
      </div>
      <div class="row q-gutter-sm">
        <q-btn v-for="s in SCOPES" :key="s.id" rounded no-caps :ripple="false" :unelevated="scope === s.id" :outline="scope !== s.id"
          :color="scope === s.id ? 'primary' : 'grey-8'" :label="s.label" @click="scope = s.id" />
      </div>
      <div v-if="scope === 'range'" class="card grid-2">
        <DateField v-model="from" label="من تاريخ" />
        <DateField v-model="to" label="حتى تاريخ" />
      </div>
      <div class="card column q-gutter-sm">
        <div class="small muted">{{ scopeHint }}</div>
        <div class="row items-center q-gutter-x-sm muted text-weight-medium"><q-icon name="bookmark_add" size="24px" /><span>أرباحي (سعر البيع − سعر الشراء)</span></div>
        <div class="big-number amount-info">{{ shown(row.real_profit) }}</div>
        <span v-if="Number(row.unknown_cost_orders)" class="small text-warning">{{ row.unknown_cost_orders }} عملية قديمة بلا سعر شراء (غير محسوبة)</span>
        <q-separator />
        <div class="grid-2">
          <div class="column"><span class="small muted">ما شحنته</span><b>{{ shown(row.topups) }}</b></div>
          <div class="column"><span class="small muted">ما استهلكته (سعر الشراء)</span><b style="color:#B45309">{{ shown(row.consumed) }}</b></div>
          <div class="column"><span class="small muted">عدد العمليات</span><b>{{ row.orders_count }}</b></div>
        </div>
      </div>
    </template>

    <div class="grid-2">
      <q-btn color="primary" unelevated size="lg" label="شراء بطاقة" to="/store" />
      <q-btn outline color="primary" size="lg" label="التحويلات" to="/transfers" />
      <q-btn outline color="primary" size="lg" icon="sports_esports" label="شحن الألعاب بالمعرّف" to="/game" />
    </div>
    <q-inner-loading :showing="session.isAdmin ? !row : !p" />
    <TopupDialog v-model="topupOpen" @done="reload" />
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useShopStore } from 'stores/shop'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import * as adminApi from 'src/api/admin'
import { money, dateTime, debtView } from 'src/api/format'
import DateField from 'components/DateField.vue'
import TopupDialog from 'components/TopupDialog.vue'
import BannerCarousel from 'components/BannerCarousel.vue'
import * as customerApi from 'src/api/customer'
import { LocalStorage } from 'quasar'
import { useLockStore } from 'stores/lock'

const session = useSessionStore()
const lock = useLockStore()
const HINT_KEY = 'cs_lock_hint_snooze'
const snoozed = ref(Number(LocalStorage.getItem(HINT_KEY) || 0) > Date.now())
const showLockHint = computed(() => !!lock.accountKey && !lock.enabled && !snoozed.value)
function snoozeLockHint () {
  LocalStorage.set(HINT_KEY, Date.now() + 7 * 24 * 3600 * 1000)
  snoozed.value = true
}
const customer = useCustomerStore()
const shop = useShopStore()
const buyer = useBuyer()
const { run } = useRun()
const hide = computed(() => buyer.hide.value)
const shown = (n) => (hide.value ? '••••••' : money(n))

// customer
const p = computed(() => customer.profile)
const debt = computed(() => debtView(p.value?.debt || 0, true))
// «+» only for a trusted customer who still has room for at least one 500 DZD step under his debt limit
const canTopup = computed(() => !!p.value?.self_topup && Number(p.value.debt_limit) - Number(p.value.debt) >= 500)
const topupOpen = ref(false)
function reload () {
  run(() => (session.isAdmin ? shop.refresh(from.value, to.value) : customer.refresh()))
}

// owner
const SCOPES = [
  { id: 'since_last', label: 'منذ آخر شحن' },
  { id: 'all', label: 'الكل' },
  { id: 'range', label: 'بالتاريخ' }
]
const scope = ref('since_last')
const from = ref('')
const to = ref('')
const row = computed(() => shop.summary?.[scope.value] || null)
const scopeHint = computed(() => {
  const s = shop.summary?.since_last
  if (scope.value === 'since_last') {
    return s?.last_topup_at ? `منذ آخر شحن: ${shown(s.last_topup_amount)} في ${dateTime(s.last_topup_at)}` : 'لا شحن بعد — تُعرض كل العمليات'
  }
  if (scope.value === 'range') return from.value || to.value ? `من ${from.value || 'البداية'} حتى ${to.value || 'اليوم'}` : 'اختر التاريخ'
  return 'منذ البداية'
})
watch([from, to], () => run(() => shop.refresh(from.value, to.value)))

const ownerAnnouncement = ref('')
const announcement = computed(() => (session.isAdmin ? ownerAnnouncement.value : p.value?.announcement))

// Image banners: same list for everyone; a failure here never blocks the home page
const banners = ref([])
async function loadBanners () {
  try {
    banners.value = (session.isAdmin ? await adminApi.liveBanners() : await customerApi.banners(customer.token)) || []
  } catch { banners.value = [] }
}

onMounted(async () => {
  loadBanners()
  if (session.isAdmin) {
    await run(() => shop.refresh(from.value, to.value))
    ownerAnnouncement.value = (await run(() => adminApi.getAnnouncement())) || ''
  } else {
    await run(() => customer.refresh())
  }
})
</script>
