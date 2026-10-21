<template>
  <div class="column q-gutter-sm">
    <div class="row justify-between items-center small muted">
      <span>{{ total ? `إظهار ${from} إلى ${to} من أصل ${total}` : 'لا نتائج' }}</span>
      <q-select v-model="size" :options="[10, 25, 50]" dense outlined options-dense label="أظهر" style="min-width:90px" bg-color="white" />
    </div>
    <nav v-if="pages > 1" aria-label="الصفحات" class="row justify-center q-gutter-xs">
      <q-btn unelevated no-caps color="grey-3" text-color="dark" label="السابق" :disable="page <= 1" @click="page--" />
      <q-btn v-for="n in nums" :key="n" unelevated :color="n === page ? 'primary' : 'grey-3'" :text-color="n === page ? 'white' : 'dark'"
        :label="String(n)" style="min-width:40px" @click="page = n" />
      <q-btn unelevated no-caps color="grey-3" text-color="dark" label="التالي" :disable="page >= pages" @click="page++" />
    </nav>
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
// at most 5 page numbers around the current page
const nums = computed(() => {
  const start = Math.max(1, Math.min(page.value - 2, pages.value - 4))
  return Array.from({ length: Math.min(5, pages.value) }, (_, i) => start + i)
})
</script>
