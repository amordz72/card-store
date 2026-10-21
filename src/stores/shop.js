import { defineStore } from 'pinia'
import { LocalStorage } from 'quasar'
import * as api from 'src/api/admin'

const HIDE_KEY = 'shop_hide_amounts'

// «حساب المحل»: the owner's own wallet, reached from the admin UI
export const useShopStore = defineStore('shop', {
  state: () => ({
    summary: null,          // { all, since_last, range } rows from store_admin_shop_summary
    hideAmounts: LocalStorage.getItem(HIDE_KEY) === true
  }),

  getters: {
    balance: (s) => s.summary?.all?.balance ?? 0
  },

  actions: {
    async refresh (from, to) {
      const rows = await api.shopSummary(from, to)
      this.summary = Object.fromEntries(rows.map((r) => [r.scope, r]))
      return this.summary
    },

    toggleHide () {
      this.hideAmounts = !this.hideAmounts
      LocalStorage.set(HIDE_KEY, this.hideAmounts)
    }
  }
})
