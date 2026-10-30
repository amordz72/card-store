<template>
  <q-layout view="hHh LpR lFf">
    <q-header class="bg-white text-dark" bordered>
      <!-- «مطلوب منك» (owner 2026-10-30): only what waits for his press, the SQL first; above the red bar, never instead of it -->
      <router-link v-if="session.isAdmin && needsYou" :to="needsYou.to" class="monitor-bar bg-indigo-8">
        <q-icon name="build" size="18px" />
        <span class="col">{{ needsYou.text }}</span>
        <span class="text-underline">افتح</span>
      </router-link>
      <!-- «المراقبة» (owner 2026-10-29): admin only, on every page, until solved or «تم» -->
      <router-link v-if="session.isAdmin && monitorBar" to="/flexy/monitor" class="monitor-bar" :class="monitorBar.level === 'down' ? 'bg-negative' : 'bg-orange-9'">
        <q-icon name="warning" size="18px" />
        <span class="col">{{ monitorBar.text }}</span>
        <span class="text-underline">افتح</span>
      </router-link>
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
              <!-- Only what has something (owner 2026-10-26): an empty bell says so in one line -->
              <q-item v-if="!bellTotal && !repoKeyAlert"><q-item-section class="text-grey-7">لا شيء يحتاجك الآن</q-item-section></q-item>
              <q-item v-if="openReports" v-close-popup clickable to="/reports">
                <q-item-section avatar><q-icon name="support" /></q-item-section>
                <q-item-section>البلاغات المفتوحة</q-item-section>
                <q-item-section side><q-badge :color="openReports ? 'negative' : 'grey-5'" :label="openReports" /></q-item-section>
              </q-item>
              <q-item v-if="idoomReview" v-close-popup clickable to="/idoom">
                <q-item-section avatar><q-icon name="wifi" /></q-item-section>
                <q-item-section>تعبئة إيدوم تحتاج مراجعة</q-item-section>
                <q-item-section side><q-badge :color="idoomReview ? 'negative' : 'grey-5'" :label="idoomReview" /></q-item-section>
              </q-item>
              <q-item v-if="monitorAlerts" v-close-popup clickable to="/flexy/monitor">
                <q-item-section avatar><q-icon name="monitor_heart" /></q-item-section>
                <q-item-section>المراقبة: أشياء تحتاجك</q-item-section>
                <q-item-section side><q-badge :color="monitorBar?.level === 'down' ? 'negative' : 'orange-8'" :label="monitorAlerts" /></q-item-section>
              </q-item>
              <q-item v-if="monitorIncidents" v-close-popup clickable to="/flexy/monitor">
                <q-item-section avatar><q-icon name="history" /></q-item-section>
                <q-item-section>حدث أثناء غيابك</q-item-section>
                <q-item-section side><q-badge color="deep-orange" :label="monitorIncidents" /></q-item-section>
              </q-item>
              <q-item v-if="flexyUnrefunded" v-close-popup clickable to="/flexy/shops">
                <q-item-section avatar><q-icon name="money_off" color="negative" /></q-item-section>
                <q-item-section>فليكسي فشل ولم يُرجع للمحل ({{ money(flexyUnrefundedAmount) }})</q-item-section>
                <q-item-section side><q-badge color="negative" :label="flexyUnrefunded" /></q-item-section>
              </q-item>
              <q-item v-if="flexyReview" v-close-popup clickable to="/flexy/shops">
                <q-item-section avatar><q-icon name="send_to_mobile" /></q-item-section>
                <q-item-section>فليكسي المحلات تحتاج حكمك</q-item-section>
                <q-item-section side><q-badge :color="flexyReview ? 'negative' : 'grey-5'" :label="flexyReview" /></q-item-section>
              </q-item>
              <q-item v-if="devicesDown" v-close-popup clickable to="/flexy/devices">
                <q-item-section avatar><q-icon name="router" /></q-item-section>
                <q-item-section>موديمات أو كمبيوترات معطّلة</q-item-section>
                <q-item-section side><q-badge :color="devicesDown ? 'negative' : 'grey-5'" :label="devicesDown" /></q-item-section>
              </q-item>
              <q-item v-if="simAlerts" v-close-popup clickable to="/flexy/devices">
                <q-item-section avatar><q-icon name="sim_card_alert" /></q-item-section>
                <q-item-section>شرائح متوقفة</q-item-section>
                <q-item-section side><q-badge :color="simAlerts ? 'negative' : 'grey-5'" :label="simAlerts" /></q-item-section>
              </q-item>
              <q-item v-if="shopsDown" v-close-popup clickable to="/usage">
                <q-item-section avatar><q-icon name="trending_down" color="negative" /></q-item-section>
                <q-item-section>{{ shopsDown }} {{ shopsDown === 1 ? 'محل انخفض' : 'محلات انخفض' }} استهلاكها هذا الأسبوع</q-item-section>
                <q-item-section side><q-badge color="negative" :label="shopsDown" /></q-item-section>
              </q-item>
              <q-item v-if="agentUpdates" v-close-popup clickable to="/flexy/devices">
                <q-item-section avatar><q-icon name="system_update" color="primary" /></q-item-section>
                <q-item-section>تحديث {{ agentUpdateVersion }} متاح لـ{{ agentUpdates }} {{ agentUpdates === 1 ? 'كمبيوتر' : 'كمبيوترات' }}</q-item-section>
                <q-item-section side><q-badge color="primary" :label="agentUpdates" /></q-item-section>
              </q-item>
              <!-- The station computers' GitHub key (Flexy Core 0042): shown only when dead or ending soon -->
              <q-item v-if="repoKeyAlert" v-close-popup clickable to="/flexy/devices">
                <q-item-section avatar><q-icon name="key_off" /></q-item-section>
                <q-item-section>{{ repoKeyLevel === 'dead' ? 'مفتاح GitHub ميت: الكمبيوترات لا تتحدّث' : 'مفتاح GitHub ينتهي قريبًا' }}</q-item-section>
                <q-item-section side><q-badge :color="repoKeyLevel === 'dead' ? 'negative' : 'orange-8'" label="1" /></q-item-section>
              </q-item>
              <q-item v-if="offerAlerts" v-close-popup clickable to="/flexy/send">
                <q-item-section avatar><q-icon name="alt_route" /></q-item-section>
                <q-item-section>عروض خرجت من المصدر الآخر</q-item-section>
                <q-item-section side><q-badge :color="offerAlerts ? 'negative' : 'grey-5'" :label="offerAlerts" /></q-item-section>
              </q-item>
              <q-item v-if="newReplies" v-close-popup clickable to="/flexy/send">
                <q-item-section avatar><q-icon name="fiber_new" /></q-item-section>
                <q-item-section>ردود وعروض جديدة من الشبكة</q-item-section>
                <q-item-section side><q-badge color="negative" :label="newReplies" /></q-item-section>
              </q-item>
              <q-item v-if="newReplies" v-close-popup clickable to="/flexy/offers">
                <q-item-section avatar><q-icon name="local_offer" /></q-item-section>
                <q-item-section>شاشة العروض (الجديدة تنتظرك)</q-item-section>
              </q-item>
              <q-item v-if="gameWaiting" v-close-popup clickable to="/game">
                <q-item-section avatar><q-icon name="sports_esports" /></q-item-section>
                <q-item-section>شحن ألعاب في الانتظار</q-item-section>
                <q-item-section side><q-badge :color="gameWaiting ? 'negative' : 'grey-5'" :label="gameWaiting" /></q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-btn>
        <!-- «نسخ الشاشة» (owner 2026-10-29): the page as text to paste in the chat instead of a screenshot -->
        <q-btn v-if="canCopyScreen" flat round icon="content_copy" class="q-ml-xs" aria-label="نسخ الشاشة" @click="copyScreen" />
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
      <!-- «إرسال فليكسي» and its phone mode are one page: switching remounts it in the other mode -->
      <router-view :key="$route.path === '/flexy/phone' ? 'flexy-phone' : undefined" />
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
import { copyToClipboard, useQuasar } from 'quasar'
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
// The owner, and his test shop «حساب 2» (owner 2026-10-29: «احربه كعميل»)
const COPY_SCREEN_SHOPS = ['حساب 2']
const canCopyScreen = computed(() => session.isAdmin || COPY_SCREEN_SHOPS.includes(customer.profile?.name))
// Customer numbers leave the screen as «…25» only; amounts stay hidden when hidden
// «نسخ الشاشة» also says when the page is wider than the phone, and which elements make it so (owner 2026-10-30):
// the innermost elements whose box goes past the screen's edges, with their class, size and first words
function widthCheck () {
  const vw = document.documentElement.clientWidth
  const extra = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - vw
  const out = []
  for (const el of document.querySelectorAll('.q-page *, .q-header *')) {
    const r = el.getBoundingClientRect()
    // Quasar's focus helpers are invisible boxes: never the cause
    if (!r.width || (r.right <= vw + 1 && r.left >= -1) || el.classList.contains('q-focus-helper')) continue
    // only the innermost: a child that overflows too explains it better
    if ([...el.children].some((c) => { const k = c.getBoundingClientRect(); return k.width && (k.right > vw + 1 || k.left < -1) })) continue
    const name = el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/).slice(0, 3).join('.') : '')
    out.push(`${name} · ${Math.round(r.width)}px · من ${Math.round(r.left)} إلى ${Math.round(r.right)} · «${(el.innerText || el.value || '').trim().slice(0, 40)}»`)
    if (out.length >= 5) break
  }
  if (extra <= 1 && !out.length) return `✓ العرض سليم (${vw}px)`
  const head = extra > 1 ? `⚠ الصفحة أعرض من الشاشة بـ${extra}px (الشاشة ${vw}px). عناصر تتجاوز الحافة:` : `⚠ عناصر تخرج من حافة الشاشة (الشاشة ${vw}px):`
  return [head, ...out.map((x) => '• ' + x)].join('\n')
}
async function copyScreen () {
  const page = (document.querySelector('.q-page')?.innerText || '') + '\n\n' + widthCheck()
  const text = [
    title.value + ' · ' + new Date().toLocaleString('ar-DZ'),
    session.isAdmin && monitorBar.value ? '⚠ ' + monitorBar.value.text : '',
    page
  ].filter(Boolean).join('\n')
    .replace(/(?:\+?213|0)[5-7](?:\s?\d){8}/g, (m) => '…' + m.replace(/\D/g, '').slice(-2))
    // Icon names (storefront, local_offer…) are not the screen's words
    .split('\n').filter((l) => !/^[a-z_]+$/.test(l.trim())).join('\n')
    .replace(/\n{3,}/g, '\n\n').trim()
  try {
    await copyToClipboard(text)
    $q.notify({ message: 'نُسخت الشاشة: الصقها في المحادثة', color: 'positive', position: 'top', timeout: 1500 })
  } catch {
    $q.notify({ message: 'تعذّر النسخ', color: 'negative', position: 'top' })
  }
}
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
  // Three entries (owner 2026-10-29): sending, watching, and the rare admin pages behind tabs
  { label: 'Flexy', admin: true, items: [{ to: '/flexy/send', label: 'إرسال فليكسي', icon: 'send' }, { to: '/flexy/monitor', label: 'المراقبة', icon: 'monitor_heart' }, { to: '/flexy/shops', label: 'الإدارة', icon: 'admin_panel_settings' }] },
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
  // Owner 2026-10-26, from the right: «فليكسي» in the transfers' place (transfers stay in the side
  // menu), then «تعبئة إيدوم», the home in the middle, the cards and the operations. One bar for both.
  session.isAdmin ? { to: '/flexy/send', label: 'فليكسي', icon: 'send_to_mobile' }
    : hasFlexy.value ? { to: '/flexy/shop', label: 'فليكسي', icon: 'send_to_mobile' }
      : { to: '/transfers', label: 'التحويلات', icon: 'swap_horiz' },
  hasIdoom.value ? { to: '/idoom', label: 'تعبئة إيدوم', icon: 'wifi' }
    : game.isOperator.value ? { to: '/game', label: 'شحن الألعاب', icon: 'sports_esports' }
      : { to: '/account', label: 'حسابي', icon: 'person' },
  { to: '/', label: 'الرئيسية', icon: 'home', exact: true, home: true },
  { to: '/store', label: 'البطاقات', icon: 'style' },
  { to: '/operations', label: 'العمليات', icon: 'receipt_long' }
])

// on phones the menu closes after choosing a page; on wide screens it stays open
watch(() => route.fullPath, () => { if ($q.screen.width < 1024) drawer.value = false })

// Bell count: refreshed on every page change and every minute (owner only)
const { handoverNeeds, sqlPending, approvalsWaiting, shopsDown, agentUpdates, agentUpdateVersion, openReports, idoomReview, gameWaiting, flexyReview, flexyUnrefunded, flexyUnrefundedAmount, devicesDown, offerAlerts, simAlerts, newReplies, repoKeyLevel, repoKeyAlert, monitorBar, monitorAlerts, monitorIncidents, bellTotal, refreshBell } = useBell()
// «مطلوب منك»: the SQL Claude put first, then approvals, a dead GitHub key, Agent updates; one line with the count
const needsYou = computed(() => {
  const items = [
    sqlPending.value && { to: '/stats', text: sqlPending.value === 1 ? '🛠 SQL ينتظر تطبيقك' : `🛠 ${sqlPending.value} أوامر SQL تنتظر تطبيقك` },
    approvalsWaiting.value && { to: '/flexy/devices', text: approvalsWaiting.value === 1 ? 'كمبيوتر جديد ينتظر الاعتماد' : `${approvalsWaiting.value} كمبيوترات تنتظر الاعتماد` },
    repoKeyLevel.value === 'dead' && { to: '/flexy/devices', text: 'مفتاح GitHub ميت: الكمبيوترات لا تتحدّث' },
    handoverNeeds.value && { to: '/ideas?tab=handover', text: `📋 ${handoverNeeds.value} ${handoverNeeds.value === 1 ? 'شيء ينتظرك' : 'أشياء تنتظرك'} في المتابعة` },
    agentUpdates.value && { to: '/flexy/devices', text: `تحديث ${agentUpdateVersion.value} متاح لـ${agentUpdates.value} ${agentUpdates.value === 1 ? 'كمبيوتر' : 'كمبيوترات'}` }
  ].filter(Boolean)
  if (!items.length) return null
  return items.length === 1 ? items[0] : { to: items[0].to, text: items[0].text + ` · و${items.length - 1} ${items.length === 2 ? 'شيء آخر' : 'أشياء أخرى'}` }
})
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
.monitor-bar { display: flex; align-items: center; gap: 8px; padding: 8px 16px; color: #fff; text-decoration: none; font-weight: 600; font-size: 14px; }
.monitor-bar .text-underline { text-decoration: underline; font-size: 13px; }
</style>
