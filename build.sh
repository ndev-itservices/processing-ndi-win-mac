#!/bin/bash
# Builds the Processing library "Processing-NDI":
#   - compiles processing.ndi into library/ProcessingNDI.jar (folder and jar names must match;
#     Processing rejects library folders with "-", so the folder is ProcessingNDI)
#   - builds the JNI bridge for the current platform (unless SKIP_NATIVE=1)
#   - copies the NDI runtime from native/runtime (scripts/fetch_ndi_runtime.sh)
#   - assembles dist/ProcessingNDI (Processing 4 library layout) and zips it
# Environment: PROCESSING_APP (default /Applications/Processing.app), JAVA_HOME, SKIP_NATIVE=1, CORE_JAR
# Author: Tiago Martins
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PROCESSING_VERSION="4.4.10"
CORE_JAR="${CORE_JAR:-}"
if [ -z "$CORE_JAR" ]; then
  PROCESSING_APP="${PROCESSING_APP:-/Applications/Processing.app}"
  CORE_JAR="$(ls "$PROCESSING_APP"/Contents/app/resources/core/library/core-*.jar 2>/dev/null | head -1 || true)"
fi
if [ -z "$CORE_JAR" ] || [ ! -f "$CORE_JAR" ]; then
  # no Processing installed (e.g. CI): use the core jar published on Maven Central
  mkdir -p build/deps
  CORE_JAR="build/deps/core-$PROCESSING_VERSION.jar"
  if [ ! -f "$CORE_JAR" ]; then
    echo "== downloading Processing core $PROCESSING_VERSION from Maven Central"
    curl -fsSL -o "$CORE_JAR" "https://repo1.maven.org/maven2/org/processing/core/$PROCESSING_VERSION/core-$PROCESSING_VERSION.jar"
  fi
fi

JDK="${JAVA_HOME:-}"
if [ -z "$JDK" ] || [ ! -x "$JDK/bin/javac" ]; then JDK="$(/usr/libexec/java_home 2>/dev/null || true)"; fi
if [ -z "$JDK" ] || [ ! -x "$JDK/bin/javac" ]; then JDK="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"; fi
if [ ! -x "$JDK/bin/javac" ]; then
  echo "ERROR: javac not found. Install a JDK 17+ or set JAVA_HOME" >&2
  exit 1
fi
JAVAC="$JDK/bin/javac"; JAR="$JDK/bin/jar"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) SEP=";" ;; *) SEP=":" ;; esac

VERSION="$(sed -n 's/^prettyVersion=//p' library.properties)"
if ! grep -q "VERSION = \"$VERSION\"" src/processing/ndi/NDISender.java; then
  echo "ERROR: NDISender.VERSION does not match prettyVersion=$VERSION in library.properties" >&2
  exit 1
fi
echo "== Processing-NDI $VERSION"
echo "   core:  $CORE_JAR"
echo "   javac: $JAVAC"

rm -rf build/classes build/test-classes dist
mkdir -p build/classes build/test-classes native/build

echo "== compiling Java"
"$JAVAC" --release 17 -encoding UTF-8 -Xlint:all -Xlint:-options -cp "$CORE_JAR" -d build/classes $(find src -name "*.java")
"$JAVAC" --release 17 -encoding UTF-8 -nowarn -cp "$CORE_JAR${SEP}build/classes" -d build/test-classes $(find test/java -name "*.java")
"$JAR" --create --file build/ProcessingNDI.jar -C build/classes processing

if [ "${SKIP_NATIVE:-0}" != "1" ] && [ "$(uname -s)" = "Darwin" ]; then
  echo "== building native bridge"
  native/build_native.sh "$ROOT/native/build"
fi

echo "== assembling dist/ProcessingNDI"
D="dist/ProcessingNDI"
mkdir -p "$D/library" "$D/examples" "$D/src" "$D/reference"
cp library.properties "$D/"
cp build/ProcessingNDI.jar "$D/library/"
FOUND=0
for v in macos-aarch64 macos-x86_64 windows-amd64; do
  [ -d "native/build/$v" ] || continue
  mkdir -p "$D/library/$v"
  cp native/build/$v/*.dylib native/build/$v/*.dll "$D/library/$v/" 2>/dev/null || true
  case "$v" in
    macos-aarch64|macos-x86_64)
      RT="native/runtime/macos/libndi.dylib"
      if [ -f "$RT" ]; then
        # one architecture per variant folder keeps the download small
        A="arm64"; [ "$v" = "macos-x86_64" ] && A="x86_64"
        if command -v lipo >/dev/null 2>&1; then lipo "$RT" -thin "$A" -output "$D/library/$v/libndi.dylib"
        else cp "$RT" "$D/library/$v/"; fi
      else echo "   WARNING: $RT missing (run scripts/fetch_ndi_runtime.sh)"; fi ;;
    windows-amd64)
      RT="native/runtime/windows-amd64/Processing.NDI.Lib.x64.dll"
      if [ -f "$RT" ]; then cp "$RT" "$D/library/$v/"
      else echo "   WARNING: $RT missing (run scripts/fetch_ndi_runtime.sh on Windows)"; fi ;;
  esac
  FOUND=$((FOUND+1))
  echo "   native: $v ($(ls "$D/library/$v" | tr '\n' ' '))"
done
[ "$FOUND" -gt 0 ] || echo "   WARNING: no native binaries found in native/build/"
cp -R examples/. "$D/examples/"
cp -R src/. "$D/src/"
cp README.md LICENSE.txt "$D/"
[ -f native/runtime/libndi_licenses.txt ] && cp native/runtime/libndi_licenses.txt "$D/NDI-THIRD-PARTY-LICENSES.txt"
cp README.md "$D/reference/index.md"
find "$D" -name ".DS_Store" -delete
rm -f dist/ProcessingNDI.zip
if command -v zip >/dev/null 2>&1; then
  ( cd dist && zip -qry ProcessingNDI.zip ProcessingNDI )
else
  "$JAR" --create --no-manifest --file dist/ProcessingNDI.zip -C dist ProcessingNDI
fi
echo "== done: $D  and  dist/ProcessingNDI.zip ($(du -h dist/ProcessingNDI.zip | cut -f1))"
