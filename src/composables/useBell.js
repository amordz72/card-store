import { ref } from 'vue'
import * as adminApi from 'src/api/admin'

// Owner's header bell: count of open card reports (pattern 18, phase 1).
// Shared so «البلاغات» can refresh it right after a decision.
const openReports = ref(0)

async function refreshBell () {
  try { openReports.value = Number(await adminApi.openReportsCount()) || 0 } catch { /* keep the last value */ }
}

export function useBell () {
  return { openReports, refreshBell }
}
