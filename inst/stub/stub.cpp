#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <filesystem>
#include <vector>
#include <cwctype>

static std::filesystem::path find_rscript(const std::filesystem::path& base) {
    const std::vector<std::filesystem::path> candidates = {
        base / "runtime" / "R" / "bin" / "x64" / "Rscript.exe",
        base / "runtime" / "R" / "bin" / "arm64" / "Rscript.exe",
        base / "runtime" / "R" / "bin" / "i386" / "Rscript.exe"
    };

    for (const auto& candidate : candidates) {
        if (std::filesystem::exists(candidate)) return candidate;
    }

    return {};
}

static std::wstring sanitize_log_component(const std::wstring& value) {
    std::wstring result;
    result.reserve(value.size());

    for (wchar_t ch : value) {
        if (std::iswalnum(ch) || ch == L'-' || ch == L'_' || ch == L'.') {
            result.push_back(ch);
        } else {
            result.push_back(L'_');
        }
    }

    if (result.empty()) return L"RDeskApp";
    return result;
}

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    // Find our own directory
    wchar_t self_path[MAX_PATH];
    GetModuleFileNameW(nullptr, self_path, MAX_PATH);
    std::filesystem::path base = std::filesystem::path(self_path).parent_path();

    // Paths relative to the zip root
    auto rscript = find_rscript(base);
    auto app_r   = base / "app" / "app.R";
    auto lib_dir = base / "packages" / "library";

    if (rscript.empty()) {
        MessageBoxW(nullptr,
            L"R runtime not found.\nExpected one of:\n"
            L"runtime\\R\\bin\\x64\\Rscript.exe\n"
            L"runtime\\R\\bin\\arm64\\Rscript.exe\n"
            L"runtime\\R\\bin\\i386\\Rscript.exe",
            L"RDesk — Launch Error", MB_ICONERROR);
        return 1;
    }

    // Build command: Rscript.exe --vanilla app/app.R
    std::wstring cmd = L"\"" + rscript.wstring() + L"\" --vanilla \"" +
                       app_r.wstring() + L"\"";

    // Set R_LIBS to include BOTH our bundle library and the R runtime library
    // This is critical for R to find base packages (utils, stats, etc.)
    auto r_base_lib = base / "runtime" / "R" / "library";
    std::wstring libs_env = L"R_LIBS=" + lib_dir.wstring() + L";" + r_base_lib.wstring();
    _wputenv(libs_env.c_str());

    // Also set R_HOME to keep R from looking in registry
    std::wstring rhome = L"R_HOME=" +
        (base / "runtime" / "R").wstring();
    _wputenv(rhome.c_str());

    // Set a flag so the R code knows it's running in a bundle
    _wputenv(L"R_BUNDLE_APP=1");
    _wputenv(L"R_APP_NAME={{APP_NAME}}");

    const std::wstring app_name = L"{{APP_NAME}}";
    const std::wstring safe_log_name = sanitize_log_component(app_name);

    // LOGGING SETUP
    std::wstring log_dir_str;
    const wchar_t* local_appdata = _wgetenv(L"LOCALAPPDATA");
    if (local_appdata) {
        log_dir_str = std::wstring(local_appdata) + L"\\RDesk\\" + safe_log_name;
    } else {
        const wchar_t* temp_dir = _wgetenv(L"TEMP");
        log_dir_str = std::wstring(temp_dir ? temp_dir : L"C:\\Temp") + L"\\RDesk\\" + safe_log_name;
    }

    std::filesystem::path log_dir = log_dir_str;
    std::filesystem::create_directories(log_dir);
    
    std::wstring log_name = safe_log_name + L"_crash.log";
    std::filesystem::path log_path = log_dir / log_name;

    SECURITY_ATTRIBUTES saAttr;
    saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
    saAttr.bInheritHandle = TRUE;
    saAttr.lpSecurityDescriptor = nullptr;

    HANDLE hLogFile = CreateFileW(log_path.wstring().c_str(),
                                  FILE_APPEND_DATA,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  &saAttr,
                                  OPEN_ALWAYS,
                                  FILE_ATTRIBUTE_NORMAL,
                                  nullptr);

    STARTUPINFOW        si = {};
    PROCESS_INFORMATION pi = {};
    si.cb = sizeof(si);
    
    if (hLogFile != INVALID_HANDLE_VALUE) {
        SetFilePointer(hLogFile, 0, nullptr, FILE_END);
        si.hStdInput  = GetStdHandle(STD_INPUT_HANDLE);
        si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
        si.hStdError = hLogFile;
        si.dwFlags |= STARTF_USESTDHANDLES;
    }

    if (!CreateProcessW(nullptr,
            const_cast<wchar_t*>(cmd.c_str()),
            nullptr, nullptr, TRUE, // TRUE to inherit handles
            CREATE_NO_WINDOW,
            nullptr,
            (base / "app").wstring().c_str(),
            &si, &pi)) {
        if (hLogFile != INVALID_HANDLE_VALUE) CloseHandle(hLogFile);
        MessageBoxW(nullptr, (L"Failed to start Rscript.exe\nCommand: " + cmd).c_str(),
                    L"RDesk — Launch Error", MB_ICONERROR);
        return 1;
    }

    // Wait for R to finish
    WaitForSingleObject(pi.hProcess, INFINITE);
    
    DWORD exitCode = 0;
    GetExitCodeProcess(pi.hProcess, &exitCode);

    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    if (hLogFile != INVALID_HANDLE_VALUE) CloseHandle(hLogFile);

    if (exitCode != 0) {
        std::wstring msg = L"The application encountered an error (Code: " + std::to_wstring(exitCode) + 
                           L").\n\nSee " + log_name + L" for details.";
        MessageBoxW(nullptr, msg.c_str(), L"RDesk — Application Error", MB_ICONERROR);
    } else {
        // Clean exit -> Remove log file
        std::error_code ec;
        std::filesystem::remove(log_path, ec);
    }

    return exitCode;
}
