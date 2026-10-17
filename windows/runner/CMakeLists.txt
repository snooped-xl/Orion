cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "orion_native.cpp"
  "windows_rain.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX" "_WIN32_WINNT=0x0A00" "WINVER=0x0A00")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# The SDK is pinned and verified; no machine-wide NuGet installation is required.
include(FetchContent)
FetchContent_Declare(orion_webview2
  URL "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.3537.50/microsoft.web.webview2.1.0.3537.50.nupkg"
  URL_HASH SHA256=5ea526bbd728adda0da4d31219267e96460494a427e4894c4e09d9f320f4b9aa
)
FetchContent_GetProperties(orion_webview2)
if(NOT orion_webview2_POPULATED)
  FetchContent_Populate(orion_webview2)
endif()
target_include_directories(${BINARY_NAME} PRIVATE "${orion_webview2_SOURCE_DIR}/build/native/include")
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
  set(ORION_WEBVIEW_ARCH arm64)
else()
  set(ORION_WEBVIEW_ARCH x64)
endif()
target_link_libraries(${BINARY_NAME} PRIVATE
  "${orion_webview2_SOURCE_DIR}/build/native/${ORION_WEBVIEW_ARCH}/WebView2Loader.dll.lib"
  d3d11.lib dxgi.lib dcomp.lib d3dcompiler.lib windowscodecs.lib shlwapi.lib shell32.lib ole32.lib
  desktop_multi_window_plugin)
install(FILES "${orion_webview2_SOURCE_DIR}/build/native/${ORION_WEBVIEW_ARCH}/WebView2Loader.dll"
  DESTINATION "." COMPONENT Runtime)
install(DIRECTORY "${CMAKE_SOURCE_DIR}/../assets/editor/"
  DESTINATION "data/monaco" COMPONENT Runtime)
install(FILES "${orion_webview2_SOURCE_DIR}/LICENSE.txt" "${orion_webview2_SOURCE_DIR}/NOTICE.txt"
  DESTINATION "data/licenses/WebView2-SDK" COMPONENT Runtime)
