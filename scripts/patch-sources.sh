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
  # Idempotency check via content marker.
  # BSD patch (macOS) is unreliable for this: --dry-run --reverse and
  # --dry-run forward both exit 0 against small hunks where unchanged
  # context lines still match the file. So instead, every patch in
  # this repo declares an "applied marker" string in a comment of
  # the form "# applied-marker: <unique substring>" near the top.
  # We grep the touched file(s) for that marker.
  marker="$(awk -F': ' '/^# applied-marker:/ {print $2; exit}' "$p")"
  if [[ -z "$marker" ]]; then
    log "$name has no '# applied-marker:' header — refusing to apply blindly"
    exit 1
  fi
  # Touched files: parse `+++ b/<path>` lines from the patch.
  # diff -u commonly appends a tab + timestamp to +++ headers; strip
  # anything from the first tab or space onwards. (Reported by Copilot
  # review on PR #1.)
  touched=()
  while IFS= read -r line; do
    path="${line#+++ b/}"
    path="${path%%[$'\t ']*}"
    touched+=("$SRC/$path")
  done < <(grep '^+++ b/' "$p")
  if (( ${#touched[@]} == 0 )); then
    log "$name: could not detect touched files (no '+++ b/' headers)"
    exit 1
  fi
  if grep -qF "$marker" "${touched[@]}" 2>/dev/null; then
    log "$name already applied (marker '$marker' present)"
    continue
  fi
  if (cd "$SRC" && patch -p1 --batch <"$p") >/dev/null 2>&1; then
    if grep -qF "$marker" "${touched[@]}" 2>/dev/null; then
      log "$name applied"
    else
      log "$name applied but marker '$marker' not found post-apply — patch is malformed"
      exit 1
    fi
  else
    log "$name does not apply cleanly — aborting"
    (cd "$SRC" && patch -p1 --batch --dry-run <"$p") >&2 || true
    exit 1
  fi
done

# After patches: copy in any standalone source files we maintain in
# patches/wine/files/<dll>/. These are NEW files (no upstream
# counterpart) that would balloon the patch size if inlined. The
# canonical copy lives in our repo, readable as plain C; the patches
# only contain edits to EXISTING upstream files.
#
# Rationale: a 500-line C file embedded in a unified diff is
# unreadable. Keeping it as a regular .c file in the repo means
# `wc -l`, `clangd`, `grep`, and code review all work normally.
#
# Idempotent: rsync only copies when source is newer or size differs.
if [[ -d "$PATCH_DIR/files" ]]; then
  log "syncing standalone source files from $PATCH_DIR/files/ -> $SRC/dlls/"
  while IFS= read -r -d '' f; do
    rel="${f#"$PATCH_DIR"/files/}"
    dst="$SRC/dlls/$rel"
    mkdir -p "$(dirname "$dst")"
    if [[ ! -f "$dst" ]] || ! cmp -s "$f" "$dst"; then
      cp "$f" "$dst"
      log "  installed dlls/$rel"
    fi
  done < <(find "$PATCH_DIR/files" -type f -print0)
fi

log "done"
