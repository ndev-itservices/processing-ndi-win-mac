/*
 * ndiload.h - locates and loads the NDI(R) runtime at run time (no link-time dependency).
 *
 * Search order:
 *   1. an explicit path (file or folder) given by the caller
 *   2. the folder that contains the module calling ndi_load() (the Processing library ships
 *      the runtime next to the JNI bridge)
 *   3. the folder named by the NDI_RUNTIME_DIR_V6 environment variable (official NDI runtime)
 *   4. the standard install locations (macOS: /usr/local/lib, the NDI SDK folder)
 *   5. the plain library name (system search path)
 *
 * Part of Processing-NDI - https://github.com/ndev-itservices/processing-ndi-win-mac
 * Author: Tiago Martins
 * Licence: MIT (see LICENSE.txt)
 * NDI(R) is a registered trademark of Vizrt NDI AB - https://ndi.video/
 */
#ifndef NDILOAD_H
#define NDILOAD_H

#ifdef _WIN32
#  ifndef _CRT_SECURE_NO_WARNINGS
#    define _CRT_SECURE_NO_WARNINGS
#  endif
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <dlfcn.h>
#  include <sys/stat.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "Processing.NDI.Lib.h"

#ifdef _WIN32
#  define NL_SEP "\\"
#else
#  define NL_SEP "/"
#endif

static const NDIlib_v6* nl_api = NULL;
static char nl_loaded_path[2048] = "";
static char nl_error[4096] = "";

static void nl_err_append(const char* path, const char* why) {
    size_t n = strlen(nl_error);
    if (n < sizeof nl_error - 1)
        snprintf(nl_error + n, sizeof nl_error - n, "%s%s: %s", n ? "\n  " : "", path, why);
}

static int nl_is_dir(const char* p) {
#ifdef _WIN32
    DWORD a = GetFileAttributesA(p);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
#else
    struct stat st;
    return stat(p, &st) == 0 && S_ISDIR(st.st_mode);
#endif
}

/* Folder that contains the module (dylib/dll) this code is compiled into. */
static void nl_module_dir(char* out, size_t size) {
    out[0] = 0;
#ifdef _WIN32
    HMODULE h = NULL;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCSTR)(void*)&nl_module_dir, &h)) {
        DWORD n = GetModuleFileNameA(h, out, (DWORD)size);
        if (n == 0 || n >= size) { out[0] = 0; return; }
    }
    char* s = strrchr(out, '\\');
    if (s) *s = 0; else out[0] = 0;
#else
    Dl_info info;
    if (dladdr((void*)&nl_module_dir, &info) && info.dli_fname) {
        snprintf(out, size, "%s", info.dli_fname);
        char* s = strrchr(out, '/');
        if (s) *s = 0; else out[0] = 0;
    }
#endif
}

static int nl_try(const char* path) {
    if (!path || !path[0]) return 0;
#ifdef _WIN32
    HMODULE h = LoadLibraryExA(path, NULL, strchr(path, '\\') || strchr(path, '/') ? LOAD_WITH_ALTERED_SEARCH_PATH : 0);
    if (!h) { char b[64]; snprintf(b, sizeof b, "LoadLibrary error %lu", (unsigned long)GetLastError()); nl_err_append(path, b); return 0; }
    const NDIlib_v6* (*load)(void) = (const NDIlib_v6* (*)(void))(void*)GetProcAddress(h, "NDIlib_v6_load");
#else
    void* h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { const char* e = dlerror(); nl_err_append(path, e ? e : "dlopen failed"); return 0; }
    const NDIlib_v6* (*load)(void) = (const NDIlib_v6* (*)(void))dlsym(h, "NDIlib_v6_load");
#endif
    if (!load) { nl_err_append(path, "NDIlib_v6_load not found (NDI 6 runtime required)"); return 0; }
    const NDIlib_v6* api = load();
    if (!api) { nl_err_append(path, "NDIlib_v6_load returned NULL"); return 0; }
    nl_api = api;
    snprintf(nl_loaded_path, sizeof nl_loaded_path, "%s", path);
    return 1;
}

static int nl_try_dir(const char* dir) {
    if (!dir || !dir[0]) return 0;
    char p[2048];
    size_t n = strlen(dir);
    int has_sep = n > 0 && (dir[n - 1] == '/' || dir[n - 1] == '\\');
    snprintf(p, sizeof p, "%s%s%s", dir, has_sep ? "" : NL_SEP, NDILIB_LIBRARY_NAME);
    return nl_try(p);
}

/* Loads the runtime once; returns the API table or NULL (see nl_error). */
static const NDIlib_v6* ndi_load(const char* explicit_path) {
    if (nl_api) return nl_api;
    nl_error[0] = 0;
    if (explicit_path && explicit_path[0]) {
        if (nl_is_dir(explicit_path) ? nl_try_dir(explicit_path) : nl_try(explicit_path)) return nl_api;
    }
    char dir[2048];
    nl_module_dir(dir, sizeof dir);
    if (nl_try_dir(dir)) return nl_api;
    const char* env = getenv(NDILIB_REDIST_FOLDER);
    if (env && nl_try_dir(env)) return nl_api;
#if defined(__APPLE__)
    if (nl_try("/usr/local/lib/libndi.dylib")) return nl_api;
    if (nl_try("/Library/NDI SDK for Apple/lib/macOS/libndi.dylib")) return nl_api;
#endif
    if (nl_try(NDILIB_LIBRARY_NAME)) return nl_api;
    return NULL;
}

#endif /* NDILOAD_H */
