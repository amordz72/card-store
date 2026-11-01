import { defineRouter } from '#q-app/wrappers'
import { createRouter, createWebHashHistory } from 'vue-router'
import routes from './routes'
import { useSessionStore } from 'stores/session'
import { useCustomerStore } from 'stores/customer'
import * as adminApi from 'src/api/admin'
import * as customerApi from 'src/api/customer'

export default defineRouter(({ store }) => {
  const router = createRouter({
    // «#feed» opens the place itself (owner 2026-11-01: «لا أدري أين التغذية»); otherwise the top
    scrollBehavior: (to) => (to.hash ? { el: to.hash, top: 70 } : { left: 0, top: 0 }),
    routes,
    history: createWebHashHistory(process.env.VUE_ROUTER_BASE)
  })

  router.beforeEach(async (to) => {
    if (!to.matched.some((r) => r.meta.auth)) return true
    const role = await useSessionStore(store).resolve()
    if (!role) return '/login'
    // a customer opening an owner page lands on the home page
    if (to.matched.some((r) => r.meta.admin) && role !== 'admin') return '/'
    if (to.matched.some((r) => r.meta.customer) && role !== 'customer') return '/'
    return true
  })

  // «الاستعمال» (v1.44): the page's path pattern only (no ids), never waited for, never an error shown
  router.afterEach((to) => {
    const page = to.matched.at(-1)?.path
    if (!page || !to.matched.some((r) => r.meta.auth)) return
    const session = useSessionStore(store)
    const sent = session.isAdmin ? adminApi.pageSeen(page)
      : session.role === 'customer' ? customerApi.pageSeen(useCustomerStore(store).token, page) : null
    sent?.catch(() => {})
  })

  return router
})
