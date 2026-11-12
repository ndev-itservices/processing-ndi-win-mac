/*
 * SenderTest - headless NDI sender used by scripts/run_tests.*: publishes a test pattern
 * as "PNDI-Test" for a number of seconds.
 *   java ... SenderTest [seconds=8] [alpha] [idle]
 *   alpha: send BGRA with a semi-transparent corner; idle: keep setOnlyWhenConnected(true)
 * Pattern: a 64x64 block at the top-left corner = 0x80FF0000, everything else = 0xFF336699
 * (blocks, because NDI compression is lossy at pixel level).
 * Author: Tiago Martins
 */
import processing.ndi.NDISender;

public class SenderTest {
    public static void main(String[] args) throws Exception {
        double secs = args.length > 0 ? Double.parseDouble(args[0]) : 8;
        boolean alpha = false, idle = false;
        for (String a : args) { if (a.equals("alpha")) alpha = true; if (a.equals("idle")) idle = true; }
        int w = 640, h = 360;
        int[] px = new int[w * h];
        java.util.Arrays.fill(px, 0xFF336699);
        for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) px[y * w + x] = 0x80FF0000;
        NDISender s = new NDISender(null, "PNDI-Test");
        if (!s.isReady()) { System.out.println("SENDER not ready"); System.exit(2); }
        s.setAlpha(alpha);
        s.setOnlyWhenConnected(idle);
        s.setFrameRate(60);
        System.out.println("SENDER " + s.getSourceName() + " ndi=" + NDISender.ndiVersion());
        long end = System.nanoTime() + (long) (secs * 1e9);
        int frames = 0, maxConn = 0;
        while (System.nanoTime() < end) {
            px[(h - 1) * w + (frames % w)] ^= 0x00FFFFFF;   // animate the bottom row so frames differ
            s.send(px, w, h);
            frames++;
            maxConn = Math.max(maxConn, s.getConnections());
            Thread.sleep(16);
        }
        s.close();
        s.send(px, w, h);   // must be a harmless no-op after close()
        System.out.println("SENT frames=" + frames + " maxConnections=" + maxConn);
    }
}
