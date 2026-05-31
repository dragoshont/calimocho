#!/usr/bin/env bash
# scripts/fixup-config-h.sh
#
# A1.6 deliverable. Idempotent post-configure patch of build/wine/include/config.h.
#
# Wine's configure on macOS leaves a few defines in shapes that are either
# harmless-but-noisy or that have historically tripped people up. We pin
# them here so the build output is reproducible and so the build log has
# something concrete to point at.
#
# Touched defines:
#   EXEEXT           force `#define EXEEXT ""` (was `/* #undef EXEEXT */` in
#                    some configure runs; macOS executables have no extension).
#   PACKAGE_VERSION  force `#define PACKAGE_VERSION "<VERSION>"` so anything
#                    pulling it from config.h sees the same string the
#                    Makefile uses. Wine itself does not read it from
#                    config.h; bundled libs do.
#   PACKAGE_STRING   force `#define PACKAGE_STRING "Wine <VERSION>"`, same
#                    reasoning as PACKAGE_VERSION.
#
# Usage: scripts/fixup-config-h.sh [path/to/config.h] [version]
# Defaults: build/wine/include/config.h, 11.0

set -euo pipefail

CONFIG_H="${1:-build/wine/include/config.h}"
VERSION="${2:-11.0}"

if [[ ! -f "$CONFIG_H" ]]; then
  echo "fixup-config-h: $CONFIG_H not found" >&2
  exit 1
fi

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] fixup-config-h: $*" >&2; }

# In-place sed with macOS BSD sed semantics (-i '').
patch_define() {
  local name="$1" value="$2"
  if grep -qE "^/\* #undef ${name} \*/$" "$CONFIG_H"; then
    sed -i '' "s|^/\* #undef ${name} \*/$|#define ${name} ${value}|" "$CONFIG_H"
    log "patched ${name} -> ${value}"
  elif grep -qE "^#define ${name} " "$CONFIG_H"; then
    sed -i '' "s|^#define ${name} .*|#define ${name} ${value}|" "$CONFIG_H"
    log "rewrote ${name} -> ${value}"
  else
    # Inject just after the opening guard so we never lose the define.
    awk -v line="#define ${name} ${value}" '
      NR==1 { print; next }
      !done && /^#define __WINE_CONFIG_H$/ { print; print line; done=1; next }
      { print }
    ' "$CONFIG_H" >"${CONFIG_H}.tmp" && mv "${CONFIG_H}.tmp" "$CONFIG_H"
    log "injected ${name} -> ${value}"
  fi
}

patch_define EXEEXT '""'
patch_define PACKAGE_VERSION "\"${VERSION}\""
patch_define PACKAGE_STRING  "\"Wine ${VERSION}\""

# Autoconf 2.72's autoheader stopped emitting #define stubs for the C99
# "standard" headers (sys/stat.h, sys/types.h, stdint.h, stdlib.h,
# string.h, inttypes.h, STDC_HEADERS, ...). They are all unconditionally
# present on macOS. Wine itself uses these unconditionally — but a few
# files (e.g. dlls/ntdll/unix/msync.c in CodeWeavers' tree) wrap one
# include in `#ifdef HAVE_SYS_STAT_H`, which silently drops the
# declaration of struct stat / stat() and the build then fails with
# "variable has incomplete type 'struct stat'".
# Force-define them so those ifdefs activate.
patch_define HAVE_SYS_STAT_H  1
patch_define HAVE_SYS_TYPES_H 1
patch_define HAVE_STDINT_H    1
patch_define HAVE_STDLIB_H    1
patch_define HAVE_STRING_H    1
patch_define HAVE_INTTYPES_H  1
patch_define STDC_HEADERS     1

# CodeWeavers' dlls/win32u/vulkan.c references SONAME_LIBVULKAN
# unconditionally even when `configure --without-vulkan` was used (their
# CW HACK 25909 path). Provide the macOS soname so the file compiles;
# at runtime this is dlopen()'d and will simply ERR cleanly if no
# MoltenVK / libvulkan is present.
patch_define SONAME_LIBVULKAN '"libMoltenVK.dylib"'

log "done"
