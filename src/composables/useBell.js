import { computed, ref } from 'vue'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'
import * as flexyApi from 'src/api/flexy'
import { indicatorsSeenThisWeek } from 'src/components/ShopIndicators.vue'

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
// v1.43: a shop's failed flexy whose charge did not come back
const flexyUnrefunded = ref(0)
const flexyUnrefundedAmount = ref(0)
const devicesDown = ref(0)
// Offers that left their first source (Flexy Core 0036): one per reason, until seen on «إرسال فليكسي».
const offerAlerts = ref(0)
// Stopped SIMs not marked seen today («المحطات والشرائح»).
const simAlerts = ref(0)
// Replies and offers the network showed that no path knows yet (Flexy Core 0056), until marked seen
const newReplies = ref(0)
// «المراقبة» (Flexy Core 0068): the red / orange bar on every admin page, and its alerts in the bell
const monitorBar = ref(null)
const monitorAlerts = ref(0)
// «حدث أثناء غيابك» (Flexy Core 0079): unseen events that solved themselves
const monitorIncidents = ref(0)
// The station computers that can take a newer Agent from main (owner 2026-10-30): count and the version
const agentUpdates = ref(0)
// v1.45: shops whose spending dropped or stopped this week, until the owner opens «المؤشرات» this week
const shopsDown = ref(0)
// v1.53: cards about to run out
const lowStock = ref(0)
// «مطلوب منك» (Flexy Core 0087, owner 2026-10-30): what does not move without the owner's press, in the blue bar
const sqlPending = ref(0)
const approvalsWaiting = ref(0)
// «ينتظرك» items that need his hand (Flexy Core src/data/handover.ts), not counted elsewhere
const handoverNeeds = ref(0)
// «تحتاج حكمك» (Flexy Core 0092): operations in review longer than an hour
const reviewWaiting = ref(0)
// 0093: money failures of 3 days that nothing solved
const failuresOpen = ref(0)
// 0094: the automix failing today above the owner's limit → «أوقف الأوتوميكس؟»
const automixAlert = ref(null)
const agentUpdateVersion = ref('')
// 'dead' | 'expiring' | other; the bell counts 1 for the first two
const repoKeyLevel = ref('')
const repoKeyAlert = computed(() => (repoKeyLevel.value === 'dead' || repoKeyLevel.value === 'expiring' ? 1 : 0))
const bellTotal = computed(() => openReports.value + idoomReview.value + gameWaiting.value + flexyReview.value + flexyUnrefunded.value + devicesDown.value + offerAlerts.value + simAlerts.value + newReplies.value + repoKeyAlert.value + monitorAlerts.value + monitorIncidents.value + agentUpdates.value + shopsDown.value + lowStock.value)

async function refreshBell () {
  try { openReports.value = Number(await adminApi.openReportsCount()) || 0 } catch { /* keep the last value */ }
  try { idoomReview.value = Number(await adminApi.idoomReviewCount()) || 0 } catch { /* keep the last value */ }
  try { gameWaiting.value = Number(await customerApi.gameOpenCount(null)) || 0 } catch { /* keep the last value */ }
  // «متاح» for game top-ups stays on while any admin page is open, not only the games page (owner 2026-10-26).
  // Only while it is live now: a switch the 30-minute rule already closed is never reopened by this.
  try {
    const b = await customerApi.gameBoard(null)
    if (b?.me_available) await customerApi.gamePresence(null, null)
  } catch { /* the games page keeps its own */ }
  try { flexyReview.value = Number(await adminApi.flexyReviewCount()) || 0 } catch { /* keep the last value */ }
  try {
    const u = await adminApi.flexyUnrefunded()
    flexyUnrefunded.value = Number(u.count) || 0
    flexyUnrefundedAmount.value = Number(u.amount) || 0
  } catch { /* before v1.43, or keep the last value */ }
  try {
    const res = await flexyApi.ownerDevices()
    if (res.status === 200) {
      devicesDown.value = Number(res.body?.summary?.down) || 0
      approvalsWaiting.value = (res.body?.stations || []).filter((s) => !s.approved && !s.phone &&
        !String(s.agent_version || '').startsWith('phone-') && (!s.status || s.status === 'pending')).length
    }
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
    const res = await flexyApi.ownerNewReplies()
    if (res.status === 200) newReplies.value = Number(res.body?.unseen) || 0
  } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerMonitor()
    if (res.status === 200) {
      monitorBar.value = res.body?.bar || null
      monitorAlerts.value = (res.body?.alerts || []).length
      monitorIncidents.value = res.body?.counts?.incidents || 0
      sqlPending.value = Number(res.body?.sql_pending) || 0
      handoverNeeds.value = Number(res.body?.handover_needs) || 0
      reviewWaiting.value = Number(res.body?.review_waiting) || 0
      failuresOpen.value = Number(res.body?.failures_open) || 0
      automixAlert.value = res.body?.automix_alert || null
    }
  } catch { /* keep the last value */ }
  try {
    if (indicatorsSeenThisWeek()) shopsDown.value = 0
    else {
      const d = await adminApi.indicators(7)
      shopsDown.value = (d?.shops || []).filter((s) => s.grp === 'down' || s.grp === 'stopped').length
    }
  } catch { /* before v1.45, or keep the last value */ }
  try { lowStock.value = ((await adminApi.lowStock())?.items || []).length } catch { /* before v1.53, or keep the last value */ }
  try {
    const res = await flexyApi.ownerUpdates()
    if (res.status === 200 && res.body?.ok) {
      const u = agentUpdatesOf(res.body)
      agentUpdates.value = u.length
      agentUpdateVersion.value = u[0]?.main_version || ''
    }
  } catch { /* keep the last value */ }
  try {
    const res = await flexyApi.ownerRepoKey()
    if (res.status === 200) repoKeyLevel.value = res.body?.repo_key?.level || ''
  } catch { /* keep the last value */ }
}

// A computer seen in the last 10 minutes whose main holds a NEWER version (a commit that keeps the version is nothing
// to press, owner 2026-10-30), with no update asked yet
const newerVersion = (a, b) => {
  const x = String(a || '0').split('.').map(Number)
  const y = String(b || '0').split('.').map(Number)
  for (let i = 0; i < 3; i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0)
  return false
}
export function agentUpdatesOf (body, now = Date.now()) {
  const busy = new Set((body?.stations || []).filter((x) => x.status === 'pending' || x.status === 'claimed').map((x) => x.station_uuid))
  return (body?.main || []).filter((m) => m.main_version && !m.main_error && !busy.has(m.station_uuid) &&
    now - Date.parse(m.reported_at || 0) < 10 * 60_000 &&
    newerVersion(m.main_version, m.agent_version))
}

export function useBell () {
  return { lowStock, automixAlert, failuresOpen, reviewWaiting, handoverNeeds, sqlPending, approvalsWaiting, shopsDown, agentUpdates, agentUpdateVersion, openReports, idoomReview, gameWaiting, flexyReview, flexyUnrefunded, flexyUnrefundedAmount, devicesDown, offerAlerts, simAlerts, newReplies, repoKeyLevel, repoKeyAlert, monitorBar, monitorAlerts, monitorIncidents, bellTotal, refreshBell }
}
