<template>
  <!-- «منصة topup-dz» (owner 2026-11-01, s178): the API key typed here, kept encrypted in Vault, never shown again -->
  <div class="column q-gutter-sm q-pa-md">
    <div v-if="missing" class="small text-negative">طبّق s178 من «ينتظر تطبيقك» أولًا.</div>
    <template v-else>
      <div v-if="info" class="row items-center q-gutter-sm">
        <q-badge color="positive" class="q-pa-sm">✓ محفوظ · آخره <bdi dir="ltr" class="q-ml-xs">…{{ info.last4 }}</bdi></q-badge>
        <span class="small muted">{{ dateTime(info.saved_at) }}</span>
        <q-space />
        <q-btn flat dense no-caps color="negative" label="احذفه" :disable="busy" @click="clear" />
      </div>
      <div v-else class="small muted">لا يوجد مفتاح محفوظ.</div>
      <q-input v-model="key" dense outlined :type="show ? 'text' : 'password'" autocomplete="off" input-class="ltr"
        :label="info ? 'استبدل المفتاح (API TOKEN)' : 'المفتاح (API TOKEN)'">
        <template #append><q-icon :name="show ? 'visibility_off' : 'visibility'" class="cursor-pointer" @click="show = !show" /></template>
      </q-input>
      <q-btn unelevated no-caps color="primary" icon="lock" label="احفظ" :loading="busy" :disable="key.trim().length < 8" @click="save" />
      <div class="small muted">يُحفظ مشفّرًا في خزنة Supabase ولا يظهر بعد الحفظ، حتى لك. «السماح لكل الايبيات» يبقى في موقع topup-dz.</div>
    </template>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import { dateTime } from 'src/api/format'

const PLATFORM = 'topup-dz'
const { busy, run } = useRun()
const key = ref('')
const show = ref(false)
const info = ref(null)
const missing = ref(false)

async function load () {
  try {
    info.value = (await api.platformKeys())?.[PLATFORM] || null
  } catch (e) {
    missing.value = /store_admin_platform_keys/.test(e?.message || '')
  }
}
async function save () {
  const r = await run(() => api.platformKeySet(PLATFORM, key.value.trim()), { success: 'حُفظ المفتاح.' })
  if (r) { key.value = ''; show.value = false; await load() }
}
async function clear () {
  const r = await run(() => api.platformKeyClear(PLATFORM), { success: 'حُذف المفتاح.' })
  if (r !== undefined) await load()
}
onMounted(load)
</script>
