import { supabase } from 'boot/supabase'
import { toStoreError } from './errors'

// Every store_* call goes through here so errors are always mapped the same way.
export async function rpc (fn, args = {}) {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw toStoreError(error)
  return data
}

// One id per user action. Reusing it on retry makes the database apply the action once.
export function newRequestId () {
  return crypto.randomUUID()
}
