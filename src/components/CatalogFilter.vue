<template>
  <div class="column q-gutter-xs">
    <div class="row q-gutter-sm">
      <q-btn v-for="c in cats" :key="c.id" rounded no-caps :ripple="false" :unelevated="cat === c.id" :outline="cat !== c.id"
        :color="cat === c.id ? 'primary' : 'grey-8'" :label="c.label" @click="pickCat(c.id)" />
    </div>
    <div v-if="brands.length > 1" class="row q-gutter-xs">
      <q-btn v-for="b in ['all', ...brands]" :key="b" dense rounded no-caps :ripple="false" size="13px" class="q-px-sm"
        :unelevated="brand === b" :outline="brand !== b" :color="brand === b ? 'deep-orange-8' : 'grey-7'"
        :label="b === 'all' ? 'كل العلامات' : b" @click="emit('update:brand', b)" />
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { CATEGORIES } from 'src/api/format'

// Category chips + brand chips of the chosen category (shared by «المخزن» and «الأسعار»)
const props = defineProps({
  cat: { type: String, required: true },
  brand: { type: String, required: true },
  brands: { type: Array, default: () => [] },
  only: { type: Array, default: null }   // show only these categories (e.g. those with profit)
})
const emit = defineEmits(['update:cat', 'update:brand'])
const cats = computed(() => [{ id: 'all', label: 'الكل' }, ...CATEGORIES.filter((c) => !props.only || props.only.includes(c.id))])
function pickCat (id) {
  emit('update:cat', id)
  emit('update:brand', 'all')
}
</script>
