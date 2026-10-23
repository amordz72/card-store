import { computed, ref } from 'vue'
import * as adminApi from 'src/api/admin'

// Owner's header bell (pattern 18): open card reports + customers' IDOOM top-ups waiting for review.
// Shared so «البلاغات» and «تعبئة إيدوم» can refresh it right after a decision.
const openReports = ref(0)
const idoomReview = ref(0)
const bellTotal = computed(() => openReports.value + idoomReview.value)

async function refreshBell () {
  try { openReports.value = Number(await adminApi.openReportsCount()) || 0 } catch { /* keep the last value */ }
  try { idoomReview.value = Number(await adminApi.idoomReviewCount()) || 0 } catch { /* keep the last value */ }
}

export function useBell () {
  return { openReports, idoomReview, bellTotal, refreshBell }
}
