#
# LibNClaw.podspec — vendors the Rust libnclaw C-ABI static library into the
# iOS Runner target as an xcframework.
#
# The xcframework is produced by scripts/build-ios.sh (Rust -> staticlib ->
# xcframework) and is a build artifact, not committed. CI builds it before
# `pod install` / `flutter build ios`; local developers run the script once.
#
# AppDelegate.swift links the C-ABI exports (nclaw_set_low_power et al.)
# declared in Runner/Runner-Bridging-Header.h; this pod provides their
# implementation at link time.
#
Pod::Spec.new do |s|
  s.name             = 'LibNClaw'
  s.version          = '1.1.2'
  s.summary          = 'Rust libnclaw C-ABI core for the nClaw iOS client.'
  s.description      = 'Vendored xcframework exposing the libnclaw mobile FFI ' \
                       'damper exports (low-power, battery, thermal) to Swift.'
  s.homepage         = 'https://github.com/nself-org/nclaw'
  s.license          = { :type => 'MIT' }
  s.author           = { 'nSelf' => 'hello@nself.org' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '14.0'

  s.vendored_frameworks = 'libnclaw.xcframework'

  # Header-only consumers do not need extra source; the bridging header in the
  # Runner target declares the symbols. The static archive carries no Swift, so
  # no module map is required.
  s.preserve_paths = 'libnclaw.xcframework'
end
