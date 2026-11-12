/*
 * ReceiverTest - headless NDIReceiver test used by scripts/run_tests.*.
 *   java ... ReceiverTest <seconds> <source> [<source> ...] [--low] [--loopback] [--alpha]
 * One NDIReceiver per <source>. With --loopback the test also publishes each <source> itself
 * with an NDISender (same pattern as SenderTest; --alpha sends BGRA).
 * Prints a STATUS line per receiver every second and a FINAL line per receiver at the end:
 *   FINAL RX<i> source=<full name> size=<w>x<h> format=<ARGB|RGB> frames=<received> reads=<read()>
 *         center=0x<AARRGGBB> corner=0x<AARRGGBB> connected=<bool> listed=<bool>
 * Author: Tiago Martins
 */
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import processing.core.PConstants;
import processing.ndi.NDI;
import processing.ndi.NDIReceiver;
import processing.ndi.NDISender;

public class ReceiverTest {
    public static void main(String[] args) throws Exception {
        double secs = Double.parseDouble(args[0]);
        boolean low = false, loopback = false, alpha = false;
        List<String> names = new ArrayList<String>();
        for (int i = 1; i < args.length; i++) {
            if (args[i].equals("--low")) low = true;
            else if (args[i].equals("--loopback")) loopback = true;
            else if (args[i].equals("--alpha")) alpha = true;
            else names.add(args[i]);
        }
        int n = names.size();
        NDISender[] tx = new NDISender[loopback ? n : 0];
        int w = 640, h = 360;
        int[] px = new int[w * h];
        Arrays.fill(px, 0xFF336699);
        for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) px[y * w + x] = alpha ? 0x80FF0000 : 0xFFFF0000;
        for (int i = 0; i < tx.length; i++) {
            tx[i] = new NDISender(null, names.get(i));
            tx[i].setAlpha(alpha);
            tx[i].setOnlyWhenConnected(false);
        }
        NDIReceiver[] rx = new NDIReceiver[n];
        int[] reads = new int[n];
        for (int i = 0; i < n; i++) rx[i] = new NDIReceiver(null, names.get(i), low);
        System.out.println("NDI " + NDI.version());

        long start = System.nanoTime(), nextStatus = start;
        int frame = 0;
        while (System.nanoTime() - start < secs * 1e9) {
            if (tx.length > 0) {
                px[(h - 1) * w + (frame++ % w)] ^= 0x00FFFFFF;
                for (NDISender s : tx) s.send(px, w, h);
            }
            for (int i = 0; i < n; i++) if (rx[i].available() && rx[i].read()) reads[i]++;
            if (System.nanoTime() >= nextStatus) {
                nextStatus += 1_000_000_000L;
                long t = Math.round((System.nanoTime() - start) / 1e9);
                for (int i = 0; i < n; i++) System.out.println("STATUS t=" + t + " " + describe(i, rx[i], reads[i]));
            }
            Thread.sleep(16);
        }
        List<String> listed = Arrays.asList(NDI.sources(0));
        for (int i = 0; i < n; i++) {
            String src = rx[i].getSourceName();
            System.out.println("FINAL " + describe(i, rx[i], reads[i]) + " listed=" + (src != null && listed.contains(src)));
        }
        for (NDIReceiver r : rx) r.close();
        for (NDIReceiver r : rx) r.read();   // harmless after close()
        for (NDISender s : tx) s.close();
        System.out.println("SOURCES " + listed);
    }

    static String describe(int i, NDIReceiver r, int reads) {
        String c = "0x00000000", k = "0x00000000";
        if (r.pixels != null && r.pixelWidth > 1) {
            c = String.format("0x%08X", r.pixels[(r.pixelHeight / 2) * r.pixelWidth + r.pixelWidth / 2]);
            k = String.format("0x%08X", r.pixels[r.pixelWidth * 8 + 8]);
        }
        return "RX" + i + " source=" + String.valueOf(r.getSourceName()).replace(' ', '_') + " size=" + r.pixelWidth + "x" + r.pixelHeight
                + " format=" + (r.format == PConstants.ARGB ? "ARGB" : "RGB") + " frames=" + r.getFrameCount() + " reads=" + reads
                + " fps=" + r.getFrameRate() + " center=" + c + " corner=" + k + " connected=" + r.isConnected();
    }
}
