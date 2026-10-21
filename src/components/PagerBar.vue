<template>
  <div class="column q-gutter-sm">
    <div class="row justify-between items-center small muted">
      <span>{{ total ? `إظهار ${from} إلى ${to} من أصل ${total}` : 'لا نتائج' }}</span>
      <q-select v-model="size" :options="[10, 25, 50]" dense outlined options-dense label="أظهر" style="min-width:90px" bg-color="white" />
    </div>
    <q-pagination v-if="pages > 1" v-model="page" :max="pages" :max-pages="5" direction-links boundary-links
      color="grey-8" active-color="primary" class="self-center" />
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({ total: { type: Number, default: 0 }, shown: { type: Number, default: 0 } })
const page = defineModel('page', { type: Number, default: 1 })
const size = defineModel('size', { type: Number, default: 10 })

const pages = computed(() => Math.max(1, Math.ceil(props.total / size.value)))
const from = computed(() => (page.value - 1) * size.value + 1)
const to = computed(() => from.value + props.shown - 1)
</script>
