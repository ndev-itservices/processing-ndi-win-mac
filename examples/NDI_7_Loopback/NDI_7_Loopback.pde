/**
 * NDI_7_Loopback
 *
 * Sends a PGraphics over NDI® and receives it back in the same sketch: left the
 * original, right what came through the network. Useful to check that NDI works
 * on this computer and to see the latency and the compression.
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

PGraphics pg;
NDISender sender;
NDIReceiver rx;

void setup() {
  size(1280, 400, P2D);
  pg = createGraphics(640, 360, P2D);
  sender = new NDISender(this, "Loopback");
  rx = new NDIReceiver(this, "Loopback");
}

void draw() {
  pg.beginDraw();
  pg.background(20, 30, 60);
  pg.fill(255, 200, 0);
  pg.noStroke();
  pg.circle(pg.width / 2 + sin(frameCount * 0.05) * 250, pg.height / 2, 80);
  pg.fill(255);
  pg.textSize(28);
  pg.text("frame " + frameCount, 20, 40);
  pg.endDraw();
  sender.send(pg);

  if (rx.available()) rx.read();

  background(0);
  image(pg, 0, 0);
  if (rx.width > 1) image(rx, 640, 0);
  fill(255);
  text("original", 10, 385);
  text(rx.isConnected() ? "received: " + rx.getSourceName() : "connecting...", 650, 385);
}
