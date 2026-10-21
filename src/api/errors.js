// Database exception codes → Arabic messages
const MESSAGES = {
  INVALID_SESSION: 'انتهت الجلسة. سجّل الدخول من جديد.',
  INVALID_LOGIN: 'رقم الهاتف أو كلمة السر غير صحيحة.',
  INSUFFICIENT_BALANCE: 'الرصيد لا يكفي لهذه العملية.',
  OUT_OF_STOCK: 'الكمية المطلوبة غير متوفرة الآن.',
  DEBT_LIMIT: 'المبلغ يتجاوز حد الدين المسموح.',
  SELF_TOPUP_DISABLED: 'الشحن الذاتي غير مفعّل لحسابك.',
  PRODUCT_NOT_FOUND: 'هذه البطاقة غير متاحة.',
  INVALID_QTY: 'الكمية غير صحيحة.',
  INVALID_AMOUNT: 'المبلغ غير صحيح.',
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
