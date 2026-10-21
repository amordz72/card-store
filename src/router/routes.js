// One app for the owner and the customers: the same paths and menu, admin-only pages carry meta.admin
const routes = [
  { path: '/login', component: () => import('pages/customer/LoginPage.vue') },
  {
    path: '/',
    component: () => import('layouts/AppLayout.vue'),
    meta: { auth: true },
    children: [
      { path: '', component: () => import('pages/customer/HomePage.vue'), meta: { title: 'الرئيسية' } },
      { path: 'store', component: () => import('pages/customer/StorePage.vue'), meta: { title: 'المتجر' } },
      { path: 'operations', component: () => import('pages/OperationsSwitch.vue'), meta: { title: 'العمليات' } },
      { path: 'transfers', component: () => import('pages/TransfersInPage.vue'), meta: { title: 'التحويلات' } },
      { path: 'account', component: () => import('pages/customer/AccountPage.vue'), meta: { title: 'حسابي' } },
      // owner only
      { path: 'transfers/out', component: () => import('pages/admin/TransfersPage.vue'), meta: { admin: true, title: 'التحويلات الصادرة' } },
      { path: 'customers', component: () => import('pages/admin/CustomersPage.vue'), meta: { admin: true, title: 'الزبائن' } },
      { path: 'customers/:id', component: () => import('pages/admin/CustomerDetailPage.vue'), props: true, meta: { admin: true, title: 'الزبون' } },
      { path: 'stock', component: () => import('pages/admin/StockPage.vue'), meta: { admin: true, title: 'المخزن' } },
      { path: 'prices', component: () => import('pages/admin/PricesPage.vue'), meta: { admin: true, title: 'أسعار الزبائن' } }
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
