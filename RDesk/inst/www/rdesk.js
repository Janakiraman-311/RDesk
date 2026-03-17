(function (global) {
  "use strict";

  var _handlers  = {};
  var _queue     = [];   // messages queued before bridge ready
  var _ready_fns = [];   // callbacks for when bridge is ready
  var _connected = false;
  var _version   = "1.0"; // RDesk IPC Contract Version

  function handleMessage(evt) {
    try {
      var envelope = (typeof evt.data === 'string') ? JSON.parse(evt.data) : evt.data;
      
      // Internal navigation handler
      if (envelope.type === "__navigate__") {
        window.location.href = envelope.payload.path;
        return;
      }

      var type     = envelope.type;
      var payload  = envelope.payload || {};
      
      var handlers = _handlers[type] || [];
      handlers.forEach(function (h) {
        try { h(payload); } catch (e) {
          console.error("[rdesk] handler error for '" + type + "':", e);
        }
      });
    } catch (e) {
      console.error("[rdesk] failed to parse message:", evt.data, e);
    }
  }

  function initBridge() {
    if (typeof window !== "undefined" && window.chrome && window.chrome.webview) {
      window.chrome.webview.addEventListener('message', handleMessage);
      _connected = true;
      
      // Flush any messages sent before bridge was ready
      var q = _queue.slice();
      _queue = [];
      q.forEach(function (msg) { window.chrome.webview.postMessage(msg); });
      
      _ready_fns.forEach(function (fn) {
        try { fn(); } catch (e) { console.error("[rdesk] ready fn error", e); }
      });
      console.log("[rdesk] Native IPC bridge connected.");
    } else {
      // WebView2 object might take a moment to inject
      setTimeout(initBridge, 50);
    }
  }

  var rdesk = {
    /**
     * Explicitly initialize the native bridge.
     * In most RDesk apps, this is called automatically.
     */
    init: function () {
      if (!_connected) initBridge();
    },

    /**
     * Send a message to the R backend via native PostWebMessage.
     */
    send: function (type, payload) {
      var msg = {
        id: "msg_" + Math.random().toString(36).slice(2, 11),
        type: type,
        version: _version,
        payload: payload || {},
        timestamp: Date.now() / 1000
      };

      if (_connected && window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(JSON.stringify(msg));
      } else {
        _queue.push(JSON.stringify(msg));
      }
    },

    /**
     * Subscribe to a message type from R.
     */
    on: function (type, handler) {
      if (!_handlers[type]) _handlers[type] = [];
      _handlers[type].push(handler);
      return rdesk;
    },

    /**
     * Unsubscribe from a message type.
     */
    off: function (type, handler) {
      if (!_handlers[type]) return rdesk;
      _handlers[type] = _handlers[type].filter(function (h) {
        return h !== handler;
      });
      return rdesk;
    },

    /**
     * Fire a callback when the bridge is ready.
     */
    ready: function (fn) {
      if (_connected) { fn(); } else { _ready_fns.push(fn); }
      return rdesk;
    },

    isConnected: function () { return _connected; }
  };

  // Auto-init on load
  if (typeof window !== "undefined") {
    if (document.readyState === "complete" || document.readyState === "interactive") {
      rdesk.init();
    } else {
      window.addEventListener("DOMContentLoaded", function() { rdesk.init(); });
    }
  }

  global.rdesk = rdesk;

})(typeof window !== "undefined" ? window : this);
