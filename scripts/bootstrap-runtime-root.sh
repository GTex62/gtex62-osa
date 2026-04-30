#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_REPO="${GTEX62_CORE_DIR:-${GTEX62_CONKY_ENGINE_DIR:-$HOME/.config/conky/gtex62-core}}"
CORE_BOOTSTRAP="${GTEX62_CORE_BOOTSTRAP:-$CORE_REPO/bin/gtex62-core-bootstrap-runtime}"

export CONKY_SUITE_DIR="$SUITE_DIR"

if [[ ! -x "$CORE_BOOTSTRAP" ]]; then
  echo "Core bootstrap not found at:" >&2
  echo "  $CORE_BOOTSTRAP" >&2
  exit 1
fi

exec "$CORE_BOOTSTRAP" --suite-dir "$SUITE_DIR" "$@"
