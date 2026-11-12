/*
 * Processing-NDI - send Processing sketches over NDI(R).
 * https://github.com/ndev-itservices/processing-ndi-win-mac
 *
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 * NDI(R) is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
package processing.ndi;

import processing.core.PApplet;
import processing.core.PConstants;
import processing.core.PGraphics;
import processing.core.PImage;

/**
 * Publishes the sketch window, a PGraphics or any PImage as an NDI&reg; video source on the
 * local network, so it can be received by OBS, vMix, Resolume, TouchDesigner, NDI Tools, etc.
 *
 * <pre>
 * import processing.ndi.*;
 *
 * NDISender sender;
 *
 * void setup() {
 *   size(1280, 720, P2D);
 *   sender = new NDISender(this, "My Sketch");
 * }
 *
 * void draw() {
 *   background(0);
 *   circle(mouseX, mouseY, 80);
 *   sender.send();          // or sender.send(pg), or sender.setAutoSend(true) once in setup()
 * }
 * </pre>
 *
 * NDI&reg; is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
public class NDISender {

    /** Library version (same as prettyVersion in library.properties). */
    public static final String VERSION = "1.0.0";

    private final PApplet parent;
    private final String name;
    private long handle;
    private boolean autoSend = false;
    private boolean alpha = false;
    private boolean onlyWhenConnected = true;
    private int fpsN = 60000;
    private int fpsD = 1000;

    /** Creates a sender named after the sketch. */
    public NDISender(PApplet parent) {
        this(parent, null, null);
    }

    /**
     * Creates a sender. Receivers will list it as "COMPUTER-NAME (name)".
     *
     * @param parent the sketch, normally {@code this}
     * @param name   the NDI source name
     */
    public NDISender(PApplet parent, String name) {
        this(parent, name, null);
    }

    /**
     * Creates a sender that belongs to the given NDI groups (comma separated, null = default group).
     */
    public NDISender(PApplet parent, String name, String groups) {
        this.parent = parent;
        this.name = (name == null || name.trim().isEmpty()) ? sketchName(parent) : name;
        if (!NDINative.init()) {
            System.err.println("Processing-NDI: " + NDINative.error());
            System.err.println("Processing-NDI: the sketch keeps running, but nothing is sent over NDI.");
            handle = 0;
        } else {
            handle = NDINative.nCreate(this.name, groups, false);
            if (handle == 0) System.err.println("Processing-NDI: could not create the NDI sender \"" + this.name + "\"");
            NDI.banner();
        }
        if (parent != null) parent.registerMethod("dispose", this);
    }

    // ------------------------------------------------------------------ sending

    /** Sends the sketch window (call it at the end of draw()). */
    public synchronized void send() {
        if (!canSend()) return;
        parent.loadPixels();
        int w = parent.pixelWidth, h = parent.pixelHeight;
        sendPixels(parent.pixels, w, h, alpha);
    }

    /**
     * Sends a PGraphics (call it after endDraw()) or any PImage (an image, a Movie, a Capture...).
     */
    public synchronized void send(PImage img) {
        if (img == null || !canSend()) return;
        if (img == parent.g) {
            send();
            return;
        }
        img.loadPixels();
        if (img.pixels == null) return;
        // images without an alpha channel may have 0 in the alpha byte: never send those as transparent
        boolean a = alpha && img.format != PConstants.RGB;
        sendPixels(img.pixels, img.pixelWidth, img.pixelHeight, a);
    }

    /** Sends raw ARGB pixels (Processing's color format), width x height, row by row. */
    public synchronized void send(int[] pixels, int width, int height) {
        if (pixels == null || !canSend()) return;
        sendPixels(pixels, width, height, alpha);
    }

    private boolean canSend() {
        if (handle == 0) return false;
        return !onlyWhenConnected || NDINative.nConnections(handle, 0) > 0;
    }

    private void sendPixels(int[] px, int w, int h, boolean a) {
        if (w <= 0 || h <= 0 || px.length < w * h) return;
        NDINative.nSend(handle, px, 0, w, h, w, a, fpsN, fpsD);
    }

    // ------------------------------------------------------------------ options

    /**
     * When true the sketch window is sent automatically at the end of every draw(), so there is
     * no need to call send().
     */
    public synchronized void setAutoSend(boolean on) {
        if (on == autoSend || parent == null) return;
        autoSend = on;
        if (on) parent.registerMethod("draw", this);
        else parent.unregisterMethod("draw", this);
    }

    public boolean isAutoSend() {
        return autoSend;
    }

    /**
     * When true the alpha channel is sent (BGRA), so a transparent PGraphics stays transparent in
     * the receiver. When false (default) every pixel is sent opaque (BGRX).
     */
    public void setAlpha(boolean on) {
        alpha = on;
    }

    public boolean isAlpha() {
        return alpha;
    }

    /**
     * The frame rate announced to receivers (default 60). Use the same value as frameRate() in
     * setup(). Fractional rates such as 29.97 or 59.94 are allowed.
     */
    public void setFrameRate(float fps) {
        if (fps <= 0) return;
        fpsN = Math.round(fps * 1000f);
        fpsD = 1000;
    }

    public float getFrameRate() {
        return fpsN / (float) fpsD;
    }

    /**
     * When true (default) frames are only read back and sent while at least one receiver is
     * connected, which saves CPU/GPU time when nobody is watching.
     */
    public void setOnlyWhenConnected(boolean on) {
        onlyWhenConnected = on;
    }

    public boolean isOnlyWhenConnected() {
        return onlyWhenConnected;
    }

    // ------------------------------------------------------------------ information

    /** The name given to this sender. */
    public String getName() {
        return name;
    }

    /** The full NDI source name as receivers see it, e.g. "STUDIO-MAC (My Sketch)". */
    public synchronized String getSourceName() {
        if (handle == 0) return null;
        String s = NDINative.nSourceName(handle);
        return s != null ? s : name;
    }

    /** Number of receivers currently connected to this sender. */
    public synchronized int getConnections() {
        return handle == 0 ? 0 : NDINative.nConnections(handle, 0);
    }

    /** True when at least one receiver is connected. */
    public boolean hasConnections() {
        return getConnections() > 0;
    }

    /** True when the NDI runtime is loaded and this sender is open. */
    public boolean isReady() {
        return handle != 0;
    }

    /** Version of the NDI runtime in use, or an empty string when it is not available. */
    public static String ndiVersion() {
        return NDINative.init() ? NDINative.nVersion() : "";
    }

    // ------------------------------------------------------------------ lifecycle

    /** Stops sending and removes the source from the network (also done when the sketch stops). */
    public synchronized void close() {
        if (handle == 0) return;
        long h = handle;
        handle = 0;
        if (parent != null && autoSend) {
            parent.unregisterMethod("draw", this);
            autoSend = false;
        }
        NDINative.nDestroy(h);
    }

    /** Called by Processing at the end of each draw() while auto send is on. Do not call it. */
    public void draw() {
        if (autoSend) send();
    }

    /** Called by Processing when the sketch stops. Do not call it. */
    public void dispose() {
        close();
    }

    // ------------------------------------------------------------------ helpers

    private static String sketchName(PApplet p) {
        if (p == null) return "Processing";
        String n = p.getClass().getSimpleName();
        return n.isEmpty() ? "Processing" : n;
    }
}
