<template>
  <q-layout view="hHh lpR fFf">
    <q-header class="bg-white text-dark" bordered>
      <q-toolbar class="q-py-sm">
        <q-toolbar-title class="column">
          <span class="text-weight-bold">{{ title }}</span>
          <span v-if="customer.profile" class="small muted">مرحبًا {{ customer.profile.name }}</span>
        </q-toolbar-title>
        <div v-if="customer.profile" class="column items-end q-px-sm q-py-xs rounded-borders" style="background:#ECFDF3;color:#15803D">
          <span class="small">رصيدك</span>
          <span class="text-weight-bold">{{ shown(customer.profile.balance) }}</span>
        </div>
        <q-btn round unelevated color="grey-7" class="q-ml-sm" :icon="customer.hideAmounts ? 'visibility_off' : 'visibility'"
          :aria-label="customer.hideAmounts ? 'إظهار المبالغ' : 'إخفاء المبالغ'" @click="customer.toggleHide()" />
      </q-toolbar>
    </q-header>

    <q-page-container>
      <router-view />
    </q-page-container>

    <q-footer class="bg-white" bordered>
      <q-tabs dense no-caps active-color="primary" class="text-grey-8" indicator-color="transparent">
        <q-route-tab to="/" exact icon="home" label="الرئيسية" />
        <q-route-tab to="/store" icon="storefront" label="المتجر" />
        <q-route-tab to="/operations" icon="receipt_long" label="العمليات" />
        <q-route-tab to="/account" icon="person" label="حسابي" />
      </q-tabs>
    </q-footer>
  </q-layout>
</template>

<script setup>
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'
import { money } from 'src/api/format'

const customer = useCustomerStore()
const route = useRoute()
const { run } = useRun()

const TITLES = { '/': 'الرئيسية', '/store': 'المتجر', '/operations': 'العمليات', '/account': 'حسابي' }
const title = computed(() => TITLES[route.path] || 'متجر البطاقات')
const shown = (n) => (customer.hideAmounts ? '••••••' : money(n))

onMounted(() => run(() => customer.refresh()))
</script>
