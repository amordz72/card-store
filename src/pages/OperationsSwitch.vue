<template>
  <component :is="session.isAdmin ? AdminOperationsPage : OperationsPage" />
</template>

<script setup>
import { defineAsyncComponent } from 'vue'
import { useSessionStore } from 'stores/session'

// «العمليات» is one menu item for everyone: the owner also sees his customers' purchases
const session = useSessionStore()
const AdminOperationsPage = defineAsyncComponent(() => import('pages/admin/AdminOperationsPage.vue'))
const OperationsPage = defineAsyncComponent(() => import('pages/customer/OperationsPage.vue'))
</script>
