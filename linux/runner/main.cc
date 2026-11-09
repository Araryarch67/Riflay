#include <dirent.h>
#include <unistd.h>

#include <cstdlib>
#include <fstream>
#include <string>

#include "my_application.h"

namespace {

// The kernel driver behind /sys/class/drm/<card> ("i915", "amdgpu", "nvidia"...), or "" when unknown.
std::string card_driver(const std::string& card) {
  char target[256];
  const std::string link = "/sys/class/drm/" + card + "/device/driver";
  const ssize_t n = readlink(link.c_str(), target, sizeof(target) - 1);
  if (n <= 0) return "";
  target[n] = '\0';
  const std::string path(target);
  return path.substr(path.rfind('/') + 1);
}

// On a laptop whose screens all hang off a non-NVIDIA GPU, only Mesa's EGL is loaded. glvnd otherwise loads every
// vendor to probe them, and NVIDIA's libraries stayed in the process unused (~38 MB of RSS in btop) while the
// window drew on the integrated GPU. Not when anything sets the vendor itself, when an NVIDIA card drives a screen,
// or with RIFLAY_ALL_EGL_VENDORS set.
void prefer_mesa_egl() {
  static const char* mesa = "/usr/share/glvnd/egl_vendor.d/50_mesa.json";
  if (getenv("RIFLAY_ALL_EGL_VENDORS") != nullptr || getenv("__EGL_VENDOR_LIBRARY_FILENAMES") != nullptr ||
      getenv("__EGL_VENDOR_LIBRARY_DIRS") != nullptr || access(mesa, R_OK) != 0) {
    return;
  }
  DIR* drm = opendir("/sys/class/drm");
  if (drm == nullptr) return;
  bool other_screen = false, nvidia_screen = false;
  while (dirent* entry = readdir(drm)) {
    const std::string name(entry->d_name);
    // Connectors: "card1-eDP-1", "card0-HDMI-A-1".
    const size_t dash = name.find('-');
    if (name.rfind("card", 0) != 0 || dash == std::string::npos) continue;
    std::ifstream status("/sys/class/drm/" + name + "/status");
    std::string state;
    if (!(status >> state) || state != "connected") continue;
    (card_driver(name.substr(0, dash)) == "nvidia" ? nvidia_screen : other_screen) = true;
  }
  closedir(drm);
  if (other_screen && !nvidia_screen) setenv("__EGL_VENDOR_LIBRARY_FILENAMES", mesa, 0);
}

}  // namespace

int main(int argc, char** argv) {
  prefer_mesa_egl();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
