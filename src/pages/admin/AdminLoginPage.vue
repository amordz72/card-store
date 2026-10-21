<template>
  <q-layout>
    <q-page-container>
      <q-page class="flex flex-center q-pa-md">
        <q-form class="card column q-gutter-md" style="width:100%;max-width:380px" @submit.prevent="submit">
          <div class="text-h6 text-weight-bold text-center">دخول المدير</div>
          <q-input v-model="email" label="البريد الإلكتروني" outlined type="email" autocomplete="username" input-class="ltr text-right" />
          <q-input v-model="password" label="كلمة السر" outlined type="password" autocomplete="current-password" />
          <div v-if="failed" class="text-negative small">بيانات الدخول غير صحيحة، أو هذا الحساب ليس مديرًا للمتجر.</div>
          <q-btn type="submit" color="primary" unelevated size="lg" label="دخول" :loading="busy" :disable="!email || !password" />
          <router-link to="/login" class="small muted text-center">دخول الزبائن</router-link>
        </q-form>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAdminStore } from 'stores/admin'

const router = useRouter()
const admin = useAdminStore()
const email = ref('')
const password = ref('')
const busy = ref(false)
const failed = ref(false)

async function submit () {
  busy.value = true
  failed.value = false
  try {
    if (await admin.login(email.value, password.value)) router.replace('/admin/customers')
    else failed.value = true
  } finally {
    busy.value = false
  }
}
</script>
