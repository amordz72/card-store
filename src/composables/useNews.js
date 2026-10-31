// «ما الجديد»: what this device has seen of the changelog (localStorage), shared by the page, the menu and the home line
import { ref } from 'vue'
import { CHANGELOG, latestNewsId } from 'src/data/changelog'

const KEY = 'cs_news_seen'
const read = () => { try { return localStorage.getItem(KEY) || '' } catch { return '' } }
const seen = ref(read())

export const newsSeen = () => seen.value
/** Lines added since this device last opened «ما الجديد» */
export const unseenNews = () => CHANGELOG.filter((e) => !seen.value || e.id > seen.value).reduce((n, e) => n + e.items.length, 0)
export function markNewsSeen () {
  seen.value = latestNewsId()
  try { localStorage.setItem(KEY, seen.value) } catch { /* private mode */ }
}
export const newsSeenRef = seen
