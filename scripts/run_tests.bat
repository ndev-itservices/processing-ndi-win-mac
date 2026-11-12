@echo off
rem End-to-end test on Windows: a headless Java sender (test\java\SenderTest) publishes "PNDI-Test"
rem and native\build\ndiprobe.exe receives it through the bundled NDI runtime; then the Java
rem NDIReceiver is tested in loopback, against "ndiprobe --send" and with three sources at once.
rem Needs: build.sh already run (dist\ProcessingNDI), native\build\ndiprobe.exe, JAVA_HOME.
rem Note: the Windows NDI runtime delivers opaque (BGRX) video as BGRA with alpha 255, so opaque
rem cases accept either FourCC / image format. Connections can take a few seconds (x64 emulation
rem on Windows ARM), hence the longer durations than on macOS.
rem Author: Tiago Martins
setlocal EnableDelayedExpansion
set "ROOT=%~dp0.."
cd /d "%ROOT%"
set "CORE="
for %%F in (build\deps\core-*.jar) do set "CORE=%%F"
set "CP=dist\ProcessingNDI\library\ProcessingNDI.jar;!CORE!;build\test-classes"
set "RT=dist\ProcessingNDI\library\windows-amd64"
set FAIL=0
call :case "opaque (BGRX)" "fourcc=BGR" "corner=0xFF[EF]"
call :case "alpha (BGRA)" "fourcc=BGRA" "corner=0x[78]" alpha
call :case "only when connected" "fourcc=BGR" "corner=0xFF[EF]" idle
call :rx "receive: loopback with alpha" "640x360 format=ARGB" 15 PNDI-Loop --loopback --alpha
start "" /b native\build\ndiprobe.exe --send PNDI-Ext 20 640 360 "%RT%" > build\tx.log 2>&1
call :rx "receive: external source" "640x360" 15 pndi-ext
for %%i in (1 2 3) do start "" /b native\build\ndiprobe.exe --send PNDI-Multi-%%i 20 640 360 "%RT%" > build\tx%%i.log 2>&1
call :rx "receive: three sources at once" "640x360" 15 PNDI-Multi-1 PNDI-Multi-2 PNDI-Multi-3
call :sleep 6
if %FAIL%==0 (echo ALL TESTS PASSED) else (echo SOME TESTS FAILED)
exit /b %FAIL%

:case
rem :case <label> <text expected in the first FRAME line> <regex for the corner pixel> [SenderTest options]
echo ### %~1
del build\sender.log 2>nul
start "" /b "%JAVA_HOME%\bin\java" -cp "%CP%" SenderTest 14 %4 > build\sender.log 2>&1
call :sleep 3
native\build\ndiprobe.exe PNDI-Test 8 "%RT%" > build\probe.log 2>&1
set RC=!errorlevel!
call :waitfor build\sender.log "SENT frames=" 20
type build\probe.log
type build\sender.log
set OK=1
if not !RC!==0 set OK=0
set "LINE="
for /f "delims=" %%L in ('findstr /b "FRAME" build\probe.log') do if not defined LINE set "LINE=%%L"
echo !LINE! | findstr /c:"640x360" >nul || set OK=0
echo !LINE! | findstr /c:"%~2" >nul || set OK=0
echo !LINE! | findstr /r /c:"%~3" >nul || set OK=0
findstr /b /c:"SENT frames=" build\sender.log >nul || set OK=0
if !OK!==1 (echo    PASS) else (echo    FAIL & set FAIL=1)
exit /b 0

:rx
rem :rx <label> <expected text in every FINAL line> <ReceiverTest args...>
echo ### %~1
set "EXPECT=%~2"
set "ARGS="
:rxargs
if "%~3"=="" goto rxrun
set "ARGS=!ARGS! %3"
shift /3
goto rxargs
:rxrun
"%JAVA_HOME%\bin\java" -cp "%CP%" ReceiverTest!ARGS! > build\rx.log 2>&1
findstr /b "FINAL" build\rx.log
set OK=1
findstr /b "FINAL" build\rx.log >nul || set OK=0
for /f "delims=" %%L in ('findstr /b "FINAL" build\rx.log') do (
  echo %%L | findstr /c:"!EXPECT!" >nul || set OK=0
  echo %%L | findstr /c:"connected=true" >nul || set OK=0
)
if !OK!==1 (echo    PASS) else (echo    FAIL & set FAIL=1)
exit /b 0

:waitfor
rem :waitfor <file> <text> <max seconds>
for /l %%s in (1,1,%3) do (
  findstr /c:"%~2" "%~1" >nul 2>&1 && exit /b 0
  call :sleep 1
)
exit /b 1

:sleep
powershell -NoProfile -Command "Start-Sleep -Seconds %1"
exit /b 0
