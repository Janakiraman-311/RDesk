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

  // HTML5/JS Web Dialogs Fallback (macOS / Linux)
  var _dialogModal = null;

  function createDialogModal(options) {
    if (_dialogModal && _dialogModal.parentNode) {
      _dialogModal.parentNode.removeChild(_dialogModal);
    }

    var modal = document.createElement("div");
    modal.id = "__rdesk_dialog_modal__";
    modal.style.cssText = [
      "position:fixed",
      "inset:0",
      "background:rgba(10,10,10,0.7)",
      "backdrop-filter:blur(8px)",
      "-webkit-backdrop-filter:blur(8px)",
      "z-index:12000",
      "display:flex",
      "align-items:center",
      "justify-content:center",
      "font-family:system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
      "color:#ffffff",
      "opacity:0",
      "transition:opacity 0.25s ease"
    ].join(";");

    var card = document.createElement("div");
    card.style.cssText = [
      "background:rgba(30, 30, 35, 0.95)",
      "border:1px solid rgba(255, 255, 255, 0.1)",
      "border-radius:16px",
      "width:450px",
      "max-width:90%",
      "padding:28px",
      "box-shadow:0 20px 50px rgba(0,0,0,0.5)",
      "transform:scale(0.9)",
      "transition:transform 0.25s cubic-bezier(0.175, 0.885, 0.32, 1.275)"
    ].join(";");

    var title = document.createElement("h3");
    title.innerText = options.title || "File Dialog";
    title.style.cssText = "margin:0 0 12px 0;font-size:18px;font-weight:600;color:#ffffff;letter-spacing:-0.2px;";
    card.appendChild(title);

    if (options.body) {
      var body = document.createElement("p");
      body.innerText = options.body;
      body.style.cssText = "margin:0 0 20px 0;font-size:14px;color:rgba(255,255,255,0.7);line-height:1.5;";
      card.appendChild(body);
    }

    var inputContainer = document.createElement("div");
    inputContainer.style.cssText = "margin-bottom:24px;";
    card.appendChild(inputContainer);

    var fileInput = null;
    var textInput = null;

    if (options.type === "open") {
      var uploadZone = document.createElement("div");
      uploadZone.style.cssText = [
        "border:2px dashed rgba(255,255,255,0.2)",
        "border-radius:10px",
        "padding:30px 20px",
        "text-align:center",
        "cursor:pointer",
        "background:rgba(255,255,255,0.02)",
        "transition:all 0.2s ease"
      ].join(";");

      uploadZone.onmouseover = function() {
        uploadZone.style.border = "2px dashed #4b8df8";
        uploadZone.style.background = "rgba(75,141,248,0.05)";
      };
      uploadZone.onmouseout = function() {
        uploadZone.style.border = "2px dashed rgba(255,255,255,0.2)";
        uploadZone.style.background = "rgba(255,255,255,0.02)";
      };

      var icon = document.createElement("div");
      icon.innerHTML = "&#x1F4C1;";
      icon.style.cssText = "font-size:32px;margin-bottom:10px;filter:drop-shadow(0 2px 4px rgba(0,0,0,0.2));";
      uploadZone.appendChild(icon);

      var label = document.createElement("div");
      label.innerText = "Click to browse files...";
      label.style.cssText = "font-size:14px;font-weight:500;color:rgba(255,255,255,0.9);";
      uploadZone.appendChild(label);

      fileInput = document.createElement("input");
      fileInput.type = "file";
      fileInput.style.display = "none";
      if (options.accept) {
        fileInput.accept = options.accept;
      }

      uploadZone.onclick = function() {
        fileInput.click();
      };

      fileInput.onchange = function(e) {
        if (e.target.files && e.target.files.length > 0) {
          var file = e.target.files[0];
          label.innerText = "Selected: " + file.name;
          label.style.color = "#4b8df8";
          confirmBtn.disabled = false;
          confirmBtn.style.opacity = "1";
        }
      };

      inputContainer.appendChild(uploadZone);
      inputContainer.appendChild(fileInput);
    } else if (options.type === "save" || options.type === "folder") {
      textInput = document.createElement("input");
      textInput.type = "text";
      textInput.placeholder = options.placeholder || "Enter path...";
      textInput.value = options.value || "";
      textInput.style.cssText = [
        "width:100%",
        "padding:12px 14px",
        "background:rgba(0,0,0,0.2)",
        "border:1px solid rgba(255,255,255,0.15)",
        "border-radius:8px",
        "color:#ffffff",
        "font-size:14px",
        "box-sizing:border-box",
        "outline:none",
        "transition:border 0.2s ease"
      ].join(";");

      textInput.onfocus = function() {
        textInput.style.border = "1px solid #4b8df8";
      };
      textInput.onblur = function() {
        textInput.style.border = "1px solid rgba(255,255,255,0.15)";
      };

      inputContainer.appendChild(textInput);
    }

    var btnContainer = document.createElement("div");
    btnContainer.style.cssText = "display:flex;justify-content:flex-end;gap:12px;";

    var cancelBtn = document.createElement("button");
    cancelBtn.innerText = "Cancel";
    cancelBtn.style.cssText = [
      "padding:10px 20px",
      "background:transparent",
      "border:1px solid rgba(255,255,255,0.2)",
      "border-radius:8px",
      "color:rgba(255,255,255,0.8)",
      "font-size:14px",
      "font-weight:500",
      "cursor:pointer",
      "transition:all 0.2s ease"
    ].join(";");
    cancelBtn.onmouseover = function() {
      cancelBtn.style.background = "rgba(255,255,255,0.05)";
      cancelBtn.style.color = "#ffffff";
    };
    cancelBtn.onmouseout = function() {
      cancelBtn.style.background = "transparent";
      cancelBtn.style.color = "rgba(255,255,255,0.8)";
    };

    var confirmBtn = document.createElement("button");
    confirmBtn.innerText = options.type === "open" ? "Open" : "Save";
    if (options.type === "folder") confirmBtn.innerText = "Select";
    confirmBtn.style.cssText = [
      "padding:10px 20px",
      "background:#4b8df8",
      "border:none",
      "border-radius:8px",
      "color:#ffffff",
      "font-size:14px",
      "font-weight:500",
      "cursor:pointer",
      "transition:all 0.2s ease"
    ].join(";");

    if (options.type === "open") {
      confirmBtn.disabled = true;
      confirmBtn.style.opacity = "0.5";
    }

    confirmBtn.onmouseover = function() {
      if (!confirmBtn.disabled) confirmBtn.style.background = "#357ae8";
    };
    confirmBtn.onmouseout = function() {
      if (!confirmBtn.disabled) confirmBtn.style.background = "#4b8df8";
    };

    btnContainer.appendChild(cancelBtn);
    btnContainer.appendChild(confirmBtn);
    card.appendChild(btnContainer);
    modal.appendChild(card);
    document.body.appendChild(modal);
    _dialogModal = modal;

    function closeModal() {
      modal.style.opacity = "0";
      card.style.transform = "scale(0.9)";
      setTimeout(function() {
        if (modal.parentNode) modal.parentNode.removeChild(modal);
        if (_dialogModal === modal) _dialogModal = null;
      }, 250);
    }

    cancelBtn.onclick = function() {
      closeModal();
      if (options.onCancel) options.onCancel();
    };

    confirmBtn.onclick = function() {
      if (options.type === "open") {
        if (fileInput.files && fileInput.files.length > 0) {
          closeModal();
          if (options.onConfirm) options.onConfirm(fileInput.files[0]);
        }
      } else if (options.type === "save" || options.type === "folder") {
        var val = textInput.value.trim();
        if (val) {
          closeModal();
          if (options.onConfirm) options.onConfirm(val);
        } else {
          textInput.style.border = "1px solid #ff3b30";
        }
      }
    };

    requestAnimationFrame(function() {
      modal.style.opacity = "1";
      card.style.transform = "scale(1)";
    });
  }

  rdesk.on("__dialog_open_web__", function(payload) {
    var acceptAttr = "";
    if (payload.filters) {
      var accepts = [];
      for (var key in payload.filters) {
        if (payload.filters.hasOwnProperty(key)) {
          accepts.push(payload.filters[key]);
        }
      }
      if (accepts.length > 0) {
        acceptAttr = accepts.join(",");
      }
    }

    createDialogModal({
      title: payload.title || "Open File",
      type: "open",
      accept: acceptAttr,
      onConfirm: function(file) {
        if (file.path) {
          rdesk.send("__dialog_result_web__", { id: payload.id, path: file.path });
        } else {
          var reader = new FileReader();
          reader.onload = function(evt) {
            var base64Data = evt.target.result.split(",")[1];
            rdesk.send("__dialog_result_web__", {
              id: payload.id,
              name: file.name,
              content: base64Data
            });
          };
          reader.onerror = function() {
            rdesk.send("__dialog_cancel_web__", { id: payload.id });
          };
          reader.readAsDataURL(file);
        }
      },
      onCancel: function() {
        rdesk.send("__dialog_cancel_web__", { id: payload.id });
      }
    });
  });

  rdesk.on("__dialog_save_web__", function(payload) {
    createDialogModal({
      title: payload.title || "Save File",
      type: "save",
      placeholder: "Enter absolute path to save...",
      value: payload.default_name || "",
      onConfirm: function(path) {
        rdesk.send("__dialog_result_web__", { id: payload.id, path: path });
      },
      onCancel: function() {
        rdesk.send("__dialog_cancel_web__", { id: payload.id });
      }
    });
  });

  rdesk.on("__dialog_folder_web__", function(payload) {
    createDialogModal({
      title: payload.title || "Select Folder",
      type: "folder",
      placeholder: "Enter absolute folder path...",
      onConfirm: function(path) {
        rdesk.send("__dialog_result_web__", { id: payload.id, path: path });
      },
      onCancel: function() {
        rdesk.send("__dialog_cancel_web__", { id: payload.id });
      }
    });
  });

  rdesk.on("__message_box_web__", function(payload) {
    var type = payload.type || "ok";
    var res = "ok";
    if (type === "ok") {
      alert(payload.message);
      res = "ok";
    } else if (type === "okcancel") {
      res = confirm(payload.message) ? "ok" : "cancel";
    } else if (type === "yesno" || type === "yesnocancel") {
      res = confirm(payload.message) ? "yes" : "no";
    }
    rdesk.send("__dialog_result_web__", { id: payload.id, result: res });
  });

  rdesk.on("__dialog_color_web__", function(payload) {
    var input = document.createElement("input");
    input.type = "color";
    input.value = payload.color || "#ffffff";
    input.onchange = function(e) {
      rdesk.send("__dialog_result_web__", { id: payload.id, result: e.target.value });
    };
    input.click();
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
