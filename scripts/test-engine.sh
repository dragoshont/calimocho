#!/usr/bin/env bash
# scripts/test-engine.sh
#
# Phase 1 acceptance: runs A1.1, A1.2, A1.3, A1.5 in sequence (A1.4
# requires a pre-installed Steam bottle and is skipped unless --with-steam
# is passed; A1.6 is a docs check, run separately).
#
# Each criterion prints PASS/FAIL/SKIP and the script exits non-zero on
# any FAIL.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out/engine"
# Use the calimocho-wine wrapper. It bakes in WINEDLLOVERRIDES,
# DYLD_FALLBACK_LIBRARY_PATH, and WINEDEBUG so callers (and Phase 2
# Calimocho.app's EngineLauncher) don't repeat the boilerplate.
# Tests still need the raw `wine` binary for --version (A1.1) so the
# string match is stable; everything else goes through the wrapper.
WINE="$OUT/bin/calimocho-wine"
WINE_RAW="$OUT/bin/wine"

WITH_STEAM=0
USER_PFX=""
for a in "$@"; do
  case "$a" in
    --with-steam)   WITH_STEAM=1 ;;
    --prefix=*)     USER_PFX="${a#--prefix=}" ;;
  esac
done

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { printf '[%s] test-engine: %s\n' "$(ts)" "$*" >&2; }
ok()   { say "PASS $*"; }
fail() { say "FAIL $*"; FAILED=1; }
skip() { say "SKIP $*"; }

FAILED=0

# We do NOT pkill -f wineserver here. That would SIGKILL any other
# calimocho engine running for the user (e.g. Phase 2+ Calimocho.app).
# Instead, we use a per-test WINEPREFIX (set below); each prefix gets
# its own wineserver, and cleanup() below shuts down only ours by
# pointing wineserver -k at our WINEPREFIX.

[[ -x "$WINE" ]] || { say "engine missing at $WINE — run build-wine.sh + bundle-deps.sh first"; exit 3; }
[[ -x "$WINE_RAW" ]] || { say "raw wine missing at $WINE_RAW — run build-wine.sh first"; exit 3; }

# --- A1.1 wine --version ---
# A1.1 spec is on the underlying `wine` binary (not the wrapper) so
# the string match is unambiguous. Wrapper adds no extra output that
# could trip this; checked both to be safe.
say "A1.1 wine --version"
ver="$("$WINE_RAW" --version 2>&1 || true)"
say "  reported: $ver"
if [[ "$ver" == wine-11.0* ]]; then ok A1.1; else fail "A1.1 (got: $ver)"; fi

# --- A1.2 wineboot --init on a clean prefix ---
say "A1.2 wineboot --init on clean prefix"
# Use the caller-supplied prefix when --prefix=/path is given (useful
# when --with-steam needs to point at a real Steam-installed bottle).
# Otherwise create an ephemeral temp prefix.
if [[ -n "$USER_PFX" ]]; then
  PFX="$USER_PFX"
  PFX_IS_TEMP=0
else
  PFX="$(mktemp -d -t calimocho-pfx.XXXXXX)"
  PFX_IS_TEMP=1
fi
cleanup() {
  # Only shut down OUR wineserver — the one bound to OUR WINEPREFIX.
  # `wineserver -k` is the polite way: signals every wine process that
  # shares this prefix and waits for them to exit. -w would wait
  # indefinitely; -k is the kill-then-wait variant.
  WINEPREFIX="$PFX" "$OUT/bin/wineserver" -k 2>/dev/null || true
  (( PFX_IS_TEMP )) && rm -rf "$PFX"
}
trap cleanup EXIT
export WINEPREFIX="$PFX"
# WINEDEBUG, WINEDLLOVERRIDES, DYLD_FALLBACK_LIBRARY_PATH are now
# baked into the calimocho-wine wrapper (A1.5.x). Tests don't need
# to set them. Callers can still override.

t0=$(date +%s)
if "$WINE" wineboot --init >/dev/null 2>>"$REPO_ROOT/docs/.phase1-make.log"; then
  # Wait for wineserver to actually flush system.reg to disk. wineboot
  # returns before its wineserver child has finished writing the
  # registry, especially under Rosetta where filesystem latency is
  # higher. Wait up to 60s.
  for _i in $(seq 1 60); do
    [[ -s "$PFX/system.reg" ]] && break
    sleep 1
  done
  t1=$(date +%s); dur=$((t1 - t0))
  say "  wineboot exited 0 in ${dur}s"
  # SPECS A1.2 mandates `#arch=win64` in system.reg (proves it's a
  # 64-bit prefix). Wine doesn't write its own version string into
  # system.reg — the version is verified by A1.1 (`wine --version`).
  # So A1.2 asserts only what is actually verifiable post-wineboot:
  #   - system.reg exists and is non-empty
  #   - `WINE REGISTRY Version 2` header (proves it's a real reg file)
  #   - `#arch=win64` (proves it's a 64-bit prefix per A1.2 spec)
  if [[ ! -s "$PFX/system.reg" ]]; then
    fail "A1.2 (system.reg missing or empty)"
  elif ! grep -Fq 'WINE REGISTRY Version 2' "$PFX/system.reg"; then
    fail "A1.2 (system.reg missing 'WINE REGISTRY Version 2' header)"
  elif ! grep -Fq '#arch=win64' "$PFX/system.reg"; then
    fail "A1.2 (system.reg has no '#arch=win64' header — prefix is not 64-bit)"
  else
    ok "A1.2 (prefix is win64, system.reg well-formed)"
  fi
else
  fail "A1.2 (wineboot --init non-zero)"
fi

# --- A1.3 notepad visible ---
# SPECS A1.3 mandates a visible window verified by screencapture + NCC
# >= 0.85 against tests/visual/baseline/notepad-window.png. That
# baseline and Tier 3 harness are Phase 5 deliverables (see PHASES.md
# Phase 1.5 followups). Until then, A1.3 is reported as DEFERRED —
# the "process alive after 6s" check below is a smoke test, not the
# acceptance criterion. (Reported by CodeRabbit on PR #1.)
say "A1.3 wine notepad.exe (smoke + DEFERRED full visual NCC check)"
"$WINE" notepad.exe >/dev/null 2>&1 &
NP_PID=$!
sleep 6
if kill -0 "$NP_PID" 2>/dev/null; then
  say "  notepad process alive after 6s (smoke ok)"
  kill "$NP_PID" 2>/dev/null || true
  wait "$NP_PID" 2>/dev/null || true
else
  fail "A1.3 (notepad process died within 6s — smoke check failed)"
fi
skip "A1.3 (visual NCC ≥ 0.85 deferred to Phase 5 baseline harness)"

# --- A1.4 Steam login ---
if (( WITH_STEAM )); then
  say "A1.4 Steam login window"
  if [[ -z "$USER_PFX" ]]; then
    skip "A1.4 (--with-steam needs --prefix=/path/to/steam-installed-bottle; the ephemeral temp prefix has no Steam)"
  else
    STEAM_EXE="$PFX/drive_c/Program Files (x86)/Steam/steam.exe"
    if [[ -f "$STEAM_EXE" ]]; then
      "$WINE" "$STEAM_EXE" >/dev/null 2>&1 &
      sleep 30
      if pgrep -fl steamwebhelper >/dev/null; then
        ok "A1.4 (steamwebhelper running)"
      else
        fail "A1.4 (steamwebhelper not running after 30s)"
      fi
      # cleanup() will wineserver -k against this prefix — don't pkill.
    else
      skip "A1.4 (Steam not installed at $STEAM_EXE in supplied prefix)"
    fi
  fi
else
  skip "A1.4 (re-run with --with-steam --prefix=/path against a Steam-installed prefix)"
fi

# --- A1.5 no copied CrossOver binaries ---
say "A1.5 no copied CrossOver binaries"
set +e
"$REPO_ROOT/scripts/verify-no-copied-binaries.sh" >/dev/null 2>&1
v_ec=$?
set -e
case $v_ec in
  0)  ok A1.5 ;;
  77) skip "A1.5 (CrossOver not installed — no comparison corpus; Phase 5 CI matrix runs this against a CrossOver Trial runner)" ;;
  *)  fail "A1.5 (verify-no-copied-binaries.sh exit=$v_ec)" ;;
esac

if (( FAILED )); then
  say "OVERALL: FAIL"
  exit 1
fi
say "OVERALL: PASS"
