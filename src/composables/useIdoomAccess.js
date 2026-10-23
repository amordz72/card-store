import { ref } from 'vue'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'

// Is «تعبئة إيدوم» enabled for the signed-in customer, and is the top-up phone online?
// Shared by the menus (bottom bar, side menu) and the page. The owner always has it.
const enabled = ref(false)
const phoneOnline = ref(false)

export function useIdoomAccess () {
  const customer = useCustomerStore()
  async function refresh () {
    if (!customer.token) { enabled.value = false; return }
    try {
      const s = await customerApi.idoomStatus(customer.token)
      enabled.value = !!s.enabled
      phoneOnline.value = !!s.phone_online
    } catch { /* keep the last value; the page shows its own errors */ }
  }
  return { enabled, phoneOnline, refresh }
}
