<template>
  <!-- «إشعارات هذا الهاتف» (owner 2026-10-30, Flexy Core 0111): with the app closed; per phone, the kinds it wants -->
  <div class="card column q-gutter-sm">
    <div class="text-weight-bold">إشعارات هذا الهاتف</div>
    <div v-if="!supported" class="small text-negative">هذا المتصفح لا يدعم الإشعارات. على آيفون: أضف التطبيق إلى الشاشة الرئيسية أولًا (iOS 16.4 أو أحدث).</div>
    <template v-else>
      <div class="small" :class="on ? 'text-positive' : 'muted'">{{ on ? '🔔 مفعّلة على هذا الهاتف' : 'غير مفعّلة على هذا الهاتف' }}</div>
      <div v-if="denied" class="small text-negative">الإشعارات ممنوعة لهذا الموقع في إعدادات الهاتف/المتصفح: اسمح بها من هناك ثم عد.</div>
      <q-checkbox v-for="k in kinds" :key="k.key" v-model="picked" :val="k.key" :label="k.name" dense @update:model-value="on && save()" />
      <div class="row q-gutter-sm">
        <q-btn v-if="!on" unelevated no-caps color="primary" icon="notifications_active" label="فعّل الإشعارات على هذا الهاتف" :loading="busy" @click="enable" />
        <template v-else>
          <q-btn outline no-caps color="primary" icon="send" label="جرّب" :loading="busy" @click="testOne" />
          <q-btn flat no-caps color="grey-8" label="أوقفها" :loading="busy" @click="disable" />
        </template>
      </div>
      <div v-if="error" class="small text-negative">{{ error }}</div>
    </template>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { Notify } from 'quasar'
import * as flexy from 'src/api/flexy'

const supported = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window
const on = ref(false)
const denied = ref(supported && Notification.permission === 'denied')
const busy = ref(false)
const error = ref('')
const kinds = ref([])
const picked = ref(['game', 'review', 'money', 'devices', 'stock'])
let publicKey = null

const keyBytes = (b64) => {
  const s = (b64 + '='.repeat((4 - (b64.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/')
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0))
}
async function current () {
  const reg = await navigator.serviceWorker.ready
  return reg.pushManager.getSubscription()
}
async function call (fn) {
  busy.value = true
  error.value = ''
  try {
    const r = await fn()
    if (r && (r.status !== 200 || !r.body?.ok)) throw new Error(r.body?.error === 'PUSH_NOT_CONFIGURED' ? 'الإشعارات غير جاهزة في الخادم بعد (طبّق 0111).' : (r.body?.error || 'FLEXY_CORE'))
    return r
  } catch (e) {
    error.value = e.message || String(e)
    return null
  } finally {
    busy.value = false
  }
}
const save = async () => { const s = await current(); if (s) await call(() => flexy.ownerPush({ subscribe: s.toJSON(), kinds: picked.value })) }
async function enable () {
  await call(async () => {
    const perm = await Notification.requestPermission()
    if (perm !== 'granted') { denied.value = perm === 'denied'; throw new Error('لم يُسمح بالإشعارات.') }
    const reg = await navigator.serviceWorker.ready
    const sub = (await reg.pushManager.getSubscription()) || await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) })
    const r = await flexy.ownerPush({ subscribe: sub.toJSON(), kinds: picked.value })
    if (r.status === 200 && r.body?.ok) { on.value = true; Notify.create({ type: 'positive', message: 'فُعّلت الإشعارات على هذا الهاتف.' }) }
    return r
  })
}
async function disable () {
  await call(async () => {
    const s = await current()
    if (s) { await flexy.ownerPush({ unsubscribe: s.endpoint }); await s.unsubscribe() }
    on.value = false
    return null
  })
}
async function testOne () {
  const s = await current()
  if (s && await call(() => flexy.ownerPush({ test: s.endpoint }))) Notify.create({ type: 'positive', message: 'أُرسل إشعار تجربة: يصل خلال ثوانٍ.' })
}
onMounted(async () => {
  if (!supported) return
  const r = await call(() => flexy.ownerPush(null))
  if (!r) return
  publicKey = r.body.public_key
  kinds.value = r.body.kinds || []
  on.value = !!(await current().catch(() => null))
})
</script>
