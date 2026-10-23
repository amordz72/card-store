import { ref } from 'vue'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'
import { useSessionStore } from 'stores/session'

// «شحن الألعاب»: is the service open now (an operator pressed «متاح»), and does this account work the queue?
// The owner always works the queue; a worker is a customer account the owner marked as operator.
// Shared by the menus and the pages.
const isOpen = ref(false)
const isOperator = ref(false)

export function useGameAccess () {
  const customer = useCustomerStore()
  const session = useSessionStore()
  // operator calls: the worker's token, or null for the owner (his Supabase session is checked)
  const opToken = () => (session.isAdmin ? null : customer.token)
  async function refresh () {
    if (session.isAdmin) { isOperator.value = true; return }
    if (!customer.token) { isOpen.value = false; isOperator.value = false; return }
    try {
      const s = await customerApi.gameStatus(customer.token)
      isOpen.value = !!s.is_open
      isOperator.value = !!s.is_operator
    } catch { /* keep the last value; the page shows its own errors */ }
  }
  return { isOpen, isOperator, opToken, refresh }
}
