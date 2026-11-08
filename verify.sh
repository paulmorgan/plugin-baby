#!/bin/bash
# Headless end-to-end check of Plugin Baby's service layer (Verify/main.swift):
# real catalog scan, archive/restore round-trip, and offline AU render. Reuses
# the app's own Models + Services + Theme, including the CLAP host shim.
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
OUT="build/verify"
mkdir -p build

CLAP_INC="Sources/CLAPBridge/include"
CLAP_HDR="Sources/CLAPBridge/clap_shim.h"
CLAP_OBJ="build/clap_shim.o"

echo "Compiling CLAP host shim…"
xcrun clang -c -O2 -std=c11 \
    -isysroot "$SDK" -target "${ARCH}-apple-macos14" -I"$CLAP_INC" \
    Sources/CLAPBridge/clap_shim.c -o "$CLAP_OBJ"

# Models + Services + Theme are the harness's dependencies (no Views / App).
SRC=$(find Sources/PluginBaby/Models Sources/PluginBaby/Services -name '*.swift')
SRC="$SRC Sources/PluginBaby/Theme.swift"

echo "Building verification harness…"
xcrun swiftc -O \
    -sdk "$SDK" -target "${ARCH}-apple-macos14" \
    -import-objc-header "$CLAP_HDR" \
    Verify/main.swift $SRC \
    "$CLAP_OBJ" \
    -framework CoreFoundation \
    -o "$OUT"

echo "Running…"
echo
exec "$OUT"
