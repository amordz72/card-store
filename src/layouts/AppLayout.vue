<template>
  <q-layout view="hHh LpR lFf">
    <q-header class="bg-white text-dark" bordered>
      <q-toolbar class="q-py-sm">
        <q-btn flat round icon="menu" aria-label="القائمة" @click="drawer = !drawer" />
        <q-toolbar-title class="column">
          <span class="text-weight-bold">{{ title }}</span>
          <span class="small muted">{{ subtitle }}</span>
        </q-toolbar-title>
        <div class="column items-end q-px-sm q-py-xs rounded-borders" style="background:#ECFDF3;color:#15803D">
          <span class="small">{{ session.isAdmin ? 'رصيد المحل' : 'رصيدك' }}</span>
          <span class="text-weight-bold">{{ buyer.hide.value ? '••••••' : money(buyer.balance.value || 0) }}</span>
        </div>
        <q-btn round unelevated color="grey-7" class="q-ml-sm" :icon="buyer.hide.value ? 'visibility_off' : 'visibility'"
          :aria-label="buyer.hide.value ? 'إظهار المبالغ' : 'إخفاء المبالغ'" @click="buyer.toggleHide()" />
      </q-toolbar>
    </q-header>

    <!-- One menu for everyone; admin-only items are simply not shown to customers -->
    <!-- Closed on phones; always open beside the page on tablets and computers -->
    <q-drawer v-model="drawer" side="left" show-if-above :breakpoint="1024" bordered :width="270">
      <q-list padding>
        <q-item-label header class="text-weight-bold text-dark">{{ subtitle }}</q-item-label>
        <template v-for="g in menu" :key="g.label">
          <q-item-label v-if="g.label" header class="q-pb-xs">{{ g.label }}</q-item-label>
          <q-item v-for="i in g.items" :key="i.to" :to="i.to" :exact="i.exact" clickable active-class="menu-active" :inset-level="i.sub ? 0.4 : 0">
            <q-item-section avatar><q-icon :name="i.icon" /></q-item-section>
            <q-item-section>{{ i.label }}</q-item-section>
          </q-item>
        </template>
        <q-separator class="q-my-sm" />
        <q-item v-if="lock.enabled" clickable @click="lock.lock()">
          <q-item-section avatar><q-icon name="lock" /></q-item-section>
          <q-item-section>قفل الآن</q-item-section>
        </q-item>
        <q-item clickable @click="logout">
          <q-item-section avatar><q-icon name="logout" color="negative" /></q-item-section>
          <q-item-section class="text-negative">خروج</q-item-section>
        </q-item>
      </q-list>
    </q-drawer>

    <LockScreen />

    <q-page-container>
      <router-view />
    </q-page-container>

    <q-footer class="bg-white">
      <QuickBar :items="nav" />
    </q-footer>
  </q-layout>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useQuasar } from 'quasar'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useAdminStore } from 'stores/admin'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import QuickBar from 'components/QuickBar.vue'
import { useMyProfits } from 'src/composables/useMyProfits'
import LockScreen from 'components/LockScreen.vue'
import { useLockStore, markActive } from 'stores/lock'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const customer = useCustomerStore()
const admin = useAdminStore()
const buyer = useBuyer()
const { run } = useRun()
const $q = useQuasar()
const drawer = ref(false)

const subtitle = computed(() => (session.isAdmin ? `المدير · ${admin.email || ''}` : customer.profile?.name || ''))
const title = computed(() => (session.isAdmin && route.path === '/transfers' ? 'التحويلات الواردة' : route.meta.title || 'متجر البطاقات'))

// Items marked admin: true exist only for the owner
const MENU = [
  { items: [{ to: '/', label: 'الرئيسية', icon: 'home', exact: true }] },
  {
    label: 'البطاقات',
    items: [
      { to: '/store', label: 'المتجر', icon: 'storefront' },
      { to: '/stock', label: 'المخزن', icon: 'inventory_2', admin: true },
      { to: '/prices', label: 'أسعار ونسب الزبائن', icon: 'sell', admin: true },
      { to: '/idoom', label: 'تعبئة إيدوم', icon: 'wifi', admin: true }
    ]
  },
  {
    label: 'العمليات',
    items: [
      { to: '/operations', label: 'كل العمليات', icon: 'receipt_long' },
      // kept discreet at the end (owner decision): visible only when the customer earns on some card
      { to: '/profits', label: 'أرباحي في البطاقات', icon: 'savings', customer: true, needsProfit: true }
    ]
  },
  {
    label: 'التحويلات',
    items: [
      { to: '/transfers', label: 'الواردة', icon: 'call_received', exact: true, admin: true, sub: true },
      { to: '/transfers/out', label: 'الصادرة', icon: 'call_made', admin: true, sub: true },
      { to: '/transfers', label: 'التحويلات', icon: 'swap_horiz', customer: true }
    ]
  },
  { label: 'الزبائن', admin: true, items: [{ to: '/customers', label: 'إدارة الحسابات', icon: 'group' }] },
  { label: 'الحساب', items: [{ to: '/account', label: 'حسابي', icon: 'person' }] }
]
const { rows: profitRows } = useMyProfits()
// «أرباحي في البطاقات» only when the customer earns on at least one card
const allowed = (x) => (x.admin ? session.isAdmin : x.customer ? !session.isAdmin && (!x.needsProfit || profitRows.value.length > 0) : true)
const menu = computed(() => MENU.filter(allowed).map((g) => ({ ...g, items: g.items.filter(allowed) })))

// Right to left: two free slots for frequent services (e.g. flexy later), «الرئيسية» in the centre, then cards and operations
const nav = [
  { to: '/transfers', label: 'التحويلات', icon: 'swap_horiz' },
  { to: '/account', label: 'حسابي', icon: 'person' },
  { to: '/', label: 'الرئيسية', icon: 'home', exact: true, home: true },
  { to: '/store', label: 'البطاقات', icon: 'style' },
  { to: '/operations', label: 'العمليات', icon: 'receipt_long' }
]

// on phones the menu closes after choosing a page; on wide screens it stays open
watch(() => route.fullPath, () => { if ($q.screen.width < 1024) drawer.value = false })
const lock = useLockStore()

// Lock after a period WITHOUT USE: any touch, click or key counts as use
let lastWrite = 0
function onActivity () {
  if (lock.locked) return
  const now = Date.now()
  if (now - lastWrite > 15000) { lastWrite = now; markActive() }
}
const onVisible = () => { if (document.visibilityState === 'visible') lock.check() }
const EVENTS = ['pointerdown', 'keydown', 'touchstart', 'wheel']
let timer = null

onMounted(async () => {
  await run(() => buyer.refresh())
  const hasPin = await run(() => (session.isAdmin ? adminApi.lockStatus() : customerApi.lockStatus(customer.token)))
  if (!session.isAdmin) run(() => useMyProfits().load())
  lock.init(session.isAdmin ? 'a:' + (admin.email || '') : 'c:' + (customer.profile?.phone || ''), hasPin)
  EVENTS.forEach((e) => window.addEventListener(e, onActivity, { passive: true }))
  document.addEventListener('visibilitychange', onVisible)
  timer = setInterval(() => lock.check(), 30000)
})
onBeforeUnmount(() => {
  EVENTS.forEach((e) => window.removeEventListener(e, onActivity))
  document.removeEventListener('visibilitychange', onVisible)
  clearInterval(timer)
})

async function logout () {
  await session.logout()
  lock.reset()
  router.replace('/login')
}
</script>

<style scoped>
.menu-active { background: #EEF0FF; color: #3730A3; font-weight: 600; }
</style>
