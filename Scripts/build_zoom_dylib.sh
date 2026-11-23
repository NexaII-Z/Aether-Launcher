#!/usr/bin/env bash
# Builds Injection/AetherZoom/AetherZoom.m into build/AetherZoom.dylib (arm64, iOS). Needs macOS + Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun --sdk iphoneos clang \
  -arch arm64 -dynamiclib -fobjc-arc -fvisibility=hidden -O2 \
  -miphoneos-version-min=13.0 \
  -Wall -Wno-deprecated-declarations \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -install_name @rpath/AetherZoom.dylib \
  -o build/AetherZoom.dylib Injection/AetherZoom/AetherZoom.m
file build/AetherZoom.dylib
echo "Built build/AetherZoom.dylib"
