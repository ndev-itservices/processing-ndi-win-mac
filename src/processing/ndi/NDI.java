/*
 * Processing-NDI - send and receive Processing sketches over NDI(R).
 * https://github.com/ndev-itservices/processing-ndi-win-mac
 *
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 * NDI(R) is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
package processing.ndi;

/**
 * NDI&reg; helpers: discovery of the sources available on the network.
 *
 * <pre>
 * String[] sources = NDI.sources();
 * printArray(sources);     // e.g. "STUDIO-PC (OBS)", "MACBOOK.LOCAL (Processing NDI_1_Basic)"
 * </pre>
 *
 * NDI&reg; is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
public final class NDI {

    private static boolean firstLookup = true;

    private NDI() {
    }

    /**
     * Names of the NDI sources currently visible on the network. The first call waits up to one
     * second so that discovery has time to find them; later calls return immediately.
     */
    public static String[] sources() {
        int wait;
        synchronized (NDI.class) {
            wait = firstLookup ? 1000 : 0;
            firstLookup = false;
        }
        return sources(wait);
    }

    /** Names of the NDI sources, waiting up to waitMillis for a change in the list. */
    public static String[] sources(int waitMillis) {
        if (!NDINative.init()) {
            System.err.println("Processing-NDI: " + NDINative.error());
            return new String[0];
        }
        String[] s = NDINative.nFindSources(Math.max(0, waitMillis));
        java.util.Arrays.sort(s, String.CASE_INSENSITIVE_ORDER);
        return s;
    }

    /** Version of the NDI runtime in use, or an empty string when it is not available. */
    public static String version() {
        return NDINative.init() ? NDINative.nVersion() : "";
    }

    /** Version of this library. */
    public static String libraryVersion() {
        return NDISender.VERSION;
    }

    static synchronized void banner() {
        if (bannerShown) return;
        bannerShown = true;
        System.out.println("Processing-NDI " + NDISender.VERSION + " by Tiago Martins - NDI runtime " + NDINative.nVersion());
        System.out.println("NDI® is a registered trademark of Vizrt NDI AB - https://ndi.video/");
    }

    private static boolean bannerShown = false;
}
