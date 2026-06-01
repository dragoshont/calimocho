# ADR 0016: dxgi.dll D3DMetal shim is required for Steam CEF

Status: Accepted
Date: 2026-06-01

## Context

ADR-0015 designed a D3DMetal forwarding shim for both `d3d11.dll`
**and** `dxgi.dll` (audit table: "dxgi same trio: ~250 lines").
Only the d3d11 half was implemented in the first pass.

This ADR adds the evidence collected on 2026-06-01 across four
falsification experiments, then commits to building the dxgi shim.

## Experiments

### B — env propagation falsified

Hypothesis: `CX_APPLEGPTK_LIBD3DSHARED_PATH` isn't propagated to
Steam's CEF GPU subprocess, so CW HACK 22434's ms_abi trampolines
fall through to sysv.

Added to shim init: `getenv("CX_APPLEGPTK_LIBD3DSHARED_PATH")` plus
a `dlopen(..., RTLD_NOLOAD)` probe. Result in CEF GPU subprocess
(pid 58358):

```text
init: pid=58358 ppid=1 CX_APPLEGPTK_LIBD3DSHARED_PATH=/Users/.../libd3dshared.dylib
init: libd3dshared already-loaded probe handle=0x77a380
```

Env IS propagated and libd3dshared IS already loaded in the
subprocess. Hypothesis **falsified**.

### A — adapter mismatch confirmed at one level, refuted at another

Hypothesis: `IDXGIAdapter*` from wine's builtin `dxgi.dll` is
incompatible with D3DMetal's `D3D11CreateDevice` adapter ABI.

Added `CALIMOCHO_D3D11_FORCE_NULL_ADAPTER=1` knob to the shim that
substitutes `(NULL, D3D_DRIVER_TYPE_HARDWARE)` regardless of caller
input. With this set, D3DMetal CreateDevice returns successfully:

```text
create_device: FORCE_NULL_ADAPTER active; orig adapter=0x2b9be0 driver_type=0
create_device: about to call D3DMetal CreateDevice@0x215331ea8 adapter=0x0 driver=1
create_device: D3DMetal CreateDevice returned
create_device: RETURN hr=0x00000000 device=0x7fe0be823000 feature_level=0xb100 context=0x7fe0c0050000
```

391 ms wall time, FL 11.1 device. **Adapter mismatch at CreateDevice
is confirmed.**

But Steam window is still black. New CEF error one level up:

```text
SwapChain11.cpp:636 Could not create additional swap chains, HRESULT: 0x887A0004
eglCreateWindowSurface failed with error EGL_BAD_ALLOC
```

So the dxgi-side `IDXGISwapChain` from wine's builtin `dxgi.dll`
can't be bound to a D3DMetal-returned `ID3D11Device`. The shim
needs to be coherent across the **whole D3D11+DXGI stack**, not
just CreateDevice.

### Apple-drop-in — confirmed Apple's PE+unixlib pair loads but CEF still crashes

Hypothesis: replace our half-shim with Apple's complete PE+unixlib
stack from GPTK, which is by construction self-consistent.

Discovery: Apple's `lib/wine/x86_64-unix/{d3d11,dxgi,d3d10,d3d12}.so`
are **all symlinks to one file**: `lib/external/libd3dshared.dylib`.
Same physical dylib loaded via different wine-side paths. This
exploits `@loader_path` rpath resolution so that
`@rpath/D3DMetal.framework/D3DMetal` correctly resolves to
`lib/external/D3DMetal.framework/D3DMetal` (same directory as the
loaded image). Initial attempt failed because we `cp`'d the
symlinks as regular files; `@loader_path` then pointed at
`lib/wine/x86_64-unix/` where D3DMetal isn't.

After re-doing the layout with symlinks, the Apple stack loads
cleanly: zero `Failed to dlopen D3DMetal` assertions (was 3 per
launch). But Steam's CEF GPU subprocess now crashes with
`exit_code=-1073741819` (STATUS_ACCESS_VIOLATION = 0xC0000005):

```text
ERROR:command_buffer_proxy_impl.cc(325) GPU state invalid after WaitForGetOffsetInRange
ERROR:gpu_process_host.cc(1002) GPU process exited unexpectedly: exit_code=-1073741819
```

Apple's libd3dshared was built against CodeWeavers' Wine 7.7 ntdll
trampolines (the original CW HACK 22434 implementation, before our
Wine 11 vintage rewrote the surrounding code). The ABI between
libd3dshared's ms_abi callbacks and our Wine 11 ntdll's asm thunks
doesn't line up, even though the env var is set. **Apple's
drop-in is not a viable shortcut without a matching CW Wine 7.7
runtime.**

## Decision

Build the dxgi.dll D3DMetal shim that ADR-0015's audit scoped
(~250 lines) but the first pass skipped. Symmetric with d3d11:

- PE side: forward `CreateDXGIFactory{1,2}` into D3DMetal via
  WINE_UNIX_CALL
- ELF unixlib: dlopen D3DMetal, dlsym the DXGI symbols, register
  __wine_unix_call_funcs
- Adapter pointer flowing in/out is now a D3DMetal-allocated object
  on both sides of the d3d11 ↔ dxgi handoff

Adapter NULL substitution (CALIMOCHO_D3D11_FORCE_NULL_ADAPTER) is
kept as a diagnostic env var but is not the production fix.

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

## Alternatives rejected

- **Apple's full GPTK PE+unixlib drop-in**: explored end-to-end on
  2026-06-01. Symlink layout is required for D3DMetal resolution.
  Even with that, CEF's GPU subprocess crashes with ACCESS_VIOLATION
  because Apple's libd3dshared expects Wine 7.7's ntdll trampoline
  layout, not Wine 11's. Not viable without CW Wine 7.7 source.
- **Patching wine's builtin `dlls/dxgi/` to call D3DMetal**: more
  invasive than the shim and harder to maintain across CodeWeavers
  rebases. Same ABI surface, less isolation.

## Related

- ADR-0013 (CW HACK 22434 env var) — verified propagated to CEF
- ADR-0014 (shim ABI coupling) — same trade-off applies here
- ADR-0015 (d3d11 shim) — sibling shim, same architecture
- Issue #4 — Steam UI black, still open
