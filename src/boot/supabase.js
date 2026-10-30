import { defineBoot } from '#q-app/wrappers'
import { createClient } from '@supabase/supabase-js'
import { timedFetch } from 'src/api/perfLog'
import '@fontsource/ibm-plex-sans-arabic/400.css'
import '@fontsource/ibm-plex-sans-arabic/600.css'
import '@fontsource/ibm-plex-sans-arabic/700.css'

// Public by design: security lives in the database functions and grants.
const SUPABASE_URL = 'https://wqyebqzbbpohbnznqdjj.supabase.co'
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_gO4umNBMJ0AWRk19HtKd7A_9X4DibYj'

// One client. Admin sign-in uses supabase.auth; customers never touch it
// (their session is a separate token, see stores/customer.js).
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { storageKey: 'card-store-admin', persistSession: true, autoRefreshToken: true },
  // Every call timed on the phone («سجل البطء»)
  global: { fetch: timedFetch }
})

export default defineBoot(({ app }) => {
  app.config.globalProperties.$supabase = supabase
})
