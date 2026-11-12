/**
 * NDI_6_Receive_Grid
 *
 * Receives every NDI® source on the network at the same time and shows them in a grid,
 * like a multiviewer. New sources are added as they appear. The low bandwidth preview
 * stream is used (setLowBandwidth / third constructor argument), which is much lighter.
 * Click a tile to switch it between preview and full quality.
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

ArrayList<NDIReceiver> receivers = new ArrayList<NDIReceiver>();

void setup() {
  size(1280, 720, P2D);
  textSize(14);
  addNewSources(NDI.sources());
}

void draw() {
  background(30);
  if (frameCount % 120 == 0) addNewSources(NDI.sources());

  int n = max(1, receivers.size());
  int cols = ceil(sqrt(n));
  int rows = ceil(n / (float) cols);
  float tw = width / (float) cols, th = height / (float) rows;
  for (int i = 0; i < receivers.size(); i++) {
    NDIReceiver rx = receivers.get(i);
    if (rx.available()) rx.read();
    float x = (i % cols) * tw, y = (i / cols) * th;
    if (rx.width > 1) {
      float s = min((tw - 8) / rx.width, (th - 8) / rx.height);
      image(rx, x + (tw - rx.width * s) / 2, y + (th - rx.height * s) / 2, rx.width * s, rx.height * s);
    }
    fill(0, 170);
    noStroke();
    rect(x + 4, y + th - 28, tw - 8, 24);
    fill(rx.isConnected() ? color(120, 255, 120) : color(255, 120, 120));
    text(rx.getSource() + "  " + rx.width + "x" + rx.height + (rx.isLowBandwidth() ? "  preview" : "  full"), x + 10, y + th - 11);
  }
  if (receivers.isEmpty()) {
    fill(255);
    text("Looking for NDI sources...", 20, 30);
  }
}

void addNewSources(String[] names) {
  for (String name : names) {
    boolean known = false;
    for (NDIReceiver rx : receivers) if (rx.getSource().equals(name)) known = true;
    if (!known) receivers.add(new NDIReceiver(this, name, true));
  }
}

void mousePressed() {
  int n = max(1, receivers.size());
  int cols = ceil(sqrt(n));
  int rows = ceil(n / (float) cols);
  int i = int(mouseY / (height / (float) rows)) * cols + int(mouseX / (width / (float) cols));
  if (i < receivers.size()) {
    NDIReceiver rx = receivers.get(i);
    rx.setLowBandwidth(!rx.isLowBandwidth());
  }
}
