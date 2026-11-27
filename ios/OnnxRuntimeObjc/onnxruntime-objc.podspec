# Riflay: stands in for the onnxruntime-objc 1.15.1 pod that the onnxruntime Flutter plugin (1.4.1) asks for, so
# `pod install` works. No iOS build of ONNX Runtime can be fetched any more: onnxruntime-c 1.15.1's archive answers
# 404, newer ones are served from a host whose certificate doesn't match it, and the project's GitHub repository is
# gone. The plugin has no native code of its own (Dart looks the library up in the app at run time), so on iOS that
# lookup fails, the poster editor's cut-out reports it found no one, and posters are made without the depth effect.
# Point this at an onnxruntime-c pod again once one can be downloaded.
Pod::Spec.new do |s|
  s.name             = 'onnxruntime-objc'
  s.version          = '1.15.1'
  s.summary          = 'Stand-in for the onnxruntime plugin on iOS, without the ONNX Runtime library (Riflay).'
  s.description      = 'Satisfies the onnxruntime plugin until an iOS build of ONNX Runtime can be downloaded again.'
  s.homepage         = 'https://github.com/Araryarch67/Riflay'
  s.license          = { :type => 'MIT' }
  s.authors          = { 'Riflay' => 'https://github.com/Araryarch67/Riflay' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.static_framework = true
  # CocoaPods refuses a spec with nothing in it.
  s.preserve_paths   = 'README.md'
end
