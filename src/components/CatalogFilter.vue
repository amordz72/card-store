<template>
  <div class="column q-gutter-xs">
    <div class="row q-gutter-sm">
      <q-btn v-for="c in cats" :key="c.id" rounded no-caps :ripple="false" :unelevated="cat === c.id" :outline="cat !== c.id"
        :color="cat === c.id ? 'primary' : 'grey-8'" :label="c.label" @click="pickCat(c.id)" />
    </div>
    <div v-if="brands.length > 1" class="row q-gutter-xs">
      <q-btn v-for="b in ['all', ...brands]" :key="b" dense rounded no-caps :ripple="false" size="13px" class="q-px-sm"
        :unelevated="brand === b" :outline="brand !== b" :color="brand === b ? 'indigo-7' : 'grey-7'"
        :label="b === 'all' ? 'كل العلامات' : b" @click="emit('update:brand', b)" />
    </div>
  </div>
</template>

<script setup>
import { CATEGORIES } from 'src/api/format'

// Category chips + brand chips of the chosen category (shared by «المخزن» and «الأسعار»)
defineProps({ cat: { type: String, required: true }, brand: { type: String, required: true }, brands: { type: Array, default: () => [] } })
const emit = defineEmits(['update:cat', 'update:brand'])
const cats = [{ id: 'all', label: 'الكل' }, ...CATEGORIES]
function pickCat (id) {
  emit('update:cat', id)
  emit('update:brand', 'all')
}
</script>
