/**
 * NDI_2_AutoSend
 *
 * With setAutoSend(true) the whole window is sent at the end of every draw(),
 * so an existing sketch only needs two lines in setup(). Works with the default
 * renderer (JAVA2D) as well as P2D and P3D.
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

void setup() {
  size(800, 600);
  NDISender sender = new NDISender(this, "Processing NDI_2_AutoSend");
  sender.setAutoSend(true);
  background(255);
}

void draw() {
  // a simple paint program: drag the mouse to draw, press any key to clear
  if (mousePressed) {
    stroke(0, 80);
    strokeWeight(8);
    line(pmouseX, pmouseY, mouseX, mouseY);
  }
}

void keyPressed() {
  background(255);
}
