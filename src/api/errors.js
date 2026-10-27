// Database exception codes → Arabic messages
const MESSAGES = {
  INVALID_SESSION: 'انتهت الجلسة. سجّل الدخول من جديد.',
  INVALID_LOGIN: 'رقم الهاتف أو كلمة السر غير صحيحة.',
  INSUFFICIENT_BALANCE: 'الرصيد لا يكفي لهذه العملية.',
  OUT_OF_STOCK: 'الكمية المطلوبة غير متوفرة الآن.',
  INVALID_LINE: 'رقم الخط غير صحيح: ثابت 9 أرقام يبدأ بـ 0، أو 4G من 12 رقمًا يبدأ بـ 213.',
  RATE_LIMIT_LINE: 'هذا الرقم فُحص 3 مرات في الساعة الأخيرة. انتظر قليلًا.',
  RATE_LIMIT_ACCOUNT: 'بلغت حد 20 فحصًا في الساعة. انتظر قليلًا.',
  NOT_CANCELLABLE: 'لا يمكن إلغاء العملية بعد أن استلمها الهاتف.',
  CARD_LINE_MISMATCH: 'البطاقة لا تناسب الخط: خط 4G (213…) يأخذ بطاقة Idoom 4G فقط، والخط الثابت يأخذ بطاقة Idoom ADSL فقط.',
  NOT_IDOOM_CARD: 'هذه ليست بطاقة IDOOM.',
  DEBT_LIMIT: 'المبلغ يتجاوز حد الدين المسموح.',
  SELF_TOPUP_DISABLED: 'الشحن الذاتي غير مفعّل لحسابك.',
  PRODUCT_NOT_FOUND: 'هذه البطاقة غير متاحة.',
  INVALID_QTY: 'الكمية غير صحيحة.',
  INVALID_AMOUNT: 'المبلغ غير صحيح.',
  INVALID_PIN: 'رمز القفل من 4 إلى 6 أرقام.',
  AMOUNT_STEP_500: 'الشحن الذاتي بمضاعفات 500 دج فقط.',
  INVALID_PASSWORD: 'كلمة السر الحالية غير صحيحة.',
  PASSWORD_TOO_SHORT: 'كلمة السر 8 أحرف على الأقل.',
  PASSWORD_TOO_LONG: 'كلمة السر طويلة جدًا.',
  INVALID_PHONE: 'رقم الهاتف غير صحيح (10 أرقام يبدأ بـ 05 أو 06 أو 07).',
  PHONE_EXISTS: 'هذا الرقم مسجّل لزبون آخر.',
  NOT_ADMIN: 'هذا الحساب ليس مديرًا للمتجر.',
  ALREADY_REVERSED: 'هذه الحركة استُردّت من قبل.',
  NOT_REVERSIBLE: 'هذه الحركة لا تُسترد.',
  NO_CODES: 'لا توجد أكواد للإضافة.',
  TOO_MANY_CODES: 'أكثر من 5000 كود في دفعة واحدة.',
  INVALID_COST: 'سعر الشراء غير صحيح.',
  COST_REQUIRED: 'سعر الشراء إجباري.',
  COST_MISSING: 'هذه البطاقة بلا سعر شراء مسجّل؛ حدّد لها سعرًا ثابتًا أو أوقفها.',
  INVALID_PRICE_RULE: 'قيمة السعر غير صحيحة.',
  SHOP_PAYS_COST: 'حساب المحل يشتري دائمًا بسعر الشراء.',
  SUPPLIER_EXISTS: 'هذه المنصة موجودة.',
  INVALID_PCT: 'النسبة بين 0 و 50.',
  ORDER_NOT_FOUND: 'العملية غير موجودة.',
  CODE_NOT_FOUND: 'الكود غير موجود.',
  REASON_REQUIRED: 'اكتب السبب.',
  NO_SUSPECT_CARD: 'لا توجد بطاقة مشكوك فيها لهذا المنتج.',
  BATCH_NOT_FOUND: 'الدفعة غير موجودة.',
  BRAND_NOT_FOUND: 'العلامة غير موجودة.',
  INVALID_IMAGE: 'الصورة غير مقبولة (PNG أو JPG أو WEBP فقط).',
  IMAGE_TOO_BIG: 'الصورة كبيرة جدًا.',
  INVALID_REASON: 'اختر سببًا صحيحًا.',
  NOT_REPORTABLE: 'لا يمكن الإبلاغ عن هذه البطاقة (عملية مسترجعة أو بطاقة ملغاة).',
  REPORT_WINDOW_CLOSED: 'انتهت مهلة الإبلاغ عن هذه البطاقة.',
  ALREADY_REPORTED: 'أبلغت عن هذه البطاقة من قبل.',
  REPORT_NOT_FOUND: 'البلاغ غير موجود.',
  ALREADY_RESOLVED: 'هذا البلاغ عولج من قبل.',
  INVALID_LINK: 'الرابط غير صحيح: رابط خارجي يبدأ بـ https://، أو صفحة من القائمة.',
  INVALID_ORIGIN: 'الموقع غير صحيح: اكتب https:// واسم الموقع فقط، بلا مسار وبلا *.',
  TOO_MANY_ORIGINS: 'الحد 3 مواقع إضافية.',
  INVALID_DATES: 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية.',
  BANNER_NOT_FOUND: 'الإعلان غير موجود.',
  TOO_MANY_BANNERS: 'الحد 20 إعلانًا. احذف إعلانًا قديمًا أولًا.',
  IDOOM_NOT_ENABLED: 'تعبئة إيدوم غير مفعّلة لحسابك. اطلب تفعيلها من المحل.',
  IDOOM_PHONE_OFFLINE: 'خدمة التعبئة متوقفة الآن (هاتف التعبئة غير متصل). حاول بعد قليل.',
  PHONE_BUSY: 'هذا الهاتف ينفذ عملية الآن. انتظر انتهاءها ثم عطّله.',
  PHONE_NOT_FOUND: 'الهاتف غير موجود.',
  PHONE_ACTIVE: 'عطّل الهاتف أولًا، ثم احذفه.',
  IDOOM_LINE_BUSY: 'لهذا الخط تعبئة قيد التنفيذ. انتظر نتيجتها.',
  IDOOM_TOO_MANY: 'لديك تعبئات كثيرة الآن. انتظر انتهاءها ثم حاول.',
  NOT_RETRYABLE: 'لا يمكن إعادة هذه العملية.',
  NOT_IN_REVIEW: 'هذه العملية ليست قيد المراجعة.',
  CUSTOMER_NOT_FOUND: 'الزبون غير موجود.',
  INVALID_PLAYER_ID: 'معرّف اللاعب أرقام فقط (من 5 إلى 15 رقمًا).',
  NOT_GAME_CARD: 'هذه البطاقة لا تُشحن بمعرّف اللاعب.',
  GAME_CLOSED: 'خدمة الشحن متوقفة الآن. يمكنك شراء البطاقة من المتجر وشحنها بنفسك.',
  GAME_PLAYER_BUSY: 'لهذا المعرّف طلب شحن قيد التنفيذ. انتظر نتيجته.',
  GAME_TOO_MANY: 'لديك طلبات شحن كثيرة الآن. انتظر انتهاءها ثم حاول.',
  PHONE_WORKING: 'الهاتف يشحن هذا الطلب الآن. انتظر نتيجته (أو 10 دقائق إن توقف الهاتف).',
  GAME_NOT_OPEN: 'هذا الطلب لم يعد في الانتظار (أخذه غيرك أو انتهى).',
  NOT_OPERATOR: 'هذا الحساب ليس عامل شحن.',
  FLEXY_NOT_ENABLED: 'الفليكسي غير مفعّل لحسابك. اطلب من المحل تفعيله.',
  FLEXY_CLOSED: 'الفليكسي متوقف الآن. حاول بعد قليل.',
  FLEXY_PHONE_NOT_MOBILIS: 'الرقم ليس موبيليس. أدخل رقمًا يبدأ بـ 06.',
  FLEXY_AMOUNT_OUT_OF_RANGE: 'المبلغ خارج الحد المسموح.',
  FLEXY_PHONE_BUSY: 'لهذا الرقم إرسال قيد التنفيذ. انتظر نتيجته.',
  FLEXY_TOO_MANY: 'لديك إرسالات كثيرة الآن. انتظر انتهاءها ثم حاول.',
  FLEXY_RATE_MISSING: 'الفليكسي غير جاهز لحسابك بعد. اطلب من المحل.',
  FLEXY_OFFERS_NOT_READY: 'العروض ستتوفر قريبًا.',
  FLEXY_OFFER_INVALID: 'هذا العرض غير معروف. أعد الاستكشاف.',
  OFFER_SAMA_DISABLED: 'هذا العرض غير متوفر الآن.',
  FLEXY_UNAVAILABLE: 'الخدمة غير متاحة الآن. حاول بعد قليل.',
  APP_SEND_DISABLED: 'الفليكسي متوقف الآن. حاول بعد قليل.',
  PHONE_NOT_MOBILIS: 'الرقم ليس موبيليس. أدخل رقمًا يبدأ بـ 06.',
  FLEXY_NOT_CONFIGURED: 'الفليكسي غير جاهز بعد.',
  FLEXY_REFUSED: 'لم يُقبل الطلب. حاول مرة أخرى.',
  NETWORK: 'تعذّر الاتصال. تحقق من الإنترنت ثم حاول.'
}

export class StoreError extends Error {
  constructor (code, raw) {
    super(MESSAGES[code] || 'حدث خطأ. حاول مرة أخرى.')
    this.code = code
    this.raw = raw
  }
}

export function toStoreError (err) {
  const text = (err && (err.message || err.details)) || ''
  const code = Object.keys(MESSAGES).find((k) => text.includes(k))
  if (!code && /Failed to fetch|NetworkError|network/i.test(text)) {
    return new StoreError('NETWORK', err)
  }
  return new StoreError(code || 'UNKNOWN', err)
}
