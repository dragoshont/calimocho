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
WINE="$OUT/bin/wine"

WITH_STEAM=0
for a in "$@"; do
  case "$a" in
    --with-steam) WITH_STEAM=1 ;;
  esac
done

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { printf '[%s] test-engine: %s\n' "$(ts)" "$*" >&2; }
ok()   { say "PASS $*"; }
fail() { say "FAIL $*"; FAILED=1; }
skip() { say "SKIP $*"; }

FAILED=0

# Always start from a clean process slate — leftover wineservers from a
# previous run cause spurious "instant" wineboot exits without a real
# init (the existing server "handles" the request and returns).
pkill -9 -f wineserver 2>/dev/null || true
pkill -9 -f "$OUT/bin/wine" 2>/dev/null || true
sleep 1

[[ -x "$WINE" ]] || { say "engine missing at $WINE — run build-wine.sh first"; exit 3; }

# --- A1.1 wine --version ---
say "A1.1 wine --version"
ver="$("$WINE" --version 2>&1 || true)"
say "  reported: $ver"
if [[ "$ver" == wine-11.0* ]]; then ok A1.1; else fail "A1.1 (got: $ver)"; fi

# --- A1.2 wineboot --init on a clean prefix ---
say "A1.2 wineboot --init on clean prefix"
PFX="$(mktemp -d -t calimocho-pfx.XXXXXX)"
cleanup() {
  pkill -9 -f wineserver 2>/dev/null || true
  pkill -9 -f "$OUT/bin/wine" 2>/dev/null || true
  rm -rf "$PFX"
}
trap cleanup EXIT
export WINEPREFIX="$PFX"
export WINEDEBUG="${WINEDEBUG:-fixme-all,err-all}"
# Skip the Wine Mono / Gecko first-prefix prompts (interactive dialogs).
# Calimocho's scope doesn't include .NET-based Windows apps; SN2 and
# Steam don't need them.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
# Wine dlopen's libfreetype etc. by SONAME and expects them on the
# standard dyld path. We installed them via the x86_64 brew at
# /usr/local/. Make sure runtime dlopen finds them.
export DYLD_FALLBACK_LIBRARY_PATH="${DYLD_FALLBACK_LIBRARY_PATH:-/usr/local/lib:/usr/lib}"

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
  if [[ -f "$PFX/system.reg" ]] && grep -qiE 'wineversion|#arch' "$PFX/system.reg"; then
    ok "A1.2 (prefix created, system.reg present)"
  else
    fail "A1.2 (system.reg missing or empty)"
  fi
else
  fail "A1.2 (wineboot --init non-zero)"
fi

# --- A1.3 notepad visible ---
say "A1.3 wine notepad.exe"
"$WINE" notepad.exe >/dev/null 2>&1 &
NP_PID=$!
sleep 6
if kill -0 "$NP_PID" 2>/dev/null; then
  ok "A1.3 (notepad process alive — visual NCC check is a Tier 3 task, deferred)"
  kill "$NP_PID" 2>/dev/null || true
  wait "$NP_PID" 2>/dev/null || true
else
  fail "A1.3 (notepad process died within 6s)"
fi

# --- A1.4 Steam login ---
if (( WITH_STEAM )); then
  say "A1.4 Steam login window"
  STEAM_EXE="$PFX/drive_c/Program Files (x86)/Steam/steam.exe"
  if [[ -f "$STEAM_EXE" ]]; then
    "$WINE" "$STEAM_EXE" >/dev/null 2>&1 &
    sleep 30
    if pgrep -fl steamwebhelper >/dev/null; then
      ok "A1.4 (steamwebhelper running)"
    else
      fail "A1.4 (steamwebhelper not running after 30s)"
    fi
    pkill -f steam.exe 2>/dev/null || true
  else
    skip "A1.4 (Steam not installed in test prefix)"
  fi
else
  skip "A1.4 (re-run with --with-steam against a Steam-installed prefix)"
fi

# --- A1.5 no copied CrossOver binaries ---
say "A1.5 no copied CrossOver binaries"
if "$REPO_ROOT/scripts/verify-no-copied-binaries.sh" >/dev/null 2>&1; then
  ok A1.5
else
  fail A1.5
fi

if (( FAILED )); then
  say "OVERALL: FAIL"
  exit 1
fi
say "OVERALL: PASS"
