#!/usr/bin/env bash
# scripts/build-wine.sh
#
# A1 deliverable. End-to-end: configure (if needed) + fixup-config-h +
# make + make install into out/engine.
#
# Idempotent: re-running picks up where the previous run left off.
# Logs everything to docs/.phase1-make.log (appended).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SRC="${SRC:-$HOME/Downloads/cxwine-build/sources/wine}"
BUILD="$REPO_ROOT/build/wine"
INSTALL="$BUILD/_install"
OUT="$REPO_ROOT/out/engine"
LOG="$REPO_ROOT/docs/.phase1-make.log"

JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

# We build x86_64 host (see ADR-0010). On Apple Silicon, force every
# configure/make invocation to run under Rosetta 2 so `uname -m`,
# `__x86_64__`, the C/ObjC compilers, and ld all see x86_64. On an
# Intel Mac the host is already x86_64; RUN_X86 stays empty.
RUN_X86=()
if [[ "$(uname -m)" == "arm64" ]]; then
  command -v arch >/dev/null && RUN_X86=(arch -x86_64)
  # On Apple Silicon the build needs an *x86_64* Homebrew prefix
  # (/usr/local) for gnutls/freetype/sdl2/etc., because we are
  # producing an x86_64 binary that links against them. The native arm64
  # /opt/homebrew prefix is incompatible and is removed from PATH for
  # the duration of the build.
  BREW_PREFIX="/usr/local"
else
  # Intel Mac: native x86_64 brew is at /usr/local (the only brew
  # prefix Intel Macs have).
  BREW_PREFIX="/usr/local"
fi
X86_BREW="$BREW_PREFIX/bin/brew"
if [[ ! -x "$X86_BREW" ]]; then
  echo "build-wine: $X86_BREW not found — run scripts/prep-build-deps.sh first" >&2
  exit 1
fi
# Order matters: brew keg-only bison/flex first, then x86 brew prefix.
# This applies to both Apple Silicon (under Rosetta) and Intel.
export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/opt/flex/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG="$BREW_PREFIX/bin/pkg-config"
export PKG_CONFIG_PATH="$BREW_PREFIX/lib/pkgconfig:$BREW_PREFIX/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$BREW_PREFIX/lib/pkgconfig:$BREW_PREFIX/share/pkgconfig"
# Wine's configure probes some headers (freetype's ft2build.h, sdl2,
# etc.) by direct compile rather than pkg-config. Point the compiler
# and linker at the x86 brew prefix so those probes succeed.
export CPPFLAGS="-I$BREW_PREFIX/include -I$BREW_PREFIX/opt/freetype/include/freetype2 -I$BREW_PREFIX/opt/libpng/include/libpng16"
export LDFLAGS="-L$BREW_PREFIX/lib"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] build-wine: $*" | tee -a "$LOG" >&2; }

[[ -d "$SRC" ]] || { log "wine source missing at $SRC — run fetch-sources.sh"; exit 1; }
mkdir -p "$BUILD" "$INSTALL" "$OUT" "$(dirname "$LOG")"

# Ensure calimocho patches are applied. patch-sources.sh is idempotent
# (marker-based); skipping when already applied is cheap. Skipping
# entirely means we'd build against unpatched upstream sources and
# silently miss e.g. the wineloader bundle ID rename (ADR-0009).
"$REPO_ROOT/scripts/patch-sources.sh" "$SRC" >>"$LOG" 2>&1

# --- configure (only if not already configured) ---
if [[ ! -f "$BUILD/Makefile" ]]; then
  log "configuring (prefix=$INSTALL)"
  # Host arch is x86_64 only — see ADR-0010. On Apple Silicon the
  # resulting binaries run under Rosetta 2. We do NOT pass aarch64
  # in --enable-archs; macOS 26 AppleSystemPolicy refuses to exec
  # ad-hoc-signed native arm64 Wine loaders.
  (cd "$BUILD" && "${RUN_X86[@]}" "$SRC/configure" \
      --prefix="$INSTALL" \
      --enable-archs=x86_64,i386 \
      --without-x \
      --disable-tests \
      --with-mingw \
      --with-gnutls \
      --without-gstreamer \
      --without-cms \
      --without-coreaudio \
      --without-fontconfig \
      --without-pcap \
      --without-vulkan \
      --without-vkd3d \
      --without-opencl \
  ) >>"$LOG" 2>&1
fi

# --- always run the config.h fixup (idempotent) ---
"$REPO_ROOT/scripts/fixup-config-h.sh" "$BUILD/include/config.h" 11.0 >>"$LOG" 2>&1

# --- make ---
log "make -j$JOBS (this takes a while)"
{ echo "=== make start $(ts)"; time "${RUN_X86[@]}" make -C "$BUILD" -j"$JOBS"; echo "=== make end $(ts)"; } >>"$LOG" 2>&1

# --- make install ---
log "make install"
{ echo "=== install start $(ts)"; "${RUN_X86[@]}" make -C "$BUILD" install; echo "=== install end $(ts)"; } >>"$LOG" 2>&1

# --- stage into out/engine ---
log "staging out/engine from $INSTALL"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/share"
# rsync preserves symlinks (wine64 -> wine, wineserver64 -> wineserver, etc.)
# CRITICAL: --exclude=external on the lib/ stage. out/engine/lib/external/
# is populated by scripts/overlay-gptk.sh with Apple GPTK D3DMetal and
# is NOT present in $INSTALL/lib/. Without --exclude=external, every
# re-run of build-wine.sh would silently wipe the bundled D3DMetal
# framework and the engine would lose GPU acceleration without any
# error. (Reported by Copilot review on PR #1.)
rsync -a --delete "$INSTALL/bin/"  "$OUT/bin/"
rsync -a --delete --exclude=external "$INSTALL/lib/"  "$OUT/lib/"
rsync -a --delete "$INSTALL/share/" "$OUT/share/"

# --- install calimocho-wine wrapper ---
# The wrapper bakes in WINEDLLOVERRIDES, DYLD_FALLBACK_LIBRARY_PATH,
# WINEDEBUG. It's the canonical entry point — Phase 2 Calimocho.app
# calls this, not `bin/wine` directly. See A1.5.10 in PHASES.md.
log "installing calimocho-wine wrapper into out/engine/bin/"
cp "$REPO_ROOT/bin/calimocho-wine" "$OUT/bin/calimocho-wine"
chmod +x "$OUT/bin/calimocho-wine"

# --- bundle runtime dylibs ---
# Wine dlopens libfreetype/libgnutls/etc. at runtime. bundle-deps.sh
# copies them and their transitive closure into lib/external/runtime/
# so the engine is self-contained (works on Macs without Homebrew).
# See A1.5.9 in PHASES.md.
log "bundling runtime dylibs (libfreetype, libgnutls, ...)"
SRC_LIBDIR="${BREW_PREFIX}/lib" "$REPO_ROOT/scripts/bundle-deps.sh" >>"$LOG" 2>&1

log "done — engine staged at $OUT"
log "  $($OUT/bin/wine --version 2>&1 | head -1)"
