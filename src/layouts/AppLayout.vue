<template>
  <q-layout view="hHh LpR lFf" :class="{ 'look-new': lookNew }">
    <q-header class="bg-white text-dark" bordered>

      <!-- Weak internet: started from the home page (startup.js); one press back to where he was going -->
      <div v-if="weakFrom" class="monitor-bar bg-grey-8">
        <q-icon name="network_check" size="18px" />
        <span class="col">الإنترنت ضعيف: بدأنا من الرئيسية</span>
        <a href="#" class="text-underline" @click.prevent="weakBack">ارجع إلى {{ weakFrom.title || 'الصفحة' }}</a>
        <a href="#" class="text-underline" @click.prevent="weakOff">لا تفعل هذا</a>
      </div>
      <q-toolbar class="q-py-sm">
        <q-btn flat round icon="menu" aria-label="القائمة" @click="drawer = !drawer" />
        <!-- «الشكل الجديد» header (look v1): the eye beside the menu, the balance big in the middle, the page's name under it
             (none on the home page), the avatar at the end -->
        <q-btn v-if="lookNew" round unelevated color="grey-6" class="q-ml-xs" :icon="buyer.hide.value ? 'visibility_off' : 'visibility'"
          :aria-label="buyer.hide.value ? 'إظهار المبالغ' : 'إخفاء المبالغ'" @click="buyer.toggleHide()" />
        <q-toolbar-title v-if="lookNew" class="column items-center look-head">
          <span class="look-balance">{{ buyer.hide.value ? '••••••' : money(buyer.balance.value || 0) }}</span>
          <span v-if="route.path !== '/'" class="small muted ellipsis">{{ title }}</span>
        </q-toolbar-title>
        <q-toolbar-title v-if="!lookNew" class="column">
          <span class="text-weight-bold">{{ title }}</span>
          <span class="small muted">{{ subtitle }}</span>
        </q-toolbar-title>
        <div v-if="!lookNew" class="column items-end q-px-sm q-py-xs rounded-borders" style="background:#ECFDF3;color:#15803D">
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
              <q-item v-if="lowStock" v-close-popup clickable to="/stock?tab=low">
                <q-item-section avatar><q-icon name="inventory_2" color="deep-orange" /></q-item-section>
                <q-item-section>{{ lowStock }} {{ lowStock === 1 ? 'بطاقة تكاد تنفد' : 'بطاقات تكاد تنفد' }}</q-item-section>
                <q-item-section side><q-badge color="deep-orange" :label="lowStock" /></q-item-section>
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
              <!-- Services (owner 2026-10-31): named by what it does, «افتح الطلب» -->
              <q-item v-if="serviceWaiting" v-close-popup clickable to="/services">
                <q-item-section avatar><q-icon name="room_service" /></q-item-section>
                <q-item-section>طلبات خدمات تنتظرك · افتح الطلب</q-item-section>
                <q-item-section side><q-badge color="negative" :label="serviceWaiting" /></q-item-section>
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
        <q-btn v-if="!lookNew" round unelevated color="grey-7" class="q-ml-sm" :icon="buyer.hide.value ? 'visibility_off' : 'visibility'"
          :aria-label="buyer.hide.value ? 'إظهار المبالغ' : 'إخفاء المبالغ'" @click="buyer.toggleHide()" />
        <router-link v-if="lookNew" to="/account" class="look-avatar q-ml-sm" :aria-label="subtitle">{{ avatarLetter }}</router-link>
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
        <!-- In reach from every page (owner N12: it was at the bottom of the IDOOM page) -->
        <q-item v-if="session.isAdmin" clickable @click="shareSite">
          <q-item-section avatar><q-icon name="share" /></q-item-section>
          <q-item-section>مشاركة رابط الموقع</q-item-section>
        </q-item>
        <q-item v-if="session.isAdmin" clickable to="/news">
          <q-item-section avatar><q-icon name="new_releases" /></q-item-section>
          <q-item-section>ما الجديد</q-item-section>
          <q-item-section v-if="newsCount" side><q-badge color="purple-6" :label="newsCount" /></q-item-section>
        </q-item>
        <!-- «تثبيت التطبيق» (owner 2026-10-31): the store as a program on a computer or phone, no address bar; hidden once installed -->
        <q-item v-if="!standalone" clickable @click="installApp">
          <q-item-section avatar><q-icon name="install_desktop" /></q-item-section>
          <q-item-section>تثبيت التطبيق</q-item-section>
        </q-item>
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
    <QuickIdea v-if="session.isAdmin" :screen-text="screenText" :page-title="title" />

    <q-footer class="bg-white">
      <!-- Owner 2026-10-31 («ينزلان الشاشة وهما مزعجان»): the admin's red and blue bars live here, right above the bottom
           buttons and outside the page: the content ends above them. On the home page only (owner, same day); the bell still counts them everywhere. Customers have neither. -->
        <!-- «المراقبة» (owner 2026-10-29): admin only, on every page, until solved or «تم» -->
      <!-- Folds like the blue one (owner 2026-10-31): one thin line when folded, the fold kept on this device (localStorage) -->
      <div v-if="session.isAdmin && onHome && monitorBar" class="monitor-bar compact" :class="monitorBar.level === 'down' ? 'bg-negative' : 'bg-orange-9'">
        <q-icon name="warning" size="16px" />
        <router-link to="/flexy/monitor?tab=now" class="col ellipsis text-white" style="text-decoration:none">
          {{ redFolded ? (monitorBar.level === 'down' ? 'المراقبة: عطل يحتاجك' : 'المراقبة: تنبيه') : monitorBar.text }}
        </router-link>
        <button type="button" class="fold-btn" :aria-label="redFolded ? 'افتح الشريط' : 'اطوِ الشريط'" @click="toggleRed">
          <q-icon :name="redFolded ? 'expand_less' : 'expand_more'" size="18px" />
        </button>
      </div>
      <!-- «مطلوب منك» (owner 2026-10-30): only what waits for his press, the SQL first; above the red bar, never instead of it.
           Owner 2026-10-31 («مزعج جدًا وينزل الشاشة»): one thin line always, never more; the count of new ones and of all.
           A press opens the stacked list: the new ones first with «جديد», the old ones stay under them. -->
      <template v-if="session.isAdmin && onHome && needsYou.length">
        <button type="button" class="monitor-bar compact bg-indigo-8 more needs-line" aria-label="ما ينتظرك">
          <q-icon name="build" size="16px" />
          <span class="col ellipsis">
            <b v-if="needsNew">{{ needsNew }} {{ needsNew === 1 ? 'جديد' : 'جديدة' }} · </b>{{ needsYou.length }} {{ needsYou.length === 1 ? 'شيء ينتظرك' : 'أشياء تنتظرك' }}
          </span>
          <q-icon name="expand_less" size="18px" />
          <q-menu fit anchor="top middle" self="bottom middle" @before-show="snapNeeds(); loadSqlRows()" @show="markNeedsSeen">
            <q-list dense separator class="needs-list">
              <template v-for="it in needsList" :key="it.text">
                <!-- Owner 2026-10-31: what waits for one press is done here, in the fixed notification («طبّق»), no page to open -->
                <template v-if="it.sql && sqlRows.length">
                  <q-item v-for="r in sqlRows" :key="r.uid">
                    <q-item-section>
                      <q-item-label>🛠 {{ r.title }} <q-badge v-if="it.isNew" color="purple-6" label="جديد" /></q-item-label>
                      <q-item-label v-if="r.error" caption class="text-negative">{{ r.error }}</q-item-label>
                      <q-item-label v-else caption>SQL ينتظر تطبيقك</q-item-label>
                    </q-item-section>
                    <q-item-section side>
                      <q-btn dense unelevated no-caps color="primary" label="طبّق" :loading="sqlBusy === r.uid" :disable="Boolean(sqlBusy)" @click.stop="applySql(r)" />
                    </q-item-section>
                  </q-item>
                </template>
                <q-item v-else v-close-popup clickable :to="it.to">
                  <q-item-section>
                    <q-item-label>{{ it.text }} <q-badge v-if="it.isNew" color="purple-6" label="جديد" /></q-item-label>
                    <q-item-label caption>{{ it.where }}</q-item-label>
                  </q-item-section>
                  <q-item-section side><q-icon name="chevron_left" /></q-item-section>
                </q-item>
              </template>
            </q-list>
          </q-menu>
        </button>
      </template>
      <!-- «ما الجديد» (owner 2026-10-31): a fixed line while something is new on this device; the page marks it seen -->
      <router-link v-if="session.isAdmin && onHome && newsCount" to="/news" class="monitor-bar compact bg-purple-7 news-line">
        <q-icon name="new_releases" size="16px" /><span class="col ellipsis">🆕 {{ newsCount }} {{ newsCount === 1 ? 'جديد' : 'جديدة' }} في البرنامج: ما الجديد</span>
        <q-icon name="chevron_left" size="18px" />
      </router-link>
      <QuickBar :items="nav" />
    </q-footer>
  </q-layout>
</template>

<script setup>
import { claudePageText, CLAUDE_REMINDER } from 'src/composables/useClaudeCopy'
import QuickIdea from 'src/components/QuickIdea.vue'
import { weakFrom, setWeakHome } from 'src/api/weakHome'
import { perfUnsent, perfMarkSent } from 'src/api/perfLog'
import * as flexyApi from 'src/api/flexy'
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
import { unseenNews, newsSeenRef } from 'src/composables/useNews'
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
// Owner 2026-10-31 «عمّم الشكل»: the new look for everyone (the old one stays in main history at 1f74987)
const lookNew = computed(() => true)
const onHome = computed(() => route.path === '/')
// The red bar's fold, kept on this device across visits (owner 2026-10-31)
const RED_FOLD_KEY = 'cs_red_bar_folded'
const redFolded = ref((() => { try { return localStorage.getItem(RED_FOLD_KEY) === '1' } catch { return false } })())
function toggleRed () {
  redFolded.value = !redFolded.value
  try { localStorage.setItem(RED_FOLD_KEY, redFolded.value ? '1' : '0') } catch { /* private mode */ }
}
const avatarLetter = computed(() => (session.isAdmin ? 'م' : (customer.profile?.name || '؟').trim().charAt(0)))
const customer = useCustomerStore()
const admin = useAdminStore()
const buyer = useBuyer()
const { run } = useRun()
const $q = useQuasar()
const drawer = ref(false)

const subtitle = computed(() => (session.isAdmin ? `المدير · ${admin.email || ''}` : customer.profile?.name || ''))
// The owner, and his test shop «حساب 2» (owner 2026-10-29: «احربه كعميل»)
// Owner 2026-10-31: administration and development tools are for the admin only, with no exception by account name
// (the «حساب 2» exception was removed: a name can be given to any account).
const canCopyScreen = computed(() => session.isAdmin)
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
  // And the height (owner 2026-10-30: «لماذا لم يكتشف عيب الطول»): an empty space of 150px or more between two shown
  // elements, said with its size and what comes before it
  const gaps = []
  for (const el of document.querySelectorAll('.q-page, .q-page *')) {
    const kids = [...el.children].map((c) => ({ c, r: c.getBoundingClientRect() })).filter((k) => k.r.height > 0 && k.r.width > 0)
      .sort((a, b) => a.r.top - b.r.top)
    // Empty at its own end, after its last shown child (a box taller than what it holds); a page-tall box by design is not
    const cs = getComputedStyle(el)
    if (kids.length && !el.classList.contains('q-page') && (cs.minHeight === '0px' || cs.minHeight === 'auto')) {
      const tail = Math.round(el.getBoundingClientRect().bottom - Math.max(...kids.map((k) => k.r.bottom)) - parseFloat(cs.paddingBottom || '0'))
      if (tail >= 150) {
        const last = kids[kids.length - 1].c
        gaps.push(`فراغ ${tail}px في آخر ${el.tagName.toLowerCase()}${typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : ''} بعد «${(last.innerText || '').trim().replace(/\s+/g, ' ').slice(-40)}»`)
      }
    }
    for (let i = 1; i < kids.length; i++) {
      const prevBottom = Math.max(...kids.slice(0, i).map((k) => k.r.bottom))
      const gap = Math.round(kids[i].r.top - prevBottom)
      if (gap < 150) continue
      const before = kids[i - 1].c
      const name = before.tagName.toLowerCase() + (typeof before.className === 'string' && before.className.trim() ? '.' + before.className.trim().split(/\s+/).slice(0, 2).join('.') : '')
      gaps.push(`فراغ ${gap}px بعد ${name} «${(before.innerText || '').trim().replace(/\s+/g, ' ').slice(-40)}» (داخل ${el.tagName.toLowerCase()}${typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/)[0] : ''})`)
      if (gaps.length >= 5) break
    }
    if (gaps.length >= 5) break
  }
  const gapText = gaps.length ? ['⚠ فراغات في الطول:', ...gaps.map((x) => '• ' + x)].join('\n') : ''
  if (extra <= 1 && !out.length) return gapText ? `✓ العرض سليم (${vw}px)\n${gapText}` : `✓ العرض سليم (${vw}px) · ✓ لا فراغات`
  const head = extra > 1 ? `⚠ الصفحة أعرض من الشاشة بـ${extra}px (الشاشة ${vw}px). عناصر تتجاوز الحافة:` : `⚠ عناصر تخرج من حافة الشاشة (الشاشة ${vw}px):`
  return [head, ...out.map((x) => '• ' + x), gapText].filter(Boolean).join('\n')
}
// The page as text (the same for «نسخ الشاشة» and the 💡 «أرفق هذه الشاشة»)
// A page with tabs (.hub-panel): every tab, the hidden ones shown for the time of reading (owner 2026-10-30:
// «نسخة واحدة للكل»)
function pageText () {
  const page = document.querySelector('.q-page')
  if (!page) return ''
  const panels = [...page.querySelectorAll('.hub-panel')]
  if (!panels.length) return page.innerText || ''
  const head = page.querySelector('.hub-head')?.innerText || ''
  return [head, ...panels.map((el) => {
    const hidden = el.style.display === 'none'
    if (hidden) el.style.display = ''
    try { return '### ' + (el.dataset.title || '') + '\n' + el.innerText } finally { if (hidden) el.style.display = 'none' }
  })].join('\n\n')
}
function screenText () {
  const page = pageText() + '\n\n' + widthCheck() + claudePageText()
  return [
    CLAUDE_REMINDER,
    title.value + ' · ' + new Date().toLocaleString('ar-DZ'),
    session.isAdmin && monitorBar.value ? '⚠ ' + monitorBar.value.text : '',
    page
  ].filter(Boolean).join('\n')
    .replace(/(?:\+?213|0)[5-7](?:\s?\d){8}/g, (m) => '…' + m.replace(/\D/g, '').slice(-2))
    // Icon names (storefront, local_offer…) are not the screen's words
    .split('\n').filter((l) => !/^[a-z_]+$/.test(l.trim())).join('\n')
    .replace(/\n{3,}/g, '\n\n').trim()
}
async function copyScreen () {
  const text = screenText()
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
      { to: '/services', label: 'الخدمات', icon: 'room_service' },
      { to: '/flexy/shop', label: 'تعبئة', icon: 'send_to_mobile', flexy: true }
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
  { label: 'Flexy', admin: true, items: [{ to: '/flexy/send', label: 'إرسال فليكسي', icon: 'send' }, { to: '/flexy/monitor', label: 'المراقبة والإحصائيات', icon: 'monitor_heart' }, { to: '/flexy/shops', label: 'الإدارة', icon: 'admin_panel_settings' },
    // Owner's idea #1 (2026-10-30): a direct way to the ideas; the statistics are a tab of «المراقبة» now
    { to: '/ideas', label: 'أفكار وأوامر', icon: 'lightbulb' }] },
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
    : hasFlexy.value ? { to: '/flexy/shop', label: 'تعبئة', icon: 'send_to_mobile' }
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
const { lowStock, automixAlert, failuresOpen, reviewWaiting, handoverNeeds, sqlPending, approvalsWaiting, shopsDown, agentUpdates, agentUpdateVersion, openReports, idoomReview, gameWaiting, serviceWaiting, flexyReview, flexyUnrefunded, flexyUnrefundedAmount, devicesDown, offerAlerts, simAlerts, newReplies, repoKeyLevel, repoKeyAlert, monitorBar, monitorAlerts, monitorIncidents, bellTotal, refreshBell } = useBell()
// «مطلوب منك»: the SQL Claude put first, then approvals, a dead GitHub key, Agent updates; one line with the count
const JUDGE = '/flexy/monitor?tab=judge'
const DB = '/flexy/monitor?tab=db'
const WHERE_JUDGE = 'المراقبة ← حكمك والفشل'
const WHERE_DB = 'المراقبة ← القاعدة وSQL'
const needsYou = computed(() => {
  return [
    // The SQL first (owner 2026-10-30: «ما ينتظر تطبيقك يُقال مقدمًا على كل شيء»), then what may have moved money
    sqlPending.value && { sql: true, to: DB, where: WHERE_DB, text: sqlPending.value === 1 ? '🛠 SQL ينتظر تطبيقك' : `🛠 ${sqlPending.value} أوامر SQL تنتظر تطبيقك` },
    reviewWaiting.value && { to: JUDGE, where: WHERE_JUDGE, text: reviewWaiting.value === 1 ? '⚖ عملية تحتاج حكمك (وصلت أم لا؟)' : `⚖ ${reviewWaiting.value} عمليات تحتاج حكمك (وصلت أم لا؟)` },
    automixAlert.value && { to: JUDGE, where: WHERE_JUDGE, text: `⚠ الأوتوميكس فشل اليوم ${automixAlert.value.pct}% (${automixAlert.value.failed} من ${automixAlert.value.total}): راجعه` },
    failuresOpen.value && { to: JUDGE, where: WHERE_JUDGE, text: failuresOpen.value === 1 ? '🔴 فشل بلا حل ينتظرك' : `🔴 ${failuresOpen.value} فشل بلا حل تنتظرك` },
    approvalsWaiting.value && { to: '/flexy/devices', where: 'الأجهزة', text: approvalsWaiting.value === 1 ? 'كمبيوتر جديد ينتظر الاعتماد' : `${approvalsWaiting.value} كمبيوترات تنتظر الاعتماد` },
    repoKeyLevel.value === 'dead' && { to: '/flexy/devices', where: 'الأجهزة', text: 'مفتاح GitHub ميت: الكمبيوترات لا تتحدّث' },
    handoverNeeds.value && { to: '/ideas?tab=handover', where: 'أفكار وأوامر ← ينتظرك', text: `📋 ${handoverNeeds.value} ${handoverNeeds.value === 1 ? 'شيء ينتظرك' : 'أشياء تنتظرك'} في المتابعة` },
    agentUpdates.value && { to: '/flexy/devices', where: 'الأجهزة', text: `تحديث ${agentUpdateVersion.value} متاح لـ${agentUpdates.value} ${agentUpdates.value === 1 ? 'كمبيوتر' : 'كمبيوترات'}` }
  ].filter(Boolean)
})
// Owner 2026-10-31: the line says how many are new; «new» = not seen in the list on this device yet (an item whose
// text changed, e.g. its count, is new again). The badges stay as they were while the list is open.
const NEEDS_SEEN_KEY = 'cs_needs_seen'
const needsSeen = ref((() => { try { return JSON.parse(localStorage.getItem(NEEDS_SEEN_KEY) || '[]') } catch { return [] } })())
const needsNew = computed(() => needsYou.value.filter((x) => !needsSeen.value.includes(x.text)).length)
const openNew = ref([])
function snapNeeds () { openNew.value = needsYou.value.filter((x) => !needsSeen.value.includes(x.text)).map((x) => x.text) }
function markNeedsSeen () {
  needsSeen.value = [...new Set([...needsYou.value.map((x) => x.text), ...needsSeen.value])].slice(0, 200)
  try { localStorage.setItem(NEEDS_SEEN_KEY, JSON.stringify(needsSeen.value)) } catch { /* private mode */ }
}
const needsList = computed(() => {
  const list = needsYou.value.map((x) => ({ ...x, isNew: openNew.value.includes(x.text) }))
  return [...list.filter((x) => x.isNew), ...list.filter((x) => !x.isNew)]
})
// Not while the page is hidden (2026-10-30, the database's load): a phone in a pocket asks nothing
// «تثبيت التطبيق»: Chrome/Edge offer the install (beforeinstallprompt); elsewhere, how to do it by hand
const standalone = ref(window.matchMedia?.('(display-mode: standalone)').matches || window.navigator.standalone === true)
let installEvent = null
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); installEvent = e })
window.addEventListener('appinstalled', () => { standalone.value = true; installEvent = null })
async function installApp () {
  if (installEvent) {
    installEvent.prompt()
    try { await installEvent.userChoice } catch { /* closed */ }
    installEvent = null
    return
  }
  $q.dialog({
    title: 'تثبيت التطبيق',
    message: 'على الكمبيوتر (Chrome أو Edge): اضغط زر التثبيت في آخر شريط العنوان، أو القائمة ⋮ ثم «تثبيت التطبيق».\n' +
      'على الهاتف (Chrome): القائمة ⋮ ثم «إضافة إلى الشاشة الرئيسية». على iPhone (Safari): زر المشاركة ثم «إضافة إلى الشاشة الرئيسية».\n' +
      'بعدها يفتح المتجر كبرنامج، بلا شريط عنوان.',
    ok: 'حسنًا',
    style: 'white-space: pre-line'
  })
}
// «طبّق» in the fixed notification: the waiting SQL listed by name, each applied here (the same server path as the page)
const sqlRows = ref([])
const sqlBusy = ref('')
async function loadSqlRows () {
  if (!sqlPending.value) { sqlRows.value = []; return }
  try {
    const r = await flexyApi.ownerSql()
    const b = r?.body
    if (r?.status !== 200 || !b?.ok) return
    const nameOf = (m) => { const first = (String(m.sql || '').split('\n').find((l) => l.startsWith('--')) || '').replace(/^--\s*/, ''); const q = first.match(/«([^»]{3,60})»/); return q ? q[1] : (first.split(/[(:]/)[0].trim().slice(0, 60) || m.key) }
    sqlRows.value = [
      ...(b.migrations || []).map((m) => ({ uid: 'm' + m.key, mig: m.key, title: m.key + ' · ' + nameOf(m) })),
      ...(b.pending?.open || []).map((p) => ({ uid: 'p' + p.id, id: p.id, title: p.title }))
    ]
  } catch { /* the line still opens the page */ }
}
function applySql (r) {
  $q.dialog({ title: 'طبّق: ' + r.title, message: 'ينفّذ كل الأوامر معًا. إن فشل أحدها لا يتغيّر شيء. متابعة؟', cancel: 'لا', ok: 'نعم، طبّق' }).onOk(async () => {
    sqlBusy.value = r.uid
    try {
      const res = await (r.mig ? flexyApi.applyMigration(r.mig) : flexyApi.applyPending(r.id))
      const b = res?.body
      if (res?.status === 200 && b?.ok !== false) {
        $q.notify({ type: 'positive', message: '✓ طُبّق: ' + r.title, position: 'top' })
        sqlRows.value = sqlRows.value.filter((x) => x.uid !== r.uid)
        refreshBell()
      } else {
        r.error = '✗ لم يُطبَّق: ' + (b?.message || b?.error || res?.status)
        sqlRows.value = [...sqlRows.value]
      }
    } catch (e) {
      r.error = '✗ لم يُطبَّق: ' + (e?.message || 'لا اتصال')
      sqlRows.value = [...sqlRows.value]
    } finally {
      sqlBusy.value = ''
    }
  })
}
// «ما الجديد»: lines this device has not seen yet
const newsCount = computed(() => { void newsSeenRef.value; return unseenNews() })
// The one official link (owner setting «الرابط الرسمي», else the built-in one), by the phone's share sheet or copied
async function shareSite () {
  let url = adminApi.DEFAULT_OFFICIAL_SITE
  try { const l = await adminApi.siteLinks(); if (l?.officialUrl) url = l.officialUrl } catch { /* the built-in link */ }
  if (navigator.share) {
    try { await navigator.share({ title: 'متجر البطاقات', text: url }) } catch { /* closed */ }
    return
  }
  await copyToClipboard(url)
  $q.notify({ message: 'نُسخ رابط الموقع', color: 'positive', position: 'top', timeout: 1500 })
}
const refreshBellIfAdmin = () => { if (session.isAdmin && document.visibilityState === 'visible') refreshBell() }
document.addEventListener('visibilitychange', refreshBellIfAdmin)
watch(() => [route.fullPath, session.isAdmin], refreshBellIfAdmin, { immediate: true })
const bellTimer = setInterval(refreshBellIfAdmin, 60000)
function weakBack () { const to = weakFrom.value.path; weakFrom.value = null; router.push(to) }
function weakOff () {
  setWeakHome(false)
  $q.notify({ message: 'لن ننقلك بعد الآن. تعيده من «حسابي».', position: 'top', timeout: 2500 })
  weakBack()
}
watch(() => route.path, (p) => { if (p !== '/') weakFrom.value = null })
// «سجل البطء»: the owner's phone sends what is new every 5 minutes, and when the internet comes back
async function sendPerf () {
  if (!session.isAdmin || !navigator.onLine) return
  const list = perfUnsent()
  if (!list.length) return
  const r = await flexyApi.ownerPerf(list).catch(() => null)
  if (r?.status === 200 && r.body?.ok) perfMarkSent(list[list.length - 1].at)
}
const perfTimer = setInterval(sendPerf, 5 * 60000)
setTimeout(sendPerf, 30000)
window.addEventListener('online', sendPerf)
onBeforeUnmount(() => { clearInterval(perfTimer); window.removeEventListener('online', sendPerf) })
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
.menu-active { background: var(--brand-soft, #FFF1E8); color: var(--brand-deep, #9A3412); font-weight: 600; }
.monitor-bar { display: flex; align-items: center; gap: 8px; padding: 8px 16px; color: #fff; text-decoration: none; font-weight: 600; font-size: 14px; }
.monitor-bar + .monitor-bar { border-top: 1px solid rgba(255, 255, 255, 0.2); }
.monitor-bar.compact { padding: 5px 12px; font-size: 13px; min-height: 30px; }
.monitor-bar .where { font-weight: 400; font-size: 12px; opacity: 0.85; }
.monitor-bar.more { width: 100%; border: 0; font: inherit; font-size: 13px; cursor: pointer; justify-content: center; }
.monitor-bar .text-underline { text-decoration: underline; font-size: 13px; }
.needs-line { justify-content: flex-start; text-align: start; }
.fold-btn { background: none; border: 0; color: #fff; cursor: pointer; padding: 0 2px; display: flex; align-items: center; }
.needs-list { max-height: 60vh; overflow-y: auto; }
</style>
