/* Riflay: dlopen / dlsym / dlclose on top of LoadLibrary, so FFmpeg's `ladspa`
 * filter builds with mingw (which has no libdl). Only what af_ladspa.c uses.
 * LOAD_WITH_ALTERED_SEARCH_PATH lets a plugin's own DLLs resolve from its folder. */
#ifndef RIFLAY_DLFCN_H
#define RIFLAY_DLFCN_H
#include <windows.h>

#define RTLD_LAZY   1
#define RTLD_NOW    2
#define RTLD_LOCAL  0
#define RTLD_GLOBAL 0

static inline void* dlopen(const char* path, int flags) {
  (void)flags;
  return (void*)LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
}
static inline void* dlsym(void* handle, const char* name) { return (void*)GetProcAddress((HMODULE)handle, name); }
static inline int dlclose(void* handle) { return FreeLibrary((HMODULE)handle) ? 0 : -1; }
static inline const char* dlerror(void) { return "the library could not be loaded"; }

#endif
