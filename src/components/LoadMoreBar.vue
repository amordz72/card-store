<template>
  <div class="column q-gutter-sm">
    <div class="text-center small muted">{{ label }}</div>
    <q-btn v-if="canMore" outline no-caps color="primary" icon="expand_more" class="full-width"
      :label="`تحميل المزيد (${next})`" :loading="loading" @click="$emit('more')" />
  </div>
</template>

<script setup>
import { computed } from 'vue'

// total null: a list that cannot count all its rows (it then says hasMore)
const props = defineProps({
  total: { type: Number, default: 0 },
  shown: { type: Number, default: 0 },
  size: { type: Number, default: 20 },
  loading: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: null }
})
defineEmits(['more'])

const canMore = computed(() => (props.hasMore ?? props.shown < props.total))
const label = computed(() => {
  if (props.total == null) return props.shown ? `إظهار ${props.shown}` : 'لا نتائج'
  return props.total ? `إظهار ${props.shown} من أصل ${props.total}` : 'لا نتائج'
})
const next = computed(() => (props.total == null ? props.size : Math.min(props.size, props.total - props.shown)))
</script>
