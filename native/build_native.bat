@echo off
rem Builds the JNI bridge for Windows: <out>\windows-amd64\ProcessingNDI.dll, plus <out>\ndiprobe.exe
rem Run from a "Developer Command Prompt for VS" (or after vcvars64.bat); needs JAVA_HOME (JDK 17+).
rem Usage: build_native.bat [out-dir]     (default: native\build)
rem Author: Tiago Martins
setlocal
set "HERE=%~dp0"
set "OUT=%~1"
if "%OUT%"=="" set "OUT=%HERE%build"
if "%JAVA_HOME%"=="" (
  echo ERROR: JAVA_HOME is not set 1>&2
  exit /b 1
)
if not exist "%JAVA_HOME%\include\jni.h" (
  echo ERROR: %JAVA_HOME%\include\jni.h not found 1>&2
  exit /b 1
)
if not exist "%OUT%\windows-amd64" mkdir "%OUT%\windows-amd64"
if not exist "%OUT%\obj" mkdir "%OUT%\obj"
echo Building the Processing-NDI JNI bridge for Windows x64
cl /nologo /O2 /W3 /I"%HERE%." /I"%HERE%include" /I"%JAVA_HOME%\include" /I"%JAVA_HOME%\include\win32" /LD ^
   "%HERE%ndijni.c" /Fe"%OUT%\windows-amd64\ProcessingNDI.dll" /Fo"%OUT%\obj\\" || exit /b 1
cl /nologo /O2 /W3 /I"%HERE%." /I"%HERE%include" "%HERE%probe\ndiprobe.c" /Fe"%OUT%\ndiprobe.exe" /Fo"%OUT%\obj\\" || exit /b 1
del /q "%OUT%\windows-amd64\*.exp" "%OUT%\windows-amd64\*.lib" 2>nul
echo built %OUT%\windows-amd64\ProcessingNDI.dll
