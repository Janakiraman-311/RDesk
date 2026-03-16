(function (global) {
  "use strict";

  var _ws        = null;
  var _handlers  = {};
  var _queue     = [];   // messages queued before connection
  var _ready_fns = [];   // callbacks for when connection opens
  var _connected = false;
  var _port      = null;

  // Auto-detect port from URL query string: ?__rdesk_port__=49217
  function detect_port() {
    var params = new URLSearchParams(window.location.search);
    var p = params.get("__rdesk_port__");
    return p ? parseInt(p, 10) : null;
  }

  function flush_queue() {
    var q = _queue.slice();
    _queue = [];
    q.forEach(function (msg) { _ws.send(msg); });
  }

  function connect(port) {
    _port = port;
    _ws   = new WebSocket("ws://127.0.0.1:" + port);

    _ws.onopen = function () {
      _connected = true;
      flush_queue();
      _ready_fns.forEach(function (fn) {
        try { fn(); } catch (e) { console.error("[rdesk] ready fn error", e); }
      });
    };

    _ws.onmessage = function (evt) {
      try {
        var msg      = JSON.parse(evt.data);
        var handlers = _handlers[msg.type] || [];
        handlers.forEach(function (h) {
          try { h(msg.payload); } catch (e) {
            console.error("[rdesk] handler error for '" + msg.type + "':", e);
          }
        });
      } catch (e) {
        console.error("[rdesk] failed to parse message:", evt.data, e);
      }
    };

    _ws.onclose = function () {
      _connected = false;
      _ws = null;
      // Reconnect after 500ms if page is still alive
      setTimeout(function () {
        if (!_connected && _port) connect(_port);
      }, 500);
    };

    _ws.onerror = function (e) {
      console.warn("[rdesk] WebSocket error — will retry on close");
    };
  }

  var rdesk = {

    init: function (port) {
      connect(port || detect_port());
    },

    send: function (type, payload) {
      var msg = JSON.stringify({ type: type, payload: payload || {} });
      if (_connected && _ws) {
        _ws.send(msg);
      } else {
        _queue.push(msg);
      }
    },

    on: function (type, handler) {
      if (!_handlers[type]) _handlers[type] = [];
      _handlers[type].push(handler);
      return rdesk;  // chainable
    },

    off: function (type, handler) {
      if (!_handlers[type]) return rdesk;
      _handlers[type] = _handlers[type].filter(function (h) {
        return h !== handler;
      });
      return rdesk;
    },

    // Fire fn immediately if connected, otherwise queue
    ready: function (fn) {
      if (_connected) { fn(); } else { _ready_fns.push(fn); }
      return rdesk;
    },

    isConnected: function () { return _connected; }
  };

  // Auto-init when port is in URL (standard RDesk app launch)
  if (typeof window !== "undefined" && window.location) {
    var autoPort = detect_port();
    if (autoPort) rdesk.init(autoPort);
  }

  global.rdesk = rdesk;

})(typeof window !== "undefined" ? window : this);
