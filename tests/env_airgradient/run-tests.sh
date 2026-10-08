#!/usr/bin/env bash
# Tests for the AirGradient indoor view in lua/suite/env.lua (rotation, alerts, staleness, scaling, PM2.5
# precedence, and the theme.env.airgradient knobs). Self-contained: synthetic caches in a temporary tree, a
# controllable clock, no conky, and nothing real is read or written. Needs lua5.4 and jq.
# Usage: tests/env_airgradient/run-tests.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(cd "$HERE/../.." && pwd)"
LUA="$(command -v lua5.4 || command -v lua)"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
[[ -n "$LUA" ]] || { echo "lua5.4 is required" >&2; exit 2; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/cfg/suites" "$TMP/cache/shared/air/home" "$TMP/cache/shared/solar/home" "$TMP/cache/shared/airgradient/indoor" \
         "$TMP/xdg" "$TMP/assets/data/pollen"
{ echo "doy,tree,grass,weed,mold"; for d in $(seq 1 366); do echo "$d,0,0,0,0"; done; } > "$TMP/assets/data/pollen/pollen_mem_v2.csv"
SC="$TMP" CONKY_SUITE_DIR="$SUITE" GTEX62_CONFIG_DIR="$TMP/cfg" GTEX62_CACHE_DIR="$TMP/cache" XDG_CACHE_HOME="$TMP/xdg" \
GTEX62_SHARED_ASSETS="$TMP/assets" GTEX62_SHARED_ASSETS_DIR="$TMP/assets" "$LUA" "$HERE/test_env.lua"
