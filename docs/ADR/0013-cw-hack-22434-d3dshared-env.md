# ADR 0013: Set CX_APPLEGPTK_LIBD3DSHARED_PATH in launcher

Status: Accepted
Date: 2026-06-01

## Context

When self-building Wine 11 from the CodeWeavers LGPL tarball
(`crossover-sources-26.1.0.tar.gz`) and bundling Apple's GPTK
`libd3dshared.dylib` per [ADR-0005](0005-bundle-gptk-d3dmetal.md), running
Steam's CEF (Chromium Embedded Framework) GPU subprocess crashes
immediately and repeatedly with `exit_code=-2147483645` (0xC0000005,
STATUS_BREAKPOINT). After 6+ crashes the CEF supervisor disables GPU
acceleration permanently and Steam's window renders solid black.

The root cause lives in two CodeWeavers patches both present in the
upstream LGPL release:

- `dlls/ntdll/unix/loader.c` ("CW HACK 22434"): `init_non_native_support()`
  reads the env var `CX_APPLEGPTK_LIBD3DSHARED_PATH`, `dlopen`s it,
  records the `__TEXT` segment's load address and end address into the
  globals `libd3dshared_load_addr` and `libd3dshared_code_end`.
- `dlls/ntdll/unix/unix_private.h` ("CX Hack 23015"): `GPT_ABI_WRAPPER`
  generates asm trampolines for syscalls that may be entered from
  D3DMetal callbacks. The trampoline checks the return address against
  the libd3dshared `__TEXT` range. If the call originated inside
  libd3dshared it jumps to the `ms_abi` thunk; otherwise it falls
  through to the `sysv` thunk.

When `CX_APPLEGPTK_LIBD3DSHARED_PATH` is unset, `libd3dshared_load_addr`
stays NULL, the asm test `cmpq $0, (%rax)` succeeds, and every
trampoline falls through to the sysv path **including those actually
invoked from D3DMetal callbacks**. D3DMetal callbacks use the Windows
`ms_abi` (rcx/rdx/r8/r9 for first four args) while the sysv path
expects `rdi/rsi/rdx/rcx`. Argument registers are read from the wrong
locations, the callbacks corrupt state, and CEF's GPU subprocess
crashes with STATUS_BREAKPOINT on the first compositor frame.

CodeWeavers' own CrossOver build sets this env var as part of its
launcher infrastructure (`/opt/cxoffice/...`). Wineskin-built engines
inherit it from their wrapper scripts. We were not setting it.

## Decision

The shipped Wine launcher (`bin/calimocho-wine`) exports

```bash
export CX_APPLEGPTK_LIBD3DSHARED_PATH="${CX_APPLEGPTK_LIBD3DSHARED_PATH-$ENGINE/lib/external/libd3dshared.dylib}"
```

pointing at the bundled GPTK `libd3dshared.dylib` (per ADR-0005). The
user-overridable form (`${VAR-default}`) lets advanced users redirect
to a system GPTK install if they prefer.

The CW HACK code paths in our compiled `ntdll.so` and the trampolines
in `winemac.so` / `wow64.so` are byte-identical to CrossOver's because
they come from the same source tree we built — we just have to feed
the env var the patch was written to read.

## Consequences

Positive:
- Eliminates the entire class of CEF GPU subprocess STATUS_BREAKPOINT
  crashes for any app that uses D3DMetal callbacks (Steam, EA App,
  Battle.net launchers, Unity games using DX11).
- Adds zero new dependencies; the dylib was already bundled.
- Does not affect non-D3D apps (the trampolines short-circuit to sysv
  when libd3dshared isn't loaded for the calling process anyway).

Negative:
- Path is baked into the launcher script. If the engine bundle moves,
  the launcher must be regenerated. Acceptable: the launcher is part
  of the engine.

Neutral:
- The env var name carries the `CX_` (CodeWeavers) prefix in our
  shipped binary. We use it because the CW patches read exactly that
  name — renaming would require patching ntdll. Documented in error
  template + troubleshooting docs as a known reality.

## Related

- [ADR-0005](0005-bundle-gptk-d3dmetal.md) — bundling
  D3DMetal.framework and libd3dshared.dylib from GPTK.
- [ADR-0007](0007-compile-never-copy.md) — we build ntdll.so from the
  CodeWeavers source, never copy CrossOver's binary.
- [ADR-0012](0012-lgpl-written-offer-compliance.md) — the CW HACK code
  is in the LGPL tarball, so this discovery confirms CodeWeavers' source
  release is functionally complete for this case (no held-back patches).

## Investigation evidence

Performed 2026-06-01 against CrossOver 26.5
(`/Users/dragoshont/Applications/CrossOver.app`):

```bash
# Step 2 — strings dump on CrossOver's ntdll.so
strings ntdll.so | grep -iE '(libd3dshared|APPLEGPTK)'
# Output:
#   CX_APPLEGPTK_LIBD3DSHARED_PATH
#   Loaded libd3dshared.dylib, does%s support non-native code regions
#   Loading libd3dshared.dylib failed: %s
```

Both CrossOver's and our compiled `ntdll.so` produce identical strings,
confirming the patch is in the LGPL source.

Source location: [`/dlls/ntdll/unix/loader.c:1323`](https://gitlab.winehq.org/wine/wine/) (CW HACK 22434),
[`/dlls/ntdll/unix/unix_private.h:604-624`](https://gitlab.winehq.org/wine/wine/) (CX Hack 23015) — file paths from
crossover-sources-26.1.0.tar.gz.
