/*
 * Processing-NDI - send and receive Processing sketches over NDI(R).
 * https://github.com/ndev-itservices/processing-ndi-win-mac
 *
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 * NDI(R) is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
package processing.ndi;

import processing.core.PApplet;
import processing.core.PConstants;
import processing.core.PImage;

/**
 * Receives an NDI&reg; video source. Like Movie and Capture it is a PImage: call read() when
 * available() is true and draw it with image().
 *
 * <pre>
 * import processing.ndi.*;
 *
 * NDIReceiver rx;
 *
 * void setup() {
 *   size(1280, 720, P2D);
 *   printArray(NDI.sources());
 *   rx = new NDIReceiver(this, "OBS");   // the name, or part of it
 * }
 *
 * void draw() {
 *   if (rx.available()) rx.read();
 *   image(rx, 0, 0, width, height);
 * }
 * </pre>
 *
 * Frames are received on a background thread, so draw() never waits for the network. When the
 * source is not on the network yet, or goes away, the receiver keeps looking for it and
 * reconnects by itself.
 *
 * NDI&reg; is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
public class NDIReceiver extends PImage {

    private final String source;
    private long handle;
    private long lastRead = 0;
    private final int[] info = new int[6];
    private boolean lowBandwidth;

    /** Receives the first NDI source found on the network. */
    public NDIReceiver(PApplet parent) {
        this(parent, null, false);
    }

    /**
     * Receives the source whose name matches {@code source}: the full name ("STUDIO-PC (OBS)"),
     * the name between brackets ("OBS"), or any part of it, ignoring upper/lower case. An exact
     * match wins over a partial one.
     */
    public NDIReceiver(PApplet parent, String source) {
        this(parent, source, false);
    }

    /**
     * Like {@link #NDIReceiver(PApplet, String)}; with {@code lowBandwidth} true the low
     * resolution preview stream is received (about 640 pixels wide), which is much lighter
     * when showing many sources at once.
     */
    public NDIReceiver(PApplet parent, String source, boolean lowBandwidth) {
        super(1, 1, PConstants.ARGB);   // a transparent pixel until the first frame arrives
        this.parent = parent;
        this.source = source == null ? "" : source.trim();
        this.lowBandwidth = lowBandwidth;
        if (!NDINative.init()) {
            System.err.println("Processing-NDI: " + NDINative.error());
            System.err.println("Processing-NDI: the sketch keeps running, but nothing is received over NDI.");
            handle = 0;
        } else {
            handle = NDINative.nRecvCreate(this.source, receiverName(parent), lowBandwidth);
            if (handle == 0) System.err.println("Processing-NDI: could not create the NDI receiver for \"" + this.source + "\"");
            NDI.banner();
        }
        if (parent != null) parent.registerMethod("dispose", this);
    }

    // ------------------------------------------------------------------ frames

    /** True when a frame newer than the last one read is waiting. */
    public boolean available() {
        return handle != 0 && NDINative.nRecvInfo(handle, null) > lastRead;
    }

    /**
     * Copies the newest frame into this image. The size follows the source (width, height
     * change when the source changes resolution). Returns true when a new frame was read.
     */
    public synchronized boolean read() {
        if (handle == 0) return false;
        for (int attempt = 0; attempt < 3; attempt++) {
            long n = NDINative.nRecvInfo(handle, info);
            int w = info[0], h = info[1];
            if (n <= lastRead || w <= 0 || h <= 0) return false;
            int fmt = info[2] != 0 ? PConstants.ARGB : PConstants.RGB;
            if (w != pixelWidth || h != pixelHeight || pixels == null || pixels.length != w * h) {
                // new size: drop the renderer's cached texture of the old one
                if (parent != null && parent.g != null) parent.g.removeCache(this);
                init(w, h, fmt);
            } else {
                format = fmt;
            }
            long got = NDINative.nRecvRead(handle, pixels, w, h);
            if (got < 0) continue;   // the size changed meanwhile: read the info again
            lastRead = got;
            updatePixels();
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ options

    /**
     * Switches between the full quality stream (false, default) and the low resolution preview
     * stream (true). The receiver reconnects to apply it.
     */
    public synchronized void setLowBandwidth(boolean low) {
        lowBandwidth = low;
        if (handle != 0) NDINative.nRecvSetLowBandwidth(handle, low);
    }

    public boolean isLowBandwidth() {
        return lowBandwidth;
    }

    // ------------------------------------------------------------------ information

    /** The name (or part of it) this receiver looks for; empty = the first source found. */
    public String getSource() {
        return source;
    }

    /** Full name of the source this receiver is attached to, e.g. "STUDIO-PC (OBS)", or null. */
    public String getSourceName() {
        return handle == 0 ? null : NDINative.nRecvSource(handle);
    }

    /** True while frames are arriving (at least one during the last two seconds). */
    public boolean isConnected() {
        if (handle == 0) return false;
        int[] i = new int[6];
        NDINative.nRecvInfo(handle, i);
        return i[3] != 0;
    }

    /** Frame rate announced by the source (e.g. 60, 29.97), or 0 before the first frame. */
    public float getFrameRate() {
        if (handle == 0) return 0;
        int[] i = new int[6];
        NDINative.nRecvInfo(handle, i);
        return i[5] > 0 ? i[4] / (float) i[5] : 0;
    }

    /** Number of frames received from the network since this receiver was created. */
    public long getFrameCount() {
        return handle == 0 ? 0 : NDINative.nRecvInfo(handle, null);
    }

    /** True when the NDI runtime is loaded and this receiver is open. */
    public boolean isReady() {
        return handle != 0;
    }

    // ------------------------------------------------------------------ lifecycle

    /** Stops receiving (also done when the sketch stops). The last frame stays in the image. */
    public synchronized void close() {
        if (handle == 0) return;
        long h = handle;
        handle = 0;
        NDINative.nRecvDestroy(h);
    }

    /** Called by Processing when the sketch stops. Do not call it. */
    public void dispose() {
        close();
    }

    private static String receiverName(PApplet p) {
        String n = p == null ? "" : p.getClass().getSimpleName();
        return n.isEmpty() ? "Processing-NDI" : n;
    }
}
