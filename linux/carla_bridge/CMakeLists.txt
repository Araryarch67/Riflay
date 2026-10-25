# LADSPA bridge to Carla, for audio plugins in the filter chain (see
# riflay_carla.cc). Needs no Carla headers or libraries to build.
add_library(riflay_carla MODULE "riflay_carla.cc")
target_compile_features(riflay_carla PRIVATE cxx_std_17)
target_compile_options(riflay_carla PRIVATE -Wall -Werror -O2 -fvisibility=hidden)
target_link_libraries(riflay_carla PRIVATE ${CMAKE_DL_LIBS})
set_target_properties(riflay_carla PROPERTIES PREFIX "lib" LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run")
add_dependencies(${BINARY_NAME} riflay_carla)
