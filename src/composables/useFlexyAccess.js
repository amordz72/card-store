import { ref } from 'vue'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'

// Is «فليكسي» enabled for the signed-in shop, and is sending open now? Shared by the menus and the page.
const enabled = ref(false)
const open = ref(false)
const maxAmount = ref(0)
const offers = ref(false)

export function useFlexyAccess () {
  const customer = useCustomerStore()
  async function refresh () {
    if (!customer.token) { enabled.value = false; return }
    try {
      const s = await customerApi.flexyStatus(customer.token)
      enabled.value = !!s.enabled
      open.value = !!s.open
      maxAmount.value = s.max_amount || 0
      offers.value = !!s.offers
    } catch { /* keep the last value; the page shows its own errors */ }
  }
  return { enabled, open, maxAmount, offers, refresh }
}
