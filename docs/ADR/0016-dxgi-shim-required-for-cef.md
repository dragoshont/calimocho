# ADR 0016: dxgi.dll D3DMetal shim is required for Steam CEF

Status: Accepted
Date: 2026-06-01

## Context

ADR-0015 designed a D3DMetal forwarding shim for both `d3d11.dll`
**and** `dxgi.dll` (audit table: "dxgi same trio: ~250 lines").
Only the d3d11 half was implemented in the first pass. Tier-1 unit
test (`tests/d3d11_shim/test_d3dmetal_shim.exe`) passed because it
calls `D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, ...)` —
**adapter=NULL**, so D3DMetal allocates its own adapter internally.

When Steam's CEF GPU subprocess runs, ANGLE first calls
`CreateDXGIFactory1` → `EnumAdapters1` to enumerate adapters, then
passes the returned `IDXGIAdapter*` into `D3D11CreateDevice(adapter,
D3D_DRIVER_TYPE_UNKNOWN, ...)`. With our current build, that
`IDXGIAdapter*` comes from wine's builtin `dxgi.dll` (wined3d-backed)
and is **incompatible with D3DMetal's adapter ABI**.

## Evidence (2026-06-01 measurements)

After flipping `bin/calimocho-wine`'s default `WINEDLLOVERRIDES` from
`d3d11,dxgi=n` to `=b` and copying the engine's `d3d11.dll` / `dxgi.dll`
into the bottle (Wine 11's loader requires the file present in
`drive_c/windows/system32/`):

| Test | Adapter | driver_type | shim ENTER | shim RETURN | Result |
|---|---|---|---|---|---|
| Tier-1 standalone | NULL | HARDWARE (1) | 1 | 1 (hr=S_OK) | PASS, D3DMetal returns FL 11.0 device |
| Steam CEF GPU subprocess | 0x2b95e0 (wined3d-backed) | UNKNOWN (0) | 1 | **0** | D3DMetal never returns; CEF logs `eglInitialize D3D11 failed with error EGL_NOT_INITIALIZED`; falls back to GLES 2.0; Steam window stays black |

Shim log excerpt (Steam launch, pid 46083):

```text
init: ready (CreateDevice=0x215355ea8, ...)
create_device: ENTER adapter=0x2b95e0 driver_type=0 flags=0x0 levels_count=5 sdk_version=7
(no RETURN line — D3DMetal faulted on adapter deref)
```

CEF log confirms the symptom one level up:

```text
EGL Driver message (Critical) eglInitialize: No available renderers.
eglInitialize D3D11 failed with error EGL_NOT_INITIALIZED, trying next display type
EGL Driver message (Error) eglCreateContext: Requested GLES version (3.0) is greater than max supported (2, 0)
```

## Decision

Build the second half of ADR-0015's design: a `dxgi.dll` D3DMetal
shim that forwards `CreateDXGIFactory{1,2}` and the resulting
`IDXGIAdapter` enumerations into D3DMetal's matching exports, so
the `IDXGIAdapter*` that ANGLE hands back to `D3D11CreateDevice` is
one D3DMetal recognizes.

Estimated scope (per ADR-0015 audit): ~250 lines of new C across
three files (PE shim, ELF unixlib, private header) plus a small
patch hooking it into wine's `dlls/dxgi/`.

## Consequences

### Positive

- Closes the last gap blocking Steam UI rendering on calimocho.
- Symmetric with the d3d11 shim — same pattern, same testing tiers.

### Negative

- Doubles the surface of "DLLs we shim" and therefore doubles the
  CodeWeavers Wine ABI coupling cost (ADR-0014).

### Neutral

- Builtin `dxgi=b` becomes a hard requirement for the engine; the
  launcher already defaults to it as of this commit.

## Related

- ADR-0013 (CW HACK 22434 env var) — unblocks D3DMetal callbacks
- ADR-0014 (shim ABI coupling) — same trade-off applies here
- ADR-0015 (d3d11 shim) — sibling shim, same architecture
- Issue #4 — Steam UI black, still open
