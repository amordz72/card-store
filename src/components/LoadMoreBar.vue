<template>
  <div class="column q-gutter-sm">
    <div class="text-center small muted">{{ total ? `إظهار ${shown} من أصل ${total}` : 'لا نتائج' }}</div>
    <q-btn v-if="shown < total" outline no-caps color="primary" icon="expand_more" class="full-width"
      :label="`تحميل المزيد (${next})`" :loading="loading" @click="$emit('more')" />
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  total: { type: Number, default: 0 },
  shown: { type: Number, default: 0 },
  size: { type: Number, default: 20 },
  loading: { type: Boolean, default: false }
})
defineEmits(['more'])

const next = computed(() => Math.min(props.size, props.total - props.shown))
</script>
