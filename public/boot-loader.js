// Before the program (owner 2026-10-30): the #boot screen of index.html says what is happening while the program
// downloads — slow, no internet, or failed with the details for the developer. The program removes #boot when it
// shows (src/boot/startup.js). Plain old JavaScript, no module: it must run on any phone before anything else.
(function () {
  var t0 = Date.now()
  window.__bootT0 = t0
  var $ = function (id) { return document.getElementById(id) }
  var alive = function () { return !!$('boot') }
  var say = function (m, sub) { if (!alive()) return; $('boot-msg').textContent = m; $('boot-sub').textContent = sub || '' }
  function net () {
    var c = navigator.connection
    return 'online=' + navigator.onLine + (c ? ' net=' + c.effectiveType + ' ' + c.downlink + 'Mbps rtt=' + c.rtt + 'ms' : '')
  }
  var failed = false
  function fail (why) {
    if (!alive() || failed) return
    failed = true
    say(navigator.onLine ? 'تعذّر الوصول إلى الموقع' : 'لا يوجد إنترنت', navigator.onLine ? 'قد يكون الإنترنت ضعيفًا أو الموقع متوقفًا.' : 'تحقق من الاتصال ثم أعد المحاولة.')
    $('boot-detail').textContent = why + '\n' + net() + '\n' + Math.round((Date.now() - t0) / 1000) + 's · ' + new Date().toISOString() + '\n' + location.href.split('#')[0] + '\n' + navigator.userAgent
    $('boot').className = 'failed'
  }
  window.__bootFail = fail
  var tick = setInterval(function () {
    if (!alive()) return clearInterval(tick)
    if (failed) return
    var s = Math.round((Date.now() - t0) / 1000)
    if (!navigator.onLine) say('لا يوجد إنترنت', 'يكمل التحميل وحده حين يعود الاتصال.')
    else if (s >= 90) fail('مرّت 90 ثانية ولم يكتمل التحميل')
    else if (s >= 10) say('الاتصال بطيء… ما زال يحمّل', s + ' ثانية')
  }, 1000)
  window.addEventListener('online', function () { if (!failed) say('عاد الاتصال: جاري التحميل…') })
  // A file of the program that did not arrive (script, style), or an error before it showed
  window.addEventListener('error', function (e) {
    var t = e.target
    if (t && (t.tagName === 'SCRIPT' || t.tagName === 'LINK')) fail('لم يصل الملف: ' + (t.src || t.href))
    else if (e.message) fail('خطأ: ' + e.message + (e.filename ? ' @ ' + e.filename + ':' + e.lineno : ''))
  }, true)
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason
    fail('خطأ: ' + (r && r.message ? r.message : String(r)))
  })
  document.addEventListener('DOMContentLoaded', function () {
    $('boot-retry').addEventListener('click', function () { location.reload() })
    $('boot-copy').addEventListener('click', function () {
      var t = $('boot-detail').textContent
      if (navigator.clipboard) navigator.clipboard.writeText(t).then(function () { $('boot-copy').textContent = 'نُسخت ✓' }, function () {})
    })
  })
})()
