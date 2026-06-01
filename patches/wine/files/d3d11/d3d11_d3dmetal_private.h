/*
 * d3d11_d3dmetal_private.h
 *
 * Shared types between PE and ELF sides of calimocho's D3DMetal shim
 * for wine's d3d11.dll. The PE side fills these args structs,
 * dispatches via WINE_UNIX_CALL(), the ELF side unpacks and forwards
 * into Apple's D3DMetal.framework.
 *
 * This file is dropped into wine's dlls/d3d11/ at build time by
 * calimocho/patches/wine/0004-d3d11-d3dmetal-shim.patch.
 *
 * Copyright (C) 2026 Dragos Hont
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

#ifndef __WINE_D3D11_D3DMETAL_PRIVATE_H
#define __WINE_D3D11_D3DMETAL_PRIVATE_H

#include <stdint.h>

/*
 * Wire-stable unix-call dispatch table indices.
 *
 * IMPORTANT: do NOT reorder. Append-only. The index becomes part of
 * the contract between d3d11_d3dmetal.c (PE) and d3d11_d3dmetal_unix.c
 * (ELF). Reordering breaks binary compatibility between a re-built
 * d3d11.dll and an unchanged d3d11.so or vice versa.
 */
enum d3d11_d3dmetal_unix_call
{
    unix_d3dmetal_init,
    unix_d3dmetal_create_device,
    unix_d3dmetal_create_device_and_swap_chain,
    unix_d3dmetal_count
};

/*
 * Args struct for unix_d3dmetal_create_device.
 *
 * Pointer parameters cross the PE/ELF boundary as opaque addresses;
 * both sides agree the COM interfaces they point to use ms_abi
 * vtables (verified empirically against D3DMetal.framework — see
 * docs/ADR/0015-d3dmetal-shim-implementation.md §Empirical findings).
 *
 * `hr` is populated by the ELF side. NTSTATUS from the unix-call
 * dispatcher is reserved for transport-level errors (lib not loaded,
 * symbol missing, etc.); D3D-level errors come back in `hr`.
 */
struct unix_create_device_params
{
    void *adapter;                        /* IDXGIAdapter*, may be NULL */
    uint32_t driver_type;                 /* D3D_DRIVER_TYPE enum */
    void *software;                       /* HMODULE; must be NULL unless driver_type == SOFTWARE */
    uint32_t flags;                       /* D3D11_CREATE_DEVICE_FLAG bitmask */
    const uint32_t *feature_levels;       /* D3D_FEATURE_LEVEL[], may be NULL */
    uint32_t feature_levels_count;
    uint32_t sdk_version;
    void **device_out;                    /* ID3D11Device**, may be NULL */
    uint32_t *feature_level_out;          /* D3D_FEATURE_LEVEL*, may be NULL */
    void **immediate_context_out;         /* ID3D11DeviceContext**, may be NULL */
    int32_t hr;                           /* HRESULT, filled by callee */
};

/*
 * Args struct for unix_d3dmetal_create_device_and_swap_chain.
 *
 * `swap_chain_desc` is the input DXGI_SWAP_CHAIN_DESC pointer; the
 * struct itself is read by D3DMetal directly via the pointer, no copy.
 * If a future GPTK release changes the desc layout this layering is
 * still correct because D3DMetal's parser is paired with its create.
 */
struct unix_create_device_and_swap_chain_params
{
    void *adapter;
    uint32_t driver_type;
    void *software;
    uint32_t flags;
    const uint32_t *feature_levels;
    uint32_t feature_levels_count;
    uint32_t sdk_version;
    const void *swap_chain_desc;          /* DXGI_SWAP_CHAIN_DESC*, must be non-NULL when swap_chain_out != NULL */
    void **swap_chain_out;                /* IDXGISwapChain**, may be NULL */
    void **device_out;
    uint32_t *feature_level_out;
    void **immediate_context_out;
    int32_t hr;
};

#endif /* __WINE_D3D11_D3DMETAL_PRIVATE_H */
