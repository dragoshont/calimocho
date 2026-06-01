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

# Exit codes:
#   0  — comparison ran, no matches found (PASS)
#   1  — comparison ran, at least one match found (FAIL)
#   77 — comparison could not run (no CrossOver corpus) (SKIP, sysexits.h-ish)
# Callers (test-engine.sh) must distinguish SKIP from PASS so we don't
# claim AGENTS rule #1 enforcement when nothing was actually checked.
# (Reported by CodeRabbit review on PR #1.)
if [[ ! -d "$CX_LIB" ]]; then
  log "SKIP: CrossOver not installed at $CX_LIB — no comparison corpus"
  log "      install CrossOver Trial to enable A1.5; the CI matrix"
  log "      (Phase 5) runs A1.5 on a runner with CrossOver Trial."
  exit 77
fi

log "indexing CrossOver lib tree at $CX_LIB"
CX_SUMS="$(mktemp -t cx-sums.XXXXXX)"
trap 'rm -f "$CX_SUMS"' EXIT
find "$CX_LIB" -type f -print0 | xargs -0 -P 4 -n 64 shasum -a 256 | awk '{print $1}' | sort -u >"$CX_SUMS"
idx_count=$(wc -l <"$CX_SUMS" | tr -d ' ')
log "indexed $idx_count unique CrossOver files"
# Defensive: shasum prints stderr warnings on unreadable files but the
# pipeline still exits 0. A genuinely empty $CX_SUMS would make every
# subsequent grep -Fxq fail to match and we'd report "no violations"
# (false PASS). Fail loud instead. (CodeRabbit on PR #1.)
(( idx_count > 0 )) || { log "ERROR: CrossOver index is empty; indexing may have failed"; exit 1; }

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
