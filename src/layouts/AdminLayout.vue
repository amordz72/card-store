<template>
  <q-layout view="hHh lpR fFf">
    <q-header class="bg-white text-dark" bordered>
      <div class="q-px-md q-pt-sm">
        <!-- Role toggle from the approved mock-up -->
        <div class="role-toggle row no-wrap">
          <q-btn class="col" unelevated no-caps :ripple="false" :class="shopMode ? 'role-idle' : 'role-on'" label="واجهة المدير" to="/admin/customers" />
          <q-btn class="col" unelevated no-caps :ripple="false" :class="shopMode ? 'role-on' : 'role-idle'" label="حساب المحل" to="/admin/shop" />
        </div>
      </div>
      <q-toolbar class="q-py-xs">
        <q-toolbar-title class="column">
          <span class="text-weight-bold">{{ title }}</span>
          <span class="small muted">{{ shopMode ? 'مشترياتك من رصيد المحل' : 'الإدارة' }}</span>
        </q-toolbar-title>
        <template v-if="shopMode">
          <div class="column items-end q-px-sm q-py-xs rounded-borders" style="background:#ECFDF3;color:#15803D">
            <span class="small">رصيد المحل</span>
            <span class="text-weight-bold">{{ shop.hideAmounts ? '••••••' : money(shop.balance) }}</span>
          </div>
          <q-btn round unelevated color="grey-7" class="q-ml-sm" :icon="shop.hideAmounts ? 'visibility_off' : 'visibility'"
            :aria-label="shop.hideAmounts ? 'إظهار المبالغ' : 'إخفاء المبالغ'" @click="shop.toggleHide()" />
        </template>
        <q-btn flat round icon="logout" aria-label="خروج" class="q-ml-xs" @click="logout" />
      </q-toolbar>
    </q-header>

    <q-page-container>
      <router-view />
    </q-page-container>

    <q-footer class="bg-white">
      <BottomNav :items="shopMode ? shopNav : adminNav" />
    </q-footer>
  </q-layout>
</template>

<script setup>
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAdminStore } from 'stores/admin'
import { useShopStore } from 'stores/shop'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import BottomNav from 'components/BottomNav.vue'

const route = useRoute()
const router = useRouter()
const admin = useAdminStore()
const shop = useShopStore()
const { run } = useRun()

const shopMode = computed(() => route.path.startsWith('/admin/shop'))
const adminNav = [
  { to: '/admin/customers', label: 'الزبائن' },
  { to: '/admin/operations', label: 'العمليات' },
  { to: '/admin/transfers', label: 'التحويلات' },
  { to: '/admin/stock', label: 'المخزن' },
  { to: '/admin/prices', label: 'الأسعار' }
]
const shopNav = [
  { to: '/admin/shop', label: 'الرئيسية', exact: true },
  { to: '/admin/shop/store', label: 'المتجر' },
  { to: '/admin/shop/operations', label: 'العمليات' }
]

const TITLES = {
  '/admin/shop': 'حساب المحل', '/admin/shop/store': 'المتجر', '/admin/shop/operations': 'عمليات المحل',
  customers: 'الزبائن', operations: 'العمليات', transfers: 'التحويلات', stock: 'المخزن', prices: 'أسعار الزبائن'
}
const title = computed(() => TITLES[route.path] || TITLES[route.path.split('/')[2]] || 'الإدارة')

watch(shopMode, (on) => { if (on) run(() => shop.refresh()) }, { immediate: true })

async function logout () {
  await admin.logout()
  router.replace('/login')
}
</script>

<style scoped>
.role-toggle { gap: 4px; background: #EEF0F5; border-radius: 12px; padding: 4px; }
.role-toggle .q-btn { height: 40px; border-radius: 9px; font-weight: 600; }
.role-on { background: #fff !important; color: #3730A3 !important; box-shadow: 0 1px 3px rgba(0, 0, 0, .12); }
.role-idle { background: transparent !important; color: #4B5160 !important; }
</style>
