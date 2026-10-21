<template>
  <q-dialog :model-value="lock.locked" maximized persistent transition-show="none" transition-hide="none">
    <div class="lock-screen column items-center justify-center q-pa-lg">
      <q-icon name="lock" size="48px" color="primary" />
      <div class="text-h6 text-weight-bold q-mt-sm">البرنامج مقفل</div>
      <div class="small muted q-mb-md">{{ who }}</div>

      <q-btn v-if="lock.bioId" unelevated color="primary" icon="fingerprint" size="lg" label="فتح بالبصمة" class="q-mb-md"
        :loading="bioBusy" @click="unlockBio" />

      <!-- PIN: digits are hidden and the keypad is shuffled each time so watchers can't learn it -->
      <div class="row q-gutter-sm q-mb-sm" aria-label="الرمز">
        <span v-for="i in 6" :key="i" class="pin-dot" :class="{ 'pin-dot--on': pin.length >= i, 'pin-dot--off': i > 4 && pin.length < i }" />
      </div>
      <div class="small q-mb-sm" :class="error ? 'text-negative' : 'muted'">{{ error || 'أو اكتب رمز القفل' }}</div>
      <div class="pin-pad">
        <q-btn v-for="(d, i) in keys" :key="i" unelevated :ripple="false" class="pin-key" :label="d"
          :disable="busy" @click="press(d)" />
        <q-btn unelevated :ripple="false" class="pin-key" icon="backspace" aria-label="مسح" @click="pin = pin.slice(0, -1)" />
        <q-btn unelevated :ripple="false" class="pin-key" color="primary" icon="check" aria-label="فتح"
          :loading="busy" :disable="pin.length < 4" @click="submit" />
      </div>
      <q-btn flat no-caps color="negative" class="q-mt-md" label="نسيت الرمز؟ خروج والدخول بكلمة السر" @click="signOut" />
    </div>
  </q-dialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Notify } from 'quasar'
import { useLockStore } from 'stores/lock'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useAdminStore } from 'stores/admin'
import { bioVerify } from 'src/composables/useBiometric'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'

const lock = useLockStore()
const session = useSessionStore()
const customer = useCustomerStore()
const admin = useAdminStore()
const router = useRouter()

const who = computed(() => (session.isAdmin ? admin.email : customer.profile?.name) || '')
const pin = ref('')
const error = ref('')
const busy = ref(false)
const bioBusy = ref(false)
const keys = ref([])
const shuffle = () => {
  const d = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
  for (let i = d.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [d[i], d[j]] = [d[j], d[i]] }
  keys.value = d
}

watch(() => lock.locked, (on) => {
  if (!on) return
  pin.value = ''
  error.value = ''
  shuffle()
  if (lock.bioId) unlockBio()   // try the fingerprint straight away (some browsers need the button)
}, { immediate: true })

function press (d) {
  if (pin.value.length < 6) pin.value += d
}

async function unlockBio () {
  bioBusy.value = true
  try {
    if (await bioVerify(lock.bioId)) lock.unlock()
  } catch {
    // cancelled or not available here: the PIN stays as the fallback
  } finally {
    bioBusy.value = false
  }
}

async function submit () {
  busy.value = true
  error.value = ''
  try {
    const status = session.isAdmin ? await adminApi.checkPin(pin.value) : await customerApi.checkPin(customer.token, pin.value)
    if (status === 'ok' || status === 'no_pin') return lock.unlock()
    if (status === 'locked_out') {
      Notify.create({ type: 'negative', message: '5 محاولات خاطئة: خرجت من هذا الجهاز. ادخل بكلمة السر.' })
      return signOut()
    }
    error.value = 'رمز خاطئ'
    pin.value = ''
    shuffle()
  } catch (e) {
    error.value = e.message || 'تعذّر التحقق. تحقق من الإنترنت.'
  } finally {
    busy.value = false
  }
}

async function signOut () {
  await session.logout().catch(() => {})
  lock.reset()
  router.replace('/login')
}
</script>

<style scoped>
.lock-screen { background: #F4F5FA; min-height: 100%; width: 100%; }
.pin-dot { width: 14px; height: 14px; border-radius: 50%; border: 2px solid #4F46E5; }
.pin-dot--on { background: #4F46E5; }
.pin-dot--off { opacity: .35; }
.pin-pad { display: grid; grid-template-columns: repeat(3, 72px); gap: 10px; direction: ltr; }
.pin-key { height: 56px; border-radius: 14px; font-size: 22px; font-weight: 600; background: #fff; color: #1F2430; }
</style>
