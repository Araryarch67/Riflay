# Riflay: stands in for the onnxruntime-objc 1.15.1 pod that the onnxruntime Flutter plugin (1.4.1) asks for.
# That pod's C library archive is no longer served (CocoaPods gets a 404 for onnxruntime-c 1.15.1), which broke
# `pod install`. The plugin has no native code of its own: Dart finds the C library's one entry point,
# OrtGetApiBase, in the app itself (DynamicLibrary.process()), and every newer runtime still answers the 1.15 API.
# So this pulls in a current onnxruntime-c from where its podspec says it lives, and keeps that symbol linked.
Pod::Spec.new do |s|
  s.name             = 'onnxruntime-objc'
  s.version          = '1.15.1'
  s.summary          = 'The ONNX Runtime C library for the onnxruntime Flutter plugin (Riflay stand-in).'
  s.description      = 'Depends on a current onnxruntime-c and keeps OrtGetApiBase linked for Dart FFI.'
  s.homepage         = 'https://github.com/microsoft/onnxruntime'
  s.license          = { :type => 'MIT' }
  s.authors          = { 'Riflay' => 'https://github.com/Araryarch67/Riflay' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.static_framework = true
  s.dependency 'onnxruntime-c', '1.20.0' # the newest that still runs on iOS 15.0, the app's minimum
  # Nothing in the app calls it directly (Dart looks it up at run time): without this the linker would leave the
  # whole library out.
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_OrtGetApiBase' }
end
