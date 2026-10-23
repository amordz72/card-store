<template>
  <div class="row items-center no-wrap q-gutter-sm">
    <div class="thumb">
      <img v-if="src" :src="src" alt="">
      <q-icon v-else name="image" size="28px" color="grey-5" />
    </div>
    <div class="col column q-gutter-xs">
      <div v-if="label" class="small text-weight-medium">{{ label }}</div>
      <div class="row q-gutter-xs">
        <q-btn dense outline size="sm" color="primary" icon="upload" :label="src ? 'تغيير' : 'رفع صورة'" :loading="busy" @click="picker.click()" />
        <q-btn v-if="src" dense flat size="sm" color="negative" label="حذف" :disable="busy" @click="save(null)" />
      </div>
    </div>
    <input ref="picker" type="file" accept="image/png,image/jpeg,image/webp" hidden @change="pick">
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'

// Upload / replace / remove the image of one brand or product (admin only)
const props = defineProps({
  src: { type: String, default: null },
  kind: { type: String, required: true },   // 'brand' | 'product'
  id: { type: Number, required: true },
  label: { type: String, default: '' }
})
const emit = defineEmits(['saved'])
const { busy, run } = useRun()
const picker = ref(null)

async function save (url) {
  const ok = await run(() => api.setImage(props.kind, props.id, url).then(() => true), { success: url ? 'حُفظت الصورة.' : 'حُذفت الصورة.' })
  if (ok) emit('saved', url)
}

async function pick (e) {
  const file = e.target.files[0]
  e.target.value = ''
  if (!file) return
  const url = await run(() => api.uploadImage(file, props.kind, props.id))
  if (url) await save(url)
}
</script>

<style scoped>
.thumb { width: 64px; height: 64px; border-radius: 8px; border: 1px solid #ECEEF3; background: #fff; overflow: hidden;
  display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
.thumb img { max-width: 100%; max-height: 100%; object-fit: contain; }
</style>
