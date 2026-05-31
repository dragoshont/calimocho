#!/usr/bin/env bash
# scripts/overlay-gptk.sh
#
# Phase 1 deliverable. Copies Apple GPTK 3.0's D3DMetal.framework and
# libd3dshared.dylib into out/engine/lib/external/.
#
# Per AGENTS.md rule #1, GPTK is the one binary we redistribute unmodified,
# under Apple's GPTK SLA §2A iii + §2C (non-commercial).
#
# Source: the mounted "Evaluation environment for Windows games 3.0" DMG.
# If the DMG is not mounted, this script mounts it from
# $HOME/Downloads/Game_Porting_Toolkit_3.0.dmg.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out/engine"
DST="$OUT/lib/external"

GPTK_DMG="$HOME/Downloads/Game_Porting_Toolkit_3.0.dmg"
EVAL_DMG_INSIDE="/Volumes/Game Porting Toolkit/Evaluation environment for Windows games 3.0.dmg"
EVAL_VOL="/Volumes/Evaluation environment for Windows games 3.0"
REDIST="$EVAL_VOL/redist/lib/external"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] overlay-gptk: $*" >&2; }

mounted_outer=0
mounted_inner=0
cleanup() {
  if [[ $mounted_inner -eq 1 ]]; then hdiutil detach "$EVAL_VOL" -quiet || true; fi
  if [[ $mounted_outer -eq 1 ]]; then hdiutil detach "/Volumes/Game Porting Toolkit" -quiet || true; fi
}
trap cleanup EXIT

if [[ ! -d "$EVAL_VOL" ]]; then
  if [[ ! -d "/Volumes/Game Porting Toolkit" ]]; then
    [[ -f "$GPTK_DMG" ]] || { log "missing $GPTK_DMG — run fetch-sources.sh"; exit 8; }
    log "mounting $GPTK_DMG"
    hdiutil attach "$GPTK_DMG" -quiet -nobrowse
    mounted_outer=1
  fi
  log "mounting $EVAL_DMG_INSIDE"
  hdiutil attach "$EVAL_DMG_INSIDE" -quiet -nobrowse
  mounted_inner=1
fi

[[ -d "$REDIST" ]] || { log "redist dir missing at $REDIST"; exit 1; }

mkdir -p "$DST"
log "copying D3DMetal.framework -> $DST/"
rsync -a --delete "$REDIST/D3DMetal.framework/" "$DST/D3DMetal.framework/"
log "copying libd3dshared.dylib -> $DST/"
rsync -a "$REDIST/libd3dshared.dylib" "$DST/libd3dshared.dylib"

log "done"
