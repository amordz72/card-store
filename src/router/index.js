import { defineRouter } from '#q-app/wrappers'
import { createRouter, createWebHashHistory } from 'vue-router'
import routes from './routes'
import { useCustomerStore } from 'stores/customer'
import { useAdminStore } from 'stores/admin'

export default defineRouter(({ store }) => {
  const router = createRouter({
    scrollBehavior: () => ({ left: 0, top: 0 }),
    routes,
    history: createWebHashHistory(process.env.VUE_ROUTER_BASE)
  })

  router.beforeEach(async (to) => {
    if (to.matched.some((r) => r.meta.admin)) {
      const ok = await useAdminStore(store).check()
      if (!ok) return '/admin/login'
    } else if (to.matched.some((r) => r.meta.customer)) {
      if (!useCustomerStore(store).signedIn) return '/login'
    }
    return true
  })

  return router
})
