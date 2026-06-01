/*
 * d3d11_d3dmetal_unix.c — ELF/sysv_abi side of calimocho's
 * D3DMetal shim. Dispatches PE-side requests into Apple's
 * D3DMetal.framework via dlopen/dlsym.
 *
 * Registered into wine's unix-call dispatcher via the exported
 * __wine_unix_call_funcs[] table at the bottom of this file.
 * Wine builds this file as part of d3d11.so (the unixlib paired
 * with d3d11.dll). See dlls/d3d11/Makefile.in's UNIXLIB declaration.
 *
 * D3DMetal entry points are compiled with __attribute__((ms_abi))
 * — verified empirically by disassembling D3D11CreateDevice's
 * prologue (spills xmm6-15, reads r9 as 4th arg). The function
 * pointer typedefs below carry the same attribute so the sysv_abi
 * ELF code calls D3DMetal with the right register layout.
 *
 * Copyright (C) 2026 Dragos Hont
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#if 0
#pragma makedep unix
#endif

#include "config.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "windef.h"
#include "winbase.h"
#include "winternl.h"
#include "wine/debug.h"
#include "wine/unixlib.h"

#include "d3d11_d3dmetal_private.h"

WINE_DEFAULT_DEBUG_CHANNEL(d3d11_d3dmetal);

/*
 * File-based diagnostic logging.
 *
 * Wine's WINEDEBUG env var is consumed before child processes spawn,
 * and Steam's CEF helper processes do not always inherit it through
 * fork/exec chains. For post-mortem diagnosis of Steam launches we
 * therefore need a separate file-based channel that:
 *
 *   - is off by default (zero cost — single env-var probe at init time)
 *   - is on when CALIMOCHO_D3D11_DEBUG is set in the env that ran
 *     calimocho-wine (which propagates to every wine child unchanged)
 *   - writes append-only line records with monotonic timestamps and pid
 *   - is safe to call from any thread (one open FILE*, line-buffered)
 *
 * Log path can be overridden via CALIMOCHO_D3D11_LOG_FILE; default is
 * $HOME/Library/Logs/Calimocho/d3d11-shim.log. We do not rotate the
 * file from inside the shim — let the user truncate it between runs.
 */
static FILE *d3dmetal_log_fp;
static int   d3dmetal_log_enabled = -1;          /* tri-state: -1 unprobed, 0 off, 1 on */
static pthread_mutex_t d3dmetal_log_lock = PTHREAD_MUTEX_INITIALIZER;

static void d3dmetal_log_init_once(void)
{
    const char *flag;
    const char *override_path;
    const char *path;
    const char *home;
    char path_buf[1024];
    char dir_buf[1024];
    char cmd[1100];
    char *slash;

    flag = getenv("CALIMOCHO_D3D11_DEBUG");
    if (!flag || flag[0] == '0' || flag[0] == '\0') {
        d3dmetal_log_enabled = 0;
        return;
    }

    override_path = getenv("CALIMOCHO_D3D11_LOG_FILE");
    if (override_path && *override_path) {
        path = override_path;
    } else {
        home = getenv("HOME");
        if (!home) {
            d3dmetal_log_enabled = 0;
            return;
        }
        snprintf(path_buf, sizeof(path_buf),
                 "%s/Library/Logs/Calimocho/d3d11-shim.log", home);
        path = path_buf;
    }

    /* Create the parent dir; ignore errors (mkdir -p is good enough).
     * Wine bans strncpy via a macro poison; use memcpy with explicit
     * length clamp + NUL terminator. */
    {
        size_t plen = strlen(path);
        if (plen >= sizeof(dir_buf)) plen = sizeof(dir_buf) - 1;
        memcpy(dir_buf, path, plen);
        dir_buf[plen] = '\0';
    }
    slash = strrchr(dir_buf, '/');
    if (slash) {
        *slash = '\0';
        snprintf(cmd, sizeof(cmd), "/bin/mkdir -p '%s'", dir_buf);
        (void)system(cmd);
    }

    d3dmetal_log_fp = fopen(path, "a");
    if (!d3dmetal_log_fp) {
        d3dmetal_log_enabled = 0;
        return;
    }
    setlinebuf(d3dmetal_log_fp);
    d3dmetal_log_enabled = 1;
}

__attribute__((format(printf, 1, 2)))
static void d3dmetal_log(const char *fmt, ...)
{
    struct timeval tv;
    char header[64];
    va_list ap;

    if (d3dmetal_log_enabled == -1) {
        pthread_mutex_lock(&d3dmetal_log_lock);
        if (d3dmetal_log_enabled == -1) d3dmetal_log_init_once();
        pthread_mutex_unlock(&d3dmetal_log_lock);
    }
    if (d3dmetal_log_enabled != 1) return;

    gettimeofday(&tv, NULL);
    snprintf(header, sizeof(header), "[%ld.%06d pid=%d] ",
             (long)tv.tv_sec, (int)tv.tv_usec, (int)getpid());

    pthread_mutex_lock(&d3dmetal_log_lock);
    fputs(header, d3dmetal_log_fp);
    va_start(ap, fmt);
    vfprintf(d3dmetal_log_fp, fmt, ap);
    va_end(ap);
    fputc('\n', d3dmetal_log_fp);
    pthread_mutex_unlock(&d3dmetal_log_lock);
}

/*
 * Function-pointer typedefs matching Apple's D3DMetal exports.
 * The __attribute__((ms_abi)) here is the load-bearing piece: it
 * tells the compiler to use Windows x64 calling convention (rcx,
 * rdx, r8, r9 + xmm0-3) when invoking through these pointers, even
 * though the surrounding C code is sysv_abi.
 *
 * Signatures mirror the Microsoft D3D11 SDK header. Pointer args
 * are typed as void* / void** to avoid pulling in d3d11.h on the
 * unix side (that header is PE-only). The PE side already enforced
 * type correctness when packing the params struct.
 */
typedef int32_t (__attribute__((ms_abi)) *pfn_D3D11CreateDevice)(
    void *adapter,
    uint32_t driver_type,
    void *software,
    uint32_t flags,
    const uint32_t *feature_levels,
    uint32_t feature_levels_count,
    uint32_t sdk_version,
    void **device_out,
    uint32_t *feature_level_out,
    void **immediate_context_out);

typedef int32_t (__attribute__((ms_abi)) *pfn_D3D11CreateDeviceAndSwapChain)(
    void *adapter,
    uint32_t driver_type,
    void *software,
    uint32_t flags,
    const uint32_t *feature_levels,
    uint32_t feature_levels_count,
    uint32_t sdk_version,
    const void *swap_chain_desc,
    void **swap_chain_out,
    void **device_out,
    uint32_t *feature_level_out,
    void **immediate_context_out);

/* Resolved entry points (NULL until d3dmetal_init succeeds). */
static pfn_D3D11CreateDevice                d3dmetal_D3D11CreateDevice;
static pfn_D3D11CreateDeviceAndSwapChain    d3dmetal_D3D11CreateDeviceAndSwapChain;
static void                                *d3dmetal_handle;

/* pthread_once for race-free init when multiple threads call into
 * d3d11.dll concurrently (CEF GPU subprocess has several worker
 * threads that all touch D3D). */
static pthread_once_t   d3dmetal_init_once = PTHREAD_ONCE_INIT;
static NTSTATUS         d3dmetal_init_status = STATUS_DLL_NOT_FOUND;

/* Candidate paths to try for D3DMetal.framework, in priority order:
 *   1. Bundled framework inside calimocho's engine tree (per ADR-0005).
 *   2. Apple's GPTK install in /Applications (developer fallback).
 *   3. System-wide private framework (future GPTK release).
 * dlopen each in order; first success wins. */
static const char *d3dmetal_candidates[] = {
    "/Library/Frameworks/D3DMetal.framework/Versions/A/D3DMetal",
    "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework/Versions/A/D3DMetal",
    NULL  /* sentinel; CALIMOCHO_D3DMETAL_PATH env-var prepended at runtime */
};

static void d3dmetal_init_do(void)
{
    const char *env = getenv("CALIMOCHO_D3DMETAL_PATH");
    d3dmetal_log("init: probing D3DMetal (CALIMOCHO_D3DMETAL_PATH=%s)",
                 env && *env ? env : "<unset>");
    if (env && *env)
    {
        d3dmetal_handle = dlopen(env, RTLD_LAZY | RTLD_LOCAL);
        if (d3dmetal_handle) {
            TRACE("D3DMetal loaded from CALIMOCHO_D3DMETAL_PATH (%s)\n", env);
            d3dmetal_log("init: loaded from env path: %s", env);
        } else {
            WARN("CALIMOCHO_D3DMETAL_PATH set to %s but dlopen failed: %s\n", env, dlerror());
            d3dmetal_log("init: env-path dlopen FAILED for %s (%s)", env, dlerror());
        }
    }

    for (size_t i = 0; !d3dmetal_handle && d3dmetal_candidates[i]; i++)
    {
        d3dmetal_handle = dlopen(d3dmetal_candidates[i], RTLD_LAZY | RTLD_LOCAL);
        if (d3dmetal_handle) {
            TRACE("D3DMetal loaded from %s\n", d3dmetal_candidates[i]);
            d3dmetal_log("init: loaded from candidate[%zu]: %s", i, d3dmetal_candidates[i]);
        } else {
            d3dmetal_log("init: candidate[%zu] dlopen failed (%s): %s", i, d3dmetal_candidates[i], dlerror());
        }
    }

    if (!d3dmetal_handle)
    {
        ERR("D3DMetal.framework not found in any candidate path\n");
        d3dmetal_log("init: D3DMetal.framework NOT FOUND in any candidate path");
        d3dmetal_init_status = STATUS_DLL_NOT_FOUND;
        return;
    }

    d3dmetal_D3D11CreateDevice =
        (pfn_D3D11CreateDevice)dlsym(d3dmetal_handle, "D3D11CreateDevice");
    d3dmetal_D3D11CreateDeviceAndSwapChain =
        (pfn_D3D11CreateDeviceAndSwapChain)dlsym(d3dmetal_handle, "D3D11CreateDeviceAndSwapChain");

    if (!d3dmetal_D3D11CreateDevice || !d3dmetal_D3D11CreateDeviceAndSwapChain)
    {
        ERR("D3DMetal.framework loaded but required symbols missing "
            "(CreateDevice=%p, CreateDeviceAndSwapChain=%p)\n",
            d3dmetal_D3D11CreateDevice, d3dmetal_D3D11CreateDeviceAndSwapChain);
        d3dmetal_log("init: SYMBOLS MISSING (CreateDevice=%p, CreateDeviceAndSwapChain=%p)",
                     d3dmetal_D3D11CreateDevice, d3dmetal_D3D11CreateDeviceAndSwapChain);
        dlclose(d3dmetal_handle);
        d3dmetal_handle = NULL;
        d3dmetal_init_status = STATUS_ENTRYPOINT_NOT_FOUND;
        return;
    }

    d3dmetal_log("init: ready (CreateDevice=%p, CreateDeviceAndSwapChain=%p)",
                 d3dmetal_D3D11CreateDevice, d3dmetal_D3D11CreateDeviceAndSwapChain);
    d3dmetal_init_status = STATUS_SUCCESS;
}

static NTSTATUS d3dmetal_init(void *args)
{
    (void)args;
    pthread_once(&d3dmetal_init_once, d3dmetal_init_do);
    return d3dmetal_init_status;
}

static NTSTATUS d3dmetal_create_device(void *args)
{
    struct unix_create_device_params *p = args;
    if (!d3dmetal_D3D11CreateDevice) {
        d3dmetal_log("create_device: ABORT (no entry point resolved)");
        return STATUS_DLL_NOT_FOUND;
    }

    d3dmetal_log("create_device: ENTER adapter=%p driver_type=%u flags=0x%x levels_count=%u sdk_version=%u",
                 p->adapter, p->driver_type, p->flags, p->feature_levels_count, p->sdk_version);

    p->hr = d3dmetal_D3D11CreateDevice(p->adapter,
                                       p->driver_type,
                                       p->software,
                                       p->flags,
                                       p->feature_levels,
                                       p->feature_levels_count,
                                       p->sdk_version,
                                       p->device_out,
                                       p->feature_level_out,
                                       p->immediate_context_out);

    d3dmetal_log("create_device: RETURN hr=0x%08x device=%p feature_level=0x%x context=%p",
                 (unsigned)p->hr,
                 p->device_out ? *p->device_out : NULL,
                 p->feature_level_out ? *p->feature_level_out : 0u,
                 p->immediate_context_out ? *p->immediate_context_out : NULL);
    return STATUS_SUCCESS;
}

static NTSTATUS d3dmetal_create_device_and_swap_chain(void *args)
{
    struct unix_create_device_and_swap_chain_params *p = args;
    if (!d3dmetal_D3D11CreateDeviceAndSwapChain) {
        d3dmetal_log("create_device_and_swap_chain: ABORT (no entry point resolved)");
        return STATUS_DLL_NOT_FOUND;
    }

    d3dmetal_log("create_device_and_swap_chain: ENTER adapter=%p driver_type=%u flags=0x%x swap_chain_desc=%p",
                 p->adapter, p->driver_type, p->flags, p->swap_chain_desc);

    p->hr = d3dmetal_D3D11CreateDeviceAndSwapChain(p->adapter,
                                                   p->driver_type,
                                                   p->software,
                                                   p->flags,
                                                   p->feature_levels,
                                                   p->feature_levels_count,
                                                   p->sdk_version,
                                                   p->swap_chain_desc,
                                                   p->swap_chain_out,
                                                   p->device_out,
                                                   p->feature_level_out,
                                                   p->immediate_context_out);

    d3dmetal_log("create_device_and_swap_chain: RETURN hr=0x%08x device=%p swap_chain=%p",
                 (unsigned)p->hr,
                 p->device_out ? *p->device_out : NULL,
                 p->swap_chain_out ? *p->swap_chain_out : NULL);
    return STATUS_SUCCESS;
}

/*
 * Wine's standard unixlib dispatch table. Indices MUST match
 * enum d3d11_d3dmetal_unix_call in the private header.
 *
 * The unixlib_entry_t type is `NTSTATUS (*)(void *args)`, so each
 * function above conforms.
 */
const unixlib_entry_t __wine_unix_call_funcs[] =
{
    d3dmetal_init,
    d3dmetal_create_device,
    d3dmetal_create_device_and_swap_chain,
};

/* WoW64 thunks: for 32-bit callers, we'd need to pack args into
 * 32-bit pointer structs and back. Steam ships 64-bit Steam.exe;
 * 32-bit games launched through Steam don't directly call
 * D3D11CreateDevice (CEF runs in the 64-bit launcher process).
 * If a real 32-bit workload needs this, fall through to wine's
 * builtin wined3d (which already supports it). */
const unixlib_entry_t __wine_unix_call_wow64_funcs[] =
{
    d3dmetal_init,                              /* init is pointer-size-agnostic */
    NULL,                                       /* 32-bit create_device: unsupported */
    NULL,                                       /* 32-bit create_device_and_swap_chain: unsupported */
};

C_ASSERT( sizeof(__wine_unix_call_funcs) / sizeof(*__wine_unix_call_funcs) == unix_d3dmetal_count );
C_ASSERT( sizeof(__wine_unix_call_wow64_funcs) / sizeof(*__wine_unix_call_wow64_funcs) == unix_d3dmetal_count );
