<template>
  <component :is="session.isAdmin ? ServiceQueuePage : MyServicesPage" />
</template>

<script setup>
import { defineAsyncComponent } from 'vue'
import { useSessionStore } from 'stores/session'

// «الخدمات» (owner 2026-10-31): the queue and the services for the owner, his own orders for a customer
const session = useSessionStore()
const ServiceQueuePage = defineAsyncComponent(() => import('pages/admin/ServiceQueuePage.vue'))
const MyServicesPage = defineAsyncComponent(() => import('pages/customer/MyServicesPage.vue'))
</script>
