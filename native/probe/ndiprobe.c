/*
 * ndiprobe.c - small NDI(R) receiver used by the tests: finds a source whose name contains a
 * given text, receives video frames for a while and prints what it got.
 *
 * Usage: ndiprobe <name-substring> [seconds=5] [runtime-path]
 *        ndiprobe --send <name> [seconds=5] [width=640] [height=360] [runtime-path]
 *          sends a test pattern (0xFF336699 with a 64x64 0xFFFF0000 block at the top-left corner)
 *          at 60 fps, clocked by NDI, then prints "SENT frames=<n>"
 * Output (one line per check):
 *   SOURCE <full name>
 *   FRAME <w>x<h> fourcc=<BGRA|BGRX|...> fps=<N>/<D> stride=<bytes> center=0x<AARRGGBB> corner=0x<AARRGGBB>
 *   RESULT frames=<n> seconds=<s> fps=<measured>
 * If the environment variable NDIPROBE_DUMP names a file, the first frame is written there as a
 * 32-bit BMP (top-down, alpha kept).
 * Exit code: 0 = at least one frame received, 1 = source not found, 2 = no frames, 3 = runtime error.
 *
 * Part of Processing-NDI - https://github.com/ndev-itservices/processing-ndi-win-mac
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 */
#include <stdint.h>
#include <stdbool.h>
#include <time.h>
#include "../ndiload.h"

static double now_s(void) {
#ifdef _WIN32
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)f.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
#endif
}

static uint32_t px(const NDIlib_video_frame_v2_t* f, int x, int y) {
    const uint8_t* p = f->p_data + (size_t)f->line_stride_in_bytes * y + (size_t)x * 4;
    return ((uint32_t)p[3] << 24) | ((uint32_t)p[2] << 16) | ((uint32_t)p[1] << 8) | p[0];
}

static void dump_bmp(const char* path, const NDIlib_video_frame_v2_t* f) {
    FILE* o = fopen(path, "wb");
    if (!o) return;
    uint32_t row = (uint32_t)f->xres * 4, img = row * (uint32_t)f->yres;
    uint8_t h[54] = { 'B', 'M' };
    uint32_t v[] = { 54 + img, 0, 54, 40 };
    memcpy(h + 2, v, sizeof v);
    int32_t w = f->xres, ht = -f->yres; /* negative height = top-down rows */
    memcpy(h + 18, &w, 4);
    memcpy(h + 22, &ht, 4);
    h[26] = 1; h[28] = 32;
    memcpy(h + 34, &img, 4);
    fwrite(h, 1, sizeof h, o);
    for (int y = 0; y < f->yres; y++) fwrite(f->p_data + (size_t)f->line_stride_in_bytes * y, 1, row, o);
    fclose(o);
}

static int send_mode(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage: ndiprobe --send <name> [seconds] [width] [height] [runtime-path]\n"); return 3; }
    const char* name = argv[2];
    double secs = argc > 3 ? atof(argv[3]) : 5.0;
    int w = argc > 4 ? atoi(argv[4]) : 640, h = argc > 5 ? atoi(argv[5]) : 360;
    if (w <= 0 || h <= 0) { fprintf(stderr, "invalid size %s x %s\n", argc > 4 ? argv[4] : "", argc > 5 ? argv[5] : ""); return 3; }
    const NDIlib_v6* ndi = ndi_load(argc > 6 ? argv[6] : NULL);
    if (!ndi) { fprintf(stderr, "cannot load the NDI runtime:\n  %s\n", nl_error); return 3; }
    if (!ndi->initialize()) { fprintf(stderr, "NDIlib_initialize failed\n"); return 3; }
    NDIlib_send_create_t cs;
    memset(&cs, 0, sizeof cs);
    cs.p_ndi_name = name;
    cs.clock_video = true;
    NDIlib_send_instance_t snd = ndi->send_create(&cs);
    if (!snd) { fprintf(stderr, "send_create failed\n"); return 3; }
    uint32_t* px = (uint32_t*)malloc((size_t)w * h * 4);
    for (int i = 0; i < w * h; i++) px[i] = 0xFF336699u;
    for (int y = 0; y < 64 && y < h; y++) for (int x = 0; x < 64 && x < w; x++) px[y * w + x] = 0xFFFF0000u;
    const NDIlib_source_t* sn = ndi->send_get_source_name(snd);
    printf("SENDING %s %dx%d\n", sn && sn->p_ndi_name ? sn->p_ndi_name : name, w, h);
    fflush(stdout);
    NDIlib_video_frame_v2_t f;
    memset(&f, 0, sizeof f);
    f.xres = w; f.yres = h;
    f.FourCC = NDIlib_FourCC_video_type_BGRX;
    f.frame_rate_N = 60000; f.frame_rate_D = 1000;
    f.frame_format_type = NDIlib_frame_format_type_progressive;
    f.timecode = NDIlib_send_timecode_synthesize;
    f.p_data = (uint8_t*)px;
    f.line_stride_in_bytes = w * 4;
    int frames = 0;
    double t0 = now_s();
    while (now_s() - t0 < secs) {
        px[(h - 1) * w + (frames % w)] ^= 0x00FFFFFFu;
        ndi->send_send_video_v2(snd, &f);   /* clocked: blocks to keep 60 fps */
        frames++;
    }
    printf("SENT frames=%d\n", frames);
    ndi->send_destroy(snd);
    free(px);
    ndi->destroy();
    return 0;
}

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "--send") == 0) return send_mode(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: ndiprobe <name-substring> [seconds] [runtime-path]\n"); return 3; }
    const char* want = argv[1];
    double secs = argc > 2 ? atof(argv[2]) : 5.0;
    const NDIlib_v6* ndi = ndi_load(argc > 3 ? argv[3] : NULL);
    if (!ndi) { fprintf(stderr, "cannot load the NDI runtime:\n  %s\n", nl_error); return 3; }
    if (!ndi->initialize()) { fprintf(stderr, "NDIlib_initialize failed\n"); return 3; }
    printf("RUNTIME %s %s\n", ndi->version(), nl_loaded_path);
    fflush(stdout);

    NDIlib_find_create_t fc;
    memset(&fc, 0, sizeof fc);
    fc.show_local_sources = true;
    NDIlib_find_instance_t find = ndi->find_create_v2(&fc);
    if (!find) { fprintf(stderr, "find_create failed\n"); return 3; }

    NDIlib_source_t src;
    bool found = false;
    char name[512] = "";
    double t0 = now_s();
    while (!found && now_s() - t0 < secs) {
        ndi->find_wait_for_sources(find, 500);
        uint32_t n = 0;
        const NDIlib_source_t* list = ndi->find_get_current_sources(find, &n);
        for (uint32_t i = 0; i < n; i++) {
            if (list[i].p_ndi_name && strstr(list[i].p_ndi_name, want)) {
                snprintf(name, sizeof name, "%s", list[i].p_ndi_name);
                src = list[i];
                found = true;
                break;
            }
        }
    }
    if (!found) {
        printf("RESULT source-not-found\n");
        ndi->find_destroy(find);
        return 1;
    }
    printf("SOURCE %s\n", name);
    fflush(stdout);

    NDIlib_recv_create_v3_t rc;
    memset(&rc, 0, sizeof rc);
    rc.source_to_connect_to = src;
    rc.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    rc.bandwidth = NDIlib_recv_bandwidth_highest;
    rc.allow_video_fields = false;
    rc.p_ndi_recv_name = "ndiprobe";
    NDIlib_recv_instance_t recv = ndi->recv_create_v3(&rc);
    ndi->find_destroy(find); /* src strings are copied by recv_create */
    if (!recv) { fprintf(stderr, "recv_create failed\n"); return 3; }

    int frames = 0;
    double first = 0, last = 0;
    t0 = now_s();
    while (now_s() - t0 < secs) {
        NDIlib_video_frame_v2_t v;
        NDIlib_frame_type_e t = ndi->recv_capture_v2(recv, &v, NULL, NULL, 500);
        if (t != NDIlib_frame_type_video) continue;
        last = now_s();
        if (frames == 0) first = last;
        if (frames == 0 && getenv("NDIPROBE_DUMP")) dump_bmp(getenv("NDIPROBE_DUMP"), &v);
        if (frames == 0 || frames % 60 == 0) {
            char cc[5] = { (char)(v.FourCC & 0xff), (char)((v.FourCC >> 8) & 0xff), (char)((v.FourCC >> 16) & 0xff),
                           (char)((v.FourCC >> 24) & 0xff), 0 };
            printf("FRAME %dx%d fourcc=%s fps=%d/%d stride=%d center=0x%08X corner=0x%08X\n", v.xres, v.yres, cc,
                   v.frame_rate_N, v.frame_rate_D, v.line_stride_in_bytes, px(&v, v.xres / 2, v.yres / 2), px(&v, 0, 0));
            fflush(stdout);
        }
        frames++;
        ndi->recv_free_video_v2(recv, &v);
    }
    double span = last - first;
    printf("RESULT frames=%d seconds=%.2f fps=%.1f\n", frames, span, frames > 1 && span > 0 ? (frames - 1) / span : 0.0);
    ndi->recv_destroy(recv);
    ndi->destroy();
    return frames > 0 ? 0 : 2;
}
