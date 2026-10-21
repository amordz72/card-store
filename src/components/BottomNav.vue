<template>
  <nav class="bottom-nav row no-wrap q-gutter-xs">
    <q-btn v-for="item in items" :key="item.label" :to="item.to" unelevated no-caps :ripple="false" class="col"
      :class="isActive(item) ? 'bottom-nav__active' : 'bottom-nav__idle'" :label="item.label" :icon="item.icon"
      @click="item.click && item.click()" />
  </nav>
</template>

<script setup>
import { useRoute } from 'vue-router'

// Text buttons with a tinted active background, as in the approved mock-up
defineProps({ items: { type: Array, required: true } })   // [{ to?, label, exact?, click?, icon? }]
const route = useRoute()
const isActive = (item) => !!item.to && (item.exact ? route.path === item.to : route.path === item.to || route.path.startsWith(item.to + '/'))
</script>

<style scoped>
.bottom-nav { background: #fff; border-top: 1px solid #E4E6EC; padding: 6px 6px 10px; }
.bottom-nav .q-btn { height: 48px; border-radius: 10px; font-weight: 600; font-size: 14px; padding: 0 4px; }
.bottom-nav__active { background: #EEF0FF !important; color: #3730A3 !important; }
.bottom-nav__idle { background: transparent !important; color: #4B5160 !important; }
</style>
