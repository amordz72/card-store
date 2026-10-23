<template>
  <component :is="session.isAdmin ? AdminIdoomPage : CustomerIdoomPage" />
</template>

<script setup>
import { defineAsyncComponent } from 'vue'
import { useSessionStore } from 'stores/session'

// «تعبئة إيدوم»: the owner's full page, or the customer's page (only for customers the owner enabled)
const session = useSessionStore()
const AdminIdoomPage = defineAsyncComponent(() => import('pages/admin/IdoomTopupPage.vue'))
const CustomerIdoomPage = defineAsyncComponent(() => import('pages/customer/IdoomPage.vue'))
</script>
