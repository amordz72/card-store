<template>
  <q-layout view="hHh lpR fFf">
    <q-header class="bg-white text-dark" bordered>
      <q-toolbar>
        <q-toolbar-title class="column">
          <span class="text-weight-bold">{{ title }}</span>
          <span class="small muted">الإدارة</span>
        </q-toolbar-title>
        <q-btn flat round icon="logout" aria-label="خروج" @click="logout" />
      </q-toolbar>
    </q-header>

    <q-page-container>
      <router-view />
    </q-page-container>

    <q-footer class="bg-white" bordered>
      <q-tabs dense no-caps active-color="primary" class="text-grey-8" indicator-color="transparent" mobile-arrows outside-arrows>
        <q-route-tab to="/admin/customers" icon="groups" label="الزبائن" />
        <q-route-tab to="/admin/operations" icon="receipt_long" label="العمليات" />
        <q-route-tab to="/admin/transfers" icon="swap_horiz" label="التحويلات" />
        <q-route-tab to="/admin/stock" icon="inventory_2" label="المخزن" />
        <q-route-tab to="/admin/rates" icon="percent" label="النسب" />
      </q-tabs>
    </q-footer>
  </q-layout>
</template>

<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAdminStore } from 'stores/admin'

const route = useRoute()
const router = useRouter()
const admin = useAdminStore()

const TITLES = { customers: 'الزبائن', operations: 'العمليات', transfers: 'التحويلات', stock: 'المخزن', rates: 'نسب الزبائن %' }
const title = computed(() => TITLES[route.path.split('/')[2]] || 'الإدارة')

async function logout () {
  await admin.logout()
  router.replace('/admin/login')
}
</script>
