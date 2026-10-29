# Sign-in window for Spotify (see riflay_spotify.cc). Optional: without
# webkit2gtk-4.1 the app still builds, it just can't offer the Spotify import.
pkg_check_modules(WEBKIT IMPORTED_TARGET webkit2gtk-4.1)
if(NOT WEBKIT_FOUND)
  message(STATUS "webkit2gtk-4.1 not found; building without the Spotify sign-in")
  return()
endif()

add_executable(riflay_spotify "riflay_spotify.cc")
apply_standard_settings(riflay_spotify)
target_link_libraries(riflay_spotify PRIVATE PkgConfig::GTK PkgConfig::WEBKIT)
set_target_properties(riflay_spotify PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run")
add_dependencies(${BINARY_NAME} riflay_spotify)
