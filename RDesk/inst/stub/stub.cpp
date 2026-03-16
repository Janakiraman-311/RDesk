#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <filesystem>

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    // Find our own directory
    wchar_t self_path[MAX_PATH];
    GetModuleFileNameW(nullptr, self_path, MAX_PATH);
    std::filesystem::path base = std::filesystem::path(self_path).parent_path();

    // Paths relative to the zip root
    auto rscript = base / "runtime" / "R" / "bin" / "x64" / "Rscript.exe";
    auto app_r   = base / "app" / "app.R";
    auto lib_dir = base / "packages" / "library";

    if (!std::filesystem::exists(rscript)) {
        MessageBoxW(nullptr,
            L"R runtime not found.\nExpected: runtime\\R\\bin\\x64\\Rscript.exe",
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

    STARTUPINFOW        si = {};
    PROCESS_INFORMATION pi = {};
    si.cb = sizeof(si);

    if (!CreateProcessW(nullptr,
            const_cast<wchar_t*>(cmd.c_str()),
            nullptr, nullptr, FALSE,
            CREATE_NO_WINDOW,   // silent — no black console flicker
            nullptr,
            base.wstring().c_str(),  // working dir = app root
            &si, &pi)) {
        MessageBoxW(nullptr, L"Failed to start Rscript.exe",
                    L"RDesk — Launch Error", MB_ICONERROR);
        return 1;
    }

    // Wait for R to finish (app$run() blocks until window closes)
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return 0;
}
