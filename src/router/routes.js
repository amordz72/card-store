const routes = [
  { path: '/login', component: () => import('pages/customer/LoginPage.vue') },
  {
    path: '/',
    component: () => import('layouts/CustomerLayout.vue'),
    meta: { customer: true },
    children: [
      { path: '', component: () => import('pages/customer/HomePage.vue') },
      { path: 'store', component: () => import('pages/customer/StorePage.vue') },
      { path: 'operations', component: () => import('pages/customer/OperationsPage.vue') },
      { path: 'account', component: () => import('pages/customer/AccountPage.vue') }
    ]
  },

  // One login page for everyone; keep the old admin link working
  { path: '/admin/login', redirect: '/login' },
  {
    path: '/admin',
    component: () => import('layouts/AdminLayout.vue'),
    meta: { admin: true },
    children: [
      { path: '', redirect: '/admin/customers' },
      { path: 'customers', component: () => import('pages/admin/CustomersPage.vue') },
      { path: 'customers/:id', component: () => import('pages/admin/CustomerDetailPage.vue'), props: true },
      { path: 'operations', component: () => import('pages/admin/AdminOperationsPage.vue') },
      { path: 'transfers', component: () => import('pages/admin/TransfersPage.vue') },
      { path: 'stock', component: () => import('pages/admin/StockPage.vue') },
      { path: 'rates', component: () => import('pages/admin/RatesPage.vue') },
      // «حساب المحل»: the owner buys like a customer from his own wallet
      { path: 'shop', component: () => import('pages/admin/ShopHomePage.vue'), meta: { shop: true } },
      { path: 'shop/store', component: () => import('pages/customer/StorePage.vue'), meta: { shop: true } },
      { path: 'shop/operations', component: () => import('pages/customer/OperationsPage.vue'), meta: { shop: true } }
    ]
  },

  { path: '/:catchAll(.*)*', redirect: '/' }
]

export default routes
