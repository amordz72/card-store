import { defineRouter } from '#q-app/wrappers'
import { createRouter, createWebHashHistory } from 'vue-router'
import routes from './routes'
import { useSessionStore } from 'stores/session'

export default defineRouter(({ store }) => {
  const router = createRouter({
    scrollBehavior: () => ({ left: 0, top: 0 }),
    routes,
    history: createWebHashHistory(process.env.VUE_ROUTER_BASE)
  })

  router.beforeEach(async (to) => {
    if (!to.matched.some((r) => r.meta.auth)) return true
    const role = await useSessionStore(store).resolve()
    if (!role) return '/login'
    // a customer opening an owner page lands on the home page
    if (to.matched.some((r) => r.meta.admin) && role !== 'admin') return '/'
    return true
  })

  return router
})
