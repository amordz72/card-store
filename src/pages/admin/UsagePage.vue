<template>
  <!-- «الاستعمال» (owner 2026-10-30, card-store v1.44): the pages opened most by the owner and by the shops, and
       each shop's last visit, so the rare pages move aside and a shop that stopped coming shows.
       Counted lightly: one per page per person every 10 minutes; kept 90 days. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
    <q-btn-toggle v-model="view" spread unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
      :options="[{ label: 'المؤشرات', value: 'money' }, { label: 'الصفحات', value: 'pages' }]" />
    <ShopIndicators v-if="view === 'money'" />

    <template v-else>
    <div class="row q-gutter-xs">
      <q-btn v-for="d in [1, 7, 30]" :key="d" rounded no-caps :unelevated="days === d" :outline="days !== d"
        :color="days === d ? 'primary' : 'grey-8'" :label="d === 1 ? 'اليوم' : d === 7 ? 'أسبوع' : 'شهر'" @click="days = d" />
      <q-space />
      <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
    </div>
    <div v-if="error" class="small text-negative">{{ error }}</div>

    <div class="card q-pa-none">
      <div class="section-title q-pa-sm">الصفحات</div>
      <div v-if="!pages.length && !busy" class="muted q-pa-md text-center">لم يُسجَّل شيء بعد: يبدأ العدّ من اليوم.</div>
      <div v-for="p in pages.filter((x) => !isInterest(x.page))" :key="p.page" class="line row items-center no-wrap q-gutter-sm">
        <div class="col">{{ titleOf(p.page) }}<div class="small muted ltr">{{ p.page }}</div></div>
        <div class="text-right small" style="min-width:88px">أنت <b>{{ p.owner }}</b></div>
        <div class="text-right small" style="min-width:110px">المحلات <b>{{ p.shops }}</b><span v-if="p.shop_count" class="muted"> ({{ p.shop_count }})</span></div>
      </div>
    </div>

    <!-- What the shops look at without buying (v1.46): brands opened, cards whose sheet opened, searches -->
    <div v-if="interests.length" class="card q-pa-none">
      <div class="section-title q-pa-sm">ما تهتم به المحلات</div>
      <div v-for="p in interests" :key="p.page" class="line row items-center no-wrap q-gutter-sm">
        <q-icon :name="interestOf(p.page).icon" color="grey-7" />
        <div class="col">{{ interestOf(p.page).text }}</div>
        <div class="small text-right" style="min-width:90px"><b>{{ p.shops }}</b> مرة<span v-if="p.shop_count" class="muted"> · {{ p.shop_count }} محل</span></div>
      </div>
    </div>

    <div class="card q-pa-none">
      <div class="section-title q-pa-sm">المحلات · اضغط محلًا لترى أين ذهب</div>
      <template v-for="s in shops" :key="s.id">
        <button type="button" class="line row items-center no-wrap q-gutter-sm shop-btn" @click="openShop(s)">
          <div class="col text-weight-bold">{{ s.name }}</div>
          <div class="small" :class="stale(s) ? 'text-deep-orange' : 'muted'">{{ s.last_at ? 'آخر دخول ' + ago(s.last_at) : 'لم يدخل بعد' }}</div>
          <q-icon :name="opened === s.id ? 'expand_less' : 'expand_more'" color="grey-7" />
        </button>
        <div v-if="opened === s.id" class="q-px-md q-pb-sm">
          <div v-if="shopBusy" class="small muted">يُقرأ…</div>
          <div v-else-if="shopError" class="small text-negative">{{ shopError }}</div>
          <div v-else-if="!shopVisits.length" class="small muted">لا زيارات في هذه المدة.</div>
          <div v-for="v in shopVisits" :key="v.page" class="row items-center no-wrap q-gutter-sm small visit">
            <q-icon :name="isInterest(v.page) ? interestOf(v.page).icon : 'article'" color="grey-6" size="16px" />
            <span class="col">{{ isInterest(v.page) ? interestOf(v.page).text : titleOf(v.page) }}</span>
            <span class="muted">{{ v.visits }}× · {{ ago(v.last_at) }}</span>
          </div>
        </div>
      </template>
    </div>
    </template>
  </q-page>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import SectionTabs from 'src/components/SectionTabs.vue'
import ShopIndicators from 'src/components/ShopIndicators.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import * as adminApi from 'src/api/admin'
import routes from 'src/router/routes'

// The page's own title from the routes (meta.title), by its path
const TITLES = Object.fromEntries((routes.find((r) => r.path === '/')?.children || [])
  .map((r) => ['/' + r.path, r.meta?.title]).filter(([, t]) => t))
const titleOf = (path) => TITLES[path] || path
// «/store/brand:PUBG», «/store/buy:…», «/store/search:…» (v1.46): interests, not pages
const isInterest = (path) => /^\/store\/(brand|buy|search):/.test(path)
function interestOf (path) {
  const [, kind, what] = path.match(/^\/store\/(brand|buy|search):(.*)$/) || []
  if (kind === 'brand') return { icon: 'sell', text: 'فتح علامة: ' + what }
  if (kind === 'buy') return { icon: 'shopping_cart', text: 'فتح شراء: ' + what }
  return { icon: 'search', text: 'بحث عن: ' + what }
}
const interests = computed(() => pages.value.filter((p) => isInterest(p.page) && p.shops > 0).sort((a, b) => b.shops - a.shops).slice(0, 20))
// One shop's visits, page by page (v1.46)
const opened = ref(null)
const shopVisits = ref([])
const shopBusy = ref(false)
const shopError = ref('')
async function openShop (s) {
  if (opened.value === s.id) { opened.value = null; return }
  opened.value = s.id
  shopBusy.value = true
  shopError.value = ''
  try {
    shopVisits.value = (await adminApi.usageShop(s.id, days.value)) || []
  } catch {
    shopError.value = 'لم تُقرأ (طبّق v1.46 من «ينتظر تطبيقك»).'
    shopVisits.value = []
  } finally {
    shopBusy.value = false
  }
}

// «المؤشرات» first (owner 2026-10-30): the money matters more than the pages
const view = ref('money')
const days = ref(7)
const pages = ref([])
const shops = ref([])
const busy = ref(false)
const error = ref('')

async function load () {
  busy.value = true
  error.value = ''
  try {
    const u = await adminApi.usage(days.value)
    pages.value = u?.pages || []
    shops.value = u?.shops || []
  } catch (e) {
    // Before v1.44 is applied
    error.value = 'لم تُقرأ (' + (e.message || 'STORE') + ').'
  } finally {
    busy.value = false
  }
}
function ago (t) {
  const m = Math.round((Date.now() - Date.parse(t)) / 60000)
  if (m < 60) return 'منذ ' + Math.max(m, 1) + ' دقيقة'
  if (m < 1440) return 'منذ ' + Math.round(m / 60) + ' ساعة'
  return 'منذ ' + Math.round(m / 1440) + ' يوم'
}
// No visit for 3 days: orange
const stale = (s) => !s.last_at || Date.now() - Date.parse(s.last_at) > 3 * 86400_000
watch(days, load)
onMounted(load)
watch(view, (v) => { if (v === 'pages') load() })
</script>

<style scoped>
.shop-btn { width: 100%; background: none; border: 0; border-top: 1px solid rgba(0, 0, 0, 0.06); font: inherit; color: inherit; cursor: pointer; text-align: right; }
.visit { padding: 3px 0; }
.line { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 8px 12px; }
.ltr { direction: ltr; text-align: right; }
</style>
