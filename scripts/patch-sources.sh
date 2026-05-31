#!/usr/bin/env bash
# scripts/patch-sources.sh
#
# Apply calimocho's source patches to the extracted CodeWeavers Wine tree.
# Idempotent: skips patches that are already applied.
#
# Usage: scripts/patch-sources.sh [path-to-wine-source-tree]
# Default: $HOME/Downloads/cxwine-build/sources/wine

set -euo pipefail

SRC="${1:-$HOME/Downloads/cxwine-build/sources/wine}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/patches/wine"

[[ -d "$SRC" ]] || { echo "patch-sources: source tree not found at $SRC" >&2; exit 1; }
[[ -d "$PATCH_DIR" ]] || { echo "patch-sources: no patches dir at $PATCH_DIR (nothing to do)"; exit 0; }

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] patch-sources: $*" >&2; }

shopt -s nullglob
for p in "$PATCH_DIR"/*.patch; do
  name="$(basename "$p")"
  if (cd "$SRC" && patch -p1 --dry-run --reverse --silent <"$p" >/dev/null 2>&1); then
    log "$name already applied (skip)"
    continue
  fi
  if ! (cd "$SRC" && patch -p1 --dry-run --silent <"$p" >/dev/null 2>&1); then
    log "$name does not apply cleanly — aborting"
    (cd "$SRC" && patch -p1 --dry-run <"$p") >&2 || true
    exit 1
  fi
  (cd "$SRC" && patch -p1 <"$p")
  log "$name applied"
done
log "done"
