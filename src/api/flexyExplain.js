// «آخر العمليات» (owner 2026-10-26): a tapped row says what happened in words, never «—».
// One sentence per Flexy Core outcome code (flexy-core src/core/operations/*), then the status.
// The order of a Sama offer: start → PIN asked → PIN → menu with the number → offer number → reply.
// Nothing is bought before the offer number is sent; Arsselli 630 moves money only on its confirm.

const CODES = {
  // Offers (665)
  '665_NETWORK_ACTIVATED': 'الشبكة فعّلت العرض للزبون.',
  '665_NETWORK_REJECTED': 'الشبكة رفضت العرض. لم يُخصم شيء.',
  '665_START_NO_RESPONSE': 'المودم لم يردّ على أول طلب. لم يُرسل الـPIN ولا رقم العرض، فلم يُخصم شيء.',
  '665_START_NOT_DISPATCHED': 'الطلب لم يصل إلى المودم. لم يُخصم شيء.',
  '665_NO_PIN_PROMPT': 'الشبكة ردّت بغير طلب الـPIN، فتوقّف البرنامج قبل إرساله. لم يُخصم شيء.',
  '665_NUMBER_NOT_ALLOWED': 'الشبكة قالت إن هذا الرقم لا يقبل العرض. لم يُخصم شيء.',
  '665_SIM_LANGUAGE_ARABIC': 'الشريحة ترد بالعربية، والبرنامج يقرأ ردّها بالإنجليزية فقط. لم يُخصم شيء.',
  '665_PIN_NO_RESPONSE': 'أُرسل الـPIN ولم تردّ الشبكة. لم يُرسل رقم العرض، فلم يُخصم شيء.',
  '665_PIN_REPROMPT': 'الشبكة طلبت الـPIN مرة ثانية: قد يكون الـPIN المحفوظ خاطئًا. لم يُخصم شيء.',
  '665_MENU_UNRECOGNIZED': 'قائمة العروض لم تُفهم، فلم يُختر شيء. لم يُخصم شيء.',
  '665_MENU_NO_PHONE': 'قائمة العروض بلا رقم الزبون، فلم يُختر شيء. لم يُخصم شيء.',
  '665_MENU_PHONE_MISMATCH': 'القائمة لرقم غير رقم الزبون، فلم يُختر شيء. لم يُخصم شيء.',
  '665_LINE_GROUP_CHANGED': 'خط الزبون تغيّرت مجموعته (Sama / PixX / Revolution)، فلم يُرسل العرض. لم يُخصم شيء.',
  '665_GROUP_UNKNOWN': 'لم تُعرف مجموعة خط الزبون. لم يُخصم شيء.',
  '665_DISCOVERED': 'قراءة عروض الرقم فقط، بلا شراء.',
  '665_CHOICE_NOT_DISPATCHED': 'رقم العرض لم يصل إلى المودم. لم يُخصم شيء.',
  '665_CHOICE_NO_RESPONSE': 'أُرسل رقم العرض ولم تردّ الشبكة: قد يكون فُعِّل. يُراجَع برسالة الشبكة قبل أي إعادة.',
  '665_REPLY_BY_SMS': 'الشبكة قالت إن الجواب يصل برسالة: يُراجَع بها.',
  '665_REPLY_UNRECOGNIZED': 'ردّ الشبكة بعد اختيار العرض لم يُفهم: يُراجَع قبل أي إعادة.',
  '665_ENDED_BEFORE_CHOICE': 'انتهت الجلسة قبل اختيار العرض. لم يُخصم شيء.',
  '665_ENDED_AFTER_MENU': 'انتهت الجلسة بعد اختيار العرض ولم يصل ردّ: يُراجَع.',
  '665_SEND_RESULT_UNKNOWN': 'لم يصل ردّ الإرسال: يُراجَع قبل أي إعادة.',
  // Ordinary credit (630)
  '630_NETWORK_ACCEPTED': 'الشبكة قبلت التحويل، وتأكيده برسالة الشبكة.',
  '630_SMS_CONFIRMED': 'رسالة الشبكة أكّدت وصول الرصيد للزبون.',
  '630_NETWORK_REJECTED': 'الشبكة رفضت التحويل. لم يُخصم شيء.',
  '630_NETWORK_INSUFFICIENT': 'رصيد الشريحة لا يكفي. لم يُخصم شيء.',
  '630_SMS_INSUFFICIENT': 'رسالة الشبكة: رصيد الشريحة لا يكفي. لم يُخصم شيء.',
  '630_SMS_PIN_REJECTED': 'رسالة الشبكة: الـPIN خاطئ. لم يُخصم شيء.',
  '630_START_NO_RESPONSE': 'المودم لم يردّ على أول طلب. لم يُخصم شيء.',
  '630_START_NOT_DISPATCHED': 'الطلب لم يصل إلى المودم. لم يُخصم شيء.',
  '630_PROMPT_MISMATCH': 'سؤال التأكيد لا يطابق الرقم أو المبلغ، فلم يُؤكَّد. لم يُخصم شيء.',
  '630_CONFIRM_NOT_DISPATCHED': 'التأكيد لم يصل إلى المودم. لم يُخصم شيء.',
  '630_CONFIRM_NOT_SENT': 'لم يُرسل التأكيد. لم يُخصم شيء.',
  '630_CONFIRM_NO_RESPONSE': 'أُرسل التأكيد ولم تردّ الشبكة: يُراجَع برسالة الشبكة.',
  '630_REPLY_UNRECOGNIZED': 'ردّ الشبكة بعد التأكيد لم يُفهم: يُراجَع.',
  '630_NO_FINAL_SMS': 'قبلت الشبكة ولم تصل رسالة التأكيد بعد: يُراجَع.',
  '630_SMS_AMBIGUOUS': 'رسالة الشبكة غير واضحة: يُراجَع.',
  '630_FAILURE_SMS_SEEN': 'رسالة فشل من الشبكة: يُراجَع.',
  '630_SEND_RESULT_UNKNOWN': 'لم يصل ردّ الإرسال: يُراجَع قبل أي إعادة.'
}
const BY_STATUS = {
  queued: 'في الطابور: يُرسل الآن.',
  running: 'جارٍ مع الشبكة الآن.',
  sent: 'جارٍ مع الشبكة الآن.',
  success: 'نجحت العملية.',
  accepted: 'قبلتها الشبكة، والتأكيد برسالتها.',
  rejected: 'رفضتها الشبكة. لم يُخصم شيء.',
  not_sent: 'لم تُرسل. لم يُخصم شيء.',
  failed: 'فشلت. لم يُخصم شيء.',
  review: 'غير محسومة: تُراجَع قبل أي إعادة.'
}
// Why a SIM was left for the next one (flexy-core advance-630.ts, migration 0029)
const MOVED = {
  '665_START_NO_RESPONSE': 'لم تردّ',
  '665_START_NOT_DISPATCHED': 'لم يصلها الطلب'
}

export const explain = (code, status) => CODES[code] || BY_STATUS[status] || 'لا تفاصيل بعد.'
export const movedWhy = (code) => MOVED[code] || 'لم تكمل'

// Times in Algeria (owner rule): 26/10 18:16:48
const ALGIERS = new Intl.DateTimeFormat('fr-DZ', {
  timeZone: 'Africa/Algiers', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
})
export const algeriaTime = (t) => (t ? ALGIERS.format(new Date(t)).replace(',', '') : '—')
// A SIM as the owner names it: «sama-4 · bergoug-n0 · 0656645038 · server-3»
export const simLine = (w) => [w.sim_code, w.sim_label, w.sim_msisdn, w.station_code].filter(Boolean).join(' · ')
