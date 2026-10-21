<template>
  <q-layout view="hHh lpR fFf">
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
    <q-drawer v-model="drawer" side="left" overlay behavior="mobile" bordered :width="280">
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
        <q-item clickable @click="logout">
          <q-item-section avatar><q-icon name="logout" color="negative" /></q-item-section>
          <q-item-section class="text-negative">خروج</q-item-section>
        </q-item>
      </q-list>
    </q-drawer>

    <q-page-container>
      <router-view />
    </q-page-container>

    <q-footer class="bg-white">
      <BottomNav :items="nav" />
    </q-footer>
  </q-layout>
</template>

<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useAdminStore } from 'stores/admin'
import { useBuyer } from 'src/composables/useBuyer'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'
import BottomNav from 'components/BottomNav.vue'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const customer = useCustomerStore()
const admin = useAdminStore()
const buyer = useBuyer()
const { run } = useRun()
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
      { to: '/prices', label: 'الأسعار', icon: 'sell', admin: true }
    ]
  },
  { label: 'العمليات', items: [{ to: '/operations', label: 'كل العمليات', icon: 'receipt_long' }] },
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
const allowed = (x) => (x.admin ? session.isAdmin : x.customer ? !session.isAdmin : true)
const menu = computed(() => MENU.filter(allowed).map((g) => ({ ...g, items: g.items.filter(allowed) })))

const nav = [
  { to: '/', label: 'الرئيسية', exact: true },
  { to: '/store', label: 'المتجر' },
  { to: '/operations', label: 'العمليات' },
  { to: '/transfers', label: 'التحويلات' },
  { label: 'القائمة', click: () => { drawer.value = true } }
]

watch(() => route.fullPath, () => { drawer.value = false })
onMounted(() => run(() => buyer.refresh()))

async function logout () {
  await session.logout()
  router.replace('/login')
}
</script>

<style scoped>
.menu-active { background: #EEF0FF; color: #3730A3; font-weight: 600; }
</style>
