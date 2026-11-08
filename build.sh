#!/bin/bash
# Builds Plugin Baby into a runnable .app bundle using swiftc directly.
# This avoids SwiftPM, whose manifest tooling is broken in the standalone
# Command Line Tools. If you install full Xcode, you can instead open
# Package.swift and build/run from there.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PluginBaby.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

echo "Building for ${ARCH} against ${SDK}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f Resources/default-sample.mp3 ] && cp Resources/default-sample.mp3 "$APP/Contents/Resources/default-sample.mp3"

# --- CLAP host shim (C) -------------------------------------------------
# Compile the C bridge that hosts CLAP plugins, then link it into the Swift
# build and expose its flat API to Swift via a bridging header.
CLAP_INC="Sources/CLAPBridge/include"
CLAP_HDR="Sources/CLAPBridge/clap_shim.h"
CLAP_OBJ="build/clap_shim.o"
echo "Compiling CLAP host shim…"
xcrun clang -c -O2 -std=c11 \
    -isysroot "$SDK" -target "${ARCH}-apple-macos14" -I"$CLAP_INC" \
    Sources/CLAPBridge/clap_shim.c -o "$CLAP_OBJ"

xcrun swiftc -parse-as-library -O \
    -sdk "$SDK" -target "${ARCH}-apple-macos14" \
    -import-objc-header "$CLAP_HDR" \
    $(find Sources -name '*.swift') \
    "$CLAP_OBJ" \
    -framework CoreFoundation \
    -o "$APP/Contents/MacOS/PluginBaby"

# Ad-hoc code signature so macOS is happy to launch it locally.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Run it with:  open \"$APP\""
