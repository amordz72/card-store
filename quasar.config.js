// Quasar config — https://v2.quasar.dev/quasar-cli-vite/quasar-config-file
import { defineConfig } from '#q-app/wrappers'

export default defineConfig(() => ({
  boot: ['supabase', 'startup'],
  css: ['app.scss'],
  extras: ['material-icons'],

  build: {
    target: { browser: ['es2022', 'firefox115', 'chrome115', 'safari15'], node: 'node20' },
    // GitHub Pages cannot rewrite unknown paths to index.html, so use hash routing
    vueRouterMode: 'hash',
    // GitHub Pages serves the site under /card-store/; Cloudflare Pages serves it at the root
    // (its build command must be: DEPLOY_TARGET=cloudflare npm run build, output dist/pwa).
    publicPath: process.env.DEPLOY_TARGET === 'cloudflare' ? '/' : '/card-store/'
  },

  devServer: { open: false, port: 9000 },

  framework: {
    lang: 'ar',
    iconSet: 'material-icons',
    config: {
      brand: { primary: '#C2410C', secondary: '#16A34A', positive: '#15803D', negative: '#B91C1C', warning: '#B45309', info: '#0E7490' },
      notify: { position: 'top', timeout: 3500 }
    },
    plugins: ['Notify', 'Dialog', 'Loading', 'LocalStorage']
  },

  animations: [],

  pwa: {
    workboxMode: 'GenerateSW',
    injectPwaMetaTags: true,
    swFilename: 'sw.js',
    manifestFilename: 'manifest.json',
    extendManifestJson (json) {
      json.name = 'متجر البطاقات'
      json.short_name = 'البطاقات'
      json.description = 'بطاقات الهاتف والإنترنت والألعاب'
      json.dir = 'rtl'
      json.lang = 'ar'
      json.display = 'standalone'
      json.start_url = '.'
    },
    extendGenerateSWOptions (cfg) {
      // Never cache API traffic: balances and codes must always be live
      cfg.navigateFallback = 'index.html'
      // apps/ holds the Rech-Doom APK: always from the network, never the app shell
      cfg.navigateFallbackDenylist = [/\/apps\//]
      cfg.globIgnores = [...(cfg.globIgnores || []), 'apps/**']
      cfg.runtimeCaching = []
      // Phone notifications (Flexy Core 0111): the push and its tap, in public/push-sw.js
      cfg.importScripts = [...(cfg.importScripts || []), 'push-sw.js']
    }
  }
}))
