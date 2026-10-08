#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# build_npd_guard_ios.sh — compile npd_guard into an iOS XCFramework
# ─────────────────────────────────────────────────────────────
# Produces:
#   ios/Frameworks/NpdGuard.xcframework/{ios-arm64,ios-arm64_x86_64-simulator}/
#     Headers/npd_guard.h
#     libnpd_guard.a
#
# Dependencies:
#   • rustup + cargo
#   • rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
#
# Flutter will link the XCFramework via the CocoaPods vendored_frameworks
# entry in `ios/Podfile`. After running this, `cd ios && pod install`.
# ─────────────────────────────────────────────────────────────

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$ROOT/rust/npd_guard"
OUT_DIR="$ROOT/ios/Frameworks"
XCF_DIR="$OUT_DIR/NpdGuard.xcframework"
HEADER_SRC="$ROOT/tool/npd_guard_assets/npd_guard.h"

cd "$CRATE_DIR"

echo "→ Building aarch64-apple-ios (device)"
cargo build --release --target aarch64-apple-ios

echo "→ Building aarch64-apple-ios-sim (Apple-silicon simulator)"
cargo build --release --target aarch64-apple-ios-sim

echo "→ Building x86_64-apple-ios (Intel simulator)"
cargo build --release --target x86_64-apple-ios

DEVICE_LIB="$CRATE_DIR/target/aarch64-apple-ios/release/libnpd_guard.a"
SIM_ARM_LIB="$CRATE_DIR/target/aarch64-apple-ios-sim/release/libnpd_guard.a"
SIM_X86_LIB="$CRATE_DIR/target/x86_64-apple-ios/release/libnpd_guard.a"

for p in "$DEVICE_LIB" "$SIM_ARM_LIB" "$SIM_X86_LIB"; do
  if [[ ! -f "$p" ]]; then
    echo "✗ missing build artefact: $p" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"
rm -rf "$XCF_DIR"

# Fat simulator slice (arm64 + x86_64) via lipo.
SIM_FAT="$CRATE_DIR/target/libnpd_guard-sim-fat.a"
lipo -create -output "$SIM_FAT" "$SIM_ARM_LIB" "$SIM_X86_LIB"

# Public header — hand-maintained so Flutter does not need bindgen.
if [[ ! -f "$HEADER_SRC" ]]; then
  echo "✗ missing header template: $HEADER_SRC" >&2
  exit 1
fi
DEVICE_HEADERS="$OUT_DIR/.headers/device"
SIM_HEADERS="$OUT_DIR/.headers/sim"
rm -rf "$OUT_DIR/.headers"
mkdir -p "$DEVICE_HEADERS" "$SIM_HEADERS"
cp "$HEADER_SRC" "$DEVICE_HEADERS/npd_guard.h"
cp "$HEADER_SRC" "$SIM_HEADERS/npd_guard.h"

xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$DEVICE_HEADERS" \
  -library "$SIM_FAT"    -headers "$SIM_HEADERS" \
  -output "$XCF_DIR"

rm -rf "$OUT_DIR/.headers"
rm -f "$SIM_FAT"

echo ""
echo "→ XCFramework:"
find "$XCF_DIR" -name 'libnpd_guard.a' -print -exec ls -lh {} \;
echo ""
echo "✓ NpdGuard.xcframework ready."
