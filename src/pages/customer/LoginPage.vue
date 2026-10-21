<template>
  <q-layout>
    <q-page-container>
      <q-page class="flex flex-center q-pa-md">
        <q-form class="card column q-gutter-md" style="width:100%;max-width:380px" @submit.prevent="submit">
          <div class="text-h6 text-weight-bold text-center">متجر البطاقات</div>
          <q-input v-model="phone" label="رقم الهاتف" outlined inputmode="tel" autocomplete="username" input-class="ltr text-right" />
          <q-input v-model="password" label="كلمة السر" outlined :type="show ? 'text' : 'password'" autocomplete="current-password">
            <template #append>
              <q-icon :name="show ? 'visibility_off' : 'visibility'" class="cursor-pointer" @click="show = !show" />
            </template>
          </q-input>
          <div v-if="failed" class="text-negative small">رقم الهاتف أو كلمة السر غير صحيحة.</div>
          <q-btn type="submit" color="primary" unelevated size="lg" label="دخول" :loading="busy" :disable="!phone || !password" />
          <router-link to="/admin/login" class="small muted text-center">دخول المدير</router-link>
        </q-form>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useCustomerStore } from 'stores/customer'
import { useRun } from 'src/composables/useRun'

const router = useRouter()
const customer = useCustomerStore()
const { busy, run } = useRun()
const phone = ref('')
const password = ref('')
const show = ref(false)
const failed = ref(false)

async function submit () {
  failed.value = false
  const ok = await run(() => customer.login(phone.value, password.value))
  if (ok) router.replace('/')
  else if (ok === false) failed.value = true
}
</script>
