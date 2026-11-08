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

xcrun swiftc -parse-as-library -O \
    -sdk "$SDK" -target "${ARCH}-apple-macos14" \
    $(find Sources -name '*.swift') \
    -o "$APP/Contents/MacOS/PluginBaby"

# Ad-hoc code signature so macOS is happy to launch it locally.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Run it with:  open \"$APP\""
