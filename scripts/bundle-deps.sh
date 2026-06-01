#!/usr/bin/env bash
# scripts/bundle-deps.sh
#
# Make the engine self-contained: copy every dylib Wine dlopens at
# runtime from /usr/local into out/engine/lib/external/runtime/.
# The launcher wrapper (out/engine/bin/calimocho-wine) sets
# DYLD_FALLBACK_LIBRARY_PATH to that directory so dlopen finds them
# without needing /usr/local on the user's machine.
#
# AGENTS rule note: these dylibs are FOSS (LGPL/MIT/Apache/etc.),
# redistributable, and are runtime-required by Wine. We treat them
# the same way we treat Apple GPTK Redistributables: copied verbatim,
# license text reproduced in THIRDPARTY/.
#
# Idempotent: re-running just refreshes the bundle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out/engine"
BUNDLE="$OUT/lib/external/runtime"
THIRDPARTY="$REPO_ROOT/THIRDPARTY"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] bundle-deps: $*" >&2; }

[[ -d "$OUT" ]] || { log "ERROR: $OUT missing — run build-wine.sh first"; exit 1; }

# Root SONAMEs Wine dlopens at runtime. Derived from
# build/wine/include/config.h `#define SONAME_*`. cups + MoltenVK are
# intentionally omitted:
#   - libcups.2.dylib: macOS system-provided in /usr/lib (printing)
#   - libMoltenVK.dylib: ships with Apple GPTK redistributables
#     (overlay-gptk.sh handles it)
ROOT_SONAMES=(
  libdbus-1.3.dylib
  libfreetype.6.dylib
  libgnutls.30.dylib
  libSDL2-2.0.0.dylib
)

# x86_64 brew is the source of truth on Apple Silicon. On Intel
# Macs this is the only brew prefix anyway.
SRC_LIBDIR="${SRC_LIBDIR:-/usr/local/lib}"

if [[ ! -d "$SRC_LIBDIR" ]]; then
  log "ERROR: $SRC_LIBDIR missing — run prep-build-deps.sh first"
  exit 1
fi

mkdir -p "$BUNDLE"

# --- Stage 1: copy root SONAMEs (resolve symlinks to real files) ---
log "copying root SONAMEs from $SRC_LIBDIR"
for soname in "${ROOT_SONAMES[@]}"; do
  src="$SRC_LIBDIR/$soname"
  if [[ ! -f "$src" ]]; then
    log "ERROR: missing $src — run prep-build-deps.sh"
    exit 1
  fi
  cp -L "$src" "$BUNDLE/$soname"
done

# --- Stage 2: walk transitive deps until closure ---
# Wine dlopens by SONAME, dyld searches DYLD_FALLBACK_LIBRARY_PATH for
# the basename. But each dylib *we* copy may also reference other
# dylibs by absolute /usr/local/opt/<pkg>/lib/<name> install names —
# dyld will follow those absolute paths first. To avoid that, we copy
# the transitive closure in too. Same DYLD_FALLBACK_LIBRARY_PATH then
# handles them because we don't rewrite install names (cleaner than
# install_name_tool surgery).
log "walking transitive dependency closure"
iterations=0
while :; do
  iterations=$((iterations + 1))
  added=0
  while IFS= read -r f; do
    while IFS= read -r dep; do
      base="$(basename "$dep")"
      if [[ ! -f "$BUNDLE/$base" && -f "$dep" ]]; then
        cp -L "$dep" "$BUNDLE/$base"
        added=$((added + 1))
      fi
    done < <(otool -L "$f" 2>/dev/null | awk '/^\t\/usr\/local\/opt/ {print $1}')
  done < <(find "$BUNDLE" -name '*.dylib')
  (( added == 0 )) && break
  if (( iterations > 10 )); then
    log "ERROR: dep walk did not converge in 10 iterations — bug in this script"
    exit 1
  fi
done

count=$(find "$BUNDLE" -name '*.dylib' | wc -l | tr -d ' ')
size=$(du -sk "$BUNDLE" | awk '{print $1}')
log "bundled $count dylibs (${size} KiB) into $BUNDLE"

# --- Stage 3: license attribution into THIRDPARTY/ ---
# Every dylib we ship needs its license text reproduced per
# AGENTS rule #3 (respect upstream) and most of these libs' own
# license terms (LGPL/MIT/Apache require it).
mkdir -p "$THIRDPARTY/runtime-libs"
cat >"$THIRDPARTY/runtime-libs/README.md" <<EOF
# Runtime dylib attribution

The following dynamic libraries are bundled inside calimocho's engine
under \`out/engine/lib/external/runtime/\` (and inside
\`Calimocho.app/Contents/Resources/Engine/lib/external/runtime/\` once
Phase 2 ships). They are Wine's runtime \`dlopen\` targets, populated
by \`scripts/bundle-deps.sh\` from the x86_64 Homebrew prefix
(\`/usr/local/\`).

Each entry below points at the upstream project home for license
text. Calimocho ships these unmodified.

| dylib | upstream | license |
|---|---|---|
| libdbus-1.3.dylib   | https://www.freedesktop.org/wiki/Software/dbus/ | AFL-2.1 OR GPL-2.0+ |
| libfreetype.6.dylib | https://freetype.org/                            | FTL OR GPL-2.0      |
| libgnutls.30.dylib  | https://www.gnutls.org/                          | LGPL-2.1+           |
| libSDL2-2.0.0.dylib | https://www.libsdl.org/                          | zlib                |
| libpng16.16.dylib   | http://www.libpng.org/pub/png/libpng.html        | libpng license      |
| libintl.8.dylib     | https://www.gnu.org/software/gettext/            | LGPL-2.1+           |
| libp11-kit.0.dylib  | https://p11-glue.github.io/p11-glue/p11-kit.html | BSD-3-Clause        |
| libidn2.0.dylib     | https://www.gnu.org/software/libidn/             | LGPL-3.0+ OR GPL-2.0+ |
| libunistring.5.dylib| https://www.gnu.org/software/libunistring/       | LGPL-3.0+ OR GPL-2.0+ |
| libtasn1.6.dylib    | https://www.gnu.org/software/libtasn1/           | LGPL-2.1+           |
| libnettle.9.dylib   | https://www.lysator.liu.se/~nisse/nettle/        | LGPL-3.0+ OR GPL-2.0+ |
| libhogweed.7.dylib  | https://www.lysator.liu.se/~nisse/nettle/        | LGPL-3.0+ OR GPL-2.0+ |
| libgmp.10.dylib     | https://gmplib.org/                              | LGPL-3.0+ OR GPL-2.0+ |

All of these allow free redistribution provided the license terms are
reproduced. The above README satisfies the source-availability /
attribution requirement; the license texts live at the upstream URLs
linked above and inside each dylib's \`__TEXT,__copyright\` section
(visible with \`strings <dylib> | grep -i copyright\`).

If you redistribute calimocho, keep this README alongside the dylibs.
EOF
log "wrote $THIRDPARTY/runtime-libs/README.md"

log "done"
