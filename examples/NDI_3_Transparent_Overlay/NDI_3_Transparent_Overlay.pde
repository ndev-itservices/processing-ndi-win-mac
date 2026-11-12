/**
 * NDI_3_Transparent_Overlay
 *
 * Sends a PGraphics with a transparent background (BGRA), e.g. a lower third or
 * a score board to put on top of a camera in OBS or vMix. The window shows the
 * overlay on a checkerboard so you can see what is transparent.
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

NDISender sender;
PGraphics overlay;

void setup() {
  size(1280, 720, P2D);
  overlay = createGraphics(1920, 1080, P2D);   // the NDI output can be bigger than the window
  sender = new NDISender(this, "Processing Overlay");
  sender.setAlpha(true);                       // keep transparency
}

void draw() {
  overlay.beginDraw();
  overlay.clear();                             // fully transparent
  overlay.noStroke();
  overlay.fill(10, 30, 80, 220);
  overlay.rect(80, 860, 900, 140, 12);
  overlay.fill(255, 180, 0);
  overlay.rect(80, 860, 16, 140);
  overlay.fill(255);
  overlay.textSize(56);
  overlay.text("Processing-NDI", 130, 925);
  overlay.textSize(32);
  overlay.text("live overlay " + nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2), 130, 975);
  overlay.endDraw();

  sender.send(overlay);

  // preview
  checkerboard();
  image(overlay, 0, 0, width, height);
}

void checkerboard() {
  noStroke();
  for (int y = 0; y < height; y += 40) {
    for (int x = 0; x < width; x += 40) {
      fill(((x + y) / 40) % 2 == 0 ? 200 : 160);
      rect(x, y, 40, 40);
    }
  }
}
