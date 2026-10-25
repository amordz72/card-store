import { computed, ref } from 'vue'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import * as flexyApi from 'src/api/flexy'

// Owner's header bell (pattern 18): open card reports + customers' IDOOM top-ups waiting for review
// + game top-ups waiting for an operator (v1.25) + shops' Flexy sends waiting for the owner's decision (v1.33)
// + modems and computers Flexy Core judges down (⛔, «المحطات والشرائح»).
// Shared so «البلاغات» and «تعبئة إيدوم» can refresh it right after a decision.
const openReports = ref(0)
const idoomReview = ref(0)
const gameWaiting = ref(0)
const flexyReview = ref(0)
const devicesDown = ref(0)
const bellTotal = computed(() => openReports.value + idoomReview.value + gameWaiting.value + flexyReview.value + devicesDown.value)

async function refreshBell () {
  try { openReports.value = Number(await adminApi.openReportsCount()) || 0 } catch { /* keep the last value */ }
  try { idoomReview.value = Number(await adminApi.idoomReviewCount()) || 0 } catch { /* keep the last value */ }
  try { gameWaiting.value = Number(await customerApi.gameOpenCount(null)) || 0 } catch { /* keep the last value */ }
  try { flexyReview.value = Number(await adminApi.flexyReviewCount()) || 0 } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerDevices()
    if (res.status === 200) devicesDown.value = Number(res.body?.summary?.down) || 0
  } catch { /* keep the last value */ }
}

export function useBell () {
  return { openReports, idoomReview, gameWaiting, flexyReview, devicesDown, bellTotal, refreshBell }
}
