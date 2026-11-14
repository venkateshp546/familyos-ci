#!/usr/bin/env bash
# Builds libweather_core.a for device (arm64) and simulator (arm64 + x86_64, lipo'd).
set -euo pipefail
cd "$(dirname "$0")/../rust-core"
export IPHONEOS_DEPLOYMENT_TARGET=17.0

rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for t in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  cargo build --release --target "$t"
done

rm -rf build && mkdir -p build/device build/sim
cp target/aarch64-apple-ios/release/libweather_core.a build/device/
lipo -create \
  target/aarch64-apple-ios-sim/release/libweather_core.a \
  target/x86_64-apple-ios/release/libweather_core.a \
  -output build/sim/libweather_core.a
lipo -info build/device/libweather_core.a build/sim/libweather_core.a
