// Old browsers (owner 2026-10-30: a fresh Windows with Edge 92 stopped on «Object.hasOwn is not a function»): the few newer
// built-ins the libraries use, loaded before the app (a file: the page's CSP refuses inline scripts)
if (!Object.hasOwn) Object.hasOwn = function (o, k) { return Object.prototype.hasOwnProperty.call(o, k) }
if (!Array.prototype.at) Object.defineProperty(Array.prototype, 'at', { configurable: true, writable: true, value: function (i) { i = Math.trunc(i) || 0; if (i < 0) i += this.length; return this[i] } })
if (!Array.prototype.findLast) Object.defineProperty(Array.prototype, 'findLast', { configurable: true, writable: true, value: function (f, t) { for (var i = this.length - 1; i >= 0; i--) if (f.call(t, this[i], i, this)) return this[i] } })
if (!Array.prototype.findLastIndex) Object.defineProperty(Array.prototype, 'findLastIndex', { configurable: true, writable: true, value: function (f, t) { for (var i = this.length - 1; i >= 0; i--) if (f.call(t, this[i], i, this)) return i; return -1 } })
if (!String.prototype.at) Object.defineProperty(String.prototype, 'at', { configurable: true, writable: true, value: function (i) { i = Math.trunc(i) || 0; if (i < 0) i += this.length; return this.charAt(i) || undefined } })
