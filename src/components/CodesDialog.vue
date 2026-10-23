<template>
  <q-dialog v-model="open" position="bottom">
    <q-card style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
      <q-card-section>
        <div class="text-h6 text-weight-bold">{{ title }}</div>
        <div class="small muted">{{ subtitle }}</div>
      </q-card-section>
      <q-card-section class="column q-gutter-sm">
        <div v-for="c in sortedCodes" :key="c._key" class="row items-center no-wrap q-pa-sm"
          :style="{ border: '1px dashed #A5A9F0', background: c._copied ? '#F0F1F3' : '#F5F6FF', borderRadius: '12px' }">
          <div class="col ltr text-left">
            <div class="text-weight-bold" style="font-size:16px;letter-spacing:.5px;overflow-wrap:anywhere"
              :style="c.status === 'void' ? 'text-decoration:line-through;color:#6B7280' : ''">
              {{ c._copied && !revealed[c._key] ? '••••' + String(c.code).slice(-4) : c.code }}
            </div>
            <div v-if="c.serial" class="small muted">{{ c.serial }}</div>
            <q-badge v-if="c._copied" color="grey-7" label="تم نسخها" class="q-mt-xs" />
            <q-badge v-if="c.badge" :color="c.badge.color" :label="c.badge.label" class="q-mt-xs" />
          </div>
          <div class="row items-center no-wrap q-gutter-xs">
            <q-btn v-if="c.action" unelevated color="primary" :label="c.actionLabel" :loading="!!pending[c._key]"
              @click="handleAction(c)" />
            <q-btn v-if="c._copied && c.actionLabel === 'نسخ' && c.status !== 'void'" flat round dense
              :icon="revealed[c._key] || !c._copied ? 'visibility_off' : 'visibility'"
              :aria-label="revealed[c._key] || !c._copied ? 'إخفاء الكود' : 'إظهار الكود'"
              @click="toggleReveal(c)" />
            <q-btn v-if="c.help" flat dense no-caps color="negative" icon="help_outline" :label="c.helpLabel || 'مساعدة'" @click="c.help()" />
          </div>
        </div>
      </q-card-section>
      <q-card-actions>
        <q-btn flat class="full-width" size="lg" label="إغلاق" v-close-popup />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { computed, reactive, watch } from 'vue'
import { LocalStorage } from 'quasar'

// Copy tracking is display-only. Never changes stock, sales or redemption status.
// codes may carry copiedAt (saved on the server, v1.27); markCopied(codeId) saves a new copy there.
// The device copy stays as a fallback when the server is unreachable.
const props = defineProps({
  title: String,
  subtitle: String,
  codes: { type: Array, default: () => [] },
  orderId: { type: [String, Number], default: null },
  markCopied: { type: Function, default: null }
})
const open = defineModel({ type: Boolean, default: false })
const copied = reactive({})
const revealed = reactive({})
const pending = reactive({})
const keyFor = (c, i) => props.orderId != null ? 'order:' + props.orderId + (c.id != null ? ':code:' + c.id : ':item:' + i) : null
function readCopied (key) {
  if (!key) return false
  try { return LocalStorage.getItem('cs_copied_v1:' + key) === true } catch { return false }
}
watch(() => [props.codes, props.orderId], () => {
  for (const k of Object.keys(copied)) delete copied[k]
  for (const k of Object.keys(revealed)) delete revealed[k]
  props.codes.forEach((c, i) => { const key = keyFor(c, i); if (key) copied[key] = !!c.copiedAt || readCopied(key) })
}, { immediate: true })
const sortedCodes = computed(() => props.codes.map((c, i) => {
  const key = keyFor(c, i) || 'temporary:' + i
  return { ...c, _key: key, _index: i, _copied: !!copied[key] }
}).sort((a, b) => Number(a._copied) - Number(b._copied) || a._index - b._index))
function toggleReveal (c) { revealed[c._key] = !revealed[c._key] }
async function handleAction (c) {
  if (pending[c._key]) return
  pending[c._key] = true
  try {
    const success = await c.action()
    if (c.actionLabel !== 'نسخ' || success !== true) return
    // Do not mark void/refunded cards, or save an unscoped purchase in device storage.
    if (c.status === 'void' || !c.action) return
    copied[c._key] = true
    revealed[c._key] = false
    if (!c._key.startsWith('temporary:')) {
      try { LocalStorage.set('cs_copied_v1:' + c._key, true) } catch { /* no persistence available */ }
    }
    // A failed save only loses the hint on other devices; the copy itself already succeeded.
    if (props.markCopied && c.id != null) props.markCopied(c.id).catch(() => {})
  } finally { pending[c._key] = false }
}
</script>
