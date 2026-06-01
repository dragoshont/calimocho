/*
 * test_d3dmetal_shim.c — minimal Windows program that calls
 * D3D11CreateDevice. Used as a Tier 1 unit test for calimocho's
 * D3DMetal shim (ADR-0015).
 *
 * Build with mingw cross-compile (or wine's winegcc):
 *   x86_64-w64-mingw32-gcc test_d3dmetal_shim.c -o test_d3dmetal_shim.exe -ld3d11
 *
 * Run via:
 *   WINEPREFIX=... wine test_d3dmetal_shim.exe
 *
 * Exit codes:
 *   0 = D3D11CreateDevice returned S_OK, device non-NULL
 *   1 = D3D11CreateDevice returned an error HRESULT
 *   2 = device pointer is NULL despite S_OK
 *   3 = AddRef/Release round trip failed
 */

#include <stdio.h>
#define COBJMACROS
#include <d3d11.h>

int main(int argc, char **argv)
{
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL got_level = 0;
    D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };

    printf("test_d3dmetal_shim: calling D3D11CreateDevice...\n");
    fflush(stdout);

    HRESULT hr = D3D11CreateDevice(
        NULL,                       /* default adapter */
        D3D_DRIVER_TYPE_HARDWARE,   /* prefer hardware */
        NULL,                       /* no software module */
        0,                          /* no flags */
        levels,
        sizeof(levels)/sizeof(levels[0]),
        D3D11_SDK_VERSION,
        &device,
        &got_level,
        &context);

    printf("test_d3dmetal_shim: D3D11CreateDevice returned hr=0x%08lx\n", hr);
    fflush(stdout);

    if (FAILED(hr))
    {
        printf("test_d3dmetal_shim: FAIL: HRESULT indicates error\n");
        return 1;
    }
    if (device == NULL)
    {
        printf("test_d3dmetal_shim: FAIL: device pointer is NULL despite S_OK\n");
        return 2;
    }

    printf("test_d3dmetal_shim: device=%p, feature_level=0x%x, context=%p\n",
           (void*)device, (unsigned)got_level, (void*)context);

    /* Round-trip AddRef / Release to verify the vtable works. */
    ULONG refs1 = ID3D11Device_AddRef(device);
    ULONG refs2 = ID3D11Device_Release(device);
    printf("test_d3dmetal_shim: AddRef -> %lu, Release -> %lu\n", refs1, refs2);

    if (refs1 != refs2 + 1)
    {
        printf("test_d3dmetal_shim: FAIL: refcount didn't round-trip cleanly\n");
        return 3;
    }

    /* Final release of the initial ref. */
    if (context) ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);

    printf("test_d3dmetal_shim: PASS\n");
    return 0;
}
