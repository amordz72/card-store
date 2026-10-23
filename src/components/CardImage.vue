<template>
  <!-- The card's own picture; else the brand logo; else the coloured tile (before v1.19) -->
  <div v-if="item.image" class="card-img"><img :src="item.image" :alt="item.name" loading="lazy"></div>
  <div v-else-if="item.brand_image" class="card-img">
    <img :src="item.brand_image" :alt="item.brand" loading="lazy">
  </div>
  <div v-else class="brand-tile" style="height:56px" :style="{ background: brandColor(item.brand) }">{{ item.brand }}</div>
</template>

<script setup>
import { brandColor } from 'src/api/format'

// item: a catalog/stock row { name, brand, image, brand_image }
defineProps({ item: { type: Object, required: true } })
</script>

<style scoped>
.card-img { height: 96px; border-radius: 10px; background: #fff; border: 1px solid #ECEEF3; overflow: hidden;
  display: flex; align-items: center; justify-content: center; }
.card-img img { max-width: 100%; max-height: 100%; object-fit: contain; }
</style>
