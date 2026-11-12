# Building Processing-NDI from source

This page is for developers. To *use* the library you do not need any of this. See the [README](README.md).

## Repository layout

| Path | What it is |
|---|---|
| `src/processing/ndi/` | The Java library: `NDISender`, `NDIReceiver`, `NDI`, and `NDINative` (the loader). |
| `native/ndijni.c`, `native/ndiload.h` | JNI bridge. It loads the NDI runtime at run time and sends and receives frames. |
| `native/include/` | NDI® SDK headers (MIT licence, © Vizrt NDI AB). |
| `native/probe/ndiprobe.c` | Small command-line NDI receiver/sender used by the tests. |
| `examples/` | Processing examples shipped with the library. |
| `test/java/` | Headless sender and receiver tests. |
| `scripts/` | Runtime download, test runners. |
| `build.sh` | Compiles everything and assembles `dist/ProcessingNDI` and `dist/ProcessingNDI.zip`. |
| `.github/workflows/build.yml` | CI for macOS and Windows, and the release zip. |

The NDI runtime (`libndi.dylib` and `Processing.NDI.Lib.x64.dll`) is **not** stored in git. It is copied from
the official NDI 6 SDK into `native/runtime/` by `scripts/fetch_ndi_runtime.sh`, and only goes into the release
zip.

## Requirements

- JDK 17 or newer.
- Processing 4. If it is not installed, `build.sh` downloads `core.jar` from Maven Central.
- The NDI 6 SDK, from https://ndi.video/for-developers/ (you accept its licence when you install it):
  - macOS: https://downloads.ndi.tv/SDK/NDI_SDK_Mac/Install_NDI_SDK_v6_Apple.pkg
  - Windows: https://downloads.ndi.tv/SDK/NDI_SDK/NDI%206%20SDK.exe

## macOS

Needs the Xcode command line tools (`xcode-select --install`).

```sh
scripts/fetch_ndi_runtime.sh   # copies the NDI runtime from "/Library/NDI SDK for Apple" into native/runtime
./build.sh                     # builds the universal (arm64 + x86_64) bridge, then dist/ProcessingNDI(.zip)
scripts/run_tests.sh           # end-to-end tests: sender and receiver against native/build/ndiprobe
```

### Windows binaries built on a Mac

```sh
brew install mingw-w64 innoextract
NDI_SDK_WIN="$HOME/Downloads/NDI 6 SDK.exe" scripts/fetch_ndi_runtime.sh windows
native/build_native_mingw.sh
./build.sh                     # the zip now contains macOS and Windows
```

## Windows

Needs Visual Studio with the C++ workload and Git for Windows (Git Bash).

1. Install the NDI 6 SDK.
2. In Git Bash, run `scripts/fetch_ndi_runtime.sh` and then `SKIP_NATIVE=1 ./build.sh`.
3. In a *Developer Command Prompt for VS*, run `native\build_native.bat`.
4. In Git Bash, run `SKIP_NATIVE=1 ./build.sh` again.
5. Run `scripts\run_tests.bat`.

## Tests

`scripts/run_tests.sh` (macOS) and `scripts\run_tests.bat` (Windows) start real NDI senders and receivers on
this computer:

- `SenderTest` → `ndiprobe` checks opaque frames, frames with alpha, and "only when connected" mode.
- `ReceiverTest` checks Java → Java loopback with alpha, an external source (`ndiprobe --send`), three sources at
  once, the low bandwidth stream, and reconnection after a source goes away (macOS).

`NDIPROBE_DUMP=frame.bmp native/build/ndiprobe "<name>"` saves the first received frame as an image.

## Releases

CI runs on every push. To publish a release, go to **Actions › build › Run workflow** and enter a tag
(e.g. `v1.0.0`). The release gets two files with fixed names:

- `ProcessingNDI.zip` is the library. The README links to `releases/latest/download/ProcessingNDI.zip`.
- `ProcessingNDI.txt` is a copy of `library.properties`, which is what Processing's Contribution Manager reads.

Before a release, bump `version` / `prettyVersion` in `library.properties` and `NDISender.VERSION` (`build.sh`
checks that they match), and update `CHANGELOG.md`.

## How it works

- **Loading:** `NDINative` loads `library/<variant>/libProcessingNDI.dylib` or `ProcessingNDI.dll`. The bridge
  then loads the NDI runtime from its own folder, or from `NDI_RUNTIME_DIR_V6`, or from the standard install
  locations.
- **Sending:** `NDIlib_send_send_video_async_v2` with two alternating native buffers. Processing's ARGB `int`
  pixels already have NDI's BGRA byte order in memory, so there is no colour conversion.
- **Receiving:** one shared NDI finder, plus one native thread per `NDIReceiver`. The thread picks the
  best-matching source (exact name, then the name between brackets, then a partial match, ignoring case), receives
  BGRX/BGRA frames and recreates the connection when the source changes. `read()` copies the newest frame into
  the `PImage` pixels.
- **Windows:** the NDI runtime delivers opaque video as BGRA with alpha 255.

## Licence obligations for redistributors

The NDI runtime may be redistributed under the NDI SDK License Agreement. Keep:

- `LICENSE.txt`, whose section 3 contains the terms the NDI licence requires to be passed on;
- `NDI-THIRD-PARTY-LICENSES.txt`;
- the notice "NDI® is a registered trademark of Vizrt NDI AB" with a link to https://ndi.video/.
