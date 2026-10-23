<template>
  <q-select :model-value="modelValue" :options="shown" emit-value map-options use-input input-debounce="0" clearable
    dense outlined stack-label label="الولاية" @filter="filter" @update:model-value="(v) => emit('update:modelValue', v ?? null)" />
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { rpc } from 'src/api/rpc'

// Province of a shop, shown as «55 - تقرت»; the list comes from the database (store_wilayas)
defineProps({ modelValue: { type: Number, default: null } })
const emit = defineEmits(['update:modelValue'])
const all = ref([])
const needle = ref('')
const shown = computed(() => all.value.filter((o) => !needle.value || o.label.includes(needle.value)))
function filter (val, update) { update(() => { needle.value = val.trim() }) }
onMounted(async () => {
  const rows = await rpc('store_wilayas').catch(() => [])
  all.value = (rows || []).map((w) => ({ value: w.code, label: `${w.code} - ${w.name_ar}` }))
})
</script>
