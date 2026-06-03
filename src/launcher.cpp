#include <iostream>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <chrono>
#include <algorithm>
#include <cctype>
#include <map>
#include <functional>
#include <sstream>
#include <vector>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

// ── Platform-specific headers and setup ──────────────────────────────────────
#ifdef _WIN32
  #include <windows.h>
  #include <commdlg.h>
  #include <shellapi.h>
  #include <shlwapi.h>
  #include <shobjidl.h> // for folder picker
  #include <wrl.h>
  #include "webview/webview.h"
  #include <WebView2.h>
  #pragma comment(lib, "comdlg32.lib")
  #pragma comment(lib, "shell32.lib")
  #pragma comment(lib, "ole32.lib")
#elif defined(__APPLE__)
  #define WEBVIEW_COCOA 1
  #include "webview/webview.h"
  #import <Cocoa/Cocoa.h>
  #import <WebKit/WebKit.h>
  #include <unistd.h>
  #include <signal.h>
  #include <sys/wait.h>
  #include <sys/types.h>
  #include <sys/stat.h>
#else
  #define WEBVIEW_GTK 1
  #include "webview/webview.h"
  #include <gtk/gtk.h>
  #include <webkit2/webkit2.h>
  #include <glib.h>
  #include <unistd.h>
  #include <signal.h>
  #include <sys/wait.h>
  #include <sys/types.h>
  #include <sys/stat.h>
#endif

// ── Global state ─────────────────────────────────────────────────────────────
static std::atomic<bool>  g_quit{false};
static std::atomic<bool>  g_intercept_close{false};
static webview::webview*  g_webview = nullptr;
static std::mutex         g_out_mutex;
static std::mutex         g_webview_mutex;

#ifdef _WIN32
  static ICoreWebView2*     g_core_webview = nullptr;
  static HMENU              g_hmenu_tray = nullptr;
  static std::map<int, std::string> g_hotkeys;
  static std::mutex         g_hotkey_mutex;
  static const UINT         WM_TRAYICON = WM_USER + 1;
#endif

static void write_stdout(const std::string& line) {
    std::lock_guard<std::mutex> lk(g_out_mutex);
    std::cout << line << "\n";
    std::cout.flush();
}

static void dispatch_to_webview(const std::function<void()>& fn) {
    std::lock_guard<std::mutex> lk(g_webview_mutex);
    if (g_quit.load() || g_webview == nullptr) return;

    g_webview->dispatch([fn]() {
        std::lock_guard<std::mutex> lk(g_webview_mutex);
        if (g_quit.load() || g_webview == nullptr) return;
        fn();
    });
}

// ── macOS Custom URI Scheme Handler ──────────────────────────────────────────
#ifdef __APPLE__
static std::string g_www_path;

@interface RDeskSchemeHandler : NSObject <WKURLSchemeHandler>
@end

@implementation RDeskSchemeHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    NSURL *url = urlSchemeTask.request.URL;
    NSString *urlPath = url.absoluteString;
    
    NSString *prefix = @"rdesk://app/";
    if ([urlPath hasPrefix:prefix]) {
        NSString *rel = [urlPath substringFromIndex:prefix.length];
        
        NSRange qRange = [rel rangeOfString:@"?"];
        if (qRange.location != NSNotFound) {
            rel = [rel substringToIndex:qRange.location];
        }
        NSRange hRange = [rel rangeOfString:@"#"];
        if (hRange.location != NSNotFound) {
            rel = [rel substringToIndex:hRange.location];
        }
        
        NSString *fullPath = [NSString stringWithFormat:@"%s/%@", g_www_path.c_str(), rel];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
             fullPath = [NSString stringWithFormat:@"%s/index.html", g_www_path.c_str()];
        }
        
        NSData *data = [NSData dataWithContentsOfFile:fullPath];
        if (data) {
            NSString *mime = @"text/plain";
            if ([rel hasSuffix:@".html"]) mime = @"text/html";
            else if ([rel hasSuffix:@".css"]) mime = @"text/css";
            else if ([rel hasSuffix:@".js"]) mime = @"text/javascript";
            else if ([rel hasSuffix:@".png"]) mime = @"image/png";
            else if ([rel hasSuffix:@".jpg"] || [rel hasSuffix:@".jpeg"]) mime = @"image/jpeg";
            else if ([rel hasSuffix:@".gif"]) mime = @"image/gif";
            else if ([rel hasSuffix:@".svg"]) mime = @"image/svg+xml";
            else if ([rel hasSuffix:@".json"]) mime = @"application/json";
            else if ([rel hasSuffix:@".wasm"]) mime = @"application/wasm";
            
            NSURLResponse *response = [[NSURLResponse alloc] initWithURL:url
                                                                MIMEType:mime
                                                   expectedContentLength:data.length
                                                        textEncodingName:@"utf-8"];
            [urlSchemeTask didReceiveResponse:response];
            [urlSchemeTask didReceiveData:data];
            [urlSchemeTask didFinish];
        } else {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorResourceUnavailable
                                             userInfo:nil];
            [urlSchemeTask didFailWithError:error];
        }
    } else {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorResourceUnavailable
                                         userInfo:nil];
        [urlSchemeTask didFailWithError:error];
    }
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
}

@end

static IMP g_orig_wk_config_init = nullptr;

static id custom_wk_config_init(id self, SEL _cmd) {
    id (*orig_init)(id, SEL) = (id (*)(id, SEL))g_orig_wk_config_init;
    self = orig_init(self, _cmd);
    if (self) {
        RDeskSchemeHandler *handler = [[RDeskSchemeHandler alloc] init];
        [self setURLSchemeHandler:handler forURLScheme:@"rdesk"];
    }
    return self;
}

void setup_macos_scheme_interceptor() {
    Class cls = objc_getClass("WKWebViewConfiguration");
    Method method = class_getInstanceMethod(cls, @selector(init));
    g_orig_wk_config_init = method_getImplementation(method);
    method_setImplementation(method, (IMP)custom_wk_config_init);
}
#endif

// ── Linux Custom URI Scheme Handler & Stderr Logging Redirects ──────────────
#ifdef WEBVIEW_GTK
static std::string g_www_path;

static void uri_scheme_request_cb(WebKitURISchemeRequest* request,
                                  gpointer               user_data) {
  const char* uri  = webkit_uri_scheme_request_get_uri(request);
  std::string path = std::string(uri);

  std::string prefix = "rdesk://app/";
  if (path.substr(0, prefix.size()) == prefix) {
    std::string rel  = path.substr(prefix.size());
    
    // Remove query/hash
    size_t q = rel.find('?');
    if (q != std::string::npos) rel = rel.substr(0, q);
    size_t h = rel.find('#');
    if (h != std::string::npos) rel = rel.substr(0, h);

    std::string full = g_www_path + "/" + rel;

    // Check if file exists, fallback to index.html
    struct stat st;
    if (stat(full.c_str(), &st) != 0) {
      full = g_www_path + "/index.html";
    }

    std::string mime = "text/plain";
    if (rel.size() > 5 && rel.substr(rel.size()-5) == ".html") mime = "text/html";
    else if (rel.size() > 4 && rel.substr(rel.size()-4) == ".css")  mime = "text/css";
    else if (rel.size() > 3 && rel.substr(rel.size()-3) == ".js")   mime = "text/javascript";
    else if (rel.size() > 4 && rel.substr(rel.size()-4) == ".png")  mime = "image/png";
    else if (rel.size() > 4 && rel.substr(rel.size()-4) == ".jpg")  mime = "image/jpeg";
    else if (rel.size() > 5 && rel.substr(rel.size()-5) == ".jpeg") mime = "image/jpeg";
    else if (rel.size() > 4 && rel.substr(rel.size()-4) == ".svg")  mime = "image/svg+xml";
    else if (rel.size() > 5 && rel.substr(rel.size()-5) == ".json") mime = "application/json";
    else if (rel.size() > 5 && rel.substr(rel.size()-5) == ".wasm") mime = "application/wasm";

    GError* error = nullptr;
    GMappedFile* mapped = g_mapped_file_new(full.c_str(), FALSE, &error);
    if (mapped) {
      GBytes* bytes = g_mapped_file_get_bytes(mapped);
      GInputStream* stream = g_memory_input_stream_new_from_bytes(bytes);
      webkit_uri_scheme_request_finish(request, stream,
        g_mapped_file_get_length(mapped), mime.c_str());
      g_object_unref(stream);
      g_bytes_unref(bytes);
      g_mapped_file_unref(mapped);
    } else {
      webkit_uri_scheme_request_finish_error(request, error);
      g_error_free(error);
    }
  }
}

void register_rdesk_scheme(WebKitWebContext* context) {
  webkit_web_context_register_uri_scheme(
    context, "rdesk",
    uri_scheme_request_cb,
    nullptr, nullptr
  );
}

static void rdesk_glib_log_handler(const gchar*   log_domain,
                                   GLogLevelFlags log_level,
                                   const gchar*   message,
                                   gpointer       user_data) {
  // Force all logs to stderr, avoiding R IPC stdout corruption
  fprintf(stderr, "[GTK %s] %s\n",
          log_domain ? log_domain : "unknown",
          message    ? message    : "");
}

void rdesk_redirect_gtk_output() {
  const char* domains[] = {
    "GLib", "GLib-GObject", "GLib-GIO",
    "Gtk",  "Gdk",
    "WebKit", "WebKitGTK",
    "JavaScriptCore",
    nullptr
  };

  GLogLevelFlags all_levels = (GLogLevelFlags)(
    G_LOG_LEVEL_ERROR   |
    G_LOG_LEVEL_CRITICAL|
    G_LOG_LEVEL_WARNING |
    G_LOG_LEVEL_MESSAGE |
    G_LOG_LEVEL_INFO    |
    G_LOG_LEVEL_DEBUG
  );

  for (int i = 0; domains[i] != nullptr; i++) {
    g_log_set_handler(
      domains[i],
      all_levels,
      rdesk_glib_log_handler,
      nullptr
    );
  }
  g_log_set_default_handler(rdesk_glib_log_handler, nullptr);
}

void rdesk_silence_webkit_diagnostics() {
  setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1", 0);
  unsetenv("JSC_dumpOptions");
  unsetenv("JSC_dumpDisassembly");
  unsetenv("WEBKIT_DEBUG");
  setenv("G_MESSAGES_DEBUG", "", 1);
}

static gboolean webkit_console_message_cb(WebKitWebView* web_view,
                                          const gchar*   message,
                                          gint           line,
                                          const gchar*   source_id,
                                          gpointer       user_data) {
  fprintf(stderr, "[WebKit console %s:%d] %s\n",
          source_id ? source_id : "?",
          line,
          message   ? message   : "");
  return TRUE; // Suppress default stdout write
}

void rdesk_setup_webkit_console_redirect(WebKitWebView* webview) {
  g_signal_connect(webview,
                   "console-message",
                   G_CALLBACK(webkit_console_message_cb),
                   nullptr);
}
#endif

// ── Windows-specific Helpers ──────────────────────────────────────────────────
#ifdef _WIN32
static std::wstring widen(const std::string& s) {
    if (s.empty()) return L"";
    int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    if (len <= 0) return L"";
    std::vector<wchar_t> buf(len);
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, buf.data(), len);
    return std::wstring(buf.data());
}

static std::string narrow(const std::wstring& ws) {
    if (ws.empty()) return "";
    int len = WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) return "";
    std::vector<char> buf(len);
    WideCharToMultiByte(CP_UTF8, 0, ws.c_str(), -1, buf.data(), len, nullptr, nullptr);
    return std::string(buf.data());
}

class MessageHandler : public ICoreWebView2WebMessageReceivedEventHandler {
    std::function<HRESULT(ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs*)> f;
    std::atomic<long> count{1};
public:
    MessageHandler(std::function<HRESULT(ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs*)> f) : f(f) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (riid == IID_IUnknown || riid == IID_ICoreWebView2WebMessageReceivedEventHandler) {
            *ppv = static_cast<ICoreWebView2WebMessageReceivedEventHandler*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++count; }
    ULONG STDMETHODCALLTYPE Release() override {
        auto c = --count;
        if (c == 0) delete this;
        return c;
    }
    HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2* sender, ICoreWebView2WebMessageReceivedEventArgs* args) override {
        return f(sender, args);
    }
};

static HMENU g_hmenu_bar = nullptr;
static std::map<UINT, std::string> g_menu_actions; // ID → action id string
static UINT  g_menu_id_counter = 1000;
static HWND  g_hwnd = nullptr;
static NOTIFYICONDATAW g_nid = {};
static bool  g_tray_active = false;
static bool  g_notify_icon_added = false;

static void ensure_notify_icon(bool visible) {
    if (!g_hwnd) return;

    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd = g_hwnd;
    g_nid.uID = 1001;
    g_nid.uCallbackMessage = WM_TRAYICON;
    g_nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    if (wcslen(g_nid.szTip) == 0) {
        wcsncpy_s(g_nid.szTip, L"RDesk App", 127);
    }

    if (!g_notify_icon_added) {
        if (Shell_NotifyIconW(NIM_ADD, &g_nid)) {
            g_notify_icon_added = true;
        } else {
            return;
        }
    }

    g_nid.uFlags = NIF_STATE | NIF_ICON | NIF_TIP;
    g_nid.dwState = visible ? 0 : NIS_HIDDEN;
    g_nid.dwStateMask = NIS_HIDDEN;
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}

static HMENU build_win32_menu(const json& items) {
    HMENU hMenu = CreatePopupMenu();
    for (auto& item : items) {
        std::string label = item.value("label", "");
        std::string item_id = item.value("id", "");
        bool checked = item.value("checked", false);

        if (label == "---") {
            AppendMenuW(hMenu, MF_SEPARATOR, 0, nullptr);
        } else if (item.contains("items") && item["items"].is_array()) {
            HMENU hSub = build_win32_menu(item["items"]);
            AppendMenuW(hMenu, MF_POPUP, (UINT_PTR)hSub, widen(label).c_str());
        } else if (!label.empty()) {
            UINT win_id = g_menu_id_counter++;
            UINT flags = MF_STRING;
            if (checked) flags |= MF_CHECKED;
            AppendMenuW(hMenu, flags, win_id, widen(label).c_str());
            if (!item_id.empty()) g_menu_actions[win_id] = item_id;
        }
    }
    return hMenu;
}

static void apply_menu(const std::string& payload_json) {
    if (!g_hwnd) return;
    g_menu_actions.clear();
    g_menu_id_counter = 1000;

    HMENU bar = CreateMenu();

    try {
        auto j = json::parse(payload_json);
        if (j.is_array()) {
            for (auto& top : j) {
                std::string label = top.value("label", "");
                if (top.contains("items") && top["items"].is_array()) {
                    HMENU sub = build_win32_menu(top["items"]);
                    std::wstring wlabel = widen(label);
                    AppendMenuW(bar, MF_POPUP, (UINT_PTR)sub, wlabel.c_str());
                } else {
                    UINT win_id = g_menu_id_counter++;
                    std::wstring wlabel = widen(label);
                    AppendMenuW(bar, MF_STRING, win_id, wlabel.c_str());
                    std::string item_id = top.value("id", "");
                    if (!item_id.empty()) g_menu_actions[win_id] = item_id;
                }
            }
        }
    } catch (const json::exception&) {}

    if (!SetMenu(g_hwnd, bar)) {
        DestroyMenu(bar);
        return;
    }
    DrawMenuBar(g_hwnd);
    if (g_hmenu_bar) DestroyMenu(g_hmenu_bar);
    g_hmenu_bar = bar;
}

static std::string open_file_dialog(const std::string& title,
                                     const std::string& filter_str) {
    wchar_t buf[32768] = {0};
    OPENFILENAMEW ofn  = {};
    ofn.lStructSize    = sizeof(ofn);
    ofn.hwndOwner      = g_hwnd;
    ofn.lpstrFile      = buf;
    ofn.nMaxFile       = 32767;
    ofn.Flags          = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

    std::wstring wfilter = widen(filter_str);
    for (auto& c : wfilter) if (c == L'|') c = L'\0';
    ofn.lpstrFilter = wfilter.empty() ? nullptr : wfilter.c_str();

    std::wstring wtitle = widen(title);
    ofn.lpstrTitle = wtitle.empty() ? nullptr : wtitle.c_str();

    if (GetOpenFileNameW(&ofn)) {
        int len = WideCharToMultiByte(CP_UTF8, 0, buf, -1, nullptr, 0, nullptr, nullptr);
        std::string result(len - 1, '\0');
        WideCharToMultiByte(CP_UTF8, 0, buf, -1, &result[0], len, nullptr, nullptr);
        return result;
    }
    return "";
}

static std::string save_file_dialog(const std::string& title,
                                     const std::string& default_name,
                                     const std::string& filter_str,
                                     const std::string& default_ext) {
    wchar_t buf[32768] = {0};
    if (!default_name.empty()) {
        std::wstring wdn = widen(default_name);
        wcsncpy_s(buf, wdn.c_str(), 32767);
    }
    OPENFILENAMEW ofn = {};
    ofn.lStructSize   = sizeof(ofn);
    ofn.hwndOwner     = g_hwnd;
    ofn.lpstrFile     = buf;
    ofn.nMaxFile      = 32767;
    ofn.Flags         = OFN_OVERWRITEPROMPT | OFN_NOCHANGEDIR;

    std::wstring wfilter = widen(filter_str);
    for (auto& c : wfilter) if (c == L'|') c = L'\0';
    ofn.lpstrFilter = wfilter.empty() ? nullptr : wfilter.c_str();

    std::wstring wtitle = widen(title);
    ofn.lpstrTitle = wtitle.empty() ? nullptr : wtitle.c_str();

    std::wstring wext = widen(default_ext);
    ofn.lpstrDefExt = default_ext.empty() ? nullptr : wext.c_str();

    if (GetSaveFileNameW(&ofn)) {
        int len = WideCharToMultiByte(CP_UTF8, 0, buf, -1, nullptr, 0, nullptr, nullptr);
        std::string result(len - 1, '\0');
        WideCharToMultiByte(CP_UTF8, 0, buf, -1, &result[0], len, nullptr, nullptr);
        return result;
    }
    return "";
}

static std::string open_folder_dialog(const std::string& title) {
    IFileOpenDialog* pFileOpen;
    std::string result = "";
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, NULL, CLSCTX_ALL, 
                                  IID_IFileOpenDialog, reinterpret_cast<void**>(&pFileOpen));
    if (SUCCEEDED(hr)) {
        std::wstring wtitle = widen(title);
        pFileOpen->SetTitle(wtitle.c_str());

        DWORD dwOptions;
        if (SUCCEEDED(pFileOpen->GetOptions(&dwOptions))) {
            pFileOpen->SetOptions(dwOptions | FOS_PICKFOLDERS);
        }

        if (SUCCEEDED(pFileOpen->Show(g_hwnd))) {
            IShellItem* pItem;
            if (SUCCEEDED(pFileOpen->GetResult(&pItem))) {
                PWSTR pszFilePath;
                if (SUCCEEDED(pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszFilePath))) {
                    int len = WideCharToMultiByte(CP_UTF8, 0, pszFilePath, -1, nullptr, 0, nullptr, nullptr);
                    result.assign(len - 1, '\0');
                    WideCharToMultiByte(CP_UTF8, 0, pszFilePath, -1, &result[0], len, nullptr, nullptr);
                    CoTaskMemFree(pszFilePath);
                }
                pItem->Release();
            }
        }
        pFileOpen->Release();
    }
    return result;
}

static std::string show_message_box(const std::string& message, const std::string& title, 
                                    const std::string& type, const std::string& icon) {
    UINT uType = MB_SETFOREGROUND;
    if (type == "ok") uType |= MB_OK;
    else if (type == "okcancel") uType |= MB_OKCANCEL;
    else if (type == "yesno") uType |= MB_YESNO;
    else if (type == "yesnocancel") uType |= MB_YESNOCANCEL;
    
    if (icon == "info") uType |= MB_ICONINFORMATION;
    else if (icon == "warning") uType |= MB_ICONWARNING;
    else if (icon == "error") uType |= MB_ICONERROR;
    else if (icon == "question") uType |= MB_ICONQUESTION;

    int res = MessageBoxW(g_hwnd, widen(message).c_str(), widen(title).c_str(), uType);
    
    if (res == IDOK) return "ok";
    if (res == IDCANCEL) return "cancel";
    if (res == IDYES) return "yes";
    if (res == IDNO) return "no";
    return "";
}

static std::string choose_color_dialog(const std::string& initial_hex) {
    CHOOSECOLORW cc = {0};
    static COLORREF custom_colors[16] = {0};
    cc.lStructSize = sizeof(cc);
    cc.hwndOwner = g_hwnd;
    
    COLORREF initial_color = RGB(255, 255, 255);
    if (initial_hex.length() == 7 && initial_hex[0] == '#') {
        try {
            int r = std::stoi(initial_hex.substr(1, 2), nullptr, 16);
            int g = std::stoi(initial_hex.substr(3, 2), nullptr, 16);
            int b = std::stoi(initial_hex.substr(5, 2), nullptr, 16);
            initial_color = RGB(r, g, b);
        } catch (...) {}
    }
    
    cc.rgbResult = initial_color;
    cc.lpCustColors = custom_colors;
    cc.Flags = CC_FULLOPEN | CC_RGBINIT;

    if (ChooseColorW(&cc)) {
        char buf[8];
        snprintf(buf, sizeof(buf), "#%02X%02X%02X", GetRValue(cc.rgbResult), 
                                                     GetGValue(cc.rgbResult), 
                                                     GetBValue(cc.rgbResult));
        return std::string(buf);
    }
    return "";
}

static void show_notification(const std::string& title, const std::string& body) {
    if (!g_hwnd) return;

    ensure_notify_icon(g_tray_active);
    if (!g_notify_icon_added) return;

    std::wstring wtitle = widen(title);
    std::wstring wbody  = widen(body);
    g_nid.uFlags = NIF_INFO | NIF_ICON | NIF_TIP | NIF_STATE;
    g_nid.dwState = g_tray_active ? 0 : NIS_HIDDEN;
    g_nid.dwStateMask = NIS_HIDDEN;
    g_nid.dwInfoFlags = NIIF_INFO;
    g_nid.uTimeout    = 4000;
    wcsncpy_s(g_nid.szInfoTitle, wtitle.c_str(), 63);
    wcsncpy_s(g_nid.szInfo,      wbody.c_str(), 255);

    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}
 
static void set_system_tray(const std::string& label, const std::string& icon_path) {
    if (!g_hwnd) return;

    std::wstring wlabel = widen(label);
    wcsncpy_s(g_nid.szTip, wlabel.c_str(), 127);

    ensure_notify_icon(true);
    if (!g_notify_icon_added) return;

    g_tray_active = true;
    g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_STATE;
    g_nid.dwState = 0;
    g_nid.dwStateMask = NIS_HIDDEN;
    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}
 
static void remove_system_tray() {
    g_tray_active = false;
    if (g_notify_icon_added) {
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        g_notify_icon_added = false;
    }
}

static void set_system_tray_menu(const std::string& payload_json) {
    try {
        auto items = json::parse(payload_json);
        if (g_hmenu_tray) DestroyMenu(g_hmenu_tray);
        g_hmenu_tray = build_win32_menu(items);
    } catch(...) {}
}

static bool set_clipboard_text(const std::string& text) {
    if (!OpenClipboard(NULL)) return false;
    EmptyClipboard();
    std::wstring wtext = widen(text);
    size_t size = (wtext.length() + 1) * sizeof(wchar_t);
    HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, size);
    if (!hGlobal) {
        CloseClipboard();
        return false;
    }
    memcpy(GlobalLock(hGlobal), wtext.c_str(), size);
    GlobalUnlock(hGlobal);
    SetClipboardData(CF_UNICODETEXT, hGlobal);
    CloseClipboard();
    return true;
}

static std::string get_clipboard_text() {
    if (!OpenClipboard(NULL)) return "";
    HANDLE hData = GetClipboardData(CF_UNICODETEXT);
    if (!hData) {
        CloseClipboard();
        return "";
    }
    wchar_t* pText = (wchar_t*)GlobalLock(hData);
    std::string result = narrow(pText);
    GlobalUnlock(hData);
    CloseClipboard();
    return result;
}
#endif // _WIN32

// ── Watchdog Thread for Parent PID ──────────────────────────────────────────
#ifdef _WIN32
static void parent_watchdog(DWORD parent_pid) {
    HANDLE hParent = OpenProcess(PROCESS_QUERY_INFORMATION | SYNCHRONIZE, FALSE, parent_pid);
    if (!hParent) return;

    while (!g_quit.load()) {
        DWORD exitCode;
        if (GetExitCodeProcess(hParent, &exitCode)) {
            if (exitCode != STILL_ACTIVE) {
                 g_quit.store(true);
                 std::lock_guard<std::mutex> lk(g_webview_mutex);
                 if (g_webview) g_webview->terminate();
                 break;
            }
        }
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
    CloseHandle(hParent);
}
#else
static void parent_watchdog(pid_t parent_pid) {
    while (!g_quit.load()) {
        if (getppid() == 1 || kill(parent_pid, 0) != 0) {
             g_quit.store(true);
             std::lock_guard<std::mutex> lk(g_webview_mutex);
             if (g_webview) g_webview->terminate();
             break;
        }
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
}
#endif

#ifdef WEBVIEW_GTK
static GtkWidget* g_vbox = nullptr;
static GtkWidget* g_menu_bar = nullptr;

static void gtk_menu_item_activate_cb(GtkWidget* widget, gpointer user_data) {
    std::string* item_id = static_cast<std::string*>(user_data);
    if (item_id) {
        json out;
        out["event"] = "MENU_CLICK";
        out["id"]    = *item_id;
        write_stdout(out.dump());
    }
}

static GtkWidget* build_gtk_submenu(const json& items) {
    GtkWidget* menu = gtk_menu_new();
    for (auto& item : items) {
        std::string label = item.value("label", "");
        std::string item_id = item.value("id", "");
        bool checked = item.value("checked", false);

        if (label == "---") {
            GtkWidget* sep = gtk_separator_menu_item_new();
            gtk_menu_shell_append(GTK_MENU_SHELL(menu), sep);
            gtk_widget_show(sep);
        } else if (item.contains("items") && item["items"].is_array()) {
            GtkWidget* sub_menu_item = gtk_menu_item_new_with_label(label.c_str());
            GtkWidget* sub_menu = build_gtk_submenu(item["items"]);
            gtk_menu_item_set_submenu(GTK_MENU_ITEM(sub_menu_item), sub_menu);
            gtk_menu_shell_append(GTK_MENU_SHELL(menu), sub_menu_item);
            gtk_widget_show(sub_menu_item);
        } else if (!label.empty()) {
            GtkWidget* menu_item = nullptr;
            if (checked) {
                menu_item = gtk_check_menu_item_new_with_label(label.c_str());
                gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(menu_item), TRUE);
            } else {
                menu_item = gtk_menu_item_new_with_label(label.c_str());
            }

            if (!item_id.empty()) {
                std::string* action_id = new std::string(item_id);
                g_signal_connect_data(G_OBJECT(menu_item), "activate",
                                      G_CALLBACK(gtk_menu_item_activate_cb),
                                      action_id,
                                      [](gpointer data, GClosure*) {
                                          delete static_cast<std::string*>(data);
                                      },
                                      static_cast<GConnectFlags>(0));
            }
            gtk_menu_shell_append(GTK_MENU_SHELL(menu), menu_item);
            gtk_widget_show(menu_item);
        }
    }
    return menu;
}

static void apply_menu(const std::string& payload_json) {
    if (!g_webview) return;
    GtkWidget* window_widget = GTK_WIDGET(g_webview->window().value());
    if (!window_widget) return;
    GtkWidget* webview_widget = GTK_WIDGET(g_webview->browser_controller().value());

    // 1. Ensure vbox is set up as the container of the window
    if (!g_vbox) {
        gtk_container_remove(GTK_CONTAINER(window_widget), webview_widget);
        g_vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
        gtk_container_add(GTK_CONTAINER(window_widget), g_vbox);
        gtk_box_pack_end(GTK_BOX(g_vbox), webview_widget, TRUE, TRUE, 0);
        gtk_widget_show(g_vbox);
    }

    // 2. Remove existing menu bar if any
    if (g_menu_bar) {
        gtk_container_remove(GTK_CONTAINER(g_vbox), g_menu_bar);
        g_menu_bar = nullptr;
    }

    // 3. Create new menu bar
    g_menu_bar = gtk_menu_bar_new();

    try {
        auto j = json::parse(payload_json);
        if (j.is_array()) {
            for (auto& top : j) {
                std::string label = top.value("label", "");
                if (top.contains("items") && top["items"].is_array()) {
                    GtkWidget* top_item = gtk_menu_item_new_with_label(label.c_str());
                    GtkWidget* sub = build_gtk_submenu(top["items"]);
                    gtk_menu_item_set_submenu(GTK_MENU_ITEM(top_item), sub);
                    gtk_menu_shell_append(GTK_MENU_SHELL(g_menu_bar), top_item);
                    gtk_widget_show(top_item);
                } else {
                    GtkWidget* top_item = gtk_menu_item_new_with_label(label.c_str());
                    std::string item_id = top.value("id", "");
                    if (!item_id.empty()) {
                        std::string* action_id = new std::string(item_id);
                        g_signal_connect_data(G_OBJECT(top_item), "activate",
                                              G_CALLBACK(gtk_menu_item_activate_cb),
                                              action_id,
                                              [](gpointer data, GClosure*) {
                                                  delete static_cast<std::string*>(data);
                                              },
                                              static_cast<GConnectFlags>(0));
                    }
                    gtk_menu_shell_append(GTK_MENU_SHELL(g_menu_bar), top_item);
                    gtk_widget_show(top_item);
                }
            }
        }
    } catch (const json::exception&) {}

    gtk_box_pack_start(GTK_BOX(g_vbox), g_menu_bar, FALSE, FALSE, 0);
    gtk_widget_show(g_menu_bar);
}

static void set_system_tray(const std::string&, const std::string&) {}
static void remove_system_tray() {}
static void set_system_tray_menu(const std::string&) {}
#endif

#ifdef __APPLE__
@interface RDeskMenuHandler : NSObject
- (void)menuClicked:(id)sender;
- (void)statusItemClicked:(id)sender;
@end

@implementation RDeskMenuHandler
- (void)menuClicked:(id)sender {
    NSMenuItem* item = (NSMenuItem*)sender;
    NSString* actionId = [item representedObject];
    if (actionId) {
        std::string act = [actionId UTF8String];
        json out;
        out["event"] = "MENU_CLICK";
        out["id"]    = act;
        write_stdout(out.dump());
    }
}

- (void)statusItemClicked:(id)sender {
    NSEvent* event = [NSApp currentEvent];
    bool isRight = ([event type] == NSEventTypeRightMouseUp || ([event modifierFlags] & NSEventModifierFlagControl));
    
    json out;
    out["event"] = "TRAY_CLICK";
    out["button"] = isRight ? "right" : "left";
    write_stdout(out.dump());
}
@end

static RDeskMenuHandler* g_menu_handler = nil;
static NSStatusItem* g_status_item = nil;
static NSMenu* g_tray_menu = nil;

static NSMenu* build_cocoa_menu(const json& items) {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    [menu setAutoenablesItems:NO];
    for (auto& item : items) {
        std::string label = item.value("label", "");
        std::string item_id = item.value("id", "");
        bool checked = item.value("checked", false);

        if (label == "---") {
            [menu addItem:[NSMenuItem separatorItem]];
        } else if (item.contains("items") && item["items"].is_array()) {
            NSMenuItem* sub_item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:label.c_str()]
                                                              action:nil
                                                       keyEquivalent:@""];
            NSMenu* sub_menu = build_cocoa_menu(item["items"]);
            [sub_item setSubmenu:sub_menu];
            [menu addItem:sub_item];
        } else if (!label.empty()) {
            SEL action = @selector(menuClicked:);
            NSMenuItem* menu_item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:label.c_str()]
                                                              action:action
                                                       keyEquivalent:@""];
            [menu_item setTarget:g_menu_handler];
            if (!item_id.empty()) {
                [menu_item setRepresentedObject:[NSString stringWithUTF8String:item_id.c_str()]];
            }
            [menu_item setState:(checked ? NSControlStateValueOn : NSControlStateValueOff)];
            [menu_item setEnabled:YES];
            [menu addItem:menu_item];
        }
    }
    return menu;
}

static void apply_menu(const std::string& payload_json) {
    if (!g_menu_handler) {
        g_menu_handler = [[RDeskMenuHandler alloc] init];
    }

    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"AMainMenu"];

    try {
        auto j = json::parse(payload_json);
        if (j.is_array()) {
            for (auto& top : j) {
                std::string label = top.value("label", "");
                NSMenuItem* top_item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:label.c_str()]
                                                                  action:nil
                                                           keyEquivalent:@""];
                if (top.contains("items") && top["items"].is_array()) {
                    NSMenu* sub = build_cocoa_menu(top["items"]);
                    [sub setTitle:[NSString stringWithUTF8String:label.c_str()]];
                    [top_item setSubmenu:sub];
                }
                [mainMenu addItem:top_item];
            }
        }
    } catch (const json::exception&) {}

    [NSApp setMainMenu:mainMenu];
}

static void set_system_tray(const std::string& label, const std::string& icon_path) {
    if (!g_menu_handler) {
        g_menu_handler = [[RDeskMenuHandler alloc] init];
    }
    if (!g_status_item) {
        g_status_item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
        [[g_status_item button] setTarget:g_menu_handler];
        [[g_status_item button] setAction:@selector(statusItemClicked:)];
    }

    if (!label.empty()) {
        [[g_status_item button] setTitle:[NSString stringWithUTF8String:label.c_str()]];
    }
    if (!icon_path.empty()) {
        NSImage* img = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:icon_path.c_str()]];
        if (img) {
            [img setSize:NSMakeSize(18, 18)];
            [[g_status_item button] setImage:img];
        }
    }
    if (g_tray_menu) {
        [g_status_item setMenu:g_tray_menu];
    }
}

static void remove_system_tray() {
    if (g_status_item) {
        [[NSStatusBar systemStatusBar] removeStatusItem:g_status_item];
        g_status_item = nil;
    }
}

static void set_system_tray_menu(const std::string& payload_json) {
    if (!g_menu_handler) {
        g_menu_handler = [[RDeskMenuHandler alloc] init];
    }
    try {
        auto items = json::parse(payload_json);
        g_tray_menu = build_cocoa_menu(items);
        if (g_status_item) {
            [g_status_item setMenu:g_tray_menu];
        }
    } catch (...) {}
}
#endif

// ── Stdin command processor ──────────────────────────────────────────────────
static void process_command(const std::string& line) {
    json j;
    try {
        j = json::parse(line);
    } catch (const json::exception&) {
        return; // skip malformed lines
    }

    std::string cmd = j.value("cmd", "");
    std::string id  = j.value("id", "");

    if (cmd == "QUIT") {
        g_quit.store(true);
        webview::webview* wv = nullptr;
        {
            std::lock_guard<std::mutex> lk(g_webview_mutex);
            wv = g_webview;
        }
        if (wv) wv->terminate();
        return;
    }

    if (cmd == "SET_TITLE") {
        std::string title = j["payload"].value("title", "");
        if (!title.empty()) {
            dispatch_to_webview([title]() {
                g_webview->set_title(title);
            });
        }
        return;
    }

    if (cmd == "SET_SIZE") {
        int w = j["payload"].value("width", 800);
        int h = j["payload"].value("height", 600);
        dispatch_to_webview([w, h]() {
            g_webview->set_size(w, h, WEBVIEW_HINT_NONE);
        });
        return;
    }

    if (cmd == "SEND_MSG") {
        if (j.contains("payload")) {
            std::string payload_str;
            if (j["payload"].is_string()) {
                payload_str = j["payload"].get<std::string>();
            } else {
                payload_str = j["payload"].dump();
            }

            if (!payload_str.empty()) {
                dispatch_to_webview([payload_str]() {
#ifdef _WIN32
                    ICoreWebView2* core = g_core_webview;
                    if (core) {
                        core->AddRef();
                        std::wstring wpayload = widen(payload_str);
                        core->PostWebMessageAsString(wpayload.c_str());
                        core->Release();
                    }
#else
                    // Escape single quotes and backslashes for JS eval
                    std::string escaped = "";
                    for (char c : payload_str) {
                        if (c == '\'' || c == '\\') escaped += '\\';
                        escaped += c;
                    }
                    std::string js = "window.dispatchEvent(new MessageEvent('message', {data: '" + escaped + "'}))";
                    g_webview->eval(js);
#endif
                });
            }
        }
        return;
    }

    if (cmd == "MINIMIZE") {
        dispatch_to_webview([]() {
#ifdef _WIN32
            ShowWindow(g_hwnd, SW_MINIMIZE);
#elif defined(WEBVIEW_GTK)
            GtkWidget* w = static_cast<GtkWidget*>(g_webview->window().value());
            if (w) gtk_window_iconify(GTK_WINDOW(w));
#elif defined(WEBVIEW_COCOA)
            NSWindow* w = (NSWindow*)(g_webview->window().value());
            if (w) [w miniaturize:nil];
#endif
        });
        return;
    }

    if (cmd == "MAXIMIZE") {
        dispatch_to_webview([]() {
#ifdef _WIN32
            ShowWindow(g_hwnd, SW_MAXIMIZE);
#elif defined(WEBVIEW_GTK)
            GtkWidget* w = static_cast<GtkWidget*>(g_webview->window().value());
            if (w) gtk_window_maximize(GTK_WINDOW(w));
#elif defined(WEBVIEW_COCOA)
            NSWindow* w = (NSWindow*)(g_webview->window().value());
            if (w) [w zoom:nil];
#endif
        });
        return;
    }

    if (cmd == "RESTORE") {
        dispatch_to_webview([]() {
#ifdef _WIN32
            ShowWindow(g_hwnd, SW_RESTORE);
#elif defined(WEBVIEW_GTK)
            GtkWidget* w = static_cast<GtkWidget*>(g_webview->window().value());
            if (w) {
                gtk_window_deiconify(GTK_WINDOW(w));
                gtk_window_unmaximize(GTK_WINDOW(w));
            }
#elif defined(WEBVIEW_COCOA)
            NSWindow* w = (NSWindow*)(g_webview->window().value());
            if (w) {
                if ([w isMiniaturized]) [w deminiaturize:nil];
            }
#endif
        });
        return;
    }

    if (cmd == "FULLSCREEN") {
        bool enabled = j["payload"].value("enabled", false);
        dispatch_to_webview([enabled]() {
#ifdef _WIN32
            static RECT pre_fs_rect = {0};
            static LONG pre_fs_style = 0;
            if (enabled) {
                pre_fs_style = GetWindowLong(g_hwnd, GWL_STYLE);
                GetWindowRect(g_hwnd, &pre_fs_rect);
                MONITORINFO mi = { sizeof(mi) };
                if (GetMonitorInfo(MonitorFromWindow(g_hwnd, MONITOR_DEFAULTTOPRIMARY), &mi)) {
                    SetWindowLong(g_hwnd, GWL_STYLE, pre_fs_style & ~WS_OVERLAPPEDWINDOW);
                    SetWindowPos(g_hwnd, HWND_TOP,
                                 mi.rcMonitor.left, mi.rcMonitor.top,
                                 mi.rcMonitor.right - mi.rcMonitor.left,
                                 mi.rcMonitor.bottom - mi.rcMonitor.top,
                                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
                }
            } else {
                if (pre_fs_style != 0) {
                    SetWindowLong(g_hwnd, GWL_STYLE, pre_fs_style);
                    SetWindowPos(g_hwnd, nullptr,
                                 pre_fs_rect.left, pre_fs_rect.top,
                                 pre_fs_rect.right - pre_fs_rect.left,
                                 pre_fs_rect.bottom - pre_fs_rect.top,
                                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
                }
            }
#elif defined(WEBVIEW_GTK)
            GtkWidget* w = static_cast<GtkWidget*>(g_webview->window().value());
            if (w) {
                if (enabled) {
                    gtk_window_fullscreen(GTK_WINDOW(w));
                } else {
                    gtk_window_unfullscreen(GTK_WINDOW(w));
                }
            }
#elif defined(WEBVIEW_COCOA)
            NSWindow* w = (NSWindow*)(g_webview->window().value());
            if (w) {
                bool is_fs = (([w styleMask] & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen);
                if (is_fs != enabled) {
                    [w toggleFullScreen:nil];
                }
            }
#endif
        });
        return;
    }
    if (cmd == "SET_MENU") {
        if (j.contains("payload")) {
            std::string payload_str = j["payload"].dump();
            dispatch_to_webview([payload_str]() {
                apply_menu(payload_str);
            });
        }
        return;
    }

    if (cmd == "SET_TRAY") {
        std::string label = j["payload"].value("label", "");
        std::string icon  = j["payload"].value("icon", "");
        dispatch_to_webview([label, icon]() {
            set_system_tray(label, icon);
        });
        return;
    }

    if (cmd == "REMOVE_TRAY") {
        dispatch_to_webview([]() {
            remove_system_tray();
        });
        return;
    }

    if (cmd == "SET_TRAY_MENU") {
        if (j.contains("payload")) {
            std::string payload_str = j["payload"].dump();
            dispatch_to_webview([payload_str]() {
                set_system_tray_menu(payload_str);
            });
        }
        return;
    }

#ifdef _WIN32

    if (cmd == "DIALOG_OPEN") {
        json pl = j.value("payload", json::object());
        std::string title   = pl.value("title", "");
        std::string filter  = pl.value("filters", "All Files|*.*|");

        std::thread([id, title, filter]() {
            std::string path = open_file_dialog(title, filter);
            json out;
            if (!path.empty()) {
                out["event"] = "DIALOG_RESULT";
                out["id"]    = id;
                out["path"]  = path;
            } else {
                out["event"] = "DIALOG_CANCEL";
                out["id"]    = id;
            }
            write_stdout(out.dump());
        }).detach();
        return;
    }

    if (cmd == "DIALOG_SAVE") {
        json pl = j.value("payload", json::object());
        std::string title   = pl.value("title", "");
        std::string defname = pl.value("default_name", "");
        std::string filter  = pl.value("filters", "All Files|*.*|");
        std::string defext  = pl.value("default_ext", "");

        std::thread([id, title, defname, filter, defext]() {
            std::string path = save_file_dialog(title, defname, filter, defext);
            json out;
            if (!path.empty()) {
                out["event"] = "DIALOG_RESULT";
                out["id"]    = id;
                out["path"]  = path;
            } else {
                out["event"] = "DIALOG_CANCEL";
                out["id"]    = id;
            }
            write_stdout(out.dump());
        }).detach();
        return;
    }

    if (cmd == "NOTIFY") {
        json pl = j.value("payload", json::object());
        std::string title = pl.value("title", "");
        std::string body  = pl.value("body", "");
        show_notification(title, body);
        return;
    }
    if (cmd == "SET_POS") {
        int x = j["payload"].value("x", 0);
        int y = j["payload"].value("y", 0);
        dispatch_to_webview([x, y]() {
            SetWindowPos(g_hwnd, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        });
        return;
    }


    if (cmd == "TOPMOST") {
        bool enabled = j["payload"].value("enabled", false);
        dispatch_to_webview([enabled]() {
            SetWindowPos(g_hwnd, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        });
        return;
    }


    if (cmd == "DIALOG_FOLDER") {
        json pl = j.value("payload", json::object());
        std::string title = pl.value("title", "Select Folder");

        std::thread([id, title]() {
            std::string path = open_folder_dialog(title);
            json out;
            if (!path.empty()) {
                out["event"] = "DIALOG_RESULT";
                out["id"]    = id;
                out["path"]  = path;
            } else {
                out["event"] = "DIALOG_CANCEL";
                out["id"]    = id;
            }
            write_stdout(out.dump());
        }).detach();
        return;
    }

    if (cmd == "MESSAGE_BOX") {
        json pl = j.value("payload", json::object());
        std::string msg     = pl.value("message", "");
        std::string title   = pl.value("title", "RDesk");
        std::string type    = pl.value("type", "ok");
        std::string icon    = pl.value("icon", "info");

        std::thread([id, msg, title, type, icon]() {
            std::string res = show_message_box(msg, title, type, icon);
            json out;
            out["event"] = "DIALOG_RESULT";
            out["id"]    = id;
            out["result"] = res;
            write_stdout(out.dump());
        }).detach();
        return;
    }

    if (cmd == "DIALOG_COLOR") {
        json pl = j.value("payload", json::object());
        std::string initial = pl.value("color", "#FFFFFF");

        std::thread([id, initial]() {
            std::string res = choose_color_dialog(initial);
            json out;
            if (!res.empty()) {
                out["event"] = "DIALOG_RESULT";
                out["id"]    = id;
                out["result"] = res;
            } else {
                out["event"] = "DIALOG_CANCEL";
                out["id"]    = id;
            }
            write_stdout(out.dump());
        }).detach();
        return;
    }

    if (cmd == "INTERCEPT_CLOSE") {
        g_intercept_close.store(j["payload"].value("enabled", false));
        return;
    }
    if (cmd == "CLIPBOARD_WRITE") {
        set_clipboard_text(j["payload"].value("text", ""));
        return;
    }

    if (cmd == "CLIPBOARD_READ") {
        std::string text = get_clipboard_text();
        json out;
        out["event"]  = "DIALOG_RESULT";
        out["id"]     = id;
        out["result"] = text;
        write_stdout(out.dump());
        return;
    }

    if (cmd == "REGISTER_HOTKEY") {
        json pl = j.value("payload", json::object());
        int  hk_id = pl.value("id", 0);
        int  mod   = pl.value("modifiers", 0);
        int  vk    = pl.value("vk", 0);
        std::string label = pl.value("label", "");
        
        dispatch_to_webview([hk_id, mod, vk, label]() {
            std::lock_guard<std::mutex> lk(g_hotkey_mutex);
            if (RegisterHotKey(g_hwnd, hk_id, mod, vk)) {
                g_hotkeys[hk_id] = label;
            }
        });
        return;
    }
#endif
}

// ── Stdin reader thread ──────────────────────────────────────────────────────
static void stdin_reader() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        process_command(line);
        if (g_quit.load()) break;
    }
    g_quit.store(true);
    webview::webview* wv = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_webview_mutex);
        wv = g_webview;
    }
    if (wv) wv->terminate();
}

// ── Main ─────────────────────────────────────────────────────────────────────
#ifdef _WIN32
int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    int    argc;
    LPWSTR* wargv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) {
        int len = WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, nullptr, 0, nullptr, nullptr);
        std::string s(len - 1, '\0');
        WideCharToMultiByte(CP_UTF8, 0, wargv[i], -1, &s[0], len, nullptr, nullptr);
        args.push_back(s);
    }
    LocalFree(wargv);
#else
int main(int argc, char* argv[]) {
    #ifdef WEBVIEW_GTK
        rdesk_silence_webkit_diagnostics();
        rdesk_redirect_gtk_output();
        // Register scheme on the default web context before any webviews are created
        WebKitWebContext* context = webkit_web_context_get_default();
        register_rdesk_scheme(context);
    #elif defined(__APPLE__)
        setup_macos_scheme_interceptor();
    #endif

    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.push_back(argv[i]);
#endif

    if (args.empty()) {
        std::cerr << "Usage: rdesk-launcher <url> <title> <width> <height> [www_path] [parent_pid]\n";
        return 1;
    }

    std::string url    = args[0];
    std::string title  = args.size() > 1 ? args[1] : "RDesk App";
    int         width  = args.size() > 2 ? std::stoi(args[2]) : 1200;
    int         height = args.size() > 3 ? std::stoi(args[3]) : 800;
    std::string www    = args.size() > 4 ? args[4] : "";
    
    unsigned long parent_pid = 0;
    if (args.size() > 5) {
        try {
            parent_pid = std::stoul(args[5]);
        } catch (...) {}
    }

#ifdef WEBVIEW_GTK
    g_www_path = www;
#elif defined(__APPLE__)
    g_www_path = www;
#endif

#ifdef _WIN32
    // Single Instance Check (Windows only)
    size_t title_hash = std::hash<std::string>{}(title);
    std::wstring mutex_name = L"Local\\RDesk_Instance_" + std::to_wstring(title_hash);
    HANDLE hMutex = CreateMutexW(NULL, TRUE, mutex_name.c_str());
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        HWND hwndExisting = FindWindowW(nullptr, widen(title).c_str());
        if (hwndExisting) {
            if (IsIconic(hwndExisting)) {
                ShowWindow(hwndExisting, SW_RESTORE);
            }
            SetForegroundWindow(hwndExisting);
        }
        if (hMutex) CloseHandle(hMutex);
        return 0;
    }
#endif

    try {
        webview::webview w(true, nullptr);
        {
            std::lock_guard<std::mutex> lk(g_webview_mutex);
            g_webview = &w;
        }

        w.set_title(title);
        w.set_size(width, height, WEBVIEW_HINT_NONE);

#ifdef _WIN32
        g_hwnd = (HWND)w.window().value();
        
        if (parent_pid != 0) {
            std::thread(parent_watchdog, (DWORD)parent_pid).detach();
        }

        // WebView2 virtual hostname + message receiver setup
        auto controller = static_cast<ICoreWebView2Controller*>(w.browser_controller().value());
        if (controller) {
            controller->get_CoreWebView2(&g_core_webview);
            if (g_core_webview) {
                ICoreWebView2_3* webview3 = nullptr;
                if (SUCCEEDED(g_core_webview->QueryInterface(IID_ICoreWebView2_3, reinterpret_cast<void**>(&webview3)))) {
                    std::wstring wwwPath = widen(www);
                    if (wwwPath.empty()) {
                        wchar_t exePath[MAX_PATH];
                        GetModuleFileNameW(NULL, exePath, MAX_PATH);
                        PathRemoveFileSpecW(exePath);
                        wwwPath = std::wstring(exePath) + L"\\www";
                    }
                    
                    webview3->SetVirtualHostNameToFolderMapping(
                        L"app.rdesk", wwwPath.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
                    webview3->Release();
                }

                EventRegistrationToken token;
                auto handler = new MessageHandler(
                        [](ICoreWebView2* sender, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                            LPWSTR message = nullptr;
                            if (SUCCEEDED(args->TryGetWebMessageAsString(&message))) {
                                int len = WideCharToMultiByte(CP_UTF8, 0, message, -1, nullptr, 0, nullptr, nullptr);
                                if (len > 0) {
                                    std::string s(len - 1, '\0');
                                    WideCharToMultiByte(CP_UTF8, 0, message, -1, &s[0], len, nullptr, nullptr);
                                    write_stdout(s);
                                }
                                CoTaskMemFree(message);
                            }
                            return S_OK;
                        });
                g_core_webview->add_WebMessageReceived(handler, &token);
                handler->Release();
            }
        }
#else
        if (parent_pid != 0) {
            std::thread(parent_watchdog, (pid_t)parent_pid).detach();
        }

        w.bind("rdesk_send_to_r", [](const std::string& s) -> std::string {
            try {
                auto j = json::parse(s);
                if (j.is_array() && !j.empty() && j[0].is_string()) {
                    write_stdout(j[0].get<std::string>());
                } else {
                    write_stdout(s);
                }
            } catch (...) {
                write_stdout(s);
            }
            return "";
        });

        #ifdef WEBVIEW_GTK
            WebKitWebView* webview = WEBKIT_WEB_VIEW(w.browser_controller().value());
            rdesk_setup_webkit_console_redirect(webview);

            GtkWidget* window_widget = GTK_WIDGET(w.window().value());
            g_signal_connect(G_OBJECT(window_widget), "delete-event",
                             G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer arg) -> gboolean {
                                 auto* w = static_cast<webview::webview*>(arg);
                                 if (g_intercept_close.load()) {
                                     json out;
                                     out["event"] = "WINDOW_CLOSING";
                                     write_stdout(out.dump());
                                     return TRUE;
                                 }
                                 write_stdout("CLOSED");
                                 w->terminate();
                                 return FALSE;
                             }), &w);
        #endif
#endif

        w.navigate(url);

        write_stdout("READY");

        std::thread(stdin_reader).detach();

#ifdef _WIN32
        static WNDPROC orig_wndproc = nullptr;
        orig_wndproc = reinterpret_cast<WNDPROC>(
            SetWindowLongPtrW(g_hwnd, GWLP_WNDPROC,
                reinterpret_cast<LONG_PTR>(+[](HWND hwnd, UINT msg,
                                                 WPARAM wp, LPARAM lp) -> LRESULT {
                    if (msg == WM_COMMAND) {
                        UINT id = LOWORD(wp);
                        auto it = g_menu_actions.find(id);
                        if (it != g_menu_actions.end()) {
                            json out;
                            out["event"] = "MENU_CLICK";
                            out["id"]    = it->second;
                            write_stdout(out.dump());
                        }
                    } else if (msg == WM_TRAYICON) {
                        if (lp == WM_LBUTTONUP || lp == WM_RBUTTONUP) {
                            json out;
                            out["event"]  = "TRAY_CLICK";
                            out["button"] = (lp == WM_LBUTTONUP) ? "left" : "right";
                            write_stdout(out.dump());
                            
                            if (lp == WM_LBUTTONUP) {
                                ShowWindow(hwnd, SW_RESTORE);
                                SetForegroundWindow(hwnd);
                            }
                            if (lp == WM_RBUTTONUP && g_hmenu_tray) {
                                POINT pt;
                                GetCursorPos(&pt);
                                SetForegroundWindow(hwnd);
                                TrackPopupMenu(g_hmenu_tray, TPM_BOTTOMALIGN | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd, NULL);
                                PostMessage(hwnd, WM_NULL, 0, 0);
                            }
                        }
                    } else if (msg == WM_HOTKEY) {
                        int id = (int)wp;
                        std::lock_guard<std::mutex> lk(g_hotkey_mutex);
                        auto it = g_hotkeys.find(id);
                        json out;
                        out["event"] = "HOTKEY";
                        out["id"]    = id;
                        out["label"] = (it != g_hotkeys.end()) ? it->second : "";
                        write_stdout(out.dump());
                    } else if (msg == WM_CLOSE) {
                        if (g_intercept_close.load()) {
                            json out;
                            out["event"] = "WINDOW_CLOSING";
                            write_stdout(out.dump());
                            return 0;
                        }
                    }
                    return CallWindowProcW(orig_wndproc, hwnd, msg, wp, lp);
                })
            )
        );
#endif

        w.run();

        g_quit.store(true);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        write_stdout("CLOSED");

#ifdef _WIN32
        ICoreWebView2* core = nullptr;
        {
            std::lock_guard<std::mutex> lk(g_webview_mutex);
            g_webview = nullptr;
            core = g_core_webview;
            g_core_webview = nullptr;
        }

        if (g_notify_icon_added) {
            Shell_NotifyIconW(NIM_DELETE, &g_nid);
            g_notify_icon_added = false;
            g_tray_active = false;
        }

        if (core) {
            core->Release();
        }
        if (hMutex) {
            CloseHandle(hMutex);
        }
#else
        {
            std::lock_guard<std::mutex> lk(g_webview_mutex);
            g_webview = nullptr;
        }
#endif

    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
