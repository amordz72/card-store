import { ref } from 'vue'
import { Notify } from 'quasar'
import { useRouter } from 'vue-router'
import { useCustomerStore } from 'stores/customer'
import { useSessionStore } from 'stores/session'

// Runs an async action with a busy flag and Arabic error notification.
// An expired customer session sends the user back to the login page.
export function useRun () {
  const busy = ref(false)
  const router = useRouter()
  const customer = useCustomerStore()
  const session = useSessionStore()

  async function run (fn, { success } = {}) {
    busy.value = true
    try {
      const result = await fn()
      if (success) Notify.create({ type: 'positive', message: typeof success === 'function' ? success(result) : success })
      return result
    } catch (e) {
      if (e.code === 'INVALID_SESSION') {
        customer.clear()
        session.set(null)
        session.resolved = false
        router.replace('/login')
      }
      Notify.create({ type: 'negative', message: e.message || 'حدث خطأ.' })
      return undefined
    } finally {
      busy.value = false
    }
  }

  return { busy, run }
}
