/**
 * NDI_1_Basic
 *
 * Sends the sketch window over NDI®. Open any NDI receiver on the same network
 * (OBS with DistroAV, vMix, Resolume, TouchDesigner, NDI Studio Monitor from
 * https://ndi.video/tools/) and pick "<this computer> (Processing NDI_1_Basic)".
 *
 * NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/
 * Processing-NDI by Tiago Martins
 */
import processing.ndi.*;

NDISender sender;

void setup() {
  size(1280, 720, P2D);
  frameRate(60);
  sender = new NDISender(this, "Processing NDI_1_Basic");
  sender.setFrameRate(60);   // tell the receivers the same rate as frameRate()
}

void draw() {
  background(20, 24, 40);
  noStroke();
  for (int i = 0; i < 12; i++) {
    float a = frameCount * 0.02 + i * TWO_PI / 12;
    fill(100 + 12 * i, 160, 255 - 15 * i);
    circle(width / 2 + cos(a) * 250, height / 2 + sin(a) * 250, 60);
  }
  fill(255, 200, 0);
  circle(mouseX, mouseY, 80);

  sender.send();   // send what has been drawn so far

  // drawn after send(): visible here but not in the NDI output
  fill(255);
  text("NDI source: " + sender.getSourceName() + "   receivers: " + sender.getConnections()
    + "   fps: " + nf(frameRate, 0, 1), 20, height - 20);
}
