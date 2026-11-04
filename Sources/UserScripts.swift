import WebKit

enum UserScripts {
    static var main: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static var source: String {
        #"""
        (function () {
          'use strict';
          if (window.__grokwebInjected) return;
          window.__grokwebInjected = true;

          // ============ 1. NATIVE LOG BRIDGE ============
          var post = function (level, msg) {
            try {
              window.webkit.messageHandlers.nativeLog.postMessage({
                level: level, msg: String(msg).slice(0, 2000), url: location.href
              });
            } catch (e) {}
          };
          var fmt = function (a) {
            try {
              if (typeof a === 'string') return a;
              if (a instanceof Error) return a.stack || (a.name + ': ' + a.message);
              if (typeof a === 'undefined') return 'undefined';
              if (typeof a === 'function') return '[Function ' + (a.name || 'anonymous') + ']';
              var seen = [];
              return JSON.stringify(a, function (k, v) {
                if (typeof v === 'object' && v !== null) {
                  if (seen.indexOf(v) !== -1) return '[Circular]';
                  seen.push(v);
                }
                return v;
              });
            } catch (e) { return String(a); }
          };
          ['log', 'info', 'warn', 'error', 'debug'].forEach(function (name) {
            var orig = console[name];
            console[name] = function () {
              try { post(name, Array.prototype.map.call(arguments, fmt).join(' ')); } catch (e) {}
              if (orig) return orig.apply(console, arguments);
            };
          });
          window.addEventListener('error', function (e) {
            if (e.target && e.target !== window && (e.target.src || e.target.href)) {
              post('error', 'Resource failed: ' + (e.target.src || e.target.href));
              return;
            }
            post('error', 'onerror: ' + e.message + ' @ ' + e.filename + ':' + e.lineno + ':' + e.colno);
          }, true);
          window.addEventListener('unhandledrejection', function (e) {
            var r = e.reason;
            post('error', 'unhandledrejection: ' + (r && r.stack ? r.stack : fmt(r)));
          });

          // ============ 2. VIEWPORT OVERRIDE (top frame only) ============
          if (window.top === window) {
            var VIEWPORT = '\#(Config.viewportContent)';
            var applyViewport = function () {
              var host = document.head || document.documentElement;
              if (!host) return;
              var m = document.querySelector('meta[name="viewport"]');
              if (!m) {
                m = document.createElement('meta');
                m.name = 'viewport';
                m.content = VIEWPORT;
                host.appendChild(m);
              } else if (m.getAttribute('content') !== VIEWPORT) {
                m.setAttribute('content', VIEWPORT);
              }
            };
            applyViewport();
            new MutationObserver(applyViewport).observe(document, {
              childList: true, subtree: true, attributes: true, attributeFilter: ['content', 'name']
            });
            document.addEventListener('DOMContentLoaded', applyViewport);
          }

          // ============ 3. POLYFILLS ============
          // >>> ADD YOUR OWN POLYFILLS IN THIS SECTION <<<
          var def = function (obj, name, value) {
            if (!obj || typeof obj[name] === 'function') return;
            try {
              Object.defineProperty(obj, name, { value: value, writable: true, configurable: true, enumerable: false });
            } catch (e) { post('error', 'polyfill failed: ' + name + ' ' + e); }
          };

          // structuredClone
          if (typeof window.structuredClone !== 'function') {
            window.structuredClone = function (value) {
              var seen = new Map();
              var clone = function (v) {
                if (v === null || typeof v !== 'object') {
                  if (typeof v === 'function' || typeof v === 'symbol')
                    throw new DOMException('Value could not be cloned.', 'DataCloneError');
                  return v;
                }
                if (seen.has(v)) return seen.get(v);
                var out;
                if (v instanceof Date) return new Date(v.getTime());
                if (v instanceof RegExp) return new RegExp(v.source, v.flags);
                if (v instanceof ArrayBuffer) return v.slice(0);
                if (ArrayBuffer.isView(v)) {
                  var buf = v.buffer.slice(0);
                  return v instanceof DataView
                    ? new DataView(buf, v.byteOffset, v.byteLength)
                    : new v.constructor(buf, v.byteOffset, v.length);
                }
                if (v instanceof Map) {
                  out = new Map(); seen.set(v, out);
                  v.forEach(function (val, key) { out.set(clone(key), clone(val)); });
                  return out;
                }
                if (v instanceof Set) {
                  out = new Set(); seen.set(v, out);
                  v.forEach(function (val) { out.add(clone(val)); });
                  return out;
                }
                if (v instanceof Error) {
                  out = new (v.constructor || Error)(v.message);
                  seen.set(v, out);
                  if (v.stack) out.stack = v.stack;
                  return out;
                }
                if (Array.isArray(v)) {
                  out = new Array(v.length); seen.set(v, out);
                  for (var i = 0; i < v.length; i++) out[i] = clone(v[i]);
                  return out;
                }
                out = {}; seen.set(v, out);
                Object.keys(v).forEach(function (k) { out[k] = clone(v[k]); });
                return out;
              };
              return clone(value);
            };
          }

          // Array / String / TypedArray .at
          var at = function (n) {
            n = Math.trunc(n) || 0;
            if (n < 0) n += this.length;
            if (n < 0 || n >= this.length) return undefined;
            return this[n];
          };
          def(Array.prototype, 'at', at);
          def(String.prototype, 'at', at);
          try { def(Object.getPrototypeOf(Int8Array.prototype), 'at', at); } catch (e) {}

          // Array.prototype.findLast / findLastIndex
          def(Array.prototype, 'findLast', function (fn, thisArg) {
            for (var i = this.length - 1; i >= 0; i--) if (fn.call(thisArg, this[i], i, this)) return this[i];
            return undefined;
          });
          def(Array.prototype, 'findLastIndex', function (fn, thisArg) {
            for (var i = this.length - 1; i >= 0; i--) if (fn.call(thisArg, this[i], i, this)) return i;
            return -1;
          });

          // Object.hasOwn
          def(Object, 'hasOwn', function (o, p) {
            if (o == null) throw new TypeError('Cannot convert undefined or null to object');
            return Object.prototype.hasOwnProperty.call(Object(o), p);
          });

          // String.prototype.replaceAll
          def(String.prototype, 'replaceAll', function (search, replacement) {
            if (search instanceof RegExp) {
              if (!search.global) throw new TypeError('replaceAll must be called with a global RegExp');
              return String(this).replace(search, replacement);
            }
            var esc = String(search).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            return String(this).replace(new RegExp(esc, 'g'), replacement);
          });

          // AbortSignal.timeout / throwIfAborted
          if (typeof AbortSignal !== 'undefined') {
            def(AbortSignal, 'timeout', function (ms) {
              var c = new AbortController();
              setTimeout(function () {
                try { c.abort(new DOMException('The operation timed out.', 'TimeoutError')); }
                catch (e) { c.abort(); }
              }, ms);
              return c.signal;
            });
            def(AbortSignal.prototype, 'throwIfAborted', function () {
              if (this.aborted) throw (this.reason !== undefined ? this.reason : new DOMException('Aborted', 'AbortError'));
            });
          }

          // crypto.randomUUID
          if (window.crypto && typeof window.crypto.randomUUID !== 'function') {
            var uuid = function () {
              var b = new Uint8Array(16);
              crypto.getRandomValues(b);
              b[6] = (b[6] & 0x0f) | 0x40;
              b[8] = (b[8] & 0x3f) | 0x80;
              var h = [];
              for (var i = 0; i < 16; i++) h.push((b[i] + 0x100).toString(16).slice(1));
              return h.slice(0, 4).join('') + '-' + h.slice(4, 6).join('') + '-' +
                     h.slice(6, 8).join('') + '-' + h.slice(8, 10).join('') + '-' + h.slice(10).join('');
            };
            try { def(window.Crypto && Crypto.prototype, 'randomUUID', uuid); } catch (e) {}
            if (typeof crypto.randomUUID !== 'function') { try { crypto.randomUUID = uuid; } catch (e) {} }
          }

          // ReadableStream async iteration
          if (typeof ReadableStream !== 'undefined' && !ReadableStream.prototype[Symbol.asyncIterator]) {
            var values = function (opts) {
              var reader = this.getReader();
              var preventCancel = !!(opts && opts.preventCancel);
              return {
                next: function () {
                  return reader.read().then(function (r) {
                    if (r.done) { reader.releaseLock(); return { done: true, value: undefined }; }
                    return { done: false, value: r.value };
                  }, function (e) { reader.releaseLock(); throw e; });
                },
                return: function (v) {
                  if (!preventCancel) {
                    var p = reader.cancel(v);
                    reader.releaseLock();
                    return p.then(function () { return { done: true, value: v }; });
                  }
                  reader.releaseLock();
                  return Promise.resolve({ done: true, value: v });
                },
                [Symbol.asyncIterator]: function () { return this; }
              };
            };
            try {
              Object.defineProperty(ReadableStream.prototype, 'values', { value: values, writable: true, configurable: true });
              Object.defineProperty(ReadableStream.prototype, Symbol.asyncIterator, { value: values, writable: true, configurable: true });
            } catch (e) { post('error', 'polyfill failed: ReadableStream iterator ' + e); }
          }

          // ============ END POLYFILLS ============
          post('info', 'user script injected: ' + location.href);
        })();
        """#
    }
}
