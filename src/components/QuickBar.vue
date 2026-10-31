<template>
  <!-- Bottom shortcuts: «الرئيسية» in the centre, frequent actions around it (everything else lives in the side menu) -->
  <nav class="quick-bar row no-wrap items-end justify-around">
    <router-link v-for="item in items" :key="item.to" :to="item.to" class="quick-bar__item column items-center no-wrap"
      :class="{ 'quick-bar__item--active': isActive(item), 'quick-bar__item--home': item.home }" :aria-label="item.label">
      <span v-if="item.home" class="quick-bar__home"><q-icon :name="item.icon" size="30px" /></span>
      <q-icon v-else :name="item.icon" size="26px" />
      <span class="quick-bar__label">{{ item.label }}</span>
    </router-link>
  </nav>
</template>

<script setup>
import { useRoute } from 'vue-router'

defineProps({ items: { type: Array, required: true } })   // [{ to, label, icon, exact?, home? }] — first item is the rightmost (RTL)
const route = useRoute()
const isActive = (item) => (item.exact ? route.path === item.to : route.path === item.to || route.path.startsWith(item.to + '/'))
</script>

<style scoped>
.quick-bar { background: #fff; border-top: 1px solid #E4E6EC; border-radius: 22px 22px 0 0; padding: 6px 4px 8px; box-shadow: 0 -2px 10px rgba(0, 0, 0, .05); }
.quick-bar__item { flex: 1; color: #5B6170; text-decoration: none; gap: 2px; min-width: 0; }
.quick-bar__item--active { color: var(--brand-deep, #9A3412); }
.quick-bar__label { font-size: 12px; font-weight: 600; white-space: nowrap; }
.quick-bar__home { width: 56px; height: 56px; border-radius: 50%; margin-top: -26px; background: #4F46E5; color: #fff;
  display: flex; align-items: center; justify-content: center; box-shadow: 0 4px 12px rgba(79, 70, 229, .35); border: 4px solid #fff; }
.quick-bar__item--home:not(.quick-bar__item--active) .quick-bar__home { background: #6366F1; }
</style>
