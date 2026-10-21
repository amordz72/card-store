import { defineStore } from 'pinia'
import { LocalStorage } from 'quasar'
import { useAdminStore } from 'stores/admin'
import { useCustomerStore } from 'stores/customer'

const ROLE_KEY = 'cs_role'

// Who is using the app right now: 'admin' (Supabase Auth) or 'customer' (store token).
// The same screens serve both; menu items and page sections show or hide by this role.
export const useSessionStore = defineStore('session', {
  state: () => ({
    role: null,
    resolved: false
  }),

  getters: {
    isAdmin: (s) => s.role === 'admin'
  },

  actions: {
    // The last login wins when both sessions exist on one device (e.g. testing a customer account)
    async resolve () {
      if (this.resolved) return this.role
      const customer = useCustomerStore()
      const admin = useAdminStore()
      const preferred = LocalStorage.getItem(ROLE_KEY)
      let role = null
      if (preferred === 'customer' && customer.signedIn) role = 'customer'
      else if (preferred === 'admin' && await admin.check()) role = 'admin'
      else if (customer.signedIn) role = 'customer'
      else if (await admin.check()) role = 'admin'
      this.set(role)
      return role
    },

    set (role) {
      this.role = role
      this.resolved = true
      if (role) LocalStorage.set(ROLE_KEY, role)
      else LocalStorage.remove(ROLE_KEY)
    },

    async logout () {
      if (this.isAdmin) await useAdminStore().logout()
      else await useCustomerStore().logout()
      this.set(null)
      this.resolved = false
    }
  }
})
