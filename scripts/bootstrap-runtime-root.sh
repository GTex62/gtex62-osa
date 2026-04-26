#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$SUITE_DIR/examples/runtime"
RUNTIME_ROOT="${GTEX62_CONFIG_DIR:-${GTEX62_CONKY_CONFIG_DIR:-$HOME/.config/gtex62-core}}"
if [[ -z "${GTEX62_CONFIG_DIR:-}" && -z "${GTEX62_CONKY_CONFIG_DIR:-}" && ! -e "$RUNTIME_ROOT" && -e "$HOME/.config/gtex62-conky" ]]; then
  RUNTIME_ROOT="$HOME/.config/gtex62-conky"
fi
FORCE=0

if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
elif [[ $# -gt 0 ]]; then
  RUNTIME_ROOT="$1"
  if [[ "${2:-}" == "--force" ]]; then
    FORCE=1
  fi
fi

install_template() {
  local src="$1"
  local rel="${src#$SRC_DIR/}"
  local dest_rel="${rel%.example}"
  local dest="$RUNTIME_ROOT/$dest_rel"

  mkdir -p "$(dirname "$dest")"

  if [[ -e "$dest" && "$FORCE" -ne 1 ]]; then
    printf 'skip  %s\n' "$dest"
    return
  fi

  sed \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__RUNTIME_ROOT__|$RUNTIME_ROOT|g" \
    -e "s|__SUITE_REPO__|$SUITE_DIR|g" \
    "$src" > "$dest"

  printf 'write %s\n' "$dest"
}

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Template directory not found: $SRC_DIR" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  install_template "$file"
done < <(find "$SRC_DIR" -type f -name '*.example' -print0 | sort -z)

mkdir -p "$RUNTIME_ROOT/overrides/core" "$RUNTIME_ROOT/overrides/suites" "$RUNTIME_ROOT/state"

cat <<EOF

Runtime root prepared at:
  $RUNTIME_ROOT

Next:
  1. Fill in API keys in:
     $RUNTIME_ROOT/profiles/weather/home.toml
     $RUNTIME_ROOT/profiles/air/home.toml
  2. Adjust local interface / SSH settings in:
     $RUNTIME_ROOT/profiles/network/local.toml
     $RUNTIME_ROOT/profiles/pfsense/main_router.toml
  3. Add optional local calendar events in:
     $RUNTIME_ROOT/state/events_extra.txt
EOF
