// One app for the owner and the customers: the same paths and menu, admin-only pages carry meta.admin
// heavy: a page that asks the server a lot on opening; on weak internet the first page opened is the home instead (weakHome.js)
const routes = [
  { path: '/login', component: () => import('pages/customer/LoginPage.vue') },
  // «صفحة الكمبيوتر الجديد» (Flexy Core 0117): no login; trusted from the owner's phone
  { path: '/new', component: () => import('pages/NewPcPage.vue') },
  {
    path: '/',
    component: () => import('layouts/AppLayout.vue'),
    meta: { auth: true },
    children: [
      { path: '', component: () => import('pages/customer/HomePage.vue'), meta: { title: 'الرئيسية' } },
      { path: 'store', component: () => import('pages/customer/StorePage.vue'), meta: { title: 'المتجر' } },
      { path: 'operations', component: () => import('pages/OperationsSwitch.vue'), meta: { heavy: true, title: 'العمليات' } },
      { path: 'transfers', component: () => import('pages/TransfersInPage.vue'), meta: { title: 'التحويلات' } },
      { path: 'account', component: () => import('pages/customer/AccountPage.vue'), meta: { title: 'حسابي' } },
      { path: 'reports', component: () => import('pages/ReportsPage.vue'), meta: { title: 'البلاغات' } },
      { path: 'profits', component: () => import('pages/customer/MyProfitsPage.vue'), meta: { customer: true, title: 'أرباحي في البطاقات' } },
      // owner only
      { path: 'transfers/out', component: () => import('pages/admin/TransfersPage.vue'), meta: { admin: true, title: 'التحويلات الصادرة' } },
      { path: 'customers', component: () => import('pages/admin/CustomersPage.vue'), meta: { heavy: true, admin: true, title: 'الزبائن' } },
      { path: 'customers/:id', component: () => import('pages/admin/CustomerDetailPage.vue'), props: true, meta: { heavy: true, admin: true, title: 'الزبون' } },
      { path: 'stock', component: () => import('pages/admin/StockPage.vue'), meta: { heavy: true, admin: true, title: 'المخزن' } },
      { path: 'prices', component: () => import('pages/admin/PricesPage.vue'), meta: { admin: true, title: 'أسعار ونسب الزبائن' } },
      { path: 'flexy', component: () => import('pages/admin/FlexyTestPage.vue'), meta: { heavy: true, admin: true, title: 'اختبار Flexy' } },
      { path: 'flexy/send', component: () => import('pages/admin/FlexySendPage.vue'), meta: { admin: true, title: 'إرسال فليكسي' } },
      // The admin phone's own screen (2026-10-27): the same page in phone mode, owner only
      { path: 'flexy/phone', component: () => import('pages/admin/FlexySendPage.vue'), meta: { admin: true, phone: true, title: 'فليكسي الهاتف' } },
      // «المراقبة» and «الإحصائيات» in one page with tabs (owner 2026-10-30): ?tab=now|judge|db
      { path: 'flexy/monitor', component: () => import('pages/admin/MonitorHub.vue'), meta: { heavy: true, admin: true, title: 'المراقبة والإحصائيات' } },
      { path: 'flexy/devices', component: () => import('pages/admin/DevicesPage.vue'), meta: { heavy: true, admin: true, title: 'المحطات والشرائح' } },
      { path: 'flexy/shops', component: () => import('pages/admin/FlexyShopsPage.vue'), meta: { heavy: true, admin: true, title: 'فليكسي المحلات' } },
      { path: 'flexy/switches', component: () => import('pages/admin/SwitchesPage.vue'), meta: { admin: true, title: 'المفاتيح' } },
      { path: 'flexy/notebook', component: () => import('pages/admin/NotebookPage.vue'), meta: { admin: true, title: 'دفتر البرنامج' } },
      { path: 'flexy/numbers', component: () => import('pages/admin/NumberMemoryPage.vue'), meta: { admin: true, title: 'ذاكرة الأرقام' } },
      // «ما الجديد» (owner 2026-10-31)
      { path: 'news', component: () => import('pages/admin/NewsPage.vue'), meta: { admin: true, title: 'ما الجديد' } },
      { path: 'ideas', component: () => import('pages/admin/IdeasPage.vue'), meta: { heavy: true, admin: true, title: 'أفكار وأوامر' } },
      { path: 'stats', redirect: '/flexy/monitor?tab=db' },
      { path: 'usage', component: () => import('pages/admin/UsagePage.vue'), meta: { heavy: true, admin: true, title: 'الاستعمال' } },
      { path: 'flexy/offers', component: () => import('pages/admin/OffersPage.vue'), meta: { heavy: true, admin: true, title: 'العروض' } },
      // the owner's page or the customer's page (customers the owner enabled)
      { path: 'idoom', component: () => import('pages/IdoomSwitch.vue'), meta: { heavy: true, title: 'تعبئة إيدوم' } },
      // the queue for the owner and his workers, the order page for customers
      { path: 'game', component: () => import('pages/GameSwitch.vue'), meta: { heavy: true, title: 'شحن الألعاب بالمعرّف' } },
      // services (owner 2026-10-31): the owner's queue, a customer's own orders
      { path: 'services', component: () => import('pages/ServicesSwitch.vue'), meta: { title: 'الخدمات' } },
      // shops the owner enabled (v1.33)
      { path: 'flexy/shop', component: () => import('pages/customer/FlexyShopPage.vue'), meta: { customer: true, title: 'فليكسي' } }
    ]
  },

  // Old links from the two-interface version
  { path: '/admin/login', redirect: '/login' },
  { path: '/admin', redirect: '/' },
  { path: '/admin/shop', redirect: '/' },
  { path: '/admin/shop/store', redirect: '/store' },
  { path: '/admin/shop/operations', redirect: '/operations' },
  { path: '/admin/transfers', redirect: '/transfers/out' },
  { path: '/admin/rates', redirect: '/prices' },
  { path: '/admin/customers/:id', redirect: (to) => '/customers/' + to.params.id },
  { path: '/admin/:page(customers|operations|stock|prices)', redirect: (to) => '/' + to.params.page },

  { path: '/:catchAll(.*)*', redirect: '/' }
]

export default routes
