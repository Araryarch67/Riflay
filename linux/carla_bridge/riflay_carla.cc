// A LADSPA plugin that runs the user's audio plugins (VST2, VST3, LV2, CLAP,
// ...) through Carla, so they can sit in mpv's filter chain like the equalizer:
//
//   af=lavfi=[ladspa=file=<bundle>/lib/libriflay_carla.so:plugin=riflay_carla]
//
// Each instance starts Carla's "rack" (a native plugin that hosts plugins in
// series) and loads the project the user made in Carla's own window:
// $RIFLAY_PLUGINS, or the app's folder (Linux $XDG_CONFIG_HOME/riflay,
// macOS ~/Library/Application Support/dev.riflay.riflay, Windows
// %APPDATA%\dev.riflay\riflay) + plugins.carxp.
//
// One source for Linux (.so), macOS (.dylib) and Windows (.dll, mingw). Carla
// is loaded when an instance starts (dlopen / LoadLibrary), so neither building
// nor running the app needs it; without it (or without a project) the audio
// passes through untouched. Where Carla lives: $RIFLAY_CARLA_LIBS, the folder
// named in carla_dir.txt next to the project (the app writes it where Carla
// has no fixed place, Windows), then the usual install places. Only the few Carla declarations used are
// repeated below (their layout is fixed by Carla's ABI, CarlaNative.h).

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif
#include <sys/stat.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#ifdef _WIN32
#define RIFLAY_EXPORT __declspec(dllexport)
#else
#define RIFLAY_EXPORT __attribute__((visibility("default")))
#endif

// ── LADSPA (ladspa.h, version 1.1) ─────────────────────────────────────────

typedef float LADSPA_Data;
typedef void* LADSPA_Handle;
typedef int LADSPA_PortDescriptor;
typedef int LADSPA_PortRangeHintDescriptor;
typedef int LADSPA_Properties;

struct LADSPA_PortRangeHint {
  LADSPA_PortRangeHintDescriptor HintDescriptor;
  LADSPA_Data LowerBound;
  LADSPA_Data UpperBound;
};

struct LADSPA_Descriptor {
  unsigned long UniqueID;
  const char* Label;
  LADSPA_Properties Properties;
  const char* Name;
  const char* Maker;
  const char* Copyright;
  unsigned long PortCount;
  const LADSPA_PortDescriptor* PortDescriptors;
  const char* const* PortNames;
  const LADSPA_PortRangeHint* PortRangeHints;
  void* ImplementationData;
  LADSPA_Handle (*instantiate)(const LADSPA_Descriptor*, unsigned long sampleRate);
  void (*connect_port)(LADSPA_Handle, unsigned long port, LADSPA_Data* location);
  void (*activate)(LADSPA_Handle);
  void (*run)(LADSPA_Handle, unsigned long sampleCount);
  void (*run_adding)(LADSPA_Handle, unsigned long sampleCount);
  void (*set_run_adding_gain)(LADSPA_Handle, LADSPA_Data gain);
  void (*deactivate)(LADSPA_Handle);
  void (*cleanup)(LADSPA_Handle);
};

static const int kPortInput = 0x1, kPortOutput = 0x2, kPortAudio = 0x8;

// ── Carla native plugin API (CarlaNative.h / CarlaNativePlugin.h / CarlaHost.h) ─

typedef void* NativeHostHandle;
typedef void* NativePluginHandle;
typedef void* CarlaHostHandle;
struct NativeMidiEvent;
struct NativeParameter;
struct NativeMidiProgram;

struct NativeTimeInfoBBT {
  bool valid;
  int32_t bar, beat;
  double tick, barStartTick;
  float beatsPerBar, beatType;
  double ticksPerBeat, beatsPerMinute;
};

struct NativeTimeInfo {
  bool playing;
  uint64_t frame;
  uint64_t usecs;
  NativeTimeInfoBBT bbt;
};

struct NativeHostDescriptor {
  NativeHostHandle handle;
  const char* resourceDir;
  const char* uiName;
  uintptr_t uiParentId;
  uint32_t (*get_buffer_size)(NativeHostHandle);
  double (*get_sample_rate)(NativeHostHandle);
  bool (*is_offline)(NativeHostHandle);
  const NativeTimeInfo* (*get_time_info)(NativeHostHandle);
  bool (*write_midi_event)(NativeHostHandle, const NativeMidiEvent*);
  void (*ui_parameter_changed)(NativeHostHandle, uint32_t, float);
  void (*ui_midi_program_changed)(NativeHostHandle, uint8_t, uint32_t, uint32_t);
  void (*ui_custom_data_changed)(NativeHostHandle, const char*, const char*);
  void (*ui_closed)(NativeHostHandle);
  const char* (*ui_open_file)(NativeHostHandle, bool, const char*, const char*);
  const char* (*ui_save_file)(NativeHostHandle, bool, const char*, const char*);
  intptr_t (*dispatcher)(NativeHostHandle, int opcode, int32_t, intptr_t, void*, float);
};

struct NativePluginDescriptor {
  int category, hints, supports;
  uint32_t audioIns, audioOuts, midiIns, midiOuts, paramIns, paramOuts;
  const char *name, *label, *maker, *copyright;
  NativePluginHandle (*instantiate)(const NativeHostDescriptor*);
  void (*cleanup)(NativePluginHandle);
  uint32_t (*get_parameter_count)(NativePluginHandle);
  const NativeParameter* (*get_parameter_info)(NativePluginHandle, uint32_t);
  float (*get_parameter_value)(NativePluginHandle, uint32_t);
  uint32_t (*get_midi_program_count)(NativePluginHandle);
  const NativeMidiProgram* (*get_midi_program_info)(NativePluginHandle, uint32_t);
  void (*set_parameter_value)(NativePluginHandle, uint32_t, float);
  void (*set_midi_program)(NativePluginHandle, uint8_t, uint32_t, uint32_t);
  void (*set_custom_data)(NativePluginHandle, const char*, const char*);
  void (*ui_show)(NativePluginHandle, bool);
  void (*ui_idle)(NativePluginHandle);
  void (*ui_set_parameter_value)(NativePluginHandle, uint32_t, float);
  void (*ui_set_midi_program)(NativePluginHandle, uint8_t, uint32_t, uint32_t);
  void (*ui_set_custom_data)(NativePluginHandle, const char*, const char*);
  void (*activate)(NativePluginHandle);
  void (*deactivate)(NativePluginHandle);
  void (*process)(NativePluginHandle, float** in, float** out, uint32_t frames, const NativeMidiEvent*, uint32_t);
  // (more fields follow; not used)
};

namespace {

constexpr uint32_t kBlock = 4096;

#ifdef _WIN32
constexpr char kSep = '\\';
constexpr const char* kLibExt = ".dll";
void* openLib(const std::string& path) {
  std::string p = path;
  for (char& c : p) {
    if (c == '/') c = '\\';
  }
  // The altered search path lets Carla's own DLLs resolve from its folder.
  return reinterpret_cast<void*>(LoadLibraryExA(p.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH));
}
void* symbol(void* lib, const char* name) {
  return reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(lib), name));
}
bool fileExists(const std::string& path) {
  // UTF-8 in, since the user's name may not be ASCII.
  const int n = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
  if (n <= 0) return false;
  std::wstring w(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, &w[0], n);
  return GetFileAttributesW(w.c_str()) != INVALID_FILE_ATTRIBUTES;
}
#else
constexpr char kSep = '/';
#ifdef __APPLE__
constexpr const char* kLibExt = ".dylib";
#else
constexpr const char* kLibExt = ".so";
#endif
void* openLib(const std::string& path) { return dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL); }
void* symbol(void* lib, const char* name) { return dlsym(lib, name); }
bool fileExists(const std::string& path) {
  struct stat st;
  return stat(path.c_str(), &st) == 0;
}
#endif

std::string env(const char* name) {
  const char* v = getenv(name);
  return v ? v : "";
}

// The folder the project, and carla_dir.txt, live in.
std::string appFolder() {
#if defined(_WIN32)
  return env("APPDATA") + "\\dev.riflay\\riflay";
#elif defined(__APPLE__)
  return env("HOME") + "/Library/Application Support/dev.riflay.riflay";
#else
  const std::string x = env("XDG_CONFIG_HOME");
  return (!x.empty() ? x : env("HOME") + "/.config") + "/riflay";
#endif
}

struct CarlaLib {
  const NativePluginDescriptor* (*rack)() = nullptr;
  CarlaHostHandle (*hostHandle)(const NativePluginDescriptor*, NativePluginHandle) = nullptr;
  void (*freeHostHandle)(CarlaHostHandle) = nullptr;
  bool (*loadProject)(CarlaHostHandle, const char*) = nullptr;
  const char* (*lastError)(CarlaHostHandle) = nullptr;
  uint32_t (*pluginCount)(CarlaHostHandle) = nullptr;
  std::string resources;
  bool ok = false;
};

const CarlaLib& carla() {
  static CarlaLib lib = [] {
    CarlaLib l;
    std::vector<std::string> dirs;
    if (const std::string d = env("RIFLAY_CARLA_LIBS"); !d.empty()) dirs.push_back(d);
    {
      std::ifstream f(appFolder() + kSep + "carla_dir.txt");
      std::string d;
      if (f && std::getline(f, d)) {
        while (!d.empty() && (d.back() == '\r' || d.back() == '\n' || d.back() == ' ')) d.pop_back();
        if (!d.empty()) dirs.push_back(d);
      }
    }
#if defined(_WIN32)
    for (const char* v : {"ProgramFiles", "LOCALAPPDATA"}) {
      if (const std::string base = env(v); !base.empty()) dirs.push_back(base + "\\Carla");
    }
#elif defined(__APPLE__)
    dirs.emplace_back("/Applications/Carla.app/Contents/MacOS");
    dirs.push_back(env("HOME") + "/Applications/Carla.app/Contents/MacOS");
#else
    for (const char* d : {"/usr/lib/carla", "/usr/lib64/carla", "/usr/local/lib/carla", "/usr/lib/x86_64-linux-gnu/carla"})
      dirs.emplace_back(d);
#endif
    for (const auto& dir : dirs) {
      void* native = openLib(dir + kSep + "libcarla_native-plugin" + kLibExt);
      if (!native) continue;
      void* host = openLib(dir + kSep + "libcarla_host-plugin" + kLibExt);
      if (!host) continue;
      l.rack = reinterpret_cast<decltype(l.rack)>(symbol(native, "carla_get_native_rack_plugin"));
      l.hostHandle = reinterpret_cast<decltype(l.hostHandle)>(symbol(native, "carla_create_native_plugin_host_handle"));
      l.freeHostHandle = reinterpret_cast<decltype(l.freeHostHandle)>(symbol(native, "carla_host_handle_free"));
      l.loadProject = reinterpret_cast<decltype(l.loadProject)>(symbol(host, "carla_load_project"));
      l.lastError = reinterpret_cast<decltype(l.lastError)>(symbol(host, "carla_get_last_error"));
      l.pluginCount = reinterpret_cast<decltype(l.pluginCount)>(symbol(host, "carla_get_current_plugin_count"));
      // Carla's resources: in its own folder (macOS app, Windows zip), or the distro's share folder (Linux).
      l.resources = dir + kSep + "resources";
#if !defined(_WIN32) && !defined(__APPLE__)
      for (const char* r : {"/usr/share/carla/resources", "/usr/local/share/carla/resources"}) {
        if (fileExists(r)) {
          l.resources = r;
          break;
        }
      }
#endif
      l.ok = l.rack && l.hostHandle && l.loadProject;
      if (l.ok) break;
    }
    if (!l.ok) fprintf(stderr, "riflay_carla: Carla not found; passing audio through\n");
    return l;
  }();
  return lib;
}

std::string projectPath() {
  if (const std::string p = env("RIFLAY_PLUGINS"); !p.empty()) return p;
  return appFolder() + kSep + "plugins.carxp";
}

struct Instance {
  double rate = 44100;
  LADSPA_Data* ports[4] = {};
  const NativePluginDescriptor* desc = nullptr;
  NativePluginHandle plugin = nullptr;
  CarlaHostHandle host = nullptr;
  NativeHostDescriptor hostDesc{};
  NativeTimeInfo time{};
  bool active = false;
};

uint32_t bufferSize(NativeHostHandle) { return kBlock; }
double sampleRate(NativeHostHandle h) { return static_cast<Instance*>(h)->rate; }
bool isOffline(NativeHostHandle) { return false; }
const NativeTimeInfo* timeInfo(NativeHostHandle h) { return &static_cast<Instance*>(h)->time; }
bool writeMidi(NativeHostHandle, const NativeMidiEvent*) { return false; }
void uiParameter(NativeHostHandle, uint32_t, float) {}
void uiProgram(NativeHostHandle, uint8_t, uint32_t, uint32_t) {}
void uiCustom(NativeHostHandle, const char*, const char*) {}
void uiClosed(NativeHostHandle) {}
const char* uiFile(NativeHostHandle, bool, const char*, const char*) { return nullptr; }
intptr_t dispatch(NativeHostHandle, int, int32_t, intptr_t, void*, float) { return 0; }

LADSPA_Handle instantiate(const LADSPA_Descriptor*, unsigned long rate) {
  auto* in = new Instance;
  in->rate = static_cast<double>(rate);
  in->time.playing = true;
  const std::string project = projectPath();
  if (!fileExists(project)) return in;  // nothing set up yet: pass through
  const CarlaLib& lib = carla();
  if (!lib.ok) return in;

  in->hostDesc = NativeHostDescriptor{in,        lib.resources.c_str(), "Riflay", 0,          bufferSize, sampleRate,
                                      isOffline, timeInfo,              writeMidi,   uiParameter, uiProgram,  uiCustom,
                                      uiClosed,  uiFile,                uiFile,      dispatch};
  in->desc = lib.rack();
  in->plugin = in->desc ? in->desc->instantiate(&in->hostDesc) : nullptr;
  if (!in->plugin) {
    fprintf(stderr, "riflay_carla: Carla's rack didn't start\n");
    in->desc = nullptr;
    return in;
  }
  in->host = lib.hostHandle(in->desc, in->plugin);
  if (!in->host || !lib.loadProject(in->host, project.c_str())) {
    fprintf(stderr, "riflay_carla: can't load %s: %s\n", project.c_str(),
            in->host && lib.lastError ? lib.lastError(in->host) : "?");
  }
  return in;
}

void connectPort(LADSPA_Handle h, unsigned long port, LADSPA_Data* data) {
  if (port < 4) static_cast<Instance*>(h)->ports[port] = data;
}

void activate(LADSPA_Handle h) {
  auto* in = static_cast<Instance*>(h);
  if (in->plugin && !in->active) {
    in->desc->activate(in->plugin);
    in->active = true;
  }
}

void deactivate(LADSPA_Handle h) {
  auto* in = static_cast<Instance*>(h);
  if (in->plugin && in->active) {
    in->desc->deactivate(in->plugin);
    in->active = false;
  }
}

void run(LADSPA_Handle h, unsigned long frames) {
  auto* in = static_cast<Instance*>(h);
  if (!in->plugin || !in->active) {
    for (int c = 0; c < 2; c++) {
      if (in->ports[2 + c] != in->ports[c]) memmove(in->ports[2 + c], in->ports[c], frames * sizeof(LADSPA_Data));
    }
    return;
  }
  for (unsigned long done = 0; done < frames;) {
    const uint32_t n = static_cast<uint32_t>(frames - done < kBlock ? frames - done : kBlock);
    float* inputs[2] = {in->ports[0] + done, in->ports[1] + done};
    float* outputs[2] = {in->ports[2] + done, in->ports[3] + done};
    in->desc->process(in->plugin, inputs, outputs, n, nullptr, 0);
    in->time.frame += n;
    done += n;
  }
}

void cleanup(LADSPA_Handle h) {
  auto* in = static_cast<Instance*>(h);
  deactivate(h);
  if (in->host && carla().freeHostHandle) carla().freeHostHandle(in->host);
  if (in->plugin) in->desc->cleanup(in->plugin);
  delete in;
}

const LADSPA_PortDescriptor kPorts[4] = {kPortInput | kPortAudio, kPortInput | kPortAudio, kPortOutput | kPortAudio,
                                         kPortOutput | kPortAudio};
const char* const kPortNames[4] = {"In L", "In R", "Out L", "Out R"};
const LADSPA_PortRangeHint kHints[4] = {};

const LADSPA_Descriptor kDescriptor = {
    0x4F4D4331,  // "OMC1"
    "riflay_carla",
    0,
    "Riflay audio plugins (Carla)",
    "Riflay",
    "GPL-3.0-or-later",
    4,
    kPorts,
    kPortNames,
    kHints,
    nullptr,
    instantiate,
    connectPort,
    activate,
    run,
    nullptr,
    nullptr,
    deactivate,
    cleanup,
};

}  // namespace

extern "C" RIFLAY_EXPORT const LADSPA_Descriptor* ladspa_descriptor(unsigned long index) {
  return index == 0 ? &kDescriptor : nullptr;
}
