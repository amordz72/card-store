<template>
  <div class="column" style="gap:8px">
    <div class="row items-center justify-between">
      <div class="section-title">إعلانات بالصور في الرئيسية</div>
      <q-btn unelevated no-caps color="primary" icon="add" label="إعلان" @click="openForm()" />
    </div>
    <div class="small muted">صورة عريضة بنسبة 2:1 (مثلًا 1200×600). تظهر للجميع بالترتيب وتتغير كل 5 ثوانٍ.</div>

    <div v-if="!list.length" class="card text-center muted">لا توجد إعلانات بالصور</div>
    <div v-for="(b, i) in list" :key="b.banner_id" class="card row no-wrap items-center q-gutter-sm">
      <img :src="b.image" alt="" class="thumb">
      <div class="col column" style="min-width:0">
        <div class="ellipsis text-weight-medium">{{ b.title || 'بلا نص' }}</div>
        <div class="small muted ellipsis">{{ linkLabel(b) }}</div>
        <div class="row items-center q-gutter-xs">
          <q-badge :color="STATES[b.state].color" :label="STATES[b.state].label" />
          <span v-if="b.starts_at || b.ends_at" class="small muted">{{ period(b) }}</span>
        </div>
      </div>
      <div class="column items-center">
        <q-btn flat round dense icon="arrow_upward" aria-label="قبله" :disable="busy || i === 0" @click="move(b, -1)" />
        <q-btn flat round dense icon="arrow_downward" aria-label="بعده" :disable="busy || i === list.length - 1" @click="move(b, 1)" />
      </div>
      <div class="column items-stretch">
        <q-btn flat dense no-caps color="primary" label="تعديل" :disable="busy" @click="openForm(b)" />
        <q-btn flat dense no-caps :color="b.active ? 'grey-8' : 'positive'" :label="b.active ? 'تجميد' : 'تفعيل'" :disable="busy" @click="toggle(b)" />
        <q-btn flat dense no-caps color="negative" label="حذف" :disable="busy" @click="remove(b)" />
      </div>
    </div>

    <q-dialog v-model="formOpen">
      <q-card class="q-pa-md column" style="width:100%;max-width:520px;gap:8px">
        <div class="text-weight-bold">{{ form.id ? 'تعديل الإعلان' : 'إعلان جديد' }}</div>
        <div class="banner-preview" @click="picker.click()">
          <img v-if="form.image" :src="form.image" alt="">
          <div v-else class="column items-center muted"><q-icon name="add_photo_alternate" size="40px" />اختر صورة</div>
        </div>
        <q-btn outline no-caps color="primary" icon="upload" :label="form.image ? 'تغيير الصورة' : 'رفع صورة'" :loading="uploading" @click="picker.click()" />
        <div v-if="ratioHint" class="small" style="color:#B45309">{{ ratioHint }}</div>
        <input ref="picker" type="file" accept="image/png,image/jpeg,image/webp" hidden @change="pick">

        <q-input v-model="form.title" dense outlined stack-label counter maxlength="120" label="نص على الصورة (اختياري)" />

        <div class="small muted">عند الضغط على الإعلان</div>
        <q-btn-toggle v-model="form.linkKind" spread no-caps unelevated toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ value: 'none', label: 'لا شيء' }, { value: 'url', label: 'رابط خارجي' }, { value: 'page', label: 'صفحة في التطبيق' }]" />
        <q-input v-if="form.linkKind === 'url'" v-model="form.url" dense outlined stack-label label="الرابط" placeholder="https://facebook.com/…"
          input-class="ltr text-left" inputmode="url" />
        <q-select v-if="form.linkKind === 'page'" v-model="form.page" :options="pageOptions" emit-value map-options dense outlined stack-label label="الصفحة" />

        <div class="grid-2">
          <DateField v-model="form.from" label="يبدأ من (اختياري)" />
          <DateField v-model="form.to" label="آخر يوم (اختياري)" />
        </div>
        <div class="small muted">بلا تاريخ = يظهر دائمًا حتى تجمّده أو تحذفه.</div>

        <div class="row justify-end q-gutter-sm">
          <q-btn v-close-popup flat no-caps label="إلغاء" />
          <q-btn unelevated no-caps color="primary" label="حفظ" :loading="busy" :disable="!form.image || uploading" @click="save" />
        </div>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { Dialog } from 'quasar'
import { useRun } from 'src/composables/useRun'
import * as api from 'src/api/admin'
import DateField from 'components/DateField.vue'

const props = defineProps({ brands: { type: Array, default: () => [] } })
const { busy, run } = useRun()
const list = ref([])

const STATES = {
  live: { label: 'يظهر الآن', color: 'positive' },
  frozen: { label: 'مجمّد', color: 'grey-7' },
  scheduled: { label: 'مجدول', color: 'info' },
  ended: { label: 'انتهى', color: 'orange-8' }
}
const PAGES = [
  { value: '/store', label: 'المتجر' },
  { value: '/operations', label: 'العمليات' },
  { value: '/transfers', label: 'التحويلات' },
  { value: '/account', label: 'حسابي' },
  { value: '/reports', label: 'البلاغات' }
]
const pageOptions = computed(() => [...PAGES,
  ...props.brands.map((b) => ({ value: '/store?brand=' + encodeURIComponent(b.name), label: 'المتجر ← ' + b.name }))])

const dayText = (t) => new Date(t).toLocaleDateString('ar-DZ')
function period (b) {
  // ends_at is the start of the day after the last day
  const last = b.ends_at ? dayText(new Date(new Date(b.ends_at).getTime() - 1)) : null
  if (b.starts_at && last) return `من ${dayText(b.starts_at)} إلى ${last}`
  return b.starts_at ? `من ${dayText(b.starts_at)}` : `حتى ${last}`
}
function linkLabel (b) {
  if (b.link_kind === 'url') return b.link
  if (b.link_kind === 'page') return 'يفتح: ' + (pageOptions.value.find((p) => p.value === b.link)?.label || b.link)
  return 'بلا رابط'
}

async function load () {
  list.value = (await run(() => api.banners())) || []
}
onMounted(load)

// --- form
const formOpen = ref(false)
const form = ref({})
const picker = ref(null)
const uploading = ref(false)
const ratioHint = ref('')
const toDay = (t) => {
  if (!t) return ''
  const d = new Date(t)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

function openForm (b) {
  ratioHint.value = ''
  form.value = b
    ? {
        id: b.banner_id, image: b.image, title: b.title, linkKind: b.link_kind,
        url: b.link_kind === 'url' ? b.link : '', page: b.link_kind === 'page' ? b.link : '/store',
        from: toDay(b.starts_at), to: b.ends_at ? toDay(new Date(b.ends_at).getTime() - 1) : ''
      }
    : { id: null, image: '', title: '', linkKind: 'none', url: '', page: '/store', from: '', to: '' }
  formOpen.value = true
}

async function pick (e) {
  const file = e.target.files[0]
  e.target.value = ''
  if (!file) return
  uploading.value = true
  try {
    const bmp = await createImageBitmap(file).catch(() => null)
    const r = bmp ? bmp.width / bmp.height : 2
    ratioHint.value = r < 1.6 || r > 2.5 ? 'الصورة ليست عريضة بنسبة 2:1 تقريبًا، فقد يُقص جزء منها في العرض.' : ''
    const url = await run(() => api.uploadImage(file, 'banner', form.value.id || 0, 1200))
    if (url) form.value.image = url
  } finally {
    uploading.value = false
  }
}

// Dates are whole days on this device: from 00:00 of the first day until 00:00 after the last day
const dayStart = (d, plus = 0) => { const [y, m, dd] = d.split('-').map(Number); return new Date(y, m - 1, dd + plus).toISOString() }

async function save () {
  const f = form.value
  const ok = await run(() => api.saveBanner({
    id: f.id, image: f.image, title: f.title.trim(), linkKind: f.linkKind,
    link: f.linkKind === 'url' ? f.url.trim() : f.page,
    startsAt: f.from ? dayStart(f.from) : null, endsAt: f.to ? dayStart(f.to, 1) : null
  }).then(() => true), { success: 'حُفظ الإعلان.' })
  if (!ok) return
  formOpen.value = false
  load()
}

async function toggle (b) {
  const ok = await run(() => api.setBannerActive(b.banner_id, !b.active).then(() => true), { success: b.active ? 'جُمّد الإعلان.' : 'فُعّل الإعلان.' })
  if (ok) load()
}

async function move (b, dir) {
  if (await run(() => api.moveBanner(b.banner_id, dir).then(() => true))) load()
}

function remove (b) {
  Dialog.create({ title: 'حذف الإعلان', message: 'يُحذف نهائيًا. للإخفاء المؤقت استعمل «تجميد».', cancel: 'إلغاء', ok: { label: 'حذف', color: 'negative' } })
    .onOk(async () => {
      if (await run(() => api.removeBanner(b.banner_id).then(() => true), { success: 'حُذف الإعلان.' })) load()
    })
}
</script>

<style scoped>
.thumb { width: 96px; aspect-ratio: 2 / 1; object-fit: cover; border-radius: 8px; border: 1px solid #ECEEF3; flex-shrink: 0; }
.banner-preview { aspect-ratio: 2 / 1; border-radius: 12px; border: 1px dashed #A5A9F0; background: #F7F8FB; overflow: hidden;
  display: flex; align-items: center; justify-content: center; cursor: pointer; }
.banner-preview img { width: 100%; height: 100%; object-fit: cover; }
</style>
