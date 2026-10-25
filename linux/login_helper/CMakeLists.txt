# Sign-in window for YouTube Music (see riflay_login.cc). Optional: without
# webkit2gtk-4.1 the app still builds and offers the browser / OAuth sign-ins.
pkg_check_modules(WEBKIT IMPORTED_TARGET webkit2gtk-4.1)
if(NOT WEBKIT_FOUND)
  message(STATUS "webkit2gtk-4.1 not found; building without the in-app Google sign-in")
  return()
endif()

add_executable(riflay_login "riflay_login.cc")
apply_standard_settings(riflay_login)
target_link_libraries(riflay_login PRIVATE PkgConfig::GTK PkgConfig::WEBKIT)
set_target_properties(riflay_login PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run")
add_dependencies(${BINARY_NAME} riflay_login)
