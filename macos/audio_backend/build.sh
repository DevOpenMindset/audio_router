#!/usr/bin/env bash
# build.sh — Compile libaudio_backend.dylib for macOS
#
# Run this script from the macos/audio_backend/ directory on a Mac:
#   cd macos/audio_backend
#   bash build.sh
#
# After building, copy the dylib into the Flutter app bundle:
#   cp libaudio_backend.dylib \
#      ../../build/macos/Build/Products/Release/audio_router.app/Contents/Frameworks/
#
# In Xcode, add a "Copy Files" build phase:
#   - Destination: Frameworks
#   - Add libaudio_backend.dylib
#
# Requirements: Xcode Command Line Tools (clang++ from Xcode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/audio_backend.mm"
OUT="$SCRIPT_DIR/libaudio_backend.dylib"

echo "Building libaudio_backend.dylib..."

clang++ \
  -dynamiclib \
  -fvisibility=hidden \
  -std=c++17 \
  -ObjC++ \
  -fobjc-arc \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=12.0 \
  -framework CoreAudio \
  -framework CoreFoundation \
  -framework Foundation \
  -framework AppKit \
  -framework AVFAudio \
  -framework AudioUnit \
  -framework Carbon \
  -install_name @rpath/libaudio_backend.dylib \
  -o "$OUT" \
  "$SRC"

echo "Done: $OUT"
echo ""
echo "Next steps:"
echo "  1. flutter build macos --release"
echo "  2. cp $OUT build/macos/Build/Products/Release/audio_router.app/Contents/Frameworks/"
echo "  OR configure the Xcode project to embed it automatically (see README)."
