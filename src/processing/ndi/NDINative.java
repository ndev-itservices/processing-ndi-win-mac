/*
 * Processing-NDI - send Processing sketches over NDI(R).
 * https://github.com/ndev-itservices/processing-ndi-win-mac
 *
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 * NDI(R) is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
package processing.ndi;

import java.io.File;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

/**
 * Native bridge (ProcessingNDI.dll / libProcessingNDI.dylib) and NDI runtime loader.
 * Not part of the public API.
 */
final class NDINative {

    static final String JNI_NAME = "ProcessingNDI";

    private static boolean attempted = false;
    private static boolean ready = false;
    private static String error = "";
    private static File nativeDir = null;

    private NDINative() {
    }

    /** Loads the JNI bridge and the NDI runtime once. Returns false (see {@link #error()}) on failure. */
    static synchronized boolean init() {
        if (attempted) return ready;
        attempted = true;
        List<String> errors = new ArrayList<String>();
        if (!loadBridge(errors)) {
            error = "cannot load the native library " + System.mapLibraryName(JNI_NAME) + " for " + variant()
                    + ":\n  " + String.join("\n  ", errors) + hint(String.join(" ", errors));
            return false;
        }
        String runtime = System.getProperty("ndi.runtime.path");
        if (runtime == null && nativeDir != null) runtime = nativeDir.getAbsolutePath();
        try {
            ready = nInit(runtime);
        } catch (UnsatisfiedLinkError e) {
            ready = false;
            error = "native library mismatch: " + e.getMessage();
            return false;
        }
        if (!ready) error = "cannot start the NDI runtime:\n  " + nError() + hint(nError());
        return ready;
    }

    static String error() {
        return error;
    }

    /** Plain-language advice for the most common installation problems. */
    private static String hint(String errors) {
        String folder = libraryFolder();
        if (errors.contains("system policy") || errors.contains("not valid for use in process")) {
            return "\n\nmacOS blocked the library because it was downloaded from the internet."
                    + "\nTo allow it, open the Terminal app, paste this line and press Enter, then run the sketch again:"
                    + "\n\n  xattr -dr com.apple.quarantine \"" + folder + "\"\n"
                    + "\n(see \"Installation\" in https://github.com/ndev-itservices/processing-ndi-win-mac)";
        }
        if (errors.contains("no ProcessingNDI") || errors.contains("Can't find")) {
            return "\n\nThe library files for this computer (" + variant() + ") are missing in " + folder
                    + "\nDownload ProcessingNDI.zip again from https://github.com/ndev-itservices/processing-ndi-win-mac";
        }
        return "";
    }

    private static String libraryFolder() {
        try {
            File jar = new File(NDINative.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            File lib = jar.isDirectory() ? jar : jar.getParentFile();
            return lib.getParentFile().getAbsolutePath();
        } catch (Exception e) {
            return "Documents/Processing/libraries/ProcessingNDI";
        }
    }

    private static boolean loadBridge(List<String> errors) {
        String explicit = System.getProperty("ndi.native.path");
        if (explicit != null && tryLoad(new File(explicit), errors)) return true;
        // Processing library layout: library/<variant>/ next to the jar
        try {
            URL src = NDINative.class.getProtectionDomain().getCodeSource().getLocation();
            File jar = new File(src.toURI());
            File libDir = jar.isDirectory() ? jar : jar.getParentFile();
            String name = System.mapLibraryName(JNI_NAME);
            String[] subs = {variant(), "", "macos-aarch64", "macos-x86_64", "windows-amd64"};
            for (String sub : subs) {
                File f = sub.isEmpty() ? new File(libDir, name) : new File(new File(libDir, sub), name);
                if (f.isFile() && tryLoad(f, errors)) return true;
            }
        } catch (Exception e) {
            errors.add("code source lookup: " + e);
        }
        // exported applications and custom setups: java.library.path
        try {
            System.loadLibrary(JNI_NAME);
            return true;
        } catch (UnsatisfiedLinkError e) {
            errors.add("System.loadLibrary(" + JNI_NAME + "): " + e.getMessage());
        }
        return false;
    }

    private static boolean tryLoad(File f, List<String> errors) {
        try {
            System.load(f.getAbsolutePath());
            nativeDir = f.getAbsoluteFile().getParentFile();
            return true;
        } catch (UnsatisfiedLinkError e) {
            errors.add(f + ": " + e.getMessage());
            return false;
        }
    }

    /** Processing 4 style platform variant, e.g. macos-aarch64. */
    static String variant() {
        String os = System.getProperty("os.name", "").toLowerCase();
        String arch = System.getProperty("os.arch", "").toLowerCase();
        String p = os.contains("mac") ? "macos" : os.contains("win") ? "windows" : "linux";
        String a = (arch.contains("aarch64") || arch.contains("arm64")) ? "aarch64"
                : (arch.contains("64") ? (p.equals("macos") ? "x86_64" : "amd64") : arch);
        return p + "-" + a;
    }

    static native boolean nInit(String runtimePath);

    static native String nError();

    static native String nRuntimePath();

    static native String nVersion();

    static native long nCreate(String name, String groups, boolean clockVideo);

    static native void nDestroy(long handle);

    static native void nSend(long handle, int[] pixels, int offset, int width, int height, int stride,
                             boolean alpha, int fpsN, int fpsD);

    static native void nFlush(long handle);

    static native int nConnections(long handle, int timeoutMs);

    static native String nSourceName(long handle);

    static native String[] nFindSources(int waitMs);

    static native long nRecvCreate(String filter, String receiverName, boolean lowBandwidth);

    static native void nRecvDestroy(long handle);

    static native void nRecvSetLowBandwidth(long handle, boolean low);

    static native long nRecvInfo(long handle, int[] info);

    static native long nRecvRead(long handle, int[] pixels, int width, int height);

    static native String nRecvSource(long handle);
}
