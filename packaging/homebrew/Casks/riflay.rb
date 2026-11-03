# Homebrew cask for the macOS app. The release workflow fills in `version` and
# `sha256` (packaging/update_manifests.sh) when the release has Riflay-macos.dmg;
# copy the result into the tap's Casks/ folder. Until a tag release carries the
# macOS build (paused for tags, see release.yml) the URL below has nothing to fetch.
#
#   brew tap Araryarch67/riflay && brew install --cask riflay
cask "riflay" do
  version "1.0.4"
  sha256 :no_check

  url "https://github.com/Araryarch67/Riflay/releases/download/v#{version}/Riflay-macos.dmg"
  name "Riflay"
  desc "Music player for your own music and YouTube Music, with hi-fi audio"
  homepage "https://github.com/Araryarch67/Riflay"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :monterey"

  app "Riflay.app"

  # Signed ad hoc, not notarized (no Apple Developer ID): without this, Gatekeeper
  # says the app "is damaged" on first start.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Riflay.app"]
  end

  zap trash: [
    "~/Library/Application Support/dev.riflay.riflay",
    "~/Library/Caches/dev.riflay.riflay",
    "~/Library/HTTPStorages/dev.riflay.riflay",
    "~/Library/Preferences/dev.riflay.riflay.plist",
    "~/Library/Saved Application State/dev.riflay.riflay.savedState",
    "~/Library/WebKit/dev.riflay.riflay",
  ]
end
