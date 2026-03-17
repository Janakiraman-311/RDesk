#include <windows.h>
#include <commdlg.h>
#include <shellapi.h>
#include <shlwapi.h>
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
#include <map>
#include <functional>
#include <sstream>
#include <vector>

// ── tiny JSON helpers (no external dep) ─────────────────────────────────────
static std::string json_str(const std::string& s) {
    std::string out = "\"";
    for (char c : s) {
        if (c == '"')  out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else out += c;
    }
    return out + "\"";
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

static std::string json_get(const std::string& json, const std::string& key) {
    // Minimal key lookup: finds "key":"value" or "key":number
    std::string search = "\"" + key + "\":\"";
    auto pos = json.find(search);
    if (pos != std::string::npos) {
        pos += search.size();
        auto end = json.find('"', pos);
        return json.substr(pos, end - pos);
    }
    // Try without quotes (number/bool)
    search = "\"" + key + "\":";
    pos = json.find(search);
    if (pos != std::string::npos) {
        pos += search.size();
        auto end = json.find_first_of(",}", pos);
        return json.substr(pos, end - pos);
    }
    return "";
}

// ── global state ─────────────────────────────────────────────────────────────
static std::atomic<bool>  g_quit{false};
static webview::webview*  g_webview = nullptr;
static ICoreWebView2*     g_core_webview = nullptr;
static std::mutex         g_out_mutex;

static void write_stdout(const std::string& line) {
    std::lock_guard<std::mutex> lk(g_out_mutex);
    std::cout << line << "\n";
    std::cout.flush();
}

// ── menu support (Windows only) ──────────────────────────────────────────────
#ifdef _WIN32

static HMENU g_hmenu_bar = nullptr;
static std::map<UINT, std::string> g_menu_actions; // ID → action id string
static UINT  g_menu_id_counter = 1000;
static HWND  g_hwnd = nullptr;
static NOTIFYICONDATAW g_nid = {};
static bool  g_tray_active = false;

static HMENU build_submenu(const std::string& items_json) {
    HMENU sub = CreatePopupMenu();
    // items_json is a JSON array: [{"label":"X","id":"y"}, {"label":"---"}, ...]
    // Simple parser: find each {"label": ... } block
    size_t pos = 0;
    while ((pos = items_json.find('{', pos)) != std::string::npos) {
        auto end = items_json.find('}', pos);
        if (end == std::string::npos) break;
        std::string item = items_json.substr(pos, end - pos + 1);
        std::string label = json_get(item, "label");
        std::string id    = json_get(item, "id");

        if (label == "---") {
            AppendMenuW(sub, MF_SEPARATOR, 0, nullptr);
        } else if (!label.empty()) {
            UINT item_id = g_menu_id_counter++;
            std::wstring wlabel(label.begin(), label.end());
            AppendMenuW(sub, MF_STRING, item_id, wlabel.c_str());
            if (!id.empty()) g_menu_actions[item_id] = id;
        }
        pos = end + 1;
    }
    return sub;
}

static void apply_menu(const std::string& payload_json) {
    if (!g_hwnd) return;
    g_menu_actions.clear();
    g_menu_id_counter = 1000;

    HMENU bar = CreateMenu();

    // payload_json is array of top-level: [{"label":"File","items":[...]}, ...]
    size_t pos = 0;
    // Find each top-level object
    int depth = 0;
    size_t obj_start = std::string::npos;
    for (size_t i = 0; i < payload_json.size(); ++i) {
        if (payload_json[i] == '{') {
            if (depth == 0) obj_start = i;
            ++depth;
        } else if (payload_json[i] == '}') {
            --depth;
            if (depth == 0 && obj_start != std::string::npos) {
                std::string obj = payload_json.substr(obj_start, i - obj_start + 1);
                std::string top_label = json_get(obj, "label");

                // Extract items array
                auto items_start = obj.find("\"items\":[");
                std::string items_json;
                if (items_start != std::string::npos) {
                    items_start += 9; // skip "items":[
                    auto items_end = obj.rfind(']');
                    if (items_end != std::string::npos)
                        items_json = obj.substr(items_start, items_end - items_start);
                }

                HMENU sub = build_submenu(items_json);
                std::wstring wlabel(top_label.begin(), top_label.end());
                AppendMenuW(bar, MF_POPUP, (UINT_PTR)sub, wlabel.c_str());
                obj_start = std::string::npos;
            }
        }
    }

    SetMenu(g_hwnd, bar);
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
    std::wstring wfilter(filter_str.begin(), filter_str.end());
    // Replace literal \0 markers — R sends "|" as separator for null bytes
    for (auto& c : wfilter) if (c == L'|') c = L'\0';
    ofn.lpstrFilter = wfilter.empty() ? nullptr : wfilter.c_str();

    std::wstring wtitle(title.begin(), title.end());
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
        std::wstring wdn(default_name.begin(), default_name.end());
        wcsncpy_s(buf, wdn.c_str(), 32767);
    }
    OPENFILENAMEW ofn = {};
    ofn.lStructSize   = sizeof(ofn);
    ofn.hwndOwner     = g_hwnd;
    ofn.lpstrFile     = buf;
    ofn.nMaxFile      = 32767;
    ofn.Flags         = OFN_OVERWRITEPROMPT | OFN_NOCHANGEDIR;

    std::wstring wfilter(filter_str.begin(), filter_str.end());
    for (auto& c : wfilter) if (c == L'|') c = L'\0';
    ofn.lpstrFilter = wfilter.empty() ? nullptr : wfilter.c_str();

    std::wstring wtitle(title.begin(), title.end());
    ofn.lpstrTitle = wtitle.empty() ? nullptr : wtitle.c_str();

    std::wstring wext(default_ext.begin(), default_ext.end());
    ofn.lpstrDefExt = default_ext.empty() ? nullptr : wext.c_str();

    if (GetSaveFileNameW(&ofn)) {
        int len = WideCharToMultiByte(CP_UTF8, 0, buf, -1, nullptr, 0, nullptr, nullptr);
        std::string result(len - 1, '\0');
        WideCharToMultiByte(CP_UTF8, 0, buf, -1, &result[0], len, nullptr, nullptr);
        return result;
    }
    return "";
}

static void show_notification(const std::string& title, const std::string& body) {
    // Windows balloon notification via Shell_NotifyIcon
    NOTIFYICONDATAW nid = {};
    nid.cbSize      = sizeof(nid);
    nid.uFlags      = NIF_INFO;
    nid.dwInfoFlags = NIIF_INFO;
    nid.uTimeout    = 4000;

    std::wstring wtitle(title.begin(), title.end());
    std::wstring wbody(body.begin(),   body.end());
    wcsncpy_s(nid.szInfoTitle, wtitle.c_str(), 63);
    wcsncpy_s(nid.szInfo,      wbody.c_str(),  255);

    // We need a valid HWND for Shell_NotifyIcon
    nid.hWnd = g_hwnd;
    nid.uID  = 1;

    // Add icon first, then modify
    nid.uFlags |= NIF_ICON | NIF_TIP;
    nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    wcsncpy_s(nid.szTip, L"RDesk App", 63);
    Shell_NotifyIconW(NIM_ADD,    &nid);
    Shell_NotifyIconW(NIM_MODIFY, &nid);
    // Remove after showing
    std::thread([nid]() mutable {
        Sleep(5000);
        Shell_NotifyIconW(NIM_DELETE, &nid);
    }).detach();
}

 
static void set_system_tray(const std::string& label, const std::string& icon_path) {
    if (!g_hwnd) return;
 
    if (!g_tray_active) {
        g_nid.cbSize = sizeof(g_nid);
        g_nid.hWnd = g_hwnd;
        g_nid.uID = 1001;
        g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        g_nid.uCallbackMessage = WM_TRAYICON;
        g_nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION); // TODO: Load from icon_path
        g_tray_active = true;
    }
 
    std::wstring wlabel(label.begin(), label.end());
    wcsncpy_s(g_nid.szTip, wlabel.c_str(), 127);
 
    if (g_tray_active) {
        Shell_NotifyIconW(NIM_ADD, &g_nid);
        Shell_NotifyIconW(NIM_MODIFY, &g_nid);
    }
}
 
static void remove_system_tray() {
    if (g_tray_active) {
        Shell_NotifyIconW(NIM_DELETE, &g_nid);
        g_tray_active = false;
    }
}
 
#endif // _WIN32

// ── stdin command processor ──────────────────────────────────────────────────
static void process_command(const std::string& line) {
    std::string cmd = json_get(line, "cmd");
    std::string id  = json_get(line, "id");

    if (cmd == "QUIT") {
        g_quit.store(true);
        if (g_webview) g_webview->terminate();
        return;
    }

    if (cmd == "SET_TITLE") {
        std::string title = json_get(json_get(line, "payload"), "title");
        if (g_webview && !title.empty()) {
            g_webview->dispatch([title]() {
                if (g_webview) g_webview->set_title(title);
            });
        }
        return;
    }

#ifdef _WIN32
    if (cmd == "SET_MENU") {
        // payload is the array of top-level menu items
        auto payload_start = line.find("\"payload\":");
        if (payload_start != std::string::npos) {
            payload_start += 10;
            std::string payload = line.substr(payload_start);
            // Remove trailing }
            auto last = payload.rfind('}');
            if (last != std::string::npos) payload = payload.substr(0, last);
            // Dispatch to UI thread (required for Win32 menu operations)
            g_webview->dispatch([payload]() {
                apply_menu(payload);
            });
        }
        return;
    }

    if (cmd == "DIALOG_OPEN") {
        std::string payload = line; // full line contains all we need
        std::string title   = json_get(payload, "title");
        std::string filter  = json_get(payload, "filters");
        if (filter.empty()) filter = "All Files|*.*|";

        std::thread([id, title, filter]() {
            std::string path = open_file_dialog(title, filter);
            if (!path.empty()) {
                write_stdout("{\"event\":\"DIALOG_RESULT\",\"id\":" + json_str(id) +
                             ",\"path\":" + json_str(path) + "}");
            } else {
                write_stdout("{\"event\":\"DIALOG_CANCEL\",\"id\":" + json_str(id) + "}");
            }
        }).detach();
        return;
    }

    if (cmd == "DIALOG_SAVE") {
        std::string title   = json_get(line, "title");
        std::string defname = json_get(line, "default_name");
        std::string filter  = json_get(line, "filters");
        std::string defext  = json_get(line, "default_ext");
        if (filter.empty()) filter = "All Files|*.*|";

        std::thread([id, title, defname, filter, defext]() {
            std::string path = save_file_dialog(title, defname, filter, defext);
            if (!path.empty()) {
                write_stdout("{\"event\":\"DIALOG_RESULT\",\"id\":" + json_str(id) +
                             ",\"path\":" + json_str(path) + "}");
            } else {
                write_stdout("{\"event\":\"DIALOG_CANCEL\",\"id\":" + json_str(id) + "}");
            }
        }).detach();
        return;
    }

    if (cmd == "NOTIFY") {
        std::string title = json_get(line, "title");
        std::string body  = json_get(line, "body");
        show_notification(title, body);
        return;
    }
 
    if (cmd == "SET_TRAY") {
        std::string label = json_get(json_get(line, "payload"), "label");
        std::string icon  = json_get(json_get(line, "payload"), "icon");
        g_webview->dispatch([label, icon]() {
            set_system_tray(label, icon);
        });
        return;
    }
 
    if (cmd == "REMOVE_TRAY") {
        g_webview->dispatch([]() {
            remove_system_tray();
        });
        return;
    }
    if (cmd == "SEND_MSG") {
        std::string payload = json_get(line, "payload");
        if (g_core_webview && !payload.empty()) {
            std::wstring wpayload;
            int len = MultiByteToWideChar(CP_UTF8, 0, payload.c_str(), -1, nullptr, 0);
            if (len > 0) {
                wpayload.resize(len - 1);
                MultiByteToWideChar(CP_UTF8, 0, payload.c_str(), -1, &wpayload[0], len);
                g_core_webview->PostWebMessageAsString(wpayload.c_str());
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
    if (g_webview) g_webview->terminate();
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
        std::cerr << "Usage: rdesk-launcher <url> [title] [width] [height] [www_path]\n";
        return 1;
    }

    std::string url    = args[0];
    std::string title  = args.size() > 1 ? args[1] : "RDesk App";
    int         width  = args.size() > 2 ? std::stoi(args[2]) : 1200;
    int         height = args.size() > 3 ? std::stoi(args[3]) : 800;
    std::string www    = args.size() > 4 ? args[4] : "";

    try {
        webview::webview w(false, nullptr);
        g_webview = &w;

#ifdef _WIN32
        // Get the underlying HWND so we can attach Win32 menus
        g_hwnd = reinterpret_cast<HWND>(w.window().value());
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
                    std::wstring wwwPath;
                    if (!www.empty()) {
                        wwwPath = std::wstring(www.begin(), www.end());
                    } else {
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
                            write_stdout("{\"event\":\"MENU_CLICK\",\"id\":" +
                                         json_str(it->second) + "}");
                        }
                    } else if (msg == WM_TRAYICON) {
                        if (lp == WM_LBUTTONUP || lp == WM_RBUTTONUP) {
                            std::string button = (lp == WM_LBUTTONUP) ? "left" : "right";
                            write_stdout("{\"event\":\"TRAY_CLICK\",\"button\":" + json_str(button) + "}");
                            
                            // Bring window to front on left click if visible
                            if (lp == WM_LBUTTONUP) {
                                ShowWindow(hwnd, SW_RESTORE);
                                SetForegroundWindow(hwnd);
                            }
                        }
                    }
                    return CallWindowProcW(orig_wndproc, hwnd, msg, wp, lp);
                })
            )
        );
#endif

        w.run();

        write_stdout("CLOSED");
        g_webview = nullptr;

    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
