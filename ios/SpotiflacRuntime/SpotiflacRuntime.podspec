Pod::Spec.new do |s|
  s.name = 'SpotiflacRuntime'
  s.version = '1.0.0'
  s.summary = 'Riflay SpotiFLAC extension runtime'
  s.homepage = 'https://github.com/Araryarch67/Riflay'
  s.license = { :type => 'MIT', :file => '../../third_party/spotiflac_backend/LICENSE' }
  s.author = 'Riflay'
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.vendored_frameworks = 'Spotiflac.xcframework'
end
