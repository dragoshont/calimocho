#!/usr/bin/env bash
# scripts/bundle-deps.sh
#
# Make the engine self-contained: copy every dylib Wine dlopens at
# runtime from /usr/local into out/engine/lib/external/runtime/, then
# rewrite their install names so the bundle is *fully* self-resolving
# regardless of whether /usr/local exists on the user's machine.
#
# Two-part fix vs. the simpler "just copy" approach:
#
#   1. Each bundled dylib gets its LC_ID_DYLIB set to
#      @rpath/<basename>, and every LC_LOAD_DYLIB pointing into
#      /usr/local/opt/<pkg>/lib/<name>.dylib is rewritten to
#      @loader_path/<name>.dylib. This means dyld never tries to
#      open an absolute /usr/local path that may not exist on the
#      user's Mac (which would be a hard failure on a future macOS
#      version that disables the basename-fallback behavior).
#
#   2. Wine's own dlopen by SONAME is handled by the wrapper's
#      DYLD_FALLBACK_LIBRARY_PATH — see bin/calimocho-wine. That
#      path's only job is finding the root SONAMEs by basename;
#      the transitive closure is then resolved internally via
#      @loader_path with no env-var involvement.
#
# install_name_tool invalidates ad-hoc signatures, so this script
# MUST run before sign-engine.sh. build-wine.sh enforces the order.
#
# License-attribution drift guard: README.md rows come from a
# license map keyed by the exact dylib basename. If a new dylib
# enters the closure (Homebrew dep edge change, gnutls bump, ...)
# whose basename is not in the map, the script fails loud and
# refuses to write a stale README.
#
# Idempotent.

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

# License map: basename -> "upstream-url|spdx-license"
# This is the single source of truth for attribution. Every dylib
# that ends up in the bundle MUST be recognized by license_for(),
# or the script refuses to write the README (prevents silent
# attribution drift if Homebrew adds a new transitive dep on a
# brew upgrade).
#
# Implemented as a case statement because macOS ships bash 3.2
# which has no associative arrays.
license_for() {
  case "$1" in
    libdbus-1.3.dylib)    echo "https://www.freedesktop.org/wiki/Software/dbus/|AFL-2.1 OR GPL-2.0+" ;;
    libfreetype.6.dylib)  echo "https://freetype.org/|FTL OR GPL-2.0" ;;
    libgnutls.30.dylib)   echo "https://www.gnutls.org/|LGPL-2.1+" ;;
    libSDL2-2.0.0.dylib)  echo "https://www.libsdl.org/|zlib" ;;
    libpng16.16.dylib)    echo "http://www.libpng.org/pub/png/libpng.html|libpng license" ;;
    libintl.8.dylib)      echo "https://www.gnu.org/software/gettext/|LGPL-2.1+" ;;
    libp11-kit.0.dylib)   echo "https://p11-glue.github.io/p11-glue/p11-kit.html|BSD-3-Clause" ;;
    libidn2.0.dylib)      echo "https://www.gnu.org/software/libidn/|LGPL-3.0+ OR GPL-2.0+" ;;
    libunistring.5.dylib) echo "https://www.gnu.org/software/libunistring/|LGPL-3.0+ OR GPL-2.0+" ;;
    libtasn1.6.dylib)     echo "https://www.gnu.org/software/libtasn1/|LGPL-2.1+" ;;
    libnettle.9.dylib)    echo "https://www.lysator.liu.se/~nisse/nettle/|LGPL-3.0+ OR GPL-2.0+" ;;
    libhogweed.7.dylib)   echo "https://www.lysator.liu.se/~nisse/nettle/|LGPL-3.0+ OR GPL-2.0+" ;;
    libgmp.10.dylib)      echo "https://gmplib.org/|LGPL-3.0+ OR GPL-2.0+" ;;
    *) return 1 ;;
  esac
}

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
  chmod u+w "$BUNDLE/$soname"
done

# --- Stage 2: walk transitive closure ---
# Each bundled dylib's LC_LOAD_DYLIB entries pointing at
# /usr/local/opt/<pkg>/lib/<dep>.dylib name a dep we must also copy.
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
        chmod u+w "$BUNDLE/$base"
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

# --- Stage 3: rewrite install names to be relocation-safe ---
# After this stage no bundled dylib has any LC_LOAD_DYLIB pointing
# at /usr/local. The bundle is fully self-resolving via @loader_path
# (which dyld resolves to the directory containing the loading
# dylib — exactly $BUNDLE for every entry here).
log "rewriting install names (LC_ID_DYLIB + LC_LOAD_DYLIB)"
while IFS= read -r f; do
  base="$(basename "$f")"
  # 1. Set the dylib's own id so anything loading it via @rpath/<base>
  #    or @loader_path/<base> sees the right name.
  install_name_tool -id "@rpath/$base" "$f"
  # 2. Rewrite every load command pointing at /usr/local/opt/.../X.dylib
  #    to @loader_path/X.dylib (sibling in the bundle by construction).
  while IFS= read -r dep; do
    depbase="$(basename "$dep")"
    install_name_tool -change "$dep" "@loader_path/$depbase" "$f"
  done < <(otool -L "$f" 2>/dev/null | awk '/^\t\/usr\/local\// {print $1}')
done < <(find "$BUNDLE" -name '*.dylib')

# --- Stage 4: verify no /usr/local references remain ---
leaks=$(find "$BUNDLE" -name '*.dylib' -exec sh -c 'otool -L "$1" 2>/dev/null | awk "/^\t\/usr\/local/ {print FILENAME\": \"\$1}" FILENAME="$1"' _ {} \; 2>/dev/null || true)
if [[ -n "$leaks" ]]; then
  log "ERROR: /usr/local references still present after rewrite:"
  echo "$leaks" >&2
  exit 1
fi

count=$(find "$BUNDLE" -name '*.dylib' | wc -l | tr -d ' ')
size=$(du -sk "$BUNDLE" | awk '{print $1}')
log "bundled $count dylibs (${size} KiB) into $BUNDLE — install names rewritten, no /usr/local refs"

# --- Stage 5: generate attribution README from actual bundle contents ---
# Fails loud if any bundled dylib is missing from LICENSE_MAP so the
# README can never drift from what's actually shipped.
log "generating attribution README from bundle contents"
mkdir -p "$THIRDPARTY/runtime-libs"

unknown=()
while IFS= read -r f; do
  base="$(basename "$f")"
  license_for "$base" >/dev/null 2>&1 || unknown+=("$base")
done < <(find "$BUNDLE" -name '*.dylib' | sort)

if (( ${#unknown[@]} > 0 )); then
  log "ERROR: bundled dylibs without license_for() entries:"
  for u in "${unknown[@]}"; do echo "  $u" >&2; done
  log "Add a case branch to license_for() in scripts/bundle-deps.sh before re-running."
  log "Find each license via: brew info \$(brew which-formula --explain <dylib-basename>)"
  exit 1
fi

{
  cat <<'HDR'
# Runtime dylib attribution

The following dynamic libraries are bundled inside calimocho's engine
under `out/engine/lib/external/runtime/` (and inside
`Calimocho.app/Contents/Resources/Engine/lib/external/runtime/` once
Phase 2 ships). They are Wine's runtime `dlopen` targets, populated
by `scripts/bundle-deps.sh` from the x86_64 Homebrew prefix
(`/usr/local/`).

Each entry below points at the upstream project home for license
text. Calimocho ships these unmodified except for install-name
rewrites (LC_ID_DYLIB → `@rpath/<basename>`, LC_LOAD_DYLIB → `@loader_path/<basename>`)
applied by `install_name_tool` to make the bundle self-resolving on
Macs without Homebrew. This rewrite does not change library
behavior; the binary code, ABI, and exported symbols are unchanged.

> **This table is auto-generated by `scripts/bundle-deps.sh`** from
> the actual bundle contents at build time. Do not edit by hand —
> changes here will be overwritten on the next build. To add a new
> dylib's attribution, edit `LICENSE_MAP` in `scripts/bundle-deps.sh`.

| dylib | upstream | license |
|---|---|---|
HDR
  while IFS= read -r f; do
    base="$(basename "$f")"
    IFS='|' read -r url lic <<<"$(license_for "$base")"
    printf "| %s | %s | %s |\n" "$base" "$url" "$lic"
  done < <(find "$BUNDLE" -name '*.dylib' | sort)
  cat <<'FTR'

All of these allow free redistribution provided the license terms are
reproduced. The above table satisfies the source-availability /
attribution requirement; the license texts live at the upstream URLs
linked above and inside each dylib's `__TEXT,__copyright` section
(visible with `strings <dylib> | grep -i copyright`).

The LGPL components in this list (gnutls, gettext, libidn2,
libunistring, libtasn1, nettle, gmp) follow the same
written-offer compliance model as Wine itself — see
[ADR-0012](../../docs/ADR/0012-lgpl-written-offer-compliance.md)
and `THIRDPARTY/Wine/NOTICE`. The same upstream-tarball-plus-no-
modifications guarantee applies: we ship verbatim copies (modulo
install_name_tool rewrites which do not alter the source code) and
recipients can rebuild from the upstream Homebrew formula.

If you redistribute calimocho, keep this README alongside the dylibs.
FTR
} >"$THIRDPARTY/runtime-libs/README.md"
log "wrote $THIRDPARTY/runtime-libs/README.md ($count entries)"

log "done"
