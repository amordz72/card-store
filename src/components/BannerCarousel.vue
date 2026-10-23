<template>
  <q-carousel v-if="banners.length" v-model="slide" class="banner" animated swipeable infinite
    :autoplay="banners.length > 1 && autoplay ? 5000 : 0" :arrows="banners.length > 1 && $q.screen.gt.xs"
    :navigation="banners.length > 1" control-color="white" transition-prev="slide-right" transition-next="slide-left"
 @touchstart.passive="autoplay = false" @mouseenter="autoplay = false" @mouseleave="autoplay = true">
    <q-carousel-slide v-for="b in banners" :key="b.banner_id" :name="b.banner_id" class="q-pa-none"
      :class="{ 'cursor-pointer': b.link_kind !== 'none' }" @click="open(b)">
      <img :src="b.image" :alt="b.title || 'إعلان'" class="banner-img" loading="lazy">
      <div v-if="b.title" class="banner-title">{{ b.title }}</div>
    </q-carousel-slide>
  </q-carousel>
</template>

<script setup>
import { ref, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useRouter } from 'vue-router'

// Home image banners: auto-advance every 5 s, swipe on the phone, arrows on the computer, dots under.
// A touch stops the auto-advance so the viewer can read. Link: external (new tab) or a page in the app.
const props = defineProps({ banners: { type: Array, default: () => [] } })
const $q = useQuasar()
const router = useRouter()
const slide = ref(null)
const autoplay = ref(true)

watch(() => props.banners, (list) => {
  if (!list.some((b) => b.banner_id === slide.value)) slide.value = list[0]?.banner_id ?? null
}, { immediate: true })


function open (b) {
  if (b.link_kind === 'url') window.open(b.link, '_blank', 'noopener')
  else if (b.link_kind === 'page') router.push(b.link)
}
</script>

<style scoped>
.banner { aspect-ratio: 2 / 1; height: auto; border-radius: 16px; overflow: hidden; background: #ECEEF3; }
.banner-img { width: 100%; height: 100%; object-fit: cover; display: block; }
.banner-title { position: absolute; inset: auto 0 0 0; line-height: 1.3; padding: 28px 14px 34px; color: #fff; font-weight: 600; font-size: 16px;
  background: linear-gradient(transparent, rgba(0, 0, 0, .6)); text-shadow: 0 1px 2px rgba(0, 0, 0, .4); }
</style>
