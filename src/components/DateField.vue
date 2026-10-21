<template>
  <q-input :model-value="model" :label="label" dense outlined readonly clearable stack-label
    placeholder="اختر التاريخ" input-class="ltr text-right" @clear="model = ''">
    <template #append>
      <q-icon name="event" class="cursor-pointer">
        <q-popup-proxy cover transition-show="scale" transition-hide="scale">
          <q-date v-model="model" mask="YYYY-MM-DD" today-btn minimal>
            <div class="row justify-end">
              <q-btn v-close-popup flat color="primary" label="تم" />
            </div>
          </q-date>
        </q-popup-proxy>
      </q-icon>
    </template>
  </q-input>
</template>

<script setup>
// Arabic date picker (the native <input type="date"> showed mm/dd/yyyy)
defineProps({ label: String })
const model = defineModel({ type: String, default: '' })
</script>
