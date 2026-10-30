<template>
  <!-- «الاستعمال» (owner 2026-10-30, card-store v1.44): the pages opened most by the owner and by the shops, and
       each shop's last visit, so the rare pages move aside and a shop that stopped coming shows.
       Counted lightly: one per page per person every 10 minutes; kept 90 days. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />

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
      <div v-for="p in pages" :key="p.page" class="line row items-center no-wrap q-gutter-sm">
        <div class="col">{{ titleOf(p.page) }}<div class="small muted ltr">{{ p.page }}</div></div>
        <div class="text-right small" style="min-width:88px">أنت <b>{{ p.owner }}</b></div>
        <div class="text-right small" style="min-width:110px">المحلات <b>{{ p.shops }}</b><span v-if="p.shop_count" class="muted"> ({{ p.shop_count }})</span></div>
      </div>
    </div>

    <div class="card q-pa-none">
      <div class="section-title q-pa-sm">المحلات</div>
      <div v-for="s in shops" :key="s.id" class="line row items-center no-wrap q-gutter-sm">
        <div class="col text-weight-bold">{{ s.name }}</div>
        <div class="small" :class="stale(s) ? 'text-deep-orange' : 'muted'">{{ s.last_at ? 'آخر دخول ' + ago(s.last_at) : 'لم يدخل بعد' }}</div>
        <div class="small muted" style="min-width:90px">{{ s.top_page ? titleOf(s.top_page) : '' }}</div>
      </div>
    </div>
  </q-page>
</template>

<script setup>
import { onMounted, ref, watch } from 'vue'
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import * as adminApi from 'src/api/admin'
import routes from 'src/router/routes'

// The page's own title from the routes (meta.title), by its path
const TITLES = Object.fromEntries((routes.find((r) => r.path === '/')?.children || [])
  .map((r) => ['/' + r.path, r.meta?.title]).filter(([, t]) => t))
const titleOf = (path) => TITLES[path] || path

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
</script>

<style scoped>
.line { border-top: 1px solid rgba(0, 0, 0, 0.06); padding: 8px 12px; }
.ltr { direction: ltr; text-align: right; }
</style>
