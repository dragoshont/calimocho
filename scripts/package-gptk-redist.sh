#!/usr/bin/env bash
# scripts/package-gptk-redist.sh
#
# MAINTAINER-ONLY one-off script. Builds a calimocho-hosted tarball of
# Apple GPTK Redistributables so that scripts/fetch-sources.sh can pull
# it from a stable URL in CI and on contributor machines that don't
# have GPTK pre-downloaded.
#
# Legal basis: Apple GPTK SLA §2A(iii) and §2C explicitly permit
# non-commercial distribution of the Redistributables separately from
# the Apple Software. License.rtf is included in the tarball verbatim
# (§2A "include all copyright notices"). See ADR-0011 for the full
# write-up.
#
# Workflow:
#   1. Mount the GPTK DMG (Evaluation environment for Windows games 3.0.dmg).
#   2. Run this script.
#   3. Upload the produced tarball as a GitHub Release asset under tag
#      `gptk-redist-<version>-<repack>`.
#   4. Paste the URL + sha256 printed at the end into versions.json
#      under `gptk_redist`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

GPTK_VERSION="3.0"
REPACK="1"
OUT_DIR="$REPO_ROOT/out/redist"
OUT_NAME="gptk-redist-${GPTK_VERSION}-${REPACK}.tar.zst"
OUT_PATH="$OUT_DIR/$OUT_NAME"

EVAL_VOL="/Volumes/Evaluation environment for Windows games 3.0"
REDIST="$EVAL_VOL/redist/lib/external"
LICENSE="$EVAL_VOL/License.rtf"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] package-gptk-redist: $*" >&2; }

# --- preconditions ---
if [[ ! -d "$EVAL_VOL" ]]; then
  log "ERROR: GPTK Evaluation DMG not mounted at $EVAL_VOL"
  log "       Mount Game_Porting_Toolkit_3.0.dmg, then mount the nested"
  log "       Evaluation environment for Windows games 3.0.dmg from it."
  exit 1
fi
[[ -d "$REDIST/D3DMetal.framework" ]] || { log "missing $REDIST/D3DMetal.framework"; exit 1; }
[[ -f "$REDIST/libd3dshared.dylib"  ]] || { log "missing $REDIST/libd3dshared.dylib"; exit 1; }
[[ -f "$LICENSE" ]]                    || { log "missing $LICENSE"; exit 1; }
command -v zstd >/dev/null || { log "ERROR: zstd not installed. brew install zstd"; exit 1; }

# --- stage into a temp tree ---
STAGE="$(mktemp -d -t gptk-redist.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/redist"
log "copying D3DMetal.framework"
rsync -a "$REDIST/D3DMetal.framework/" "$STAGE/redist/D3DMetal.framework/"
log "copying libd3dshared.dylib"
rsync -a "$REDIST/libd3dshared.dylib"  "$STAGE/redist/libd3dshared.dylib"
log "copying License.rtf (Apple GPTK SLA, included per §2A copyright-notices clause)"
cp "$LICENSE" "$STAGE/redist/License.rtf"

# Write a README so anyone untarring the file knows what it is.
cat >"$STAGE/redist/README.md" <<EOF
# Apple GPTK Redistributables (calimocho repack ${GPTK_VERSION}-${REPACK})

This tarball contains the **Redistributables** from Apple's Game Porting
Toolkit ${GPTK_VERSION}, separated from the rest of the Apple Software
per the Apple GPTK Software License Agreement §2C:

> Notwithstanding the foregoing, the Framework in its entirety or any
> part of the Redistributables may be distributed separately from the
> Apple Software.

Distribution is permitted for **non-commercial purposes only** per
§2A(iii):

> distribute the Apple Software solely for non-commercial purposes and
> in accordance with this Agreement, including Section 2C.

Contents:

- \`D3DMetal.framework/\` — Apple's DX12 → Metal translator
- \`libd3dshared.dylib\`  — companion library for D3DMetal
- \`License.rtf\`         — verbatim Apple GPTK SLA (§2A copyright-notices clause)

Calimocho ships this tarball as a non-commercial OSS project per
[ADR-0011](https://github.com/dragoshont/calimocho/blob/main/docs/ADR/0011-ci-and-gptk-redistribution.md).
Apple, the Game Porting Toolkit, D3DMetal, and Metal are trademarks of
Apple Inc. Calimocho is not affiliated with or endorsed by Apple.
EOF

# --- tar + zstd ---
log "packing $OUT_NAME"
mkdir -p "$OUT_DIR"
(cd "$STAGE" && tar --no-mac-metadata -cf - redist | zstd -19 -T0 -o "$OUT_PATH")

SHA="$(shasum -a 256 "$OUT_PATH" | awk '{print $1}')"
SIZE="$(stat -f %z "$OUT_PATH")"
SIZE_MB=$(( SIZE / 1024 / 1024 ))

cat <<EOF >&2

[$(ts)] package-gptk-redist: done.

  file:    $OUT_PATH
  sha256:  $SHA
  size:    ${SIZE} bytes (~${SIZE_MB} MB)

Next steps:
  1) Create a GitHub Release on dragoshont/calimocho with tag
     'gptk-redist-${GPTK_VERSION}-${REPACK}'.
  2) Upload $OUT_NAME as a release asset.
  3) Paste these into versions.json under "gptk_redist":
       "url":    "https://github.com/dragoshont/calimocho/releases/download/gptk-redist-${GPTK_VERSION}-${REPACK}/$OUT_NAME",
       "sha256": "$SHA",
  4) Commit versions.json; CI will then succeed.
EOF
