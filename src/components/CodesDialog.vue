<template>
  <q-dialog v-model="open" position="bottom">
    <q-card style="width:100%;max-width:560px;border-radius:20px 20px 0 0">
      <q-card-section>
        <div class="text-h6 text-weight-bold">{{ title }}</div>
        <div class="small muted">{{ subtitle }}</div>
      </q-card-section>
      <q-card-section class="column q-gutter-sm">
        <div v-for="(c, i) in codes" :key="i" class="row items-center no-wrap q-pa-sm"
          style="border:1px dashed #A5A9F0;background:#F5F6FF;border-radius:12px">
          <div class="col ltr text-left">
            <div class="text-weight-bold" style="font-size:16px;letter-spacing:.5px" :style="c.status === 'void' ? 'text-decoration:line-through;color:#6B7280' : ''">{{ c.code }}</div>
            <div v-if="c.serial" class="small muted">{{ c.serial }}</div>
            <q-badge v-if="c.badge" :color="c.badge.color" :label="c.badge.label" class="q-mt-xs" />
          </div>
          <div class="column q-gutter-xs items-stretch">
            <q-btn v-if="c.action" unelevated color="primary" :label="c.actionLabel" @click="c.action()" />
            <q-btn v-if="c.help" flat dense no-caps color="negative" icon="help_outline" label="مساعدة" @click="c.help()" />
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
// codes: [{ code, serial, status, action?, actionLabel?, help? (report button), badge? { label, color } }]
defineProps({ title: String, subtitle: String, codes: { type: Array, default: () => [] } })
const open = defineModel({ type: Boolean, default: false })
</script>
