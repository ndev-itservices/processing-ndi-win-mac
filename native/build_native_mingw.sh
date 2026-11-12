#!/bin/bash
# Cross-compiles the Windows x64 JNI bridge and ndiprobe.exe on macOS/Linux with mingw-w64
# (brew install mingw-w64), so a complete release can be built without a Windows machine:
#   <out>/windows-amd64/ProcessingNDI.dll, <out>/ndiprobe.exe
# The Windows JNI types are provided by a tiny jni_md.h (they are fixed by the JNI spec), so no
# Windows JDK is needed. CI builds with MSVC instead (native\build_native.bat).
# Usage: build_native_mingw.sh [out-dir]     (default: native/build)
# Author: Tiago Martins
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$HERE/build}"
CC="${MINGW_CC:-x86_64-w64-mingw32-gcc}"
command -v "$CC" >/dev/null || { echo "ERROR: $CC not found (brew install mingw-w64)" >&2; exit 1; }

JDK="${JAVA_HOME:-}"
if [ -z "$JDK" ] || [ ! -f "$JDK/include/jni.h" ]; then JDK="$(/usr/libexec/java_home 2>/dev/null || true)"; fi
if [ -z "$JDK" ] || [ ! -f "$JDK/include/jni.h" ]; then JDK="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"; fi
[ -f "$JDK/include/jni.h" ] || { echo "ERROR: jni.h not found; set JAVA_HOME" >&2; exit 1; }

INC="$OUT_DIR/.mingw-include"
mkdir -p "$INC" "$OUT_DIR/windows-amd64"
cp "$JDK/include/jni.h" "$INC/"
cat > "$INC/jni_md.h" <<'H'
/* Windows x64 jni_md.h (values fixed by the JNI specification) */
#ifndef _JAVASOFT_JNI_MD_H_
#define _JAVASOFT_JNI_MD_H_
#define JNIEXPORT __declspec(dllexport)
#define JNIIMPORT __declspec(dllimport)
#define JNICALL __stdcall
typedef long jint;
typedef __int64 jlong;
typedef signed char jbyte;
#endif
H
CFLAGS=(-O2 -Wall -Wno-unused-function -Wno-deprecated-declarations -D_WIN32_WINNT=0x0601 -I"$HERE" -I"$HERE/include" -I"$INC")
echo "Cross-compiling the Processing-NDI JNI bridge for Windows x64 ($CC)"
"$CC" "${CFLAGS[@]}" -shared -static-libgcc -Wl,--kill-at "$HERE/ndijni.c" -o "$OUT_DIR/windows-amd64/ProcessingNDI.dll"
"$CC" "${CFLAGS[@]}" -static "$HERE/probe/ndiprobe.c" -o "$OUT_DIR/ndiprobe.exe"
rm -rf "$INC"
file "$OUT_DIR/windows-amd64/ProcessingNDI.dll" "$OUT_DIR/ndiprobe.exe"
