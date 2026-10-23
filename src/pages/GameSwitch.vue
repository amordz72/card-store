<template>
  <component :is="game.isOperator.value ? GameQueuePage : CustomerGamePage" v-if="ready" />
  <q-inner-loading v-else showing />
</template>

<script setup>
import { defineAsyncComponent, onMounted, ref } from 'vue'
import { useGameAccess } from 'src/composables/useGameAccess'

// «شحن الألعاب»: the queue for the owner and his workers, the order page for customers
const game = useGameAccess()
const ready = ref(false)
const GameQueuePage = defineAsyncComponent(() => import('pages/GameQueuePage.vue'))
const CustomerGamePage = defineAsyncComponent(() => import('pages/customer/GamePage.vue'))
onMounted(async () => { await game.refresh(); ready.value = true })
</script>
