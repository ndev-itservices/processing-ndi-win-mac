/**
 * NDI_5_Receive
 *
 * Receives one NDI® source and draws it in the window, like a Movie or a Capture.
 * The sources found on the network are listed on screen: press 1-9 to switch to one,
 * or change SOURCE below to (part of) a source name, e.g. "OBS" or "Arena".
 * If the source is not running yet, or stops, the receiver waits and reconnects by itself.
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

String SOURCE = "";          // "" = the first source found
NDIReceiver rx;
String[] sources = new String[0];

void setup() {
  size(1280, 720, P2D);
  rx = new NDIReceiver(this, SOURCE);
  sources = NDI.sources();   // waits up to 1 s the first time
}

void draw() {
  if (rx.available()) rx.read();
  background(0);
  if (rx.width > 1) {
    // fit the frame in the window, keeping its proportions
    float s = min(width / (float) rx.width, height / (float) rx.height);
    imageMode(CENTER);
    image(rx, width / 2, height / 2, rx.width * s, rx.height * s);
    imageMode(CORNER);
  }
  if (frameCount % 60 == 0) sources = NDI.sources();
  drawInfo();
}

void drawInfo() {
  fill(0, 160);
  noStroke();
  rect(10, 10, 560, 50 + 20 * sources.length);
  fill(255);
  String state = rx.isConnected()
    ? rx.getSourceName() + "  " + rx.width + "x" + rx.height + " @ " + nf(rx.getFrameRate(), 0, 2)
    : "waiting for \"" + rx.getSource() + "\"...";
  text(state, 20, 30);
  text("Sources (press 1-9):", 20, 50);
  for (int i = 0; i < sources.length; i++) {
    fill(sources[i].equals(rx.getSourceName()) ? color(255, 200, 0) : 255);
    text((i + 1) + "  " + sources[i], 30, 70 + 20 * i);
  }
}

void keyPressed() {
  int i = key - '1';
  if (i >= 0 && i < sources.length) {
    rx.close();
    rx = new NDIReceiver(this, sources[i]);
  }
}
