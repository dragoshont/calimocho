/*
 * d3d11_d3dmetal.c — PE-side intercept of D3D11 device creation
 * forwarding into Apple's D3DMetal.framework via wine's unixlib.
 *
 * This file is dropped into wine's dlls/d3d11/ at build time by
 * calimocho/patches/wine/0004-d3d11-d3dmetal-shim.patch. It defines
 * two helpers:
 *
 *   d3dmetal_is_available()
 *       returns TRUE iff this process can route D3D11 creation
 *       through D3DMetal. Caches result. Fails fast and stays
 *       FALSE if anything's missing — caller falls back to wined3d.
 *
 *   d3dmetal_create_device()
 *   d3dmetal_create_device_and_swap_chain()
 *       Pack args into the wire structs, dispatch via WINE_UNIX_CALL,
 *       return HRESULT.
 *
 * The patched D3D11CreateDevice / D3D11CreateDeviceAndSwapChain in
 * d3d11_main.c call these helpers first; only on failure do they
 * fall through to wine's existing wined3d-backed implementation.
 *
 * Copyright (C) 2026 Dragos Hont
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#include <stdarg.h>

#define COBJMACROS
#include "ntstatus.h"
#define WIN32_NO_STATUS
#include "windef.h"
#include "winbase.h"
#include "winerror.h"
#include "winternl.h"
#include "wine/debug.h"
#include "wine/unixlib.h"

#include "d3d11.h"
#include "dxgi.h"

#include "d3d11_d3dmetal_private.h"

WINE_DEFAULT_DEBUG_CHANNEL(d3d11_d3dmetal);

/* Tri-state cache for whether the unixlib + D3DMetal could be loaded.
 * -1 = not yet probed, 0 = unavailable (don't retry), 1 = available. */
static LONG d3dmetal_cached_state = -1;

BOOL d3dmetal_is_available(void)
{
    LONG state;
    NTSTATUS s;

    state = InterlockedCompareExchange(&d3dmetal_cached_state, -1, -1);
    if (state != -1) return state == 1;

    /* Init the unixlib dispatcher. Safe to call repeatedly. */
    if (__wine_init_unix_call())
    {
        WARN("__wine_init_unix_call failed; D3DMetal shim disabled\n");
        InterlockedExchange(&d3dmetal_cached_state, 0);
        return FALSE;
    }

    /* Probe the unix side. It dlopens D3DMetal.framework and resolves
     * the symbols we need. Returns STATUS_SUCCESS only when both
     * succeed. */
    s = WINE_UNIX_CALL(unix_d3dmetal_init, NULL);
    if (s != STATUS_SUCCESS)
    {
        WARN("D3DMetal init returned %#lx; shim disabled\n", (long)s);
        InterlockedExchange(&d3dmetal_cached_state, 0);
        return FALSE;
    }

    TRACE("D3DMetal shim active\n");
    InterlockedExchange(&d3dmetal_cached_state, 1);
    return TRUE;
}

HRESULT d3dmetal_create_device(IDXGIAdapter *adapter,
                               D3D_DRIVER_TYPE driver_type,
                               HMODULE software,
                               UINT flags,
                               const D3D_FEATURE_LEVEL *feature_levels,
                               UINT feature_levels_count,
                               UINT sdk_version,
                               ID3D11Device **device_out,
                               D3D_FEATURE_LEVEL *feature_level_out,
                               ID3D11DeviceContext **immediate_context_out)
{
    struct unix_create_device_params p;
    NTSTATUS s;

    if (!d3dmetal_is_available()) return DXGI_ERROR_UNSUPPORTED;

    p.adapter               = adapter;
    p.driver_type           = driver_type;
    p.software              = software;
    p.flags                 = flags;
    p.feature_levels        = (const uint32_t *)feature_levels;
    p.feature_levels_count  = feature_levels_count;
    p.sdk_version           = sdk_version;
    p.device_out            = (void **)device_out;
    p.feature_level_out     = (uint32_t *)feature_level_out;
    p.immediate_context_out = (void **)immediate_context_out;
    p.hr                    = E_FAIL;

    s = WINE_UNIX_CALL(unix_d3dmetal_create_device, &p);
    if (s != STATUS_SUCCESS)
    {
        ERR("unix_d3dmetal_create_device dispatch failed: %#lx\n", (long)s);
        return E_FAIL;
    }
    return p.hr;
}

HRESULT d3dmetal_create_device_and_swap_chain(IDXGIAdapter *adapter,
                                              D3D_DRIVER_TYPE driver_type,
                                              HMODULE software,
                                              UINT flags,
                                              const D3D_FEATURE_LEVEL *feature_levels,
                                              UINT feature_levels_count,
                                              UINT sdk_version,
                                              const DXGI_SWAP_CHAIN_DESC *swap_chain_desc,
                                              IDXGISwapChain **swap_chain_out,
                                              ID3D11Device **device_out,
                                              D3D_FEATURE_LEVEL *feature_level_out,
                                              ID3D11DeviceContext **immediate_context_out)
{
    struct unix_create_device_and_swap_chain_params p;
    NTSTATUS s;

    if (!d3dmetal_is_available()) return DXGI_ERROR_UNSUPPORTED;

    p.adapter               = adapter;
    p.driver_type           = driver_type;
    p.software              = software;
    p.flags                 = flags;
    p.feature_levels        = (const uint32_t *)feature_levels;
    p.feature_levels_count  = feature_levels_count;
    p.sdk_version           = sdk_version;
    p.swap_chain_desc       = swap_chain_desc;
    p.swap_chain_out        = (void **)swap_chain_out;
    p.device_out            = (void **)device_out;
    p.feature_level_out     = (uint32_t *)feature_level_out;
    p.immediate_context_out = (void **)immediate_context_out;
    p.hr                    = E_FAIL;

    s = WINE_UNIX_CALL(unix_d3dmetal_create_device_and_swap_chain, &p);
    if (s != STATUS_SUCCESS)
    {
        ERR("unix_d3dmetal_create_device_and_swap_chain dispatch failed: %#lx\n", (long)s);
        return E_FAIL;
    }
    return p.hr;
}
