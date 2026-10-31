// What a shop sees for each Idoom top-up state (same words as «تعبئة إيدوم»); the money side is automatic.
export function idoomView (j) {
  if (j.attempt > 1 && ['queued', 'claimed'].includes(j.status)) return { label: 'فشل الشحن — جاري الإعادة', color: 'warning' }
  if (j.status === 'success') return { label: 'تمت التعبئة', color: 'positive' }
  if (j.status === 'likely_success') return { label: 'تمت على الأرجح', color: 'teal' }
  if (j.status === 'queued') return { label: 'في الانتظار', color: 'grey-7' }
  if (j.status === 'claimed') return { label: 'قيد التنفيذ', color: 'info' }
  if (j.status === 'review') return { label: 'قيد المراجعة من المحل', color: 'deep-orange' }
  if (j.status === 'cancelled') return { label: 'أُلغيت — أُعيد المبلغ', color: 'grey' }
  if (j.status === 'used_card' || j.status === 'failed') return { label: 'لم تتم — أُعيد المبلغ', color: 'orange-8' }
  return { label: j.status, color: 'grey' }
}
