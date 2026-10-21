import { computed } from 'vue'
import { useCustomerStore } from 'stores/customer'
import { useShopStore } from 'stores/shop'
import { useSessionStore } from 'stores/session'
import * as customerApi from 'src/api/customer'
import * as adminApi from 'src/api/admin'

// The same store/operations screens serve a customer and the owner (who buys from «حساب المحل»).
// This picks the right API, balance and amount-hiding state from the signed-in role.
export function useBuyer () {
  const customer = useCustomerStore()
  const shop = useShopStore()
  const session = useSessionStore()
  const isShop = computed(() => session.isAdmin)

  return {
    isShop,
    hide: computed(() => (isShop.value ? shop.hideAmounts : customer.hideAmounts)),
    toggleHide: () => (isShop.value ? shop.toggleHide() : customer.toggleHide()),
    balance: computed(() => (isShop.value ? shop.balance : customer.profile?.balance)),
    refresh: () => (isShop.value ? shop.refresh() : customer.refresh()),
    catalog: () => (isShop.value ? adminApi.shopCatalog() : customerApi.catalog(customer.token)),
    buy: (productId, qty, requestId) => (isShop.value
      ? adminApi.shopBuy(productId, qty, requestId)
      : customerApi.buy(customer.token, productId, qty, requestId)),
    orders: (f) => (isShop.value
      ? adminApi.orders({ ...f, scope: 'shop' })
      : customerApi.orders(customer.token, f)),
    // shop codes come back in full for the admin; customer codes are the customer's own
    orderCodes: (orderId) => (isShop.value
      ? adminApi.orderCodes(orderId).then((rows) => rows.map((c) => ({ code: c.masked_code, serial: c.serial, status: c.status })))
      : customerApi.orderCodes(customer.token, orderId))
  }
}
