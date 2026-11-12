# Changelog

## 1.0.0
- First release.
- `NDISender` sends the sketch window, a `PGraphics`, any `PImage` or raw ARGB pixels over NDI®.
  Auto send, optional alpha (BGRA), announced frame rate, "only when connected" mode, several senders per sketch.
- `NDIReceiver` (a `PImage`, used like `Movie`/`Capture`) receives an NDI source found by full or partial name.
  It receives on its own thread, reconnects automatically, supports several receivers at once and has a low
  bandwidth preview mode.
- `NDI.sources()` lists the sources on the network.
- The NDI 6 runtime is bundled. Runs on macOS 13+ (Apple Silicon and Intel) and Windows 10/11 x64.
