#!/bin/bash
# Copies the NDI(R) runtime that is bundled with the library into native/runtime/:
#   native/runtime/macos/libndi.dylib               (universal arm64 + x86_64)
#   native/runtime/windows-amd64/Processing.NDI.Lib.x64.dll
#   native/runtime/libndi_licenses.txt              (third-party licences required by NDI)
# The runtime is NOT kept in git: it comes from the NDI SDK, whose licence you accept when
# you install it (https://ndi.video/for-developers/ndi-sdk/).
#
# macOS sources, in order: $NDI_SDK_APPLE, "/Library/NDI SDK for Apple", or (CI, FETCH_NDI_DOWNLOAD=1)
#   the official SDK installer, expanded without installing it.
# Windows: run on Windows (Git Bash) after installing the NDI 6 SDK (CI extracts the installer instead),
#   or set NDI_SDK_WIN to the folder that contains it. On a Mac: NDI_SDK_WIN="<...>/NDI 6 SDK.exe"
#   scripts/fetch_ndi_runtime.sh windows   (extracts the installer with innoextract).
# Author: Tiago Martins
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/native/runtime"
mkdir -p "$OUT"
APPLE_PKG_URL="https://downloads.ndi.tv/SDK/NDI_SDK_Mac/Install_NDI_SDK_v6_Apple.pkg"

fetch_macos() {
  local sdk="${NDI_SDK_APPLE:-/Library/NDI SDK for Apple}"
  if [ ! -f "$sdk/lib/macOS/libndi.dylib" ] && [ "${FETCH_NDI_DOWNLOAD:-0}" = "1" ]; then
    local tmp="$ROOT/build/ndi-sdk"
    rm -rf "$tmp"; mkdir -p "$tmp"
    echo "== downloading the NDI SDK for Apple"
    curl -fsSL -o "$tmp/sdk.pkg" "$APPLE_PKG_URL"
    pkgutil --expand-full "$tmp/sdk.pkg" "$tmp/x"
    local lib; lib="$(find "$tmp/x" -path "*lib/macOS/libndi.dylib" | head -1)"
    [ -n "$lib" ] || { echo "ERROR: libndi.dylib not found inside the SDK installer" >&2; exit 1; }
    sdk="$(dirname "$(dirname "$(dirname "$lib")")")"
  fi
  if [ ! -f "$sdk/lib/macOS/libndi.dylib" ]; then
    echo "ERROR: NDI SDK for Apple not found in '$sdk'." >&2
    echo "       Install it from $APPLE_PKG_URL (or set NDI_SDK_APPLE)." >&2
    exit 1
  fi
  mkdir -p "$OUT/macos"
  cp "$sdk/lib/macOS/libndi.dylib" "$OUT/macos/"
  cp "$sdk/lib/macOS/libndi_licenses.txt" "$OUT/libndi_licenses.txt" 2>/dev/null || cp "$sdk/licenses/libndi_licenses.txt" "$OUT/"
  [ -f "$sdk/Version.txt" ] && cp "$sdk/Version.txt" "$OUT/macos/NDI-Version.txt"
  echo "   macOS runtime: $(cat "$OUT/macos/NDI-Version.txt" 2>/dev/null || echo '?')"
}

fetch_windows() {
  # the NDI 6 SDK installs into "C:\Program Files\NDI\NDI 6 SDK" (Bin\x64\Processing.NDI.Lib.x64.dll)
  local base="${NDI_SDK_WIN:-/c/Program Files/NDI}"
  if [ -f "$base" ] && [[ "$base" == *.exe ]]; then
    # the SDK installer itself (Inno Setup): extract it without installing (brew install innoextract)
    command -v innoextract >/dev/null || { echo "ERROR: innoextract is needed to read $base" >&2; exit 1; }
    local tmp="$ROOT/build/ndi-sdk-win"
    rm -rf "$tmp"; mkdir -p "$tmp"
    innoextract -s -d "$tmp" "$base"
    base="$tmp"
  fi
  local dll; dll="$(find "$base" -iname "Processing.NDI.Lib.x64.dll" 2>/dev/null | grep -i -v runtime | head -1 || true)"
  [ -n "$dll" ] || dll="$(find "$base" -iname "Processing.NDI.Lib.x64.dll" 2>/dev/null | head -1 || true)"
  if [ -z "$dll" ]; then
    echo "ERROR: Processing.NDI.Lib.x64.dll not found under '$base'. Install the NDI 6 SDK or set NDI_SDK_WIN." >&2
    exit 1
  fi
  local bin; bin="$(dirname "$dll")"
  mkdir -p "$OUT/windows-amd64"
  cp "$dll" "$OUT/windows-amd64/"
  local lic; lic="$(find "$bin" -maxdepth 1 -iname "*licenses*.txt" 2>/dev/null | head -1 || true)"
  [ -n "$lic" ] && cp "$lic" "$OUT/libndi_licenses.txt"
  local ver; ver="$(find "$base" -maxdepth 2 -iname "Version.txt" 2>/dev/null | head -1 || true)"
  [ -n "$ver" ] && cp "$ver" "$OUT/windows-amd64/NDI-Version.txt"
  echo "   Windows runtime: $dll"
}

# "scripts/fetch_ndi_runtime.sh windows" on a Mac: NDI_SDK_WIN=<path to "NDI 6 SDK.exe">
case "${1:-$(uname -s)}" in
  macos|Darwin) fetch_macos ;;
  windows|MINGW*|MSYS*|CYGWIN*) fetch_windows ;;
  *) echo "ERROR: only macOS and Windows are supported" >&2; exit 1 ;;
esac
