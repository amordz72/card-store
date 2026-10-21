import { ref } from 'vue'
import { useCustomerStore } from 'stores/customer'
import * as api from 'src/api/customer'

// Cards where the customer earns something (selling price − what he pays > 0).
// Cards with no profit are never listed, and no percentage is shown to customers (owner decision).
const rows = ref([])
const loaded = ref(false)

export function useMyProfits () {
  const customer = useCustomerStore()

  async function load () {
    const [prices, catalog] = await Promise.all([api.myPrices(customer.token), api.catalog(customer.token)])
    const cat = new Map((catalog || []).map((c) => [c.product_id, c.category]))
    rows.value = (prices || [])
      .filter((r) => r.pay_now != null && Number(r.base_price) - Number(r.pay_now) > 0)
      .map((r) => ({
        ...r,
        category: cat.get(r.product_id) || null,
        // «Mobilis 1000» → «1000» under the Mobilis heading
        short: r.name.startsWith(r.brand + ' ') ? r.name.slice(r.brand.length + 1) : r.name,
        profit: Number(r.base_price) - Number(r.pay_now)
      }))
    loaded.value = true
    return rows.value
  }

  return { rows, loaded, load }
}
