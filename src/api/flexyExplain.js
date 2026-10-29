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
  // Owner 2026-10-29: «Transaction échouée» = the number has no such offer (e.g. 50 DA to a Sama Mix line)
  '630_SMS_TRANSACTION_FAILED': 'رسالة الشبكة: «Transaction échouée»، هذا الرقم ليس له هذا العرض. لم يُخصم شيء وأُرجع المبلغ.',
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
  '630_SEND_RESULT_UNKNOWN': 'لم يصل ردّ الإرسال: يُراجَع قبل أي إعادة.',
  // Djezzy ordinary credit (760): the flow recorded live 2026-10-27 (prompt 1/2, then «… TRANSFERE … VERS LE NUMERO …»)
  '760_NETWORK_TRANSFERRED': 'الشبكة حوّلت المبلغ إلى رقم الزبون فورًا، ونصّها هو الدليل.',
  '760_REPLY_UNRECORDED': 'ردّ الشبكة محفوظ كما وصل ولم يُسجَّل تصنيفه بعد: اقرأه وقرّر.',
  '760_START_NO_RESPONSE': 'أُرسل الكود ولم تردّ الشبكة: قد يكون نُفّذ. يُراجَع قبل أي إعادة.',
  '760_START_NOT_DISPATCHED': 'الطلب لم يصل إلى المودم. لم يُخصم شيء.',
  '760_CONFIRM_NOT_DISPATCHED': 'التأكيد لم يصل إلى المودم. لم يُخصم شيء.',
  '760_CONFIRM_NOT_SENT': 'لم يُرسل التأكيد. لم يُخصم شيء.',
  '760_CONFIRM_NO_RESPONSE': 'أُرسل التأكيد ولم تردّ الشبكة: يُراجَع.',
  '760_NO_COMMAND_RECORDED': 'لم يصل أي أمر إلى المودم. لم يُخصم شيء.',
  '760_NO_DJEZZY_READY': 'لا شريحة جيزي معتمدة ومتصلة ولها PIN على مودم حر. لم يُرسل شيء.',
  '760_PREVIOUS_TRANSFER_UNSETTLED_OR_TOO_RECENT': 'لهذا الرقم عملية جيزي غير محسومة أو نفس المبلغ قبل أقل من دقيقة. لم يُرسل شيء.',
  '760_SEND_RESULT_UNKNOWN': 'لم يصل ردّ الإرسال: يُراجَع قبل أي إعادة.',
  // Ooredoo ordinary credit (590): recorded live 2026-10-27 (prompt 1/2, then «Recharge … realisee avec succes»)
  '590_NETWORK_TRANSFERRED': 'الشبكة شحنت رقم الزبون فورًا، ونصّها مع رقم العملية هو الدليل.',
  '590_NUMBER_NOT_RECHARGEABLE': 'الشبكة قالت إن هذا الرقم لا يمكن شحنه. لم يُخصم شيء.',
  // Before «1» nothing is bought (Flexy Core, owner 2026-10-28): said as such, never «قيد المراجعة»
  '590_CUSTOMER_LOAN': 'الزبون عليه دين «سبقلي» لدى أوريدو، والشبكة سألت عن دفعه قبل التحويل. لم يُرسل شيء.',
  '590_NEW_REPLY_BEFORE_CONFIRM': 'ردّت الشبكة بخطوة جديدة قبل التأكيد. لم يُرسل شيء، وأُبلغت الإدارة.',
  '760_NEW_REPLY_BEFORE_CONFIRM': 'ردّت الشبكة بخطوة جديدة قبل التأكيد. لم يُرسل شيء، وأُبلغت الإدارة.',
  '760O_NEW_REPLY_BEFORE_CONFIRM': 'ردّت الشبكة بغير قائمة العروض. لم يُرسل شيء، وأُبلغت الإدارة.',
  '760_NETWORK_TECHNICAL_DIFFICULTIES': 'شبكة جيزي فيها عطل مؤقت. لم يُرسل شيء، أعد بعد قليل.',
  '760_PREVIOUS_UNSETTLED': 'لهذا الرقم عملية جيزي لم تُحسم بعد. لم يُرسل شيء.',
  '760O_PREVIOUS_UNSETTLED': 'لهذا الرقم عملية جيزي لم تُحسم بعد. لم يُرسل شيء.',
  '590_PREVIOUS_UNSETTLED': 'لهذا الرقم عملية أوريدو لم تُحسم بعد. لم يُرسل شيء.',
  '760_SAME_NUMBER_RECENT': 'لهذا الرقم عملية قبل أقل من دقيقتين. لم يُرسل شيء.',
  '760O_SAME_NUMBER_RECENT': 'لهذا الرقم عملية قبل أقل من دقيقتين. لم يُرسل شيء.',
  '590_SAME_NUMBER_RECENT': 'لهذا الرقم عملية قبل أقل من دقيقتين. لم يُرسل شيء.',
  OWNER_SETTLED_NOT_SENT: 'حسمها المدير: لم تُرسل.',
  '590_REPLY_UNRECORDED': 'ردّ الشبكة محفوظ كما وصل ولم يُسجَّل تصنيفه بعد: اقرأه وقرّر.',
  '590_START_NO_RESPONSE': 'أُرسل الكود ولم تردّ الشبكة قبل التأكيد. لم يُخصم شيء.',
  '590_START_NOT_DISPATCHED': 'الطلب لم يصل إلى المودم. لم يُخصم شيء.',
  '590_CONFIRM_NOT_DISPATCHED': 'التأكيد لم يصل إلى المودم. لم يُخصم شيء.',
  '590_CONFIRM_NOT_SENT': 'لم يُرسل التأكيد. لم يُخصم شيء.',
  '590_CONFIRM_NO_RESPONSE': 'أُرسل التأكيد ولم تردّ الشبكة: يُراجَع.',
  '590_NO_COMMAND_RECORDED': 'لم يصل أي أمر إلى المودم. لم يُخصم شيء.',
  '590_NO_OOREDOO_READY': 'لا شريحة أوريدو معتمدة ومتصلة ولها PIN على مودم حر. لم يُرسل شيء.',
  '590_PREVIOUS_TRANSFER_UNSETTLED_OR_TOO_RECENT': 'لهذا الرقم عملية أوريدو غير محسومة أو نفس المبلغ قبل أقل من دقيقة. لم يُرسل شيء.',
  '590_SEND_RESULT_UNKNOWN': 'لم يصل ردّ الإرسال: يُراجَع قبل أي إعادة.',
  // Djezzy offers (760 without an amount), recorded live 2026-10-27: the confirmation SMS goes to the customer,
  // so the SIM's balance drop (*766#, a minute later) is the proof.
  // Ooredoo offers (*585*, Flexy Core 0059): the PIN after the network names the price is the money step
  '585_NETWORK_OK': 'ردّت الشبكة «OK» للرقم: نجح العرض.',
  '585_NEW_REPLY_BEFORE_PIN': 'ردّت الشبكة بنص غير مسجّل قبل الـPIN. لم يُخصم شيء، وأُبلغت الإدارة.',
  '585_CODE_SHOWN_TWICE': 'رمز العرض ظهر مرتين في القائمة، فلم يُختر. لم يُخصم شيء.',
  '585_OFFER_NOT_IN_MENU': 'قائمة الرقم لا تحمل هذا العرض برمزه واسمه. لم يُخصم شيء، وحُفظت قائمة الرقم.',
  '585_START_NO_RESPONSE': 'المودم لم يردّ على أول طلب. لم يُخصم شيء.',
  '585_CHOICE_NO_RESPONSE': 'لا ردّ بعد اختيار العرض. لم يُرسل الـPIN، فلم يُخصم شيء.',
  '585_PIN_NO_RESPONSE': 'أُرسل الـPIN ولم يصل ردّ: قد يكون خُصم، يحسمه الرصيد.',
  '585_REPLY_UNRECORDED': 'ردّ غير مسجّل بعد الـPIN: قد يكون خُصم، يحسمه الرصيد.',
  '585_PREVIOUS_UNSETTLED': 'لهذا الرقم عملية أوريدو لم تُحسم بعد. لم يُرسل شيء.',
  '585_SAME_NUMBER_RECENT': 'لهذا الرقم عملية قبل أقل من دقيقتين. لم يُرسل شيء.',
  '585_NO_CATALOG_OFFER_IN_MENU': 'قائمة الرقم لا تحمل أي عرض من عروضنا المسجّلة.',
  '760O_NETWORK_PROCESSING': 'الشبكة قبلت العرض وهو قيد المعالجة؛ يُحسم بفرق رصيد الشريحة بعد دقيقة.',
  '760O_DISCOVERED': 'قراءة قائمة عروض الرقم فقط، بلا شراء.',
  '760O_OFFER_NOT_IN_MENU': 'قائمة الرقم لا تحمل هذا العرض بالرقم المعتمد (نوع الخط مختلف أو تغيّرت القائمة). لم يُخصم شيء.',
  '760O_CONFIRM_PROMPT_MISMATCH': 'رسالة التأكيد لا تحمل اسم العرض ورقم الزبون، فلم يُؤكَّد. لم يُخصم شيء.',
  '760O_MENU_UNRECOGNIZED': 'ردّ الشبكة ليس قائمة عروض: محفوظ كما وصل. لم يُخصم شيء.',
  '760O_PATH_MENU_MISSING': 'القائمة الفرعية لم تظهر، فتوقف المسار. لم يُخصم شيء.',
  '760O_START_NO_RESPONSE': 'المودم لم يردّ على أول طلب. لم يُخصم شيء.',
  '760O_START_NOT_DISPATCHED': 'الطلب لم يصل إلى المودم. لم يُخصم شيء.',
  '760O_CHOICE_NO_RESPONSE': 'أُرسل رقم العرض ولم تردّ الشبكة قبل التأكيد. لم يُخصم شيء.',
  '760O_CHOICE_NOT_DISPATCHED': 'رقم العرض لم يصل إلى المودم. لم يُخصم شيء.',
  '760O_CONFIRM_NO_RESPONSE': 'أُرسل التأكيد ولم تردّ الشبكة: يُراجَع بفرق الرصيد.',
  '760O_CONFIRM_NOT_DISPATCHED': 'التأكيد لم يصل إلى المودم. لم يُخصم شيء.',
  '760O_REPLY_UNRECORDED': 'ردّ الشبكة بعد التأكيد محفوظ ولم يُسجَّل تصنيفه: اقرأه وقرّر.',
  '760O_ENDED_BEFORE_CONFIRM': 'انتهت الجلسة قبل التأكيد. لم يُخصم شيء.',
  '760O_BALANCE_UNEXPLAINED': 'رصيد الشريحة تغيّر بغير سعر العرض: يُراجَع (ربما تغيّر السعر).',
  '760O_PREVIOUS_OFFER_UNSETTLED_OR_TOO_RECENT': 'لهذا الرقم عرض جيزي غير محسوم أو نفس العرض قبل أقل من دقيقة. لم يُرسل شيء.',
  '760O_SEND_RESULT_UNKNOWN': 'لم يصل ردّ الإرسال: يُراجَع قبل أي إعادة.'
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
// «Mixed N» is the automix (Flexy Core 0071+, owner 2026-10-29): «مختلط N»; the network names the line's offer it took
export const offerTitle = (label) => (/^Mixed \d+$/.test(label || '') ? 'مختلط ' + label.slice(6) + ' (أوتوميكس)' : label)
export const simLine = (w) => [w.sim_code, w.sim_label, w.sim_msisdn, w.station_code].filter(Boolean).join(' · ')
