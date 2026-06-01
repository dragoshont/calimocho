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

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${ROOT:-$HOME/Downloads/cxwine-build}"
mkdir -p "$ROOT"

CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.1.0.tar.gz"
CX_TARBALL="$ROOT/cx-sources.tar.gz"
CX_SHA256="e4ec87d5821a009dd1f1d2e36ffe2e24b8fcbae9516375ea42f95a16928ab8fa"

# GPTK Redistributables (D3DMetal.framework + libd3dshared.dylib) are
# hosted on calimocho's GitHub Releases per Apple GPTK SLA §2A(iii) +
# §2C, which explicitly permits non-commercial redistribution of the
# Redistributables separately from the Apple Software. See ADR-0011.
# versions.json holds the URL and sha256 (single source of truth).
GPTK_REDIST_TARBALL="$ROOT/gptk-redist.tar.zst"
if [[ -f "$REPO_ROOT/versions.json" ]] && command -v python3 >/dev/null; then
  GPTK_REDIST_URL="$(python3 -c "import json; print(json.load(open('$REPO_ROOT/versions.json'))['gptk_redist']['url'])" 2>/dev/null || true)"
  GPTK_REDIST_SHA256="$(python3 -c "import json; print(json.load(open('$REPO_ROOT/versions.json'))['gptk_redist']['sha256'])" 2>/dev/null || true)"
fi
GPTK_REDIST_URL="${GPTK_REDIST_URL:-}"
GPTK_REDIST_SHA256="${GPTK_REDIST_SHA256:-}"

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
  # CodeWeavers tarball is laid out as a directory of subdirs (wine,
  # vkd3d, mpg123, ...). It used to live at $ROOT/sources/wine, then
  # in a 2026 release moved to $ROOT/sources/sources/wine. Detect and
  # normalize to $ROOT/sources/wine so build-wine.sh's default SRC works.
  if [[ ! -d "$ROOT/sources/wine" ]]; then
    detected_cfg="$(find "$ROOT/sources" -maxdepth 4 -name configure.ac -path '*/wine/*' -print -quit 2>/dev/null || true)"
    detected_wine="${detected_cfg:+$(dirname "$detected_cfg")}"
    if [[ -z "$detected_wine" || ! -d "$detected_wine" ]]; then
      log "ERROR: wine source directory not found after extraction"
      exit 1
    fi
    # Move the containing directory's contents up one level so paths
    # match the expected $ROOT/sources/{wine,vkd3d,...}.
    parent="$(dirname "$detected_wine")"
    if [[ "$parent" != "$ROOT/sources" ]]; then
      log "normalizing $parent -> $ROOT/sources"
      mv "$parent"/* "$ROOT/sources/"
      rmdir "$parent" 2>/dev/null || true
    fi
  fi
  [[ -d "$ROOT/sources/wine" ]] || { log "ERROR: $ROOT/sources/wine still missing"; exit 1; }
fi
log "wine source: $ROOT/sources/wine"

# --- Apple GPTK Redistributables tarball (calimocho-hosted) ---
if [[ -z "$GPTK_REDIST_URL" || -z "$GPTK_REDIST_SHA256" ]]; then
  log "versions.json missing gptk_redist.{url,sha256}"
  log "  Maintainer bootstrap: run scripts/package-gptk-redist.sh to build"
  log "  the tarball, upload it as a GitHub Release asset, then fill"
  log "  gptk_redist in versions.json with the URL + sha256."
  exit 8
fi
if [[ -f "$GPTK_REDIST_TARBALL" ]] && verify_sha "$GPTK_REDIST_TARBALL" "$GPTK_REDIST_SHA256"; then
  log "GPTK redist tarball present and verified"
else
  log "downloading $GPTK_REDIST_URL"
  curl -L --fail --retry 3 -o "$GPTK_REDIST_TARBALL.part" "$GPTK_REDIST_URL"
  mv "$GPTK_REDIST_TARBALL.part" "$GPTK_REDIST_TARBALL"
  verify_sha "$GPTK_REDIST_TARBALL" "$GPTK_REDIST_SHA256"
  log "GPTK redist tarball downloaded and verified"
fi

log "done"
