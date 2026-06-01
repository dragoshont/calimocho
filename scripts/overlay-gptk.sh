#!/usr/bin/env bash
# scripts/overlay-gptk.sh
#
# Phase 1 deliverable. Copies Apple GPTK 3.0's D3DMetal.framework and
# libd3dshared.dylib into out/engine/lib/external/.
#
# Per AGENTS.md rule #1, GPTK is the one binary we redistribute
# unmodified, under Apple's GPTK SLA §2A(iii) + §2C (non-commercial).
# See ADR-0005 and ADR-0011.
#
# Source resolution order:
#   1. $REDIST_TARBALL (default $HOME/Downloads/cxwine-build/gptk-redist.tar.zst)
#      — the calimocho-hosted Redistributables tarball that
#      fetch-sources.sh pulls down. Used by CI and by contributors.
#   2. /Volumes/Evaluation environment for Windows games 3.0/redist/
#      — the mounted GPTK DMG. Maintainer iteration path for when
#      package-gptk-redist.sh itself is being changed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out/engine"
DST="$OUT/lib/external"

REDIST_TARBALL="${REDIST_TARBALL:-$HOME/Downloads/cxwine-build/gptk-redist.tar.zst}"
EVAL_VOL="/Volumes/Evaluation environment for Windows games 3.0"
DMG_REDIST="$EVAL_VOL/redist/lib/external"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] overlay-gptk: $*" >&2; }

mkdir -p "$DST"

if [[ -f "$REDIST_TARBALL" ]]; then
  log "using calimocho-hosted GPTK Redistributables: $REDIST_TARBALL"
  command -v zstd >/dev/null || { log "ERROR: zstd not installed. brew install zstd"; exit 1; }
  STAGE="$(mktemp -d -t gptk-redist-extract.XXXXXX)"
  trap 'rm -rf "$STAGE"' EXIT
  zstd -d -c "$REDIST_TARBALL" | tar -xf - -C "$STAGE"
  [[ -d "$STAGE/redist/D3DMetal.framework" ]] || { log "ERROR: tarball missing D3DMetal.framework"; exit 1; }
  rsync -a --delete "$STAGE/redist/D3DMetal.framework/" "$DST/D3DMetal.framework/"
  rsync -a          "$STAGE/redist/libd3dshared.dylib"  "$DST/libd3dshared.dylib"
  if [[ -f "$STAGE/redist/License.rtf" ]]; then
    mkdir -p "$REPO_ROOT/THIRDPARTY/Apple-GPTK"
    cp "$STAGE/redist/License.rtf" "$REPO_ROOT/THIRDPARTY/Apple-GPTK/License.rtf"
    log "copied License.rtf -> THIRDPARTY/Apple-GPTK/ (per §2A copyright-notices clause)"
  fi
  log "done (from redist tarball)"
  exit 0
fi

if [[ -d "$DMG_REDIST" ]]; then
  log "using mounted GPTK DMG: $DMG_REDIST"
  rsync -a --delete "$DMG_REDIST/D3DMetal.framework/" "$DST/D3DMetal.framework/"
  rsync -a          "$DMG_REDIST/libd3dshared.dylib"  "$DST/libd3dshared.dylib"
  if [[ -f "$EVAL_VOL/License.rtf" ]]; then
    mkdir -p "$REPO_ROOT/THIRDPARTY/Apple-GPTK"
    cp "$EVAL_VOL/License.rtf" "$REPO_ROOT/THIRDPARTY/Apple-GPTK/License.rtf"
    log "copied License.rtf -> THIRDPARTY/Apple-GPTK/ (per §2A copyright-notices clause)"
  fi
  log "done (from mounted DMG)"
  exit 0
fi

log "ERROR: no GPTK Redistributables source found."
log "       Expected one of:"
log "         $REDIST_TARBALL"
log "         $DMG_REDIST"
log "       Run scripts/fetch-sources.sh first (downloads the tarball),"
log "       or mount the GPTK DMG manually."
exit 1
