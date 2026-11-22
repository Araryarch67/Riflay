#include "media_controls.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shcore.h>
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {

namespace wf = winrt::Windows::Foundation;
namespace wm = winrt::Windows::Media;
namespace ws = winrt::Windows::Storage::Streams;

using flutter::EncodableMap;
using flutter::EncodableValue;

enum Command : WPARAM { kPlay = 1, kPause, kStop, kNext, kPrevious, kSeek };

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string GetString(const EncodableMap& map, const char* key) {
  const auto* v = Find(map, key);
  return v && std::holds_alternative<std::string>(*v) ? std::get<std::string>(*v) : std::string();
}

int64_t GetInt(const EncodableMap& map, const char* key) {
  const auto* v = Find(map, key);
  if (!v) return 0;
  if (std::holds_alternative<int32_t>(*v)) return std::get<int32_t>(*v);
  if (std::holds_alternative<int64_t>(*v)) return std::get<int64_t>(*v);
  return 0;
}

double GetDouble(const EncodableMap& map, const char* key, double fallback) {
  const auto* v = Find(map, key);
  return v && std::holds_alternative<double>(*v) ? std::get<double>(*v) : fallback;
}

bool GetBool(const EncodableMap& map, const char* key) {
  const auto* v = Find(map, key);
  return v && std::holds_alternative<bool>(*v) && std::get<bool>(*v);
}

// A cover file as a stream the shell can read. Read here, synchronously: covers are cached JPEG / PNG files of a
// few hundred kilobytes, and the stream needs no file access from the shell.
ws::RandomAccessStreamReference CoverFromFile(const std::string& utf8_path) {
  const std::wstring path(winrt::to_hstring(utf8_path).c_str());
  std::ifstream in(path, std::ios::binary);
  if (!in) return nullptr;
  std::vector<char> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  if (bytes.empty() || bytes.size() > 32 * 1024 * 1024) return nullptr;
  ws::InMemoryRandomAccessStream stream;
  winrt::com_ptr<IStream> writer;
  winrt::check_hresult(CreateStreamOverRandomAccessStream(winrt::get_unknown(stream), IID_PPV_ARGS(writer.put())));
  ULONG written = 0;
  winrt::check_hresult(writer->Write(bytes.data(), static_cast<ULONG>(bytes.size()), &written));
  stream.Seek(0);
  return ws::RandomAccessStreamReference::CreateFromStream(stream);
}

}  // namespace

struct MediaControls::Impl {
  HWND window = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  wm::SystemMediaTransportControls smtc{nullptr};
  winrt::event_token buttons{};
  winrt::event_token seeks{};
  std::string art;

  bool Enable() {
    // Once per window: a second enable (a Dart hot restart) keeps the one session and its handlers.
    if (smtc) return true;
    try {
      auto interop = winrt::get_activation_factory<wm::SystemMediaTransportControls,
                                                   ISystemMediaTransportControlsInterop>();
      wm::SystemMediaTransportControls controls{nullptr};
      winrt::check_hresult(interop->GetForWindow(window, winrt::guid_of<wm::SystemMediaTransportControls>(),
                                                 winrt::put_abi(controls)));
      controls.IsPlayEnabled(true);
      controls.IsPauseEnabled(true);
      controls.IsStopEnabled(true);
      controls.IsNextEnabled(false);
      controls.IsPreviousEnabled(false);
      // Shown once something plays (see SetState).
      controls.IsEnabled(false);
      const HWND target = window;
      buttons = controls.ButtonPressed(
          [target](const wm::SystemMediaTransportControls&,
                   const wm::SystemMediaTransportControlsButtonPressedEventArgs& args) {
            WPARAM command = 0;
            switch (args.Button()) {
              case wm::SystemMediaTransportControlsButton::Play:
                command = kPlay;
                break;
              case wm::SystemMediaTransportControlsButton::Pause:
                command = kPause;
                break;
              case wm::SystemMediaTransportControlsButton::Stop:
                command = kStop;
                break;
              case wm::SystemMediaTransportControlsButton::Next:
                command = kNext;
                break;
              case wm::SystemMediaTransportControlsButton::Previous:
                command = kPrevious;
                break;
              default:
                break;
            }
            if (command) PostMessage(target, kCommandMessage, command, 0);
          });
      seeks = controls.PlaybackPositionChangeRequested(
          [target](const wm::SystemMediaTransportControls&,
                   const wm::PlaybackPositionChangeRequestedEventArgs& args) {
            const auto ms =
                std::chrono::duration_cast<std::chrono::milliseconds>(args.RequestedPlaybackPosition()).count();
            PostMessage(target, kCommandMessage, kSeek, static_cast<LPARAM>(ms < 0 ? 0 : ms));
          });
      smtc = controls;
      return true;
    } catch (const winrt::hresult_error&) {
      return false;
    }
  }

  void Disable() {
    if (!smtc) return;
    try {
      smtc.ButtonPressed(buttons);
      smtc.PlaybackPositionChangeRequested(seeks);
      smtc.DisplayUpdater().ClearAll();
      smtc.DisplayUpdater().Update();
      smtc.PlaybackStatus(wm::MediaPlaybackStatus::Closed);
      smtc.IsEnabled(false);
    } catch (const winrt::hresult_error&) {
    }
    smtc = nullptr;
    art.clear();
  }

  void SetMetadata(const EncodableMap& map) {
    if (!smtc) return;
    auto updater = smtc.DisplayUpdater();
    if (!Find(map, "id") || std::holds_alternative<std::monostate>(*Find(map, "id"))) {
      updater.ClearAll();
      updater.Update();
      art.clear();
      return;
    }
    updater.Type(wm::MediaPlaybackType::Music);
    auto music = updater.MusicProperties();
    const auto artist = GetString(map, "artist");
    music.Title(winrt::to_hstring(GetString(map, "title")));
    music.Artist(winrt::to_hstring(artist));
    music.AlbumArtist(winrt::to_hstring(artist));
    music.AlbumTitle(winrt::to_hstring(GetString(map, "album")));
    const auto cover = GetString(map, "art");
    if (cover != art) {
      art = cover;
      ws::RandomAccessStreamReference thumbnail{nullptr};
      try {
        if (cover.rfind("http://", 0) == 0 || cover.rfind("https://", 0) == 0) {
          thumbnail = ws::RandomAccessStreamReference::CreateFromUri(wf::Uri(winrt::to_hstring(cover)));
        } else if (!cover.empty()) {
          thumbnail = CoverFromFile(cover);
        }
      } catch (const winrt::hresult_error&) {
        thumbnail = nullptr;
      }
      updater.Thumbnail(thumbnail);
    }
    updater.Update();
  }

  void SetState(const EncodableMap& map) {
    if (!smtc) return;
    const auto status = GetString(map, "status");
    if (status == "closed") {
      smtc.PlaybackStatus(wm::MediaPlaybackStatus::Closed);
      smtc.IsEnabled(false);
      return;
    }
    smtc.IsEnabled(true);
    smtc.PlaybackStatus(status == "playing"   ? wm::MediaPlaybackStatus::Playing
                        : status == "stopped" ? wm::MediaPlaybackStatus::Stopped
                        : status == "changing" ? wm::MediaPlaybackStatus::Changing
                                               : wm::MediaPlaybackStatus::Paused);
    smtc.IsNextEnabled(GetBool(map, "canNext"));
    smtc.IsPreviousEnabled(GetBool(map, "canPrevious"));
    smtc.PlaybackRate(GetDouble(map, "rate", 1.0));
    // The flyout moves the position on from here at the rate; it is sent again on a seek, a pause or a new song.
    const auto duration = std::chrono::milliseconds(GetInt(map, "durationMs"));
    auto position = std::chrono::milliseconds(GetInt(map, "positionMs"));
    if (position.count() < 0) position = std::chrono::milliseconds(0);
    if (duration.count() > 0 && position > duration) position = duration;
    wm::SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(wf::TimeSpan(0));
    timeline.MinSeekTime(wf::TimeSpan(0));
    timeline.EndTime(duration);
    timeline.MaxSeekTime(duration);
    timeline.Position(position);
    smtc.UpdateTimelineProperties(timeline);
  }

  void HandleCall(const flutter::MethodCall<EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto& method = call.method_name();
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    try {
      if (method == "enable") return result->Success(EncodableValue(Enable()));
      if (method == "disable") {
        Disable();
        return result->Success();
      }
      if (method == "metadata" && args) {
        SetMetadata(*args);
        return result->Success();
      }
      if (method == "state" && args) {
        SetState(*args);
        return result->Success();
      }
    } catch (const winrt::hresult_error& e) {
      return result->Error("smtc", winrt::to_string(e.message()));
    }
    result->NotImplemented();
  }
};

MediaControls::MediaControls(flutter::BinaryMessenger* messenger, HWND window) : impl_(std::make_unique<Impl>()) {
  impl_->window = window;
  impl_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "riflay/media_session", &flutter::StandardMethodCodec::GetInstance());
  impl_->channel->SetMethodCallHandler(
      [impl = impl_.get()](const auto& call, auto result) { impl->HandleCall(call, std::move(result)); });
}

MediaControls::~MediaControls() {
  impl_->channel->SetMethodCallHandler(nullptr);
  impl_->Disable();
}

bool MediaControls::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message != kCommandMessage) return false;
  // Disabled since it was posted: nothing to tell.
  if (!impl_->smtc) return true;
  const char* name = nullptr;
  switch (wparam) {
    case kPlay:
      name = "play";
      break;
    case kPause:
      name = "pause";
      break;
    case kStop:
      name = "stop";
      break;
    case kNext:
      name = "next";
      break;
    case kPrevious:
      name = "previous";
      break;
    case kSeek:
      name = "seek";
      break;
    default:
      return true;
  }
  EncodableMap args{{EncodableValue("command"), EncodableValue(name)}};
  if (wparam == kSeek) args[EncodableValue("positionMs")] = EncodableValue(static_cast<int64_t>(lparam));
  impl_->channel->InvokeMethod("command", std::make_unique<EncodableValue>(std::move(args)));
  return true;
}
