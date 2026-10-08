<#
  build_npd_guard_ios.ps1 — Windows / PowerShell helper that forwards
  to the bash script on macOS runners. iOS .xcframework can only be
  produced from macOS (xcodebuild requirement), so this script is
  effectively a reminder to run the Mac build. Keep it so Windows
  developers do not stare at a missing .ps1 for the iOS target.
#>
$ErrorActionPreference = 'Stop'
Write-Error 'The iOS XCFramework must be built on macOS. Run `bash tool/build_npd_guard_ios.sh` from a macOS checkout and commit the regenerated `ios/Frameworks/NpdGuard.xcframework/`.'
