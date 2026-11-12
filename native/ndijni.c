/*
 * ndijni.c - JNI bridge between processing.ndi.NDINative (Java) and the NDI(R) runtime.
 *
 * Part of Processing-NDI - https://github.com/ndev-itservices/processing-ndi-win-mac
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 * NDI(R) is a registered trademark of Vizrt NDI AB - https://ndi.video/
 *
 * Design
 * ------
 *  - The NDI runtime is loaded at run time (ndiload.h), normally from the folder of this
 *    library, so the Processing library works without installing anything else.
 *  - Processing pixels are ints 0xAARRGGBB; on little-endian machines (all supported
 *    platforms) their bytes are B,G,R,A in memory, which is exactly NDI's BGRA/BGRX layout.
 *  - Frames are copied into one of two native buffers and sent with
 *    NDIlib_send_send_video_async_v2, so colour conversion, compression and networking run
 *    on NDI's threads. Sending frame N+1 releases frame N's buffer (NDI synchronising event),
 *    so two buffers are enough.
 *  - Receiving: one shared NDI finder (discovery) and one thread per receiver. The thread finds
 *    the source by name, receives BGRX/BGRA frames into a native buffer and reconnects when the
 *    source disappears; Java copies the latest frame into the PImage pixels with nRecvRead().
 */

#include <jni.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include "ndiload.h"

/* ------------------------------------------------------------------------- */
/* Portability: threads, mutex, sleep, clock                                 */

#ifdef _WIN32
typedef HANDLE pn_thread_t;
typedef CRITICAL_SECTION pn_mutex_t;
static void pn_mutex_init(pn_mutex_t* m) { InitializeCriticalSection(m); }
static void pn_mutex_destroy(pn_mutex_t* m) { DeleteCriticalSection(m); }
static void pn_lock(pn_mutex_t* m) { EnterCriticalSection(m); }
static void pn_unlock(pn_mutex_t* m) { LeaveCriticalSection(m); }
static void pn_sleep_ms(int ms) { Sleep((DWORD)ms); }
static int64_t pn_now_ms(void) { return (int64_t)GetTickCount64(); }
typedef DWORD(WINAPI* pn_thread_fn)(LPVOID);
static int pn_thread_create(pn_thread_t* t, pn_thread_fn fn, void* arg) { *t = CreateThread(NULL, 0, fn, arg, 0, NULL); return *t ? 0 : -1; }
static void pn_thread_join(pn_thread_t t) { WaitForSingleObject(t, INFINITE); CloseHandle(t); }
#  define PN_THREAD_RET DWORD WINAPI
#  define PN_THREAD_RETURN return 0
#else
#  include <pthread.h>
#  include <unistd.h>
#  include <time.h>
typedef pthread_t pn_thread_t;
typedef pthread_mutex_t pn_mutex_t;
static void pn_mutex_init(pn_mutex_t* m) { pthread_mutex_init(m, NULL); }
static void pn_mutex_destroy(pn_mutex_t* m) { pthread_mutex_destroy(m); }
static void pn_lock(pn_mutex_t* m) { pthread_mutex_lock(m); }
static void pn_unlock(pn_mutex_t* m) { pthread_mutex_unlock(m); }
static void pn_sleep_ms(int ms) { usleep((useconds_t)ms * 1000); }
static int64_t pn_now_ms(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000; }
typedef void* (*pn_thread_fn)(void*);
static int pn_thread_create(pn_thread_t* t, pn_thread_fn fn, void* arg) { return pthread_create(t, NULL, fn, arg); }
static void pn_thread_join(pn_thread_t t) { pthread_join(t, NULL); }
#  define PN_THREAD_RET void*
#  define PN_THREAD_RETURN return NULL
#endif

typedef struct {
    NDIlib_send_instance_t inst;
    uint8_t* buf[2];
    size_t cap[2];
    int next;
    bool pending;   /* an async frame is still owned by NDI */
} sender_t;

static bool g_initialized = false;
static void find_global_init(void);

static void throw_ex(JNIEnv* env, const char* cls, const char* msg) {
    jclass c = (*env)->FindClass(env, cls);
    if (c) (*env)->ThrowNew(env, c, msg);
}

static void flush(sender_t* s) {
    if (s->pending) {
        nl_api->send_send_video_v2(s->inst, NULL);
        s->pending = false;
    }
}

/* boolean nInit(String runtimePath) */
JNIEXPORT jboolean JNICALL Java_processing_ndi_NDINative_nInit(JNIEnv* env, jclass cls, jstring jpath) {
    (void)cls;
    if (g_initialized) return JNI_TRUE;
    const char* path = jpath ? (*env)->GetStringUTFChars(env, jpath, NULL) : NULL;
    const NDIlib_v6* api = ndi_load(path);
    if (path) (*env)->ReleaseStringUTFChars(env, jpath, path);
    if (!api) return JNI_FALSE;
    if (!api->is_supported_CPU()) {
        snprintf(nl_error, sizeof nl_error, "this CPU is not supported by NDI (SSSE3 or NEON required)");
        return JNI_FALSE;
    }
    if (!api->initialize()) {
        snprintf(nl_error, sizeof nl_error, "NDIlib_initialize() failed");
        return JNI_FALSE;
    }
    find_global_init();
    g_initialized = true;
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL Java_processing_ndi_NDINative_nError(JNIEnv* env, jclass cls) {
    (void)cls;
    return (*env)->NewStringUTF(env, nl_error);
}

JNIEXPORT jstring JNICALL Java_processing_ndi_NDINative_nRuntimePath(JNIEnv* env, jclass cls) {
    (void)cls;
    return (*env)->NewStringUTF(env, nl_loaded_path);
}

JNIEXPORT jstring JNICALL Java_processing_ndi_NDINative_nVersion(JNIEnv* env, jclass cls) {
    (void)cls;
    return (*env)->NewStringUTF(env, g_initialized ? nl_api->version() : "");
}

/* long nCreate(String name, String groups, boolean clockVideo) */
JNIEXPORT jlong JNICALL Java_processing_ndi_NDINative_nCreate(JNIEnv* env, jclass cls, jstring jname, jstring jgroups,
                                                              jboolean clock) {
    (void)cls;
    if (!g_initialized) { throw_ex(env, "java/lang/IllegalStateException", "NDI runtime not initialised"); return 0; }
    const char* name = jname ? (*env)->GetStringUTFChars(env, jname, NULL) : NULL;
    const char* groups = jgroups ? (*env)->GetStringUTFChars(env, jgroups, NULL) : NULL;
    NDIlib_send_create_t cs;
    memset(&cs, 0, sizeof cs);
    cs.p_ndi_name = name;
    cs.p_groups = groups;
    cs.clock_video = clock ? true : false;
    cs.clock_audio = false;
    NDIlib_send_instance_t inst = nl_api->send_create(&cs);
    if (name) (*env)->ReleaseStringUTFChars(env, jname, name);
    if (groups) (*env)->ReleaseStringUTFChars(env, jgroups, groups);
    if (!inst) return 0;
    sender_t* s = (sender_t*)calloc(1, sizeof *s);
    if (!s) { nl_api->send_destroy(inst); return 0; }
    s->inst = inst;
    return (jlong)(intptr_t)s;
}

JNIEXPORT void JNICALL Java_processing_ndi_NDINative_nDestroy(JNIEnv* env, jclass cls, jlong h) {
    (void)env; (void)cls;
    sender_t* s = (sender_t*)(intptr_t)h;
    if (!s) return;
    flush(s);
    nl_api->send_destroy(s->inst);
    free(s->buf[0]);
    free(s->buf[1]);
    free(s);
}

/* void nSend(long h, int[] pixels, int offset, int width, int height, int stride, boolean alpha, int fpsN, int fpsD)
 * stride is in pixels (ints). */
JNIEXPORT void JNICALL Java_processing_ndi_NDINative_nSend(JNIEnv* env, jclass cls, jlong h, jintArray jpx, jint offset,
                                                           jint w, jint hgt, jint stride, jboolean alpha, jint fpsN,
                                                           jint fpsD) {
    (void)cls;
    sender_t* s = (sender_t*)(intptr_t)h;
    if (!s || !jpx || w <= 0 || hgt <= 0) return;
    if (stride < w) stride = w;
    jsize len = (*env)->GetArrayLength(env, jpx);
    if (offset < 0 || (int64_t)offset + (int64_t)stride * (hgt - 1) + w > (int64_t)len) {
        throw_ex(env, "java/lang/ArrayIndexOutOfBoundsException", "pixel array is smaller than width x height");
        return;
    }
    size_t row = (size_t)w * 4;
    size_t need = row * (size_t)hgt;
    int i = s->next;
    if (s->cap[i] < need) {
        /* this buffer is not in flight (only the other one can be), so it can be reallocated */
        uint8_t* nb = (uint8_t*)realloc(s->buf[i], need);
        if (!nb) { throw_ex(env, "java/lang/OutOfMemoryError", "NDI frame buffer"); return; }
        s->buf[i] = nb;
        s->cap[i] = need;
    }
    jint* src = (jint*)(*env)->GetPrimitiveArrayCritical(env, jpx, NULL);
    if (!src) return;
    if (stride == w) {
        memcpy(s->buf[i], src + offset, need);
    } else {
        for (int y = 0; y < hgt; y++) memcpy(s->buf[i] + row * y, src + offset + (size_t)stride * y, row);
    }
    (*env)->ReleasePrimitiveArrayCritical(env, jpx, src, JNI_ABORT);

    NDIlib_video_frame_v2_t f;
    memset(&f, 0, sizeof f);
    f.xres = w;
    f.yres = hgt;
    f.FourCC = alpha ? NDIlib_FourCC_video_type_BGRA : NDIlib_FourCC_video_type_BGRX;
    f.frame_rate_N = fpsN > 0 ? fpsN : 60000;
    f.frame_rate_D = fpsD > 0 ? fpsD : 1000;
    f.picture_aspect_ratio = 0.0f; /* square pixels */
    f.frame_format_type = NDIlib_frame_format_type_progressive;
    f.timecode = NDIlib_send_timecode_synthesize;
    f.p_data = s->buf[i];
    f.line_stride_in_bytes = (int)row;
    nl_api->send_send_video_async_v2(s->inst, &f);
    s->pending = true;
    s->next = 1 - i;
}

/* Blocks until the last asynchronous frame has been consumed by NDI. */
JNIEXPORT void JNICALL Java_processing_ndi_NDINative_nFlush(JNIEnv* env, jclass cls, jlong h) {
    (void)env; (void)cls;
    sender_t* s = (sender_t*)(intptr_t)h;
    if (s) flush(s);
}

JNIEXPORT jint JNICALL Java_processing_ndi_NDINative_nConnections(JNIEnv* env, jclass cls, jlong h, jint timeoutMs) {
    (void)env; (void)cls;
    sender_t* s = (sender_t*)(intptr_t)h;
    if (!s) return 0;
    return nl_api->send_get_no_connections(s->inst, (uint32_t)(timeoutMs < 0 ? 0 : timeoutMs));
}

JNIEXPORT jstring JNICALL Java_processing_ndi_NDINative_nSourceName(JNIEnv* env, jclass cls, jlong h) {
    (void)cls;
    sender_t* s = (sender_t*)(intptr_t)h;
    if (!s) return NULL;
    const NDIlib_source_t* src = nl_api->send_get_source_name(s->inst);
    return (src && src->p_ndi_name) ? (*env)->NewStringUTF(env, src->p_ndi_name) : NULL;
}

/* ========================================================================= */
/* Discovery: one finder shared by NDI.sources() and every receiver          */

static pn_mutex_t g_find_mutex;
static NDIlib_find_instance_t g_find = NULL;

/* called from nInit (single-threaded, under the Java class lock) */
static void find_global_init(void) {
    static bool done = false;
    if (done) return;
    pn_mutex_init(&g_find_mutex);
    done = true;
}

static NDIlib_find_instance_t find_get(void) {   /* g_find_mutex held */
    if (!g_find) {
        NDIlib_find_create_t fc;
        memset(&fc, 0, sizeof fc);
        fc.show_local_sources = true;
        g_find = nl_api->find_create_v2(&fc);
    }
    return g_find;
}

static int ci_equal(const char* a, const char* b) {
    for (; *a && *b; a++, b++) if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
    return *a == *b;
}

static int ci_contains(const char* hay, const char* needle) {
    size_t n = strlen(needle);
    if (n == 0) return 1;
    for (; *hay; hay++) {
        size_t i = 0;
        while (i < n && hay[i] && tolower((unsigned char)hay[i]) == tolower((unsigned char)needle[i])) i++;
        if (i == n) return 1;
    }
    return 0;
}

/* How well a full source name "MACHINE (Source)" matches the filter: 3 exact, 2 source part, 1 substring, 0 no */
static int match_score(const char* full, const char* filter) {
    if (!full) return 0;
    if (!filter || !filter[0]) return 1;
    if (strcmp(full, filter) == 0) return 3;
    const char* open = strchr(full, '(');
    const char* close = strrchr(full, ')');
    if (open && close && close > open) {
        char part[512];
        size_t n = (size_t)(close - open - 1);
        if (n >= sizeof part) n = sizeof part - 1;
        memcpy(part, open + 1, n);
        part[n] = 0;
        if (ci_equal(part, filter)) return 2;
    }
    return ci_contains(full, filter) ? 1 : 0;
}

/* Best source for the filter; returns 1 and copies its full name into out. */
static int find_best(const char* filter, char* out, size_t size) {
    int best = 0;
    pn_lock(&g_find_mutex);
    NDIlib_find_instance_t f = find_get();
    if (f) {
        uint32_t n = 0;
        const NDIlib_source_t* list = nl_api->find_get_current_sources(f, &n);
        for (uint32_t i = 0; i < n; i++) {
            int sc = match_score(list[i].p_ndi_name, filter);
            if (sc > best) {
                best = sc;
                snprintf(out, size, "%s", list[i].p_ndi_name);
            }
        }
    }
    pn_unlock(&g_find_mutex);
    return best > 0;
}

/* String[] nFindSources(int waitMs) */
JNIEXPORT jobjectArray JNICALL Java_processing_ndi_NDINative_nFindSources(JNIEnv* env, jclass cls, jint waitMs) {
    (void)cls;
    jclass strCls = (*env)->FindClass(env, "java/lang/String");
    if (!g_initialized) return (*env)->NewObjectArray(env, 0, strCls, NULL);
    pn_lock(&g_find_mutex);
    NDIlib_find_instance_t f = find_get();
    pn_unlock(&g_find_mutex);
    if (!f) return (*env)->NewObjectArray(env, 0, strCls, NULL);
    if (waitMs > 0) nl_api->find_wait_for_sources(f, (uint32_t)waitMs);   /* thread safe in NDI; no lock while waiting */
    pn_lock(&g_find_mutex);
    uint32_t n = 0;
    const NDIlib_source_t* list = nl_api->find_get_current_sources(f, &n);
    jobjectArray arr = (*env)->NewObjectArray(env, (jsize)n, strCls, NULL);
    for (uint32_t i = 0; arr && i < n; i++) {
        jstring js = (*env)->NewStringUTF(env, list[i].p_ndi_name ? list[i].p_ndi_name : "");
        (*env)->SetObjectArrayElement(env, arr, (jsize)i, js);
        (*env)->DeleteLocalRef(env, js);
    }
    pn_unlock(&g_find_mutex);
    return arr;
}

/* ========================================================================= */
/* Receiver                                                                  */

#define RECV_LOST_MS 2000     /* no frame for this long = not connected */
#define RECV_SWITCH_MS 3000   /* no frame for this long: look for another source matching the filter */

typedef struct {
    char filter[512];
    char recv_name[256];
    pn_thread_t thread;
    pn_mutex_t m;
    volatile int stop;
    volatile int restart;     /* recreate the NDI receiver (bandwidth changed) */
    volatile int low_bandwidth;
    /* shared with Java, under m */
    char source[512];         /* full name of the source the receiver is attached to ("" = none) */
    int receiving;            /* frames arrived during the last RECV_LOST_MS */
    uint8_t* buf;
    size_t cap;
    int w, h, alpha, fps_n, fps_d;
    int64_t frame_no;
} receiver_t;

static void recv_copy_frame(receiver_t* r, const NDIlib_video_frame_v2_t* v) {
    size_t row = (size_t)v->xres * 4, need = row * (size_t)v->yres;
    pn_lock(&r->m);
    if (r->cap < need) {
        uint8_t* nb = (uint8_t*)realloc(r->buf, need);
        if (!nb) { pn_unlock(&r->m); return; }
        r->buf = nb;
        r->cap = need;
    }
    if (v->line_stride_in_bytes == (int)row) memcpy(r->buf, v->p_data, need);
    else for (int y = 0; y < v->yres; y++) memcpy(r->buf + row * y, v->p_data + (size_t)v->line_stride_in_bytes * y, row);
    r->w = v->xres;
    r->h = v->yres;
    r->alpha = v->FourCC == NDIlib_FourCC_video_type_BGRA;
    r->fps_n = v->frame_rate_N;
    r->fps_d = v->frame_rate_D;
    r->frame_no++;
    r->receiving = 1;
    pn_unlock(&r->m);
}

static void recv_set_source(receiver_t* r, const char* name) {
    pn_lock(&r->m);
    snprintf(r->source, sizeof r->source, "%s", name ? name : "");
    if (!name) r->receiving = 0;
    pn_unlock(&r->m);
}

static PN_THREAD_RET recv_thread(void* arg) {
    receiver_t* r = (receiver_t*)arg;
    NDIlib_recv_instance_t recv = NULL;
    char current[512] = "";
    int64_t last_frame = 0, last_search = 0;
    while (!r->stop) {
        if (r->restart && recv) {
            nl_api->recv_destroy(recv);
            recv = NULL;
        }
        r->restart = 0;
        if (!recv) {
            char name[512];
            if (!find_best(r->filter, name, sizeof name)) {
                recv_set_source(r, NULL);
                pn_sleep_ms(200);
                continue;
            }
            NDIlib_recv_create_v3_t rc;
            memset(&rc, 0, sizeof rc);
            rc.source_to_connect_to.p_ndi_name = name;
            rc.color_format = NDIlib_recv_color_format_BGRX_BGRA;
            rc.bandwidth = r->low_bandwidth ? NDIlib_recv_bandwidth_lowest : NDIlib_recv_bandwidth_highest;
            rc.allow_video_fields = false;
            rc.p_ndi_recv_name = r->recv_name[0] ? r->recv_name : NULL;
            recv = nl_api->recv_create_v3(&rc);
            if (!recv) { pn_sleep_ms(500); continue; }
            snprintf(current, sizeof current, "%s", name);
            recv_set_source(r, current);
            last_frame = last_search = pn_now_ms();
        }
        NDIlib_video_frame_v2_t v;
        NDIlib_frame_type_e t = nl_api->recv_capture_v2(recv, &v, NULL, NULL, 100);
        int64_t now = pn_now_ms();
        if (t == NDIlib_frame_type_video) {
            if (v.p_data && v.xres > 0 && v.yres > 0) recv_copy_frame(r, &v);
            nl_api->recv_free_video_v2(recv, &v);
            last_frame = now;
        } else if (t == NDIlib_frame_type_error) {
            nl_api->recv_destroy(recv);
            recv = NULL;
            recv_set_source(r, NULL);
            pn_sleep_ms(200);
            continue;
        }
        if (now - last_frame > RECV_LOST_MS) {
            pn_lock(&r->m);
            r->receiving = 0;
            pn_unlock(&r->m);
        }
        /* NDI reconnects by itself to a source that comes back with the same name; when the
           filter matches a different source (another machine, or a better match), switch to it */
        if (now - last_frame > RECV_SWITCH_MS && now - last_search > 1000) {
            last_search = now;
            char name[512];
            int found = find_best(r->filter, name, sizeof name);
            if (found && strcmp(name, current) != 0) {
                nl_api->recv_destroy(recv);
                recv = NULL;
            }   /* not found: keep the receiver, the same source may come back */
        }
    }
    if (recv) nl_api->recv_destroy(recv);
    PN_THREAD_RETURN;
}

/* long nRecvCreate(String filter, String receiverName, boolean lowBandwidth) */
JNIEXPORT jlong JNICALL Java_processing_ndi_NDINative_nRecvCreate(JNIEnv* env, jclass cls, jstring jfilter, jstring jname,
                                                                  jboolean low) {
    (void)cls;
    if (!g_initialized) { throw_ex(env, "java/lang/IllegalStateException", "NDI runtime not initialised"); return 0; }
    receiver_t* r = (receiver_t*)calloc(1, sizeof *r);
    if (!r) return 0;
    if (jfilter) {
        const char* f = (*env)->GetStringUTFChars(env, jfilter, NULL);
        snprintf(r->filter, sizeof r->filter, "%s", f);
        (*env)->ReleaseStringUTFChars(env, jfilter, f);
    }
    if (jname) {
        const char* n = (*env)->GetStringUTFChars(env, jname, NULL);
        snprintf(r->recv_name, sizeof r->recv_name, "%s", n);
        (*env)->ReleaseStringUTFChars(env, jname, n);
    }
    r->low_bandwidth = low ? 1 : 0;
    pn_mutex_init(&r->m);
    if (pn_thread_create(&r->thread, recv_thread, r) != 0) {
        pn_mutex_destroy(&r->m);
        free(r);
        return 0;
    }
    return (jlong)(intptr_t)r;
}

JNIEXPORT void JNICALL Java_processing_ndi_NDINative_nRecvDestroy(JNIEnv* env, jclass cls, jlong h) {
    (void)env; (void)cls;
    receiver_t* r = (receiver_t*)(intptr_t)h;
    if (!r) return;
    r->stop = 1;
    pn_thread_join(r->thread);
    pn_mutex_destroy(&r->m);
    free(r->buf);
    free(r);
}

JNIEXPORT void JNICALL Java_processing_ndi_NDINative_nRecvSetLowBandwidth(JNIEnv* env, jclass cls, jlong h, jboolean low) {
    (void)env; (void)cls;
    receiver_t* r = (receiver_t*)(intptr_t)h;
    if (!r || r->low_bandwidth == (low ? 1 : 0)) return;
    r->low_bandwidth = low ? 1 : 0;
    r->restart = 1;
}

/* long nRecvInfo(long h, int[] info): info = {width, height, alpha, receiving, fpsN, fpsD}; returns the frame number */
JNIEXPORT jlong JNICALL Java_processing_ndi_NDINative_nRecvInfo(JNIEnv* env, jclass cls, jlong h, jintArray jinfo) {
    (void)cls;
    receiver_t* r = (receiver_t*)(intptr_t)h;
    if (!r) return 0;
    jint info[6];
    pn_lock(&r->m);
    info[0] = r->w; info[1] = r->h; info[2] = r->alpha; info[3] = r->receiving; info[4] = r->fps_n; info[5] = r->fps_d;
    jlong n = r->frame_no;
    pn_unlock(&r->m);
    if (jinfo && (*env)->GetArrayLength(env, jinfo) >= 6) (*env)->SetIntArrayRegion(env, jinfo, 0, 6, info);
    return n;
}

/* Copies the latest frame into dst (ARGB ints, BGRX made opaque). Returns its frame number, or -1 when
   the frame size is not width x height any more (the caller re-reads the info and retries). */
JNIEXPORT jlong JNICALL Java_processing_ndi_NDINative_nRecvRead(JNIEnv* env, jclass cls, jlong h, jintArray jdst, jint w,
                                                                jint hgt) {
    (void)cls;
    receiver_t* r = (receiver_t*)(intptr_t)h;
    if (!r || !jdst) return -1;
    if ((*env)->GetArrayLength(env, jdst) < (jsize)((int64_t)w * hgt)) return -1;
    pn_lock(&r->m);
    if (r->w != w || r->h != hgt || !r->buf) { pn_unlock(&r->m); return -1; }
    jint* dst = (jint*)(*env)->GetPrimitiveArrayCritical(env, jdst, NULL);
    if (!dst) { pn_unlock(&r->m); return -1; }
    size_t n = (size_t)w * (size_t)hgt;
    memcpy(dst, r->buf, n * 4);
    if (!r->alpha) {
        uint32_t* p = (uint32_t*)dst;
        for (size_t i = 0; i < n; i++) p[i] |= 0xFF000000u;
    }
    jlong fno = r->frame_no;
    (*env)->ReleasePrimitiveArrayCritical(env, jdst, dst, 0);
    pn_unlock(&r->m);
    return fno;
}

/* String nRecvSource(long h): full name of the attached source, or null */
JNIEXPORT jstring JNICALL Java_processing_ndi_NDINative_nRecvSource(JNIEnv* env, jclass cls, jlong h) {
    (void)cls;
    receiver_t* r = (receiver_t*)(intptr_t)h;
    if (!r) return NULL;
    char name[512];
    pn_lock(&r->m);
    snprintf(name, sizeof name, "%s", r->source);
    pn_unlock(&r->m);
    return name[0] ? (*env)->NewStringUTF(env, name) : NULL;
}
