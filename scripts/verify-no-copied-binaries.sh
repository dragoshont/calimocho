#!/usr/bin/env bash
# scripts/verify-no-copied-binaries.sh
#
# AGENTS.md hard rule #1 enforcement (A1.5).
#
# Walk every file under out/engine and assert that none of them shares a
# sha256 with any file under /Applications/CrossOver.app's Wine lib tree.
#
# Files under out/engine/lib/external/ (D3DMetal, libd3dshared) are
# expected to match Apple GPTK's redistributed binaries — they are checked
# only against CrossOver, never sourced from it.
#
# Exit 0: no CrossOver binaries copied. Exit 1: at least one match found.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out/engine"
CX_LIB="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] verify-no-copied-binaries: $*" >&2; }

[[ -d "$OUT" ]] || { log "out/engine missing — nothing to verify"; exit 0; }

if [[ ! -d "$CX_LIB" ]]; then
  log "CrossOver not installed at $CX_LIB — rule trivially holds"
  exit 0
fi

log "indexing CrossOver lib tree at $CX_LIB"
CX_SUMS="$(mktemp -t cx-sums.XXXXXX)"
trap 'rm -f "$CX_SUMS"' EXIT
find "$CX_LIB" -type f -print0 | xargs -0 -P 4 -n 64 shasum -a 256 | awk '{print $1}' | sort -u >"$CX_SUMS"
log "indexed $(wc -l <"$CX_SUMS" | tr -d ' ') unique CrossOver files"

log "scanning $OUT"
violations=0
while IFS= read -r -d '' f; do
  sum="$(shasum -a 256 "$f" | awk '{print $1}')"
  if grep -Fxq "$sum" "$CX_SUMS"; then
    log "VIOLATION: $f matches a CrossOver binary (sha256=$sum)"
    violations=$((violations + 1))
  fi
done < <(find "$OUT" -type f -print0)

if (( violations > 0 )); then
  log "FAIL: $violations file(s) match CrossOver binaries"
  exit 1
fi
log "PASS: no out/engine file matches any CrossOver binary"
