require 'fileutils'
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint media_kit_libs_macos_audio.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  # Riflay: Mpv.xcframework is Riflay's own libmpv (tool/build_libmpv_apple.sh: the FFmpeg
  # filters the app uses) instead of media_kit's download, which has none. Built here when missing.
  here = File.realpath(__dir__)
  unless File.exist?(File.join(here, 'Frameworks', 'Mpv.xcframework'))
    script = File.expand_path('../../../tool/build_libmpv_apple.sh', here)
    system(script, 'macos') or raise "Building libmpv failed; run #{script} macos"
  end

  # media_kit_video links Mpv.framework from Frameworks/.symlinks/mpv/<platform>, the layout media_kit's own
  # packages make: one relative link per slice of the xcframework (ios-arm64 -> ios, ...-simulator -> ios-simulator).
  links = File.join(here, 'Frameworks', '.symlinks', 'mpv')
  Dir.glob(File.join(here, 'Frameworks', 'Mpv.xcframework', '*')).select { |d| File.directory?(d) }.each do |slice|
    slug = File.basename(slice)
    parts = slug.split('-')
    name = [parts[0], parts[2]].compact.join('-')
    link = File.join(links, name)
    next if File.symlink?(link) && File.exist?(link)
    FileUtils.mkdir_p(links)
    FileUtils.rm_f(link)
    File.symlink(File.join('..', '..', 'Mpv.xcframework', slug), link)
  end

  s.name             = 'media_kit_libs_macos_audio'
  s.version          = '1.0.4'
  s.summary          = 'macOS dependency package for package:media_kit'
  s.description      = <<-DESC
  macOS dependency package for package:media_kit.
                       DESC
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :osx, '10.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
