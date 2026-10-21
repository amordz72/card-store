<template>
  <div class="section-title">قفل البرنامج</div>
  <div class="card column q-gutter-sm">
    <div class="row items-center q-gutter-sm">
      <span class="badge" :style="{ background: lock.enabled ? '#15803D' : '#9CA3AF' }">{{ lock.enabled ? 'القفل مفعّل' : 'القفل غير مفعّل' }}</span>
      <span class="small muted">يُقفل البرنامج بعد مدة بلا استعمال، ويُفتح بالبصمة أو برمز.</span>
    </div>

    <q-form class="column q-gutter-sm" @submit.prevent="savePin">
      <div class="text-weight-medium">{{ lock.enabled ? 'تغيير رمز القفل' : 'ضع رمز القفل لتفعيله' }}</div>
      <div class="grid-2">
        <q-input v-model="pin" dense outlined type="password" inputmode="numeric" maxlength="6" label="الرمز (4–6 أرقام)" autocomplete="off" />
        <q-input v-model="pin2" dense outlined type="password" inputmode="numeric" maxlength="6" label="أعد كتابته" autocomplete="off"
          :error="!!pin2 && pin2 !== pin" error-message="غير متطابق" />
      </div>
      <q-btn type="submit" outline color="primary" class="self-start" :label="lock.enabled ? 'حفظ الرمز الجديد' : 'تفعيل القفل'" :loading="busy"
        :disable="!/^[0-9]{4,6}$/.test(pin) || pin !== pin2" />
    </q-form>

    <template v-if="lock.enabled">
      <q-separator />
      <q-toggle v-if="bioOk" :model-value="!!lock.bioId" color="positive" icon="fingerprint"
        label="الفتح بالبصمة أو الوجه على هذا الجهاز" @update:model-value="toggleBio" />
      <div v-else class="small muted">البصمة غير متاحة في هذا الجهاز أو المتصفح؛ يُستعمل الرمز.</div>
      <q-select :model-value="lock.idleMin" :options="IDLE_OPTIONS" emit-value map-options dense outlined
        label="يُقفل بعد مدة بلا استعمال" hint="على هذا الجهاز فقط" @update:model-value="(v) => lock.setIdle(v)" />
      <div class="row q-gutter-sm">
        <q-btn unelevated color="grey-8" icon="lock" label="قفل الآن" @click="lock.lock()" />
        <q-btn flat color="negative" icon="lock_open" label="إيقاف القفل" @click="turnOff" />
      </div>
    </template>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { Dialog, Notify } from 'quasar'
import { useLockStore, IDLE_OPTIONS } from 'stores/lock'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import { useAdminStore } from 'stores/admin'
import { useRun } from 'src/composables/useRun'
import { bioAvailable, bioRegister } from 'src/composables/useBiometric'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'

const lock = useLockStore()
const session = useSessionStore()
const customer = useCustomerStore()
const admin = useAdminStore()
const { busy, run } = useRun()
const pin = ref('')
const pin2 = ref('')
const bioOk = ref(false)
onMounted(async () => { bioOk.value = await bioAvailable() })

async function savePin () {
  const ok = await run(() => (session.isAdmin ? adminApi.setPin(pin.value) : customerApi.setPin(customer.token, pin.value)).then(() => true),
    { success: lock.enabled ? 'تم تغيير رمز القفل.' : 'فُعّل القفل.' })
  if (!ok) return
  lock.hasPin = true
  pin.value = ''
  pin2.value = ''
}

function turnOff () {
  Dialog.create({ title: 'إيقاف القفل', message: 'لن يُقفل البرنامج بعد الآن على أي جهاز. تستطيع تفعيله لاحقًا بوضع رمز جديد.', cancel: 'إلغاء', ok: 'إيقاف' })
    .onOk(async () => {
      const ok = await run(() => (session.isAdmin ? adminApi.lockOff() : customerApi.lockOff(customer.token)).then(() => true), { success: 'أُوقف القفل.' })
      if (!ok) return
      lock.hasPin = false
      lock.setBio(null)
    })
}

async function toggleBio (on) {
  if (!on) { lock.setBio(null); return }
  try {
    const label = (session.isAdmin ? admin.email : customer.profile?.phone) || 'متجر البطاقات'
    lock.setBio(await bioRegister(label))
    Notify.create({ type: 'positive', message: 'فُعّلت البصمة على هذا الجهاز.' })
  } catch {
    Notify.create({ type: 'warning', message: 'لم تُفعَّل البصمة (أُلغيت أو غير مدعومة هنا).' })
  }
}
</script>
