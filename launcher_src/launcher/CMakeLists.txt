cmake_minimum_required(VERSION 3.16)
project(rdesk_launcher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
FetchContent_Declare(
  webview
  GIT_REPOSITORY https://github.com/webview/webview
  GIT_TAG        0.12.0
)
FetchContent_MakeAvailable(webview)

add_executable(rdesk-launcher WIN32 main.cpp)
target_include_directories(rdesk-launcher PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/webview2_sdk/build/native/include")
target_link_libraries(rdesk-launcher PRIVATE webview::core)

# On Windows, also need these
if(WIN32)
  target_link_libraries(rdesk-launcher PRIVATE ole32 shell32 shlwapi user32 version)
endif()

# Copy binary to inst/bin/ so R can find it after package install
add_custom_command(TARGET rdesk-launcher POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory
    "${CMAKE_SOURCE_DIR}/../../inst/bin"
  COMMAND ${CMAKE_COMMAND} -E copy
    $<TARGET_FILE:rdesk-launcher>
    "${CMAKE_SOURCE_DIR}/../../inst/bin/"
)
