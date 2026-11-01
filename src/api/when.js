// Time in words (owner 2026-10-30: «يقول لي عملية الأمس، لماذا أقرأ تاريخًا كاملًا»):
// «اليوم 12:24», «أمس 16:50», «قبل 3 أيام 09:10», a date only after a week
export function when (t) {
  if (!t) return '—'
  const d = new Date(t)
  if (Number.isNaN(d.getTime())) return String(t)
  const a = new Date(d); a.setHours(0, 0, 0, 0)
  const b = new Date(); b.setHours(0, 0, 0, 0)
  const days = Math.round((b - a) / 86400000)
  const hm = d.toLocaleTimeString('ar-DZ', { timeZone: 'Africa/Algiers', hour: '2-digit', minute: '2-digit' })
  if (days <= 0) return 'اليوم ' + hm
  if (days === 1) return 'أمس ' + hm
  if (days === 2) return 'قبل يومين ' + hm
  if (days < 7) return `قبل ${days} أيام ` + hm
  return d.toLocaleDateString('ar-DZ', { timeZone: 'Africa/Algiers', day: '2-digit', month: '2-digit' })
}
