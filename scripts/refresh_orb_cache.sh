#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:-}"
SUITE_DIR="${CONKY_SUITE_DIR:-${HOME_DIR}/.config/conky/gtex62-osa}"
CACHE_ROOT="${GTEX62_CACHE_DIR:-${GTEX62_CONKY_CACHE_DIR:-${HOME_DIR}/.cache/gtex62-core}}"
SUITE_ID="${GTEX62_SUITE_ID:-${GTEX62_CONKY_SUITE_ID:-osa}}"
OUT_DIR="$CACHE_ROOT/suites/$SUITE_ID/orb"
TMP_DIR="$CACHE_ROOT/tmp"
mkdir -p "$OUT_DIR" "$TMP_DIR"

TMP_OUT="$TMP_DIR/orb_ephemeris_${SUITE_ID}.tmp"
OUT_FILE="$OUT_DIR/ephemeris.vars"

if python3 "$SUITE_DIR/scripts/orb_ephemeris.py" > "$TMP_OUT" 2>/dev/null; then
  mv -f "$TMP_OUT" "$OUT_FILE"
else
  rm -f "$TMP_OUT"
fi
