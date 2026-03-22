#include <windows.h>
#include <commdlg.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <shobjidl.h> // for folder picker
#pragma comment(lib, "comdlg32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")


#if defined(_WIN32)
#include <wrl.h>
#endif
#include "webview/webview.h"
#include <WebView2.h>

// IID_ICoreWebView2_3 is already in WebView2.h, removing manual definition.
 
static const UINT WM_TRAYICON = WM_USER + 1;

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

// --- Custom WebView2 Event Handler (MinGW/RTools doesn't have WRL) ---
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



// ── global state ─────────────────────────────────────────────────────────────
static std::atomic<bool>  g_quit{false};
static std::atomic<bool>  g_intercept_close{false};
static webview::webview*  g_webview = nullptr;
static ICoreWebView2*     g_core_webview = nullptr;
static HMENU              g_hmenu_tray = nullptr;
static std::map<int, std::string> g_hotkeys;
static std::mutex         g_out_mutex;
static std::mutex         g_webview_mutex;

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

// ── menu support (Windows only) ──────────────────────────────────────────────
#ifdef _WIN32

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
                    // Top-level direct entry (unusual for a bar but allowed)
                    UINT win_id = g_menu_id_counter++;
                    std::wstring wlabel = widen(label);
                    AppendMenuW(bar, MF_STRING, win_id, wlabel.c_str());
                    std::string item_id = top.value("id", "");
                    if (!item_id.empty()) g_menu_actions[win_id] = item_id;
                }
            }
        }
    } catch (const json::exception&) {
        // Skip malformed menu JSON
    }

    if (!SetMenu(g_hwnd, bar)) {
        DestroyMenu(bar);
        return;
    }
    DrawMenuBar(g_hwnd);
    if (g_hmenu_bar) DestroyMenu(g_hmenu_bar);
    g_hmenu_bar = bar;
}

// File dialog helpers (Windows IFileDialog - modern Vista+ API)
static std::string open_file_dialog(const std::string& title,
                                     const std::string& filter_str) {
    wchar_t buf[32768] = {0};
    OPENFILENAMEW ofn  = {};
    ofn.lStructSize    = sizeof(ofn);
    ofn.hwndOwner      = g_hwnd;
    ofn.lpstrFile      = buf;
    ofn.nMaxFile       = 32767;
    ofn.Flags          = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

    // Convert filter string (pairs separated by \0, double-\0 terminated)
    std::wstring wfilter = widen(filter_str);
    // Replace literal \0 markers — R sends "|" as separator for null bytes
    for (auto& c : wfilter) if (c == L'|') c = L'\0';
    ofn.lpstrFilter = wfilter.empty() ? nullptr : wfilter.c_str();

    std::wstring wtitle = widen(title);
    ofn.lpstrTitle = wtitle.empty() ? nullptr : wtitle.c_str();

    if (GetOpenFileNameW(&ofn)) {
        // Convert back to UTF-8
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
    
    // Parse hex color string "#RRGGBB"
    COLORREF initial_color = RGB(255, 255, 255);
    if (initial_hex.length() == 7 && initial_hex[0] == '#') {
        try {
            int r = std::stoi(initial_hex.substr(1, 2), nullptr, 16);
            int g = std::stoi(initial_hex.substr(3, 2), nullptr, 16);
            int b = std::stoi(initial_hex.substr(5, 2), nullptr, 16);
            initial_color = RGB(r, g, b);
        } catch (...) {
            // Malformed hex string, use default
        }
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

    if (!icon_path.empty()) {
        // TODO: Load custom tray icons from icon_path.
    }

    Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}
 
static void remove_system_tray() {
    g_tray_active = false;
    if (g_notify_icon_added) {
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        g_notify_icon_added = false;
    }
}
 
#endif // _WIN32

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


static int parse_dimension_arg(const std::vector<std::string>& args, size_t index, int fallback) {
    if (args.size() <= index || args[index].empty()) return fallback;

    const std::string& value = args[index];
    size_t start = (value[0] == '+' || value[0] == '-') ? 1 : 0;
    if (start == value.size()) return fallback;

    if (!std::all_of(value.begin() + static_cast<std::ptrdiff_t>(start), value.end(),
            [](unsigned char ch) { return std::isdigit(ch) != 0; })) {
        return fallback;
    }

    try {
        int parsed = std::stoi(value);
        return parsed > 0 ? parsed : fallback;
    } catch (...) {
        return fallback;
    }
}

// ── stdin command processor ──────────────────────────────────────────────────
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

#ifdef _WIN32
    if (cmd == "SET_MENU") {
        if (j.contains("payload")) {
            std::string payload_str = j["payload"].dump();
            dispatch_to_webview([payload_str]() {
                apply_menu(payload_str);
            });
        }
        return;
    }

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

    if (cmd == "SET_SIZE") {
        int w = j["payload"].value("width", 800);
        int h = j["payload"].value("height", 600);
        dispatch_to_webview([w, h]() {
            g_webview->set_size(w, h, WEBVIEW_HINT_NONE);
        });
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

    if (cmd == "MINIMIZE") {
        dispatch_to_webview([]() { ShowWindow(g_hwnd, SW_MINIMIZE); });
        return;
    }

    if (cmd == "MAXIMIZE") {
        dispatch_to_webview([]() { ShowWindow(g_hwnd, SW_MAXIMIZE); });
        return;
    }

    if (cmd == "RESTORE") {
        dispatch_to_webview([]() { ShowWindow(g_hwnd, SW_RESTORE); });
        return;
    }

    if (cmd == "TOPMOST") {
        bool enabled = j["payload"].value("enabled", false);
        dispatch_to_webview([enabled]() {
            SetWindowPos(g_hwnd, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        });
        return;
    }

    if (cmd == "FULLSCREEN") {
        bool enabled = j["payload"].value("enabled", false);
        dispatch_to_webview([enabled]() {
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

    if (cmd == "SET_TRAY_MENU") {
        if (j.contains("payload")) {
            std::string payload_str = j["payload"].dump();
            dispatch_to_webview([payload_str]() {
                try {
                    auto items = json::parse(payload_str);
                    if (g_hmenu_tray) DestroyMenu(g_hmenu_tray);
                    g_hmenu_tray = build_win32_menu(items);
                } catch(...) {}
            });
        }
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
        int  mod   = pl.value("modifiers", 0); // 1=Alt, 2=Ctrl, 4=Shift, 8=Win
        int  vk    = pl.value("vk", 0);
        std::string label = pl.value("label", "");
        
        dispatch_to_webview([hk_id, mod, vk, label]() {
            if (RegisterHotKey(g_hwnd, hk_id, mod, vk)) {
                g_hotkeys[hk_id] = label;
            }
        });
        return;
    }

    if (cmd == "SEND_MSG") {
        if (j.contains("payload")) {
            // We need the RAW JSON string for the payload to pass to PostWebMessageAsString
            // If the payload was already a string in original line, nlohmann might have escaped it.
            // But RDesk sends the entire message envelope as JSON, and payload is an object or escaped JSON string.
            // If payload is an object, dump it. If it's a string, use it.
            std::string payload_str;
            if (j["payload"].is_string()) {
                payload_str = j["payload"].get<std::string>();
            } else {
                payload_str = j["payload"].dump();
            }

            if (!payload_str.empty()) {
                dispatch_to_webview([payload_str]() {
                    ICoreWebView2* core = g_core_webview;
                    if (core) {
                        core->AddRef();
                        std::wstring wpayload = widen(payload_str);
                        core->PostWebMessageAsString(wpayload.c_str());
                        core->Release();
                    }
                });
            }
        }
        return;
    }
#endif
}

// ── stdin reader thread ──────────────────────────────────────────────────────
static void stdin_reader() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        process_command(line);
        if (g_quit.load()) break;
    }
    // stdin closed — terminate window
    g_quit.store(true);
    webview::webview* wv = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_webview_mutex);
        wv = g_webview;
    }
    if (wv) wv->terminate();
}

// ── main ─────────────────────────────────────────────────────────────────────
#ifdef _WIN32
int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR lpCmdLine, int) {
    // Parse args from lpCmdLine (space-separated, no quoting support needed
    // because R/processx passes them as separate argv)
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
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.push_back(argv[i]);
#endif

    if (args.empty()) {
        std::cerr << "Usage: rdesk-launcher.exe <url> <title> <width> <height> [www_path] [parent_pid]\n";
        return 1;
    }

    std::string url    = args[0];
    std::string title  = args.size() > 1 ? args[1] : "RDesk App";
    int         width  = args.size() > 2 ? std::stoi(args[2]) : 1200;
    int         height = args.size() > 3 ? std::stoi(args[3]) : 800;
    std::string www    = args.size() > 4 ? args[4] : "";
    
    DWORD parent_pid = 0;
    if (args.size() > 5) {
        try {
            parent_pid = std::stoul(args[5]);
        } catch (...) { /* ignore */ }
    }

    // Single Instance Check (Optional - based on title hash)
    size_t title_hash = std::hash<std::string>{}(title);
    std::wstring mutex_name = L"Local\\RDesk_Instance_" + std::to_wstring(title_hash);
    HANDLE hMutex = CreateMutexW(NULL, TRUE, mutex_name.c_str());
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        // App already running. Focus existing? For now, just exit.
        if (hMutex) CloseHandle(hMutex);
        return 0;
    }

    try {
        webview::webview w(true, nullptr);
        {
            std::lock_guard<std::mutex> lk(g_webview_mutex);
            g_webview = &w;
        }

#ifdef _WIN32
        // Get the underlying HWND so we can attach Win32 menus
        g_hwnd = (HWND)w.window().value();
        
        // Watchdog Thread for Parent PID
        if (parent_pid != 0) {
            std::thread(parent_watchdog, parent_pid).detach();
        }
#endif

        w.set_title(title);
        w.set_size(width, height, WEBVIEW_HINT_NONE);

        // --- Native IPC & Virtual Hostname setup ---
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

                // Register native message handler
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
                handler->Release(); // WebView2 will hold onto it via AddRef
            }
        }

        w.navigate(url);

        write_stdout("READY");

        // Start stdin reader on background thread
        std::thread(stdin_reader).detach();

#ifdef _WIN32
        // Subclass the window procedure to catch WM_COMMAND (menu clicks)
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
                            
                            // Bring window to front on left click if visible
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
                            return 0; // Prevent close
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

    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
