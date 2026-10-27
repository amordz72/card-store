import { computed, ref } from 'vue'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import * as flexyApi from 'src/api/flexy'

// Owner's header bell (pattern 18): open card reports + customers' IDOOM top-ups waiting for review
// + game top-ups waiting for an operator (v1.25) + shops' Flexy sends waiting for the owner's decision (v1.33)
// + modems and computers Flexy Core judges down (⛔, «المحطات والشرائح»)
// + offers sent from their second source, with the reason (a SIM to add, to feed or to fix)
// + stopped SIMs (Flexy Core 0039), again every day until solved
// + the GitHub key of the station computers dead or ending soon (Flexy Core 0042).
// Shared so «البلاغات» and «تعبئة إيدوم» can refresh it right after a decision.
const openReports = ref(0)
const idoomReview = ref(0)
const gameWaiting = ref(0)
const flexyReview = ref(0)
const devicesDown = ref(0)
// Offers that left their first source (Flexy Core 0036): one per reason, until seen on «إرسال فليكسي».
const offerAlerts = ref(0)
// Stopped SIMs not marked seen today («المحطات والشرائح»).
const simAlerts = ref(0)
// 'dead' | 'expiring' | other; the bell counts 1 for the first two
const repoKeyLevel = ref('')
const repoKeyAlert = computed(() => (repoKeyLevel.value === 'dead' || repoKeyLevel.value === 'expiring' ? 1 : 0))
const bellTotal = computed(() => openReports.value + idoomReview.value + gameWaiting.value + flexyReview.value + devicesDown.value + offerAlerts.value + simAlerts.value + repoKeyAlert.value)

async function refreshBell () {
  try { openReports.value = Number(await adminApi.openReportsCount()) || 0 } catch { /* keep the last value */ }
  try { idoomReview.value = Number(await adminApi.idoomReviewCount()) || 0 } catch { /* keep the last value */ }
  try { gameWaiting.value = Number(await customerApi.gameOpenCount(null)) || 0 } catch { /* keep the last value */ }
  try { flexyReview.value = Number(await adminApi.flexyReviewCount()) || 0 } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerDevices()
    if (res.status === 200) devicesDown.value = Number(res.body?.summary?.down) || 0
  } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerOfferAlerts()
    if (res.status === 200) offerAlerts.value = (res.body?.alerts || []).length
  } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerSimAlerts()
    if (res.status === 200) simAlerts.value = (res.body?.alerts || []).length
  } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerRepoKey()
    if (res.status === 200) repoKeyLevel.value = res.body?.repo_key?.level || ''
  } catch { /* keep the last value */ }
}

export function useBell () {
  return { openReports, idoomReview, gameWaiting, flexyReview, devicesDown, offerAlerts, simAlerts, repoKeyLevel, repoKeyAlert, bellTotal, refreshBell }
}
