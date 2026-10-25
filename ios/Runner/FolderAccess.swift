import Flutter
import UIKit
import UniformTypeIdentifiers

/// Lets the user pick a music folder outside the app and keeps reading it after a restart.
///
/// iOS only allows that through a security-scoped URL, and the access ends when the app quits
/// unless a bookmark is stored. Access is left open for the app's lifetime because mpv opens
/// the songs by path whenever they are played.
final class FolderAccess: NSObject, UIDocumentPickerDelegate {
  private static let defaultsKey = "folderBookmarks.v1"

  private var pending: FlutterResult?
  /// URLs whose security scope is open; kept so the access is not given back.
  private var open: [String: URL] = [:]

  func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "riflay/folders", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "pick": self?.pick(result)
      case "restore": result(self?.restore() ?? [:])
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private var bookmarks: [String: Data] {
    get { UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil, let presenter = Self.topViewController() else { return result(nil) }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let done = pending
    pending = nil
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else { return done?(nil) ?? () }
    do {
      var stored = bookmarks
      stored[url.path] = try url.bookmarkData()
      bookmarks = stored
      open[url.path]?.stopAccessingSecurityScopedResource()
      open[url.path] = url
      done?(url.path)
    } catch {
      NSLog("Riflay: could not bookmark folder: \(error)")
      url.stopAccessingSecurityScopedResource()
      done?(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let done = pending
    pending = nil
    done?(nil)
  }

  /// Opens every remembered folder again. Returns each stored path with the path it has now,
  /// since iOS may move a folder between launches; folders that are gone are forgotten.
  private func restore() -> [String: String] {
    var kept: [String: Data] = [:]
    var moved: [String: String] = [:]
    for (oldPath, data) in bookmarks {
      var stale = false
      guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
        url.startAccessingSecurityScopedResource()
      else { continue }
      open[url.path]?.stopAccessingSecurityScopedResource()
      open[url.path] = url
      kept[url.path] = stale ? ((try? url.bookmarkData()) ?? data) : data
      moved[oldPath] = url.path
    }
    bookmarks = kept
    return moved
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.keyWindow?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
  }
}
