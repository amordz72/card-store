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
        <!-- Bell (owner): open card reports + customers' IDOOM top-ups waiting for review (pattern 18) -->
        <q-btn v-if="session.isAdmin" flat round icon="notifications" class="q-ml-xs" :aria-label="`إعلامات: ${bellTotal}`">
          <q-badge v-if="bellTotal" color="negative" floating rounded :label="bellTotal" />
          <q-menu anchor="bottom end" self="top end">
            <q-list style="min-width:240px">
              <q-item v-close-popup clickable to="/reports">
                <q-item-section avatar><q-icon name="support" /></q-item-section>
                <q-item-section>البلاغات المفتوحة</q-item-section>
                <q-item-section side><q-badge :color="openReports ? 'negative' : 'grey-5'" :label="openReports" /></q-item-section>
              </q-item>
              <q-item v-close-popup clickable to="/idoom">
                <q-item-section avatar><q-icon name="wifi" /></q-item-section>
                <q-item-section>تعبئة إيدوم تحتاج مراجعة</q-item-section>
                <q-item-section side><q-badge :color="idoomReview ? 'negative' : 'grey-5'" :label="idoomReview" /></q-item-section>
              </q-item>
              <q-item v-close-popup clickable to="/flexy/shops">
                <q-item-section avatar><q-icon name="send_to_mobile" /></q-item-section>
                <q-item-section>فليكسي المحلات تحتاج حكمك</q-item-section>
                <q-item-section side><q-badge :color="flexyReview ? 'negative' : 'grey-5'" :label="flexyReview" /></q-item-section>
              </q-item>
              <q-item v-close-popup clickable to="/flexy/devices">
                <q-item-section avatar><q-icon name="router" /></q-item-section>
                <q-item-section>موديمات أو كمبيوترات معطّلة</q-item-section>
                <q-item-section side><q-badge :color="devicesDown ? 'negative' : 'grey-5'" :label="devicesDown" /></q-item-section>
              </q-item>
              <q-item v-close-popup clickable to="/game">
                <q-item-section avatar><q-icon name="sports_esports" /></q-item-section>
                <q-item-section>شحن ألعاب في الانتظار</q-item-section>
                <q-item-section side><q-badge :color="gameWaiting ? 'negative' : 'grey-5'" :label="gameWaiting" /></q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-btn>
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
          <q-item v-for="i in g.items" :key="i.to || i.href" :to="i.to" :href="i.href" :target="i.href ? '_blank' : undefined" :exact="i.exact" clickable active-class="menu-active" :inset-level="i.sub ? 0.4 : 0">
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
      <!-- «↑ للأعلى» on every long page, above the bottom bar -->
      <q-page-scroller position="bottom-right" :scroll-offset="400" :offset="[16, 16]">
        <q-btn fab-mini unelevated color="primary" icon="keyboard_arrow_up" aria-label="للأعلى" />
      </q-page-scroller>
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
import { useBell } from 'src/composables/useBell'
import { useMyProfits } from 'src/composables/useMyProfits'
import LockScreen from 'components/LockScreen.vue'
import { useLockStore, markActive } from 'stores/lock'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import { useIdoomAccess } from 'src/composables/useIdoomAccess'
import { useGameAccess } from 'src/composables/useGameAccess'
import { useFlexyAccess } from 'src/composables/useFlexyAccess'

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
      { to: '/idoom', label: 'تعبئة إيدوم', icon: 'wifi', idoom: true },
      { to: '/game', label: 'شحن الألعاب بالمعرّف', icon: 'sports_esports', game: true },
      { to: '/flexy/shop', label: 'فليكسي', icon: 'send_to_mobile', flexy: true }
    ]
  },
  {
    label: 'العمليات',
    items: [
      { to: '/operations', label: 'كل العمليات', icon: 'receipt_long' },
      { to: '/reports', label: 'البلاغات', icon: 'support', admin: true },
      { to: '/reports', label: 'بلاغاتي', icon: 'support', customer: true },
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
  { label: 'Flexy', admin: true, items: [{ to: '/flexy/send', label: 'إرسال فليكسي', icon: 'send' }, { to: '/flexy/shops', label: 'فليكسي المحلات', icon: 'storefront' }, { to: '/flexy/devices', label: 'المحطات والشرائح', icon: 'router' }, { href: 'https://claude.ai/artifact/7LMGEfJRBcyV9d2LbijxnD', label: 'دليل فهم Flexy', icon: 'menu_book' }, { to: '/flexy', label: 'اختبار Flexy', icon: 'bolt' }] },
  { label: 'الحساب', items: [{ to: '/account', label: 'حسابي', icon: 'person' }] }
]
const { rows: profitRows } = useMyProfits()
// «أرباحي في البطاقات» only when the customer earns on at least one card
// «تعبئة إيدوم»: the owner, and customers the owner enabled
const idoom = useIdoomAccess()
const hasIdoom = computed(() => session.isAdmin || idoom.enabled.value)
// «شحن الألعاب»: everyone except the shop account sees it (customers order, the owner and workers work the queue)
const game = useGameAccess()
// «فليكسي»: shops the owner enabled (the owner sends from «إرسال فليكسي»)
const flexy = useFlexyAccess()
const hasFlexy = computed(() => !session.isAdmin && flexy.enabled.value)
const allowed = (x) => (x.game ? true : x.flexy ? hasFlexy.value : x.idoom ? hasIdoom.value
  : x.admin ? session.isAdmin
    : x.customer ? !session.isAdmin && (!x.needsProfit || profitRows.value.length > 0) : true)
const menu = computed(() => MENU.filter(allowed).map((g) => ({ ...g, items: g.items.filter(allowed) })))

// Right to left: two free slots for frequent services (e.g. flexy later), «الرئيسية» in the centre, then cards and operations
// Whoever has «تعبئة إيدوم» (the owner, enabled customers) gets it in place of «حسابي», still in the side menu
const nav = computed(() => [
  { to: '/transfers', label: 'التحويلات', icon: 'swap_horiz' },
  hasFlexy.value ? { to: '/flexy/shop', label: 'فليكسي', icon: 'send_to_mobile' }
    : hasIdoom.value ? { to: '/idoom', label: 'تعبئة إيدوم', icon: 'wifi' }
    : game.isOperator.value ? { to: '/game', label: 'شحن الألعاب', icon: 'sports_esports' }
      : { to: '/account', label: 'حسابي', icon: 'person' },
  { to: '/', label: 'الرئيسية', icon: 'home', exact: true, home: true },
  { to: '/store', label: 'البطاقات', icon: 'style' },
  { to: '/operations', label: 'العمليات', icon: 'receipt_long' }
])

// on phones the menu closes after choosing a page; on wide screens it stays open
watch(() => route.fullPath, () => { if ($q.screen.width < 1024) drawer.value = false })

// Bell count: refreshed on every page change and every minute (owner only)
const { openReports, idoomReview, gameWaiting, flexyReview, devicesDown, bellTotal, refreshBell } = useBell()
const refreshBellIfAdmin = () => { if (session.isAdmin) refreshBell() }
watch(() => [route.fullPath, session.isAdmin], refreshBellIfAdmin, { immediate: true })
const bellTimer = setInterval(refreshBellIfAdmin, 60000)
onBeforeUnmount(() => clearInterval(bellTimer))
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
  if (!session.isAdmin) { run(() => useMyProfits().load()); idoom.refresh(); game.refresh(); flexy.refresh() }
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
.menu-active { background: #FFF1E8; color: #9A3412; font-weight: 600; }
</style>
