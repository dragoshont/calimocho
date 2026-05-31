#!/usr/bin/env bash
# scripts/sign-engine.sh
#
# Ad-hoc sign every Mach-O file under out/engine/ with the entitlements
# Wine needs on Apple Silicon (JIT, unsigned exec memory, disabled
# page-protection, dyld env vars). AGENTS.md rule #8 (ad-hoc only).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out/engine"
ENT="$REPO_ROOT/scripts/wine-entitlements.plist"

[[ -d "$OUT" ]] || { echo "sign-engine: $OUT missing" >&2; exit 1; }
[[ -f "$ENT" ]] || { echo "sign-engine: $ENT missing" >&2; exit 1; }

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] sign-engine: $*" >&2; }

count=0
while IFS= read -r -d '' f; do
  [[ -L "$f" ]] && continue
  # Detect Mach-O via `file` (handles thin + fat, arm64 + x86_64).
  if file -b "$f" | grep -q 'Mach-O'; then
    # Adhoc sign with entitlements + hardened runtime. The hardened
    # runtime is compatible with x86_64 Wine because the entitlements
    # plist grants the four loosening keys Wine needs:
    #   allow-jit, allow-unsigned-executable-memory,
    #   disable-executable-page-protection, allow-dyld-environment-vars,
    #   disable-library-validation.
    # The runtime flag adds defense-in-depth (DYLD_INSERT_LIBRARIES is
    # respected only with our entitlement, env-var injection from
    # outside is blocked, etc.) without breaking Wine.
    codesign --force --timestamp=none --sign - \
             --entitlements "$ENT" --options runtime "$f"
    count=$((count+1))
  fi
done < <(find "$OUT" -type f -print0)

log "signed $count Mach-O files in $OUT"
