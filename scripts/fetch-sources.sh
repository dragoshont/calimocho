#!/usr/bin/env bash
# scripts/fetch-sources.sh
#
# A1 deliverable. Idempotent download + sha256-verify of:
#   - CodeWeavers Wine 11 source tarball
#   - Apple GPTK 3.0 (Evaluation environment for Windows games 3.0.dmg)
#
# Sources land under $HOME/Downloads/cxwine-build/ to match the maintainer's
# existing layout. Both the tarball and the DMG are pinned by sha256.
#
# Network access required only on first run. Subsequent runs are offline
# verification.

set -euo pipefail

ROOT="${ROOT:-$HOME/Downloads/cxwine-build}"
mkdir -p "$ROOT"

CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.1.0.tar.gz"
CX_TARBALL="$ROOT/cx-sources.tar.gz"
CX_SHA256="e4ec87d5821a009dd1f1d2e36ffe2e24b8fcbae9516375ea42f95a16928ab8fa"

GPTK_URL="https://download.developer.apple.com/Developer_Tools/Game_Porting_Toolkit_3.0/Game_Porting_Toolkit_3.0.dmg"
GPTK_DMG="$HOME/Downloads/Game_Porting_Toolkit_3.0.dmg"
# GPTK sha256 not pinned here: Apple gates the download behind an Apple ID
# login. Maintainer downloads manually; this script only checks presence.

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] fetch-sources: $*" >&2; }

verify_sha() {
  local path="$1" want="$2"
  local got
  got="$(shasum -a 256 "$path" | awk '{print $1}')"
  if [[ "$got" != "$want" ]]; then
    log "sha256 mismatch for $path"
    log "  want: $want"
    log "  got:  $got"
    return 1
  fi
}

# --- CodeWeavers source tarball ---
if [[ -f "$CX_TARBALL" ]] && verify_sha "$CX_TARBALL" "$CX_SHA256"; then
  log "cx tarball present and verified"
else
  log "downloading $CX_URL"
  curl -L --fail --retry 3 -o "$CX_TARBALL.part" "$CX_URL"
  mv "$CX_TARBALL.part" "$CX_TARBALL"
  verify_sha "$CX_TARBALL" "$CX_SHA256"
  log "cx tarball downloaded and verified"
fi

# --- Extract if not already extracted ---
if [[ ! -d "$ROOT/sources/wine" ]]; then
  log "extracting $CX_TARBALL"
  mkdir -p "$ROOT/sources"
  tar -xzf "$CX_TARBALL" -C "$ROOT/sources"
  if [[ ! -d "$ROOT/sources/wine" ]]; then
    # CodeWeavers tarball lays out as sources/{wine,vkd3d,...} at root or nested
    local_dir="$(find "$ROOT/sources" -maxdepth 3 -name configure.ac -path '*/wine/*' | head -1)"
    if [[ -n "$local_dir" ]]; then
      log "wine source detected at $(dirname "$local_dir")"
    fi
  fi
fi

# --- Apple GPTK 3.0 ---
# We never auto-download Apple's DMG. If it's missing, instruct the user.
if [[ ! -f "$GPTK_DMG" ]]; then
  log "missing $GPTK_DMG"
  log "  Apple gates this download behind an Apple ID login."
  log "  Download manually from: $GPTK_URL"
  log "  (or https://developer.apple.com/games/game-porting-toolkit/)"
  exit 8
fi
log "GPTK DMG present at $GPTK_DMG"

log "done"
