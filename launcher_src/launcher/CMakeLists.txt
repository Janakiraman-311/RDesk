cmake_minimum_required(VERSION 3.16)
project(rdesk_launcher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Use vendored local webview header (no network access required at build time)
# The header lives at launcher_src/launcher/webview/webview.h
# This avoids FetchContent git-cloning at build time, which fails in CI
# environments with restricted outbound access.
set(WEBVIEW_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/webview")

# Validate it exists so the error is clear rather than a compile failure
if(NOT EXISTS "${WEBVIEW_INCLUDE_DIR}/webview.h")
  message(FATAL_ERROR
    "webview.h not found at ${WEBVIEW_INCLUDE_DIR}/webview.h\n"
    "Expected vendored header at launcher_src/launcher/webview/webview.h")
endif()

add_executable(rdesk-launcher WIN32 main.cpp)

target_include_directories(rdesk-launcher PRIVATE
    "${WEBVIEW_INCLUDE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../inst/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/webview2_sdk/build/native/include"
)

# Windows system libraries required by WebView2 and Win32 APIs
if(WIN32)
  target_link_libraries(rdesk-launcher PRIVATE
    ole32 shell32 shlwapi user32 version comdlg32 oleaut32 uuid)
endif()

# Copy binary to inst/bin/ so R can find it after package install
add_custom_command(TARGET rdesk-launcher POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory
    "${CMAKE_SOURCE_DIR}/../../inst/bin"
  COMMAND ${CMAKE_COMMAND} -E copy
    $<TARGET_FILE:rdesk-launcher>
    "${CMAKE_SOURCE_DIR}/../../inst/bin/"
  COMMENT "Copying rdesk-launcher.exe to inst/bin/"
)
