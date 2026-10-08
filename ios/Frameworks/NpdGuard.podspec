#
# NpdGuard — local podspec that vendors the prebuilt
# NpdGuard.xcframework into the Runner target. The .xcframework is
# produced by `tool/build_npd_guard_ios.sh` (macOS only) and committed
# alongside this file so CI / fresh clones do not need Rust installed
# just to build the iOS app.
#
Pod::Spec.new do |s|
  s.name             = 'NpdGuard'
  s.version          = '0.1.0'
  s.summary          = 'NeonPlumeDrop native guard (opaque Rust library).'
  s.description      = 'Opaque Rust library linked into the Runner binary.'
  s.homepage         = 'https://neonplumedrop.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'NeonPlumeDrop' => 'ops@neonplumedrop.com' }
  s.source           = { :path => '.' }

  s.platform         = :ios, '15.0'
  s.ios.deployment_target = '15.0'

  s.vendored_frameworks = 'NpdGuard.xcframework'
  s.libraries           = 'c++'

  s.pod_target_xcconfig = {
    'ENABLE_BITCODE' => 'NO',
  }
end
