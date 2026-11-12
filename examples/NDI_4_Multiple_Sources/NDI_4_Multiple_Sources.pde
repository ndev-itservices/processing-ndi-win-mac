/**
 * NDI_4_Multiple_Sources
 *
 * One sketch can publish several NDI® sources: here the window and two separate
 * PGraphics layers, each one with its own name.
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

NDISender main, layerA, layerB;
PGraphics a, b;

void setup() {
  size(960, 540, P2D);
  a = createGraphics(640, 360, P2D);
  b = createGraphics(640, 360, P2D);
  main = new NDISender(this, "Multi - Window");
  layerA = new NDISender(this, "Multi - Layer A");
  layerB = new NDISender(this, "Multi - Layer B");
}

void draw() {
  a.beginDraw();
  a.background(200, 40, 60);
  a.fill(255);
  a.circle(a.width / 2 + sin(frameCount * 0.05) * 200, a.height / 2, 120);
  a.endDraw();

  b.beginDraw();
  b.background(30, 120, 200);
  b.fill(255);
  b.rectMode(CENTER);
  b.translate(b.width / 2, b.height / 2);
  b.rotate(frameCount * 0.03);
  b.rect(0, 0, 160, 160);
  b.endDraw();

  background(0);
  image(a, 0, 0, width / 2, height / 2);
  image(b, width / 2, 0, width / 2, height / 2);
  fill(255);
  text("Window: " + main.getConnections() + " receivers\nLayer A: " + layerA.getConnections()
    + "\nLayer B: " + layerB.getConnections(), 20, height / 2 + 40);

  layerA.send(a);
  layerB.send(b);
  main.send();
}
