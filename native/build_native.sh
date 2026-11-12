#!/bin/bash
# Builds the JNI bridge (and the ndiprobe test receiver) for the current platform:
#   macOS -> <out>/macos-aarch64/libProcessingNDI.dylib and <out>/macos-x86_64/libProcessingNDI.dylib
#            (the same universal arm64 + x86_64 binary), <out>/ndiprobe
# Usage: build_native.sh [out-dir]     (default: native/build)
# Author: Tiago Martins
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HERE/build}"
mkdir -p "$OUT_DIR"

JDK="${JAVA_HOME:-}"
if [ -z "$JDK" ] || [ ! -f "$JDK/include/jni.h" ]; then JDK="$(/usr/libexec/java_home 2>/dev/null || true)"; fi
if [ -z "$JDK" ] || [ ! -f "$JDK/include/jni.h" ]; then JDK="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"; fi
if [ ! -f "$JDK/include/jni.h" ]; then
  echo "ERROR: jni.h not found. Set JAVA_HOME to a JDK (17+) with include/jni.h" >&2
  exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: build_native.sh builds the macOS binaries; on Windows use native\\build_native.bat" >&2
  exit 1
fi
echo "Building the Processing-NDI JNI bridge (JDK headers: $JDK)"
# the Command Line Tools SDK of macOS 27 has tbd files clang 15 cannot read: prefer Xcode's SDK
SDKROOT_X="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
SYSROOT=(); [ -d "$SDKROOT_X" ] && SYSROOT=(-isysroot "$SDKROOT_X")
CFLAGS=(-O2 -fPIC -Wall -Wno-unused-function -mmacosx-version-min=10.15 -I"$HERE" -I"$HERE/include" -I"$JDK/include" -I"$JDK/include/darwin")
TMP="$OUT_DIR/.tmp"; mkdir -p "$TMP"
for a in arm64 x86_64; do
  clang "${SYSROOT[@]}" -arch $a "${CFLAGS[@]}" -dynamiclib -install_name @rpath/libProcessingNDI.dylib \
        "$HERE/ndijni.c" -o "$TMP/jni-$a.dylib"
  clang "${SYSROOT[@]}" -arch $a "${CFLAGS[@]}" "$HERE/probe/ndiprobe.c" -o "$TMP/probe-$a"
done
lipo -create "$TMP/jni-arm64.dylib" "$TMP/jni-x86_64.dylib" -output "$TMP/libProcessingNDI.dylib"
lipo -create "$TMP/probe-arm64" "$TMP/probe-x86_64" -output "$OUT_DIR/ndiprobe"
codesign --force --sign - "$TMP/libProcessingNDI.dylib" >/dev/null 2>&1 || true
codesign --force --sign - "$OUT_DIR/ndiprobe" >/dev/null 2>&1 || true
for v in macos-aarch64 macos-x86_64; do
  mkdir -p "$OUT_DIR/$v"; cp "$TMP/libProcessingNDI.dylib" "$OUT_DIR/$v/"
done
rm -rf "$TMP"
lipo -info "$OUT_DIR/macos-aarch64/libProcessingNDI.dylib"
