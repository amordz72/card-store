// «قفل بطاقات إيدوم» (owner 2026-11-01): while a top-up for THIS line waits or runs, its cards stay locked
// until the answer; another number, Flexy or another 4G line go on. jobs: () => [{ line, status, created_at, kind? }]
import { computed, onUnmounted, ref, watch } from 'vue'

export function useLineBusy (jobs, line) {
  const busyLine = computed(() => (jobs() || []).find((j) => String(j.line) === String(line() || '') && j.kind !== 'lookup' &&
    ['queued', 'claimed'].includes(j.status)) || null)
  const now = ref(Date.now())
  let tick = null
  watch(busyLine, (b) => { clearInterval(tick); tick = b ? setInterval(() => { now.value = Date.now() }, 1000) : null }, { immediate: true })
  onUnmounted(() => clearInterval(tick))
  const busySince = computed(() => {
    if (!busyLine.value) return ''
    const s = Math.max(0, Math.round((now.value - Date.parse(busyLine.value.created_at)) / 1000))
    return s < 60 ? s + ' ث' : Math.round(s / 60) + ' د'
  })
  return { busyLine, busySince }
}
