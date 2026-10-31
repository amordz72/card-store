// «ما الجديد» (owner 2026-10-31): every change the owner sees, one short Arabic line each, newest first.
// Rule for every PR that changes something the owner sees: add its line here in the same PR (developer AGENTS.md).
// id: unique and increasing (date + letter); to: the page it concerns; pr: the repository and number.
export const CHANGELOG = [
  {
    id: '2026-10-31-i',
    date: '2026-10-31',
    title: 'فليكسي: بطاقات سما ومفتاحها',
    items: [
      { text: 'حقل الرقم وحده حتى يكتمل، ثم «رصيد عادي» و«عروض»؛ رقم موبيليس يُقرأ خطه في الخلفية من تلك اللحظة', to: '/flexy/send', pr: 'card-store' },
      { text: '«عروض»: تحميل 3 ثوانٍ، ثم بطاقات Sama Mix (مفتوحة) وSama Talk وSama Net وعروض أخرى بشكل واحد', to: '/flexy/send', pr: 'card-store' },
      { text: 'عرض ليس لخط الزبون: نافذة «لا يوجد عرض…» تختفي وحدها، وخلفها عروض خطه الحقيقية', to: '/flexy/send', pr: 'card-store' },
      { text: 'مفتاح «لوحة سما التلقائية» في «المفاتيح» (بعد تطبيق s166)', to: '/flexy/switches', pr: 'card-store، s166' },
      { text: 'الرقم لا يبقى بعد تحديث الصفحة، وزر المسح خارج الحقل، والرقم أقرب في موزيلا', to: '/flexy/send', pr: 'card-store' }
    ]
  },
  {
    id: '2026-10-31-h',
    date: '2026-10-31',
    title: 'لوحة سما الجديدة',
    items: [
      { text: 'عروض موبيليس في تبويبات مغلقة أولًا (Sama Mix، Sama Net، عروض أخرى)، والصفوف ثابتة لا تُعتَّم ولا تتغير وحدها', to: '/flexy/send', pr: 'card-store' },
      { text: 'الضغطة تُرسل مباشرة؛ إن لم يكن العرض لخط الزبون: «لا يوجد عرض متاح لهذا الرقم» ويختفي ذلك الصف وحده', to: '/flexy/send', pr: 'card-store' },
      { text: 'لا كلمة «أوتوميكس» ولا «عُرف الخط» على الشاشة: العرض التلقائي اسمه Sama Mix للجميع', to: '/flexy/send', pr: 'card-store' }
    ]
  },
  {
    id: '2026-10-31-g',
    date: '2026-10-31',
    title: 'الألعاب من رصيد المنصة',
    items: [
      { text: 'منتج ألعاب «من رصيد المنصة» (topup-dz): لا يأخذ بطاقة من المخزن، تشحنه من رصيدك هناك. فعّله وسعر المنصة من إعدادات «شحن الألعاب»', to: '/game', pr: 'card-store، s165' },
      { text: 'يطلبه الزبون من صفحته، وتطلبه أنت باسم زبون؛ «لم يتم» يعيد المبلغ كاملًا', to: '/game', pr: 'card-store، s165' }
    ]
  },
  {
    id: '2026-10-31-f',
    date: '2026-10-31',
    title: 'Free Fire من الهاتف',
    items: [
      { text: 'شحن Free Fire من هاتف Rech-Doom: مفتاح «Free Fire» لكل هاتف في «تعبئة إيدوم»', to: '/idoom', pr: 'card-store #280' },
      { text: 'تحت كل طلب أخذه هاتف: ما رآه الهاتف ونص الموقع، وأنت تحكم بـ«تمّ» أو «لم يتم»', to: '/game', pr: 'card-store #280' },
      { text: 'Rech-Doom 0.9.2: يتوقف عند أي نافذة أو فحص لا يعرفه، وتكمل أنت بـ«أكمل»', to: '/idoom', pr: 'Rech-Doom #9' },
      { text: '«طبّق» ملفات SQL من قائمة الشريط الأزرق مباشرة، و«ما الجديد» هذه الصفحة', pr: 'card-store' }
    ]
  },
  {
    id: '2026-10-31-e',
    date: '2026-10-31',
    title: 'الشكل الجديد',
    items: [
      { text: 'الشكل الجديد للجميع: بطاقات بيضاء، رأس صفحة بالرصيد في الوسط، قائمة بأقسام', to: '/', pr: 'card-store #274–#279' },
      { text: 'فليكسي: لوحة سما ثابتة، الأسطر لا تتحرك ويتغيّر النص فقط حين يُعرف الخط (للمحلات أيضًا)', pr: 'card-store #276، #279' },
      { text: '«تثبيت التطبيق» في القائمة: المتجر كبرنامج على الكمبيوتر والهاتف', pr: 'card-store #278' }
    ]
  },
  {
    id: '2026-10-31-d',
    date: '2026-10-31',
    title: 'الإشعارات',
    items: [
      { text: 'الشريطان الأحمر والأزرق فوق الأزرار السفلية، في الرئيسية فقط', to: '/', pr: 'card-store #275' },
      { text: 'الأزرق سطر واحد «N جديدة · M تنتظرك»، والقائمة عند الضغط', pr: 'card-store #273' },
      { text: 'الأحمر ينطوي، ويتذكّر الهاتف حالته', pr: 'card-store #277' },
      { text: '«نسخ الشاشة» للمدير فقط', pr: 'card-store #272' }
    ]
  },
  {
    id: '2026-10-31-c',
    date: '2026-10-31',
    title: 'التغذية والهاتف والخدمات',
    items: [
      { text: 'تغذية سما: الشريحة غير المتاحة (كمبيوتر أو هاتف مطفأ) لا تُسحب لها بطاقة، والسبب ظاهر', to: '/flexy/monitor', pr: 'flexy-core #248، card-store #271' },
      { text: 'هاتف الإدارة لا يبقى «مشغولًا» بعد اختبار USSD (يعمل بعد نشر flexy-api)', pr: 'flexy-core #248' },
      { text: 'الخدمات: صفحة «الخدمات» وطلبات الزبائن وطابورك مفعّلة في القاعدة', to: '/services', pr: 'flexy-core #250' }
    ]
  },
  {
    id: '2026-10-31-b',
    date: '2026-10-31',
    title: 'Rech-Doom',
    items: [
      { text: 'Rech-Doom 0.8.4: زرّا idoom Internet و4G يوجدان وحدهما، أو تضبطهما على صورة شاشة الهاتف', to: '/idoom', pr: 'Rech-Doom #7' },
      { text: 'ملف التحميل يحمل رقم نسخته', to: '/idoom', pr: 'card-store #270' }
    ]
  }
]

export const latestNewsId = () => CHANGELOG[0]?.id || ''
