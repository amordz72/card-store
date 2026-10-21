<template>
  <q-layout>
    <q-page-container>
      <q-page class="flex flex-center q-pa-md">
        <q-form class="card column q-gutter-md" style="width:100%;max-width:380px" @submit.prevent="submit">
          <div class="text-h6 text-weight-bold text-center">متجر البطاقات</div>
          <q-input v-model="id" label="رقم الهاتف أو البريد" outlined autocomplete="username" input-class="ltr text-right"
            hint="الزبائن: رقم الهاتف · الإدارة: البريد" />
          <q-input v-model="password" label="كلمة السر" outlined :type="show ? 'text' : 'password'" autocomplete="current-password">
            <template #append>
              <q-icon :name="show ? 'visibility_off' : 'visibility'" class="cursor-pointer" @click="show = !show" />
            </template>
          </q-input>
          <div v-if="failed" class="text-negative small">{{ failed }}</div>
          <q-btn type="submit" color="primary" unelevated size="lg" label="دخول" :loading="busy" :disable="!id || !password" />
        </q-form>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useCustomerStore } from 'stores/customer'
import { useAdminStore } from 'stores/admin'
import { useSessionStore } from 'stores/session'
import { markActive } from 'stores/lock'
import { useRun } from 'src/composables/useRun'

// One login page: an e-mail signs the admin in (Supabase Auth), a phone number signs a customer in.
const router = useRouter()
const customer = useCustomerStore()
const admin = useAdminStore()
const session = useSessionStore()
const { busy, run } = useRun()
const id = ref('')
const password = ref('')
const show = ref(false)
const failed = ref('')

async function submit () {
  failed.value = ''
  const value = id.value.trim()
  if (value.includes('@')) {
    const ok = await run(() => admin.login(value, password.value))
    if (ok) { session.set('admin'); markActive(); router.replace('/') }
    else if (ok === false) failed.value = 'بيانات الدخول غير صحيحة، أو هذا الحساب ليس مديرًا للمتجر.'
    return
  }
  const ok = await run(() => customer.login(value, password.value))
  if (ok) { session.set('customer'); markActive(); router.replace('/') }
  else if (ok === false) failed.value = 'رقم الهاتف أو كلمة السر غير صحيحة.'
}
</script>
