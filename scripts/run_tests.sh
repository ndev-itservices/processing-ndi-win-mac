#!/bin/bash
# End-to-end test on macOS: a headless Java sender (test/java/SenderTest) publishes "PNDI-Test"
# and native/build/ndiprobe receives it through the bundled NDI runtime.
# Sender checks: opaque BGRX frames, BGRA with alpha, and "only when connected" mode.
# Receiver checks (test/java/ReceiverTest): Java -> Java loopback with alpha, an external source
# (ndiprobe --send), three sources at once, the low bandwidth preview stream, and reconnection
# after the source goes away and comes back.
# (Windows: scripts\run_tests.bat)
# Author: Tiago Martins
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
JDK="${JAVA_HOME:-}"
if [ -z "$JDK" ] || [ ! -x "$JDK/bin/java" ]; then JDK="$(/usr/libexec/java_home 2>/dev/null || true)"; fi
if [ -z "$JDK" ] || [ ! -x "$JDK/bin/java" ]; then JDK="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"; fi
[ -f dist/ProcessingNDI/library/ProcessingNDI.jar ] || ./build.sh
CORE_JAR="$(ls /Applications/Processing.app/Contents/app/resources/core/library/core-*.jar build/deps/core-*.jar 2>/dev/null | head -1)"
CP="dist/ProcessingNDI/library/ProcessingNDI.jar:$CORE_JAR:build/test-classes"
VARIANT="macos-$( [ "$(uname -m)" = "arm64" ] && echo aarch64 || echo x86_64 )"
PROBE="native/build/ndiprobe"
RUNTIME="dist/ProcessingNDI/library/$VARIANT"
FAIL=0

near() { # near <hex AARRGGBB> <hex expected> <tolerance per channel>
  local a=$((16#${1#0x})) b=$((16#${2#0x})) t=$3 s
  for s in 0 8 16 24; do
    local x=$(( (a >> s) & 255 )) y=$(( (b >> s) & 255 )) d
    d=$(( x > y ? x - y : y - x )); [ $d -le $t ] || return 1
  done
}

run_case() { # run_case <label> <expected fourcc> <expected corner> <sender args...>
  local label="$1" fourcc="$2" corner="$3"; shift 3
  echo "### $label"
  "$JDK/bin/java" -cp "$CP" SenderTest 9 "$@" > build/sender.log 2>&1 &
  local pid=$!
  sleep 2
  "$PROBE" PNDI-Test 4 "$RUNTIME" > build/probe.log 2>&1
  local rc=$?
  wait $pid
  cat build/probe.log build/sender.log | sed 's/^/   /'
  local line; line="$(grep -m1 '^FRAME' build/probe.log)"
  local ok=1
  [ $rc -eq 0 ] || ok=0
  [[ "$line" == *"640x360 fourcc=$fourcc fps=60000/1000"* ]] || ok=0
  local c k; c="$(sed -n 's/.*center=\(0x[0-9A-F]*\).*/\1/p' <<<"$line")"; k="$(sed -n 's/.*corner=\(0x[0-9A-F]*\).*/\1/p' <<<"$line")"
  near "${c:-0}" 0xFF336699 6 || ok=0
  near "${k:-0}" "$corner" 6 || ok=0
  grep -q '^SENT frames=' build/sender.log || ok=0
  if [ $ok -eq 1 ]; then echo "   PASS"; else echo "   FAIL"; FAIL=1; fi
}

run_case "opaque (BGRX)" BGRX 0xFFFF0000
run_case "alpha (BGRA)" BGRA 0x80FF0000 alpha
run_case "only when connected" BGRX 0xFFFF0000 idle
# ------------------------------------------------------------------ receiver
JAVA_RX=("$JDK/bin/java" -cp "$CP" ReceiverTest)

final_field() { # final_field <RXi> <field>  (from build/rx.log)
  grep "^FINAL $1 " build/rx.log | tr ' ' '\n' | sed -n "s/^$2=//p"
}

check() { # check <label> <condition result 0/1>
  if [ "$2" -eq 0 ]; then echo "   PASS $1"; else echo "   FAIL $1"; FAIL=1; fi
}

echo "### receive: loopback Java -> Java with alpha"
"${JAVA_RX[@]}" 6 PNDI-Loop --loopback --alpha > build/rx.log 2>&1
grep '^FINAL' build/rx.log | sed 's/^/   /'
[ "$(final_field RX0 size)" = "640x360" ] && [ "$(final_field RX0 format)" = "ARGB" ] && near "$(final_field RX0 corner)" 0x80FF0000 6 \
  && near "$(final_field RX0 center)" 0xFF336699 6 && [ "$(final_field RX0 listed)" = "true" ]; check "loopback" $?

echo "### receive: external source (ndiprobe --send)"
"$PROBE" --send PNDI-Ext 9 640 360 "$RUNTIME" > build/tx.log 2>&1 &
"${JAVA_RX[@]}" 6 pndi-ext > build/rx.log 2>&1
wait
grep '^FINAL' build/rx.log | sed 's/^/   /'
[ "$(final_field RX0 size)" = "640x360" ] && [ "$(final_field RX0 format)" = "RGB" ] && near "$(final_field RX0 corner)" 0xFFFF0000 6 \
  && [ "$(final_field RX0 connected)" = "true" ] && [ "$(final_field RX0 frames)" -gt 100 ]; check "external source (partial, case-insensitive name)" $?

echo "### receive: three sources at once"
for i in 1 2 3; do "$PROBE" --send "PNDI-Multi-$i" 9 $((320 * i)) $((180 * i)) "$RUNTIME" > build/tx$i.log 2>&1 & done
"${JAVA_RX[@]}" 6 PNDI-Multi-1 PNDI-Multi-2 PNDI-Multi-3 > build/rx.log 2>&1
wait
grep '^FINAL' build/rx.log | sed 's/^/   /'
OK=0
for i in 1 2 3; do
  [ "$(final_field RX$((i - 1)) size)" = "$((320 * i))x$((180 * i))" ] && [ "$(final_field RX$((i - 1)) frames)" -gt 100 ] || OK=1
done
check "three receivers, each on its own source" $OK

echo "### receive: low bandwidth preview stream"
"$PROBE" --send PNDI-Low 9 1920 1080 "$RUNTIME" > build/tx.log 2>&1 &
"${JAVA_RX[@]}" 6 PNDI-Low --low > build/rx.log 2>&1
wait
grep '^FINAL' build/rx.log | sed 's/^/   /'
SZ="$(final_field RX0 size)"
[ -n "$SZ" ] && [ "${SZ%x*}" -gt 1 ] && [ "${SZ%x*}" -lt 1920 ] && [ "$(final_field RX0 frames)" -gt 50 ]; check "preview stream smaller than 1920x1080 ($SZ)" $?

echo "### receive: reconnection (source stops for 4 s, then comes back)"
"${JAVA_RX[@]}" 16 PNDI-Re > build/rx.log 2>&1 &
RXPID=$!
sleep 1; "$PROBE" --send PNDI-Re 4 640 360 "$RUNTIME" > /dev/null 2>&1
sleep 4; "$PROBE" --send PNDI-Re 5 640 360 "$RUNTIME" > /dev/null 2>&1
wait $RXPID
SEQ="$(grep '^STATUS' build/rx.log | grep -o 'connected=[a-z]*' | cut -d= -f2 | uniq | tr '\n' ' ')"
echo "   connected over time: $SEQ"
[[ "$SEQ" == *"true false true"* ]]; check "reconnects after the source comes back" $?

[ $FAIL -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
