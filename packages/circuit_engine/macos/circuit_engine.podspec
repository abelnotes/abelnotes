#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint circuit_engine.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'circuit_engine'
  s.version          = '0.0.1'
  s.summary          = 'AbelNotes circuit engine (C).'
  s.description      = <<-DESC
AbelNotes circuit tidy-up engine, built from source.
                       DESC
  s.homepage         = 'https://abelnotes.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AbelNotes' => 'noreply@abelnotes.app' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'OTHER_CFLAGS' => '-O3 -fno-math-errno', 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
