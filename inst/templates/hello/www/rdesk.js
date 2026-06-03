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

    isConnected: function () { return _connected; },

    /**
     * Loading state management.
     */
    loading: {
      _listeners: [],
      on: function(fn) { this._listeners.push(fn); return rdesk; },
      _set: function(state) {
        this._listeners.forEach(function(fn) {
          try { fn(state); } catch(e) {}
        });
      }
    }
  };

  rdesk._overlay = null;

  rdesk._ensureOverlay = function() {
    if (rdesk._overlay) return rdesk._overlay;
    var el = document.createElement("div");
    el.id = "__rdesk_overlay__";
    el.style.cssText = [
      "display:none",
      "position:fixed",
      "inset:0",
      "background:rgba(0,0,0,0.45)",
      "z-index:9999",
      "flex-direction:column",
      "align-items:center",
      "justify-content:center",
      "font-family:system-ui,sans-serif",
      "color:#fff",
      "backdrop-filter:blur(4px)"
    ].join(";");
    el.innerHTML = [
      '<div style="text-align:center;width:280px;padding:32px;',
      'background:rgba(20,20,20,0.85);border-radius:20px;box-shadow:0 20px 40px rgba(0,0,0,0.3);',
      'border:1px solid rgba(255,255,255,0.1)">',
      '<div id="__rdesk_spinner__" style="width:40px;height:40px;margin:0 auto 16px;',
      'border:3px solid rgba(255,255,255,0.2);border-top-color:#fff;',
      'border-radius:50%;animation:rdesk-spin 0.8s linear infinite"></div>',
      '<div id="__rdesk_progress_wrap__" style="display:none;',
      'background:rgba(255,255,255,0.15);border-radius:4px;',
      'height:4px;margin-bottom:12px;overflow:hidden">',
      '<div id="__rdesk_progress_bar__" style="height:100%;',
      'background:#fff;width:0%;transition:width 0.3s ease"></div></div>',
      '<div id="__rdesk_msg__" style="font-size:14px;opacity:0.9;',
      'margin-bottom:12px">Loading...</div>',
      '<button id="__rdesk_cancel_btn__" style="display:none;',
      'padding:6px 16px;border:1px solid rgba(255,255,255,0.4);',
      'background:transparent;color:#fff;border-radius:6px;',
      'cursor:pointer;font-size:13px">Cancel</button>',
      '</div>'
    ].join("");
    var style = document.createElement("style");
    style.textContent = "@keyframes rdesk-spin{to{transform:rotate(360deg)}} #__rdesk_spinner_inner__{animation:rdesk-spin 1s ease-in-out infinite}";
    document.head.appendChild(style);
    document.body.appendChild(el);
    rdesk._overlay = el;
    return el;
  };

  // Replace the basic __loading__ handler with the full overlay handler
  rdesk.on("__loading__", function(payload) {
    var overlay = rdesk._ensureOverlay();
    rdesk.loading._set(payload);

    if (!payload.active) {
      overlay.style.display = "none";
      return;
    }

    // Show overlay
    overlay.style.display = "flex";
    document.getElementById("__rdesk_msg__").textContent =
      payload.message || "Loading...";

    // Progress bar
    var wrap = document.getElementById("__rdesk_progress_wrap__");
    var bar  = document.getElementById("__rdesk_progress_bar__");
    if (payload.progress != null) {
      wrap.style.display = "block";
      bar.style.width = Math.min(100, Math.max(0, payload.progress)) + "%";
    } else {
      wrap.style.display = "none";
    }

    // Cancel button
    var btn = document.getElementById("__rdesk_cancel_btn__");
    btn.style.display = payload.cancellable ? "inline-block" : "none";
    if (payload.cancellable && payload.job_id) {
      btn.onclick = function() {
        rdesk.send("__cancel_job__", { job_id: payload.job_id });
      };
    }
  });

  // Toast system
  rdesk.on("__toast__", function(payload) {
    var toast = document.createElement("div");
    var colors = {
      info:    "rgba(30,120,220,0.95)",
      success: "rgba(40,180,100,0.95)",
      warning: "rgba(220,150,0,0.95)",
      error:   "rgba(220,50,50,0.95)"
    };
    toast.style.cssText = [
      "position:fixed",
      "top:32px",
      "right:32px",
      "padding:12px 24px",
      "border-radius:10px",
      "color:#fff",
      "font-weight:500",
      "font-size:14px",
      "box-shadow: 0 4px 20px rgba(0,0,0,0.15)",
      "font-family:system-ui,sans-serif",
      "z-index:11000",
      "opacity:0",
      "transform: translateY(-20px)",
      "transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275)",
      "max-width:350px",
      "background:" + (colors[payload.type] || colors.info)
    ].join(";");
    
    toast.textContent = payload.message;
    document.body.appendChild(toast);

    // Frame delay for transition
    requestAnimationFrame(function() { 
      toast.style.opacity = "1"; 
      toast.style.transform = "translateY(0)";
    });

    setTimeout(function() {
      toast.style.opacity = "0";
      toast.style.transform = "translateY(-20px)";
      setTimeout(function() {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
      }, 500);
    }, payload.duration_ms || 4000);
  });

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
