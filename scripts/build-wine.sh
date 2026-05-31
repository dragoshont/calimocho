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

# Brew bison/flex are required (Apple's system bison 2.3 is too old for
# Wine's parser.y files). Pin PATH here so the script works regardless
# of caller environment.
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"

# We build x86_64 host (see ADR-0010). On Apple Silicon, force every
# configure/make invocation to run under Rosetta 2 so `uname -m`,
# `__x86_64__`, the C/ObjC compilers, and ld all see x86_64.
RUN_X86=()
if [[ "$(uname -m)" == "arm64" ]]; then
  command -v arch >/dev/null && RUN_X86=(arch -x86_64)
  # On Apple Silicon the build needs an *x86_64* Homebrew prefix
  # (/usr/local) for gnutls/freetype/sdl2/etc., because we are
  # producing an x86_64 binary that links against them. The native arm64
  # /opt/homebrew prefix is incompatible and is removed from PATH for
  # the duration of the build.
  X86_BREW="/usr/local/bin/brew"
  if [[ ! -x "$X86_BREW" ]]; then
    echo "build-wine: $X86_BREW not found — run scripts/prep-build-deps.sh first" >&2
    exit 1
  fi
  # Order matters: brew keg-only bison/flex first, then x86 brew prefix.
  export PATH="/usr/local/opt/bison/bin:/usr/local/opt/flex/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
  # pkg-config from x86 brew, looking at x86 brew prefix's .pc files.
  export PKG_CONFIG="/usr/local/bin/pkg-config"
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig"
  export PKG_CONFIG_LIBDIR="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig"
  # Wine's configure probes some headers (freetype's ft2build.h, sdl2,
  # etc.) by direct compile rather than pkg-config. Point the compiler
  # and linker at the x86 brew prefix so those probes succeed.
  export CPPFLAGS="-I/usr/local/include -I/usr/local/opt/freetype/include/freetype2 -I/usr/local/opt/libpng/include/libpng16"
  export LDFLAGS="-L/usr/local/lib"
fi

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] build-wine: $*" | tee -a "$LOG" >&2; }

[[ -d "$SRC" ]] || { log "wine source missing at $SRC — run fetch-sources.sh"; exit 1; }
mkdir -p "$BUILD" "$INSTALL" "$OUT" "$(dirname "$LOG")"

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
rsync -a --delete "$INSTALL/bin/"  "$OUT/bin/"
rsync -a --delete "$INSTALL/lib/"  "$OUT/lib/"
rsync -a --delete "$INSTALL/share/" "$OUT/share/"

log "done — engine staged at $OUT"
log "  $($OUT/bin/wine --version 2>&1 | head -1)"
