cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "egl_lifetime.cc"
  "task_runner_lifetime.cc"
  "my_application.cc"
  "frameless_window.cc"
  "monaco_host.cc"
  "window_configuration.cc"
  "desktop_glass.cc"
  "window_shape.cc"
  "bridge_notification_native.cc"
  "rain_effect.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::EPOXY)
target_link_libraries(${BINARY_NAME} PRIVATE ${CMAKE_DL_LIBS})
# Export only the guarded timeout adapter used by the pinned Flutter embedder.
# Its source owns callback data until dispatch/cancellation completes.
target_link_options(${BINARY_NAME} PRIVATE
  "-Wl,--export-dynamic-symbol=g_timeout_add")
pkg_check_modules(WEBKIT REQUIRED IMPORTED_TARGET webkit2gtk-4.1>=2.40)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WEBKIT)
find_package(PNG REQUIRED)
target_link_libraries(${BINARY_NAME} PRIVATE PNG::PNG)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Monaco is served from the application bundle over a loopback HTTP endpoint.
install(DIRECTORY "${CMAKE_SOURCE_DIR}/../assets/editor/"
  DESTINATION "data/monaco" COMPONENT Runtime)

# Optional GNOME compositor companion for real behind-window refraction.
install(DIRECTORY "${CMAKE_SOURCE_DIR}/gnome/"
  DESTINATION "data/gnome" COMPONENT Runtime
  PATTERN "__pycache__" EXCLUDE
  PATTERN "*.pyc" EXCLUDE)
install(PROGRAMS "${CMAKE_SOURCE_DIR}/../scripts/install-gnome-glass.sh"
  DESTINATION "." COMPONENT Runtime)
