#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_ROOT="${GTEX62_CONFIG_DIR:-${GTEX62_CONKY_CONFIG_DIR:-$HOME/.config/gtex62-core}}"
CACHE_ROOT="${GTEX62_CACHE_DIR:-${GTEX62_CONKY_CACHE_DIR:-$HOME/.cache/gtex62-core}}"
CORE_REPO="${GTEX62_CORE_DIR:-${GTEX62_CONKY_ENGINE_DIR:-$HOME/.config/conky/gtex62-core}}"
CORE_LAUNCHER="${GTEX62_CORE_LAUNCHER:-${GTEX62_CONKY_LAUNCHER:-$CORE_REPO/bin/gtex62-core-launch}}"
SHARED_ASSETS_ROOT="${GTEX62_SHARED_ASSETS:-${GTEX62_CONKY_SHARED_ASSETS:-$HOME/.config/conky/gtex62-shared-assets}}"
WALLPAPER_DIR="${GTEX62_WALLPAPERS_DIR:-${GTEX62_CONKY_WALLPAPERS_DIR:-$SHARED_ASSETS_ROOT/wallpapers}}"

export CONKY_SUITE_DIR="$SUITE_DIR"
export GTEX62_CONFIG_DIR="$RUNTIME_ROOT"
export GTEX62_CACHE_DIR="$CACHE_ROOT"
export GTEX62_SUITE_ID="osa"
export GTEX62_SHARED_ASSETS="$SHARED_ASSETS_ROOT"
export GTEX62_SHARED_ASSETS_DIR="$SHARED_ASSETS_ROOT"
export GTEX62_WALLPAPERS_DIR="$WALLPAPER_DIR"
export GTEX62_CONKY_CONFIG_DIR="$RUNTIME_ROOT"
export GTEX62_CONKY_CACHE_DIR="$CACHE_ROOT"
export GTEX62_CONKY_SUITE_ID="osa"
export GTEX62_CONKY_SHARED_ASSETS="$SHARED_ASSETS_ROOT"
export GTEX62_CONKY_WALLPAPERS_DIR="$WALLPAPER_DIR"

if [[ ! -f "$RUNTIME_ROOT/core.toml" || ! -f "$RUNTIME_ROOT/suites/osa.toml" ]]; then
  "$SUITE_DIR/scripts/bootstrap-runtime-root.sh" "$RUNTIME_ROOT" >/dev/null
fi

PIDS_DIR="$CACHE_ROOT/runtime/pids"
LAUNCHER_PID_FILE="$PIDS_DIR/osa-launcher.pid"
CONKY_PID_FILE="$PIDS_DIR/osa-conky.pid"

stop_pid_file() {
  local file="$1"
  local pid=""
  [[ -f "$file" ]] || return 0
  pid="$(cat "$file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
}

wait_pid_file_exit() {
  local file="$1"
  local pid=""
  local i
  [[ -f "$file" ]] || return 0
  pid="$(cat "$file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 0
  for i in {1..30}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
}

stop_pid_file "$LAUNCHER_PID_FILE"
stop_pid_file "$CONKY_PID_FILE"
pkill -x conky 2>/dev/null || true
wait_pid_file_exit "$LAUNCHER_PID_FILE"
wait_pid_file_exit "$CONKY_PID_FILE"

choose_palette() {
  local palette_file="$SUITE_DIR/theme/osa-palettes.lua"
  local cache_dir="$CACHE_ROOT/runtime"
  local cache_last="$cache_dir/osa-palette"
  local default_palette=""
  local default_choice=""
  local choice=""
  local last=""

  [[ -f "$palette_file" ]] || return 0

  default_palette="$(
    awk -F'"' '/default[[:space:]]*=/{print $2; exit}' "$palette_file"
  )"
  default_palette="${default_palette:-amber}"

  local row=""
  local group=""
  local last_group=""
  local -a PALETTE_ROWS=()
  local -a PALETTE_GROUPS=()
  local -a PALETTES=()

  mapfile -t PALETTE_ROWS < <(
    awk '
      /^  palettes = \{/ { inside = 1; next }
      inside && /^  }/ { exit }
      inside && match($0, /^    --[[:space:]]*(.*)$/, m) { print "@GROUP@" m[1]; next }
      inside && match($0, /^    ([a-z0-9_]+) = \{/, m) { print m[1] }
    ' "$palette_file"
  )

  for row in "${PALETTE_ROWS[@]}"; do
    if [[ "$row" == @GROUP@* ]]; then
      group="${row#@GROUP@}"
      continue
    fi
    PALETTES+=("$row")
    PALETTE_GROUPS+=("$group")
  done

  [[ "${#PALETTES[@]}" -gt 0 ]] || return 0

  mkdir -p "$cache_dir"

  if [[ -f "$cache_last" ]]; then
    last="$(cat "$cache_last" 2>/dev/null || true)"
  fi

  for i in "${!PALETTES[@]}"; do
    if [[ "${PALETTES[$i]}" == "${last:-$default_palette}" ]]; then
      default_choice="$((i + 1))"
      break
    fi
  done

  echo "OSA palettes:"
  for i in "${!PALETTES[@]}"; do
    local n="$((i + 1))"
    if [[ "${PALETTE_GROUPS[$i]}" != "$last_group" ]]; then
      last_group="${PALETTE_GROUPS[$i]}"
      [[ -n "$last_group" ]] && printf "\n%s\n" "$last_group"
    fi
    if [[ "${PALETTES[$i]}" == "$default_palette" ]]; then
      printf "%d) %s (default)\n" "$n" "${PALETTES[$i]}"
    else
      printf "%d) %s\n" "$n" "${PALETTES[$i]}"
    fi
  done

  if [[ -n "$default_choice" ]]; then
    read -rp "Select palette [1-${#PALETTES[@]}] (Enter=$default_choice): " choice
    choice="${choice:-$default_choice}"
  else
    read -rp "Select palette [1-${#PALETTES[@]}]: " choice
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#PALETTES[@]} )); then
    echo "Invalid selection."
    exit 1
  fi

  export CONKY_OSA_PALETTE="${PALETTES[$((choice - 1))]}"
  echo "$CONKY_OSA_PALETTE" > "$cache_last"
}

choose_wallpaper() {
  local cache_dir="$CACHE_ROOT/runtime"
  local cache_last="$cache_dir/osa-wallpaper"
  local default_choice=""
  local choice=""
  local last=""

  if [[ ! -d "$WALLPAPER_DIR" ]]; then
    echo "Shared wallpaper directory not found:"
    echo "  $WALLPAPER_DIR"
    return 0
  fi

  mapfile -t WALLS < <(
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
      -printf '%f\n' | sort
  )

  if [[ "${#WALLS[@]}" -eq 0 ]]; then
    echo "No wallpapers found in: $WALLPAPER_DIR"
    return 0
  fi

  mkdir -p "$cache_dir"

  if [[ -f "$cache_last" ]]; then
    last="$(cat "$cache_last" 2>/dev/null || true)"
    for i in "${!WALLS[@]}"; do
      if [[ "${WALLS[$i]}" == "$last" ]]; then
        default_choice="$((i + 1))"
        break
      fi
    done
  fi

  if [[ "${#WALLS[@]}" -eq 1 ]]; then
    choice="1"
  else
    echo "Available wallpapers for gtex62-osa:"
    for i in "${!WALLS[@]}"; do
      printf "%d) %s\n" "$((i + 1))" "${WALLS[$i]}"
    done

    if [[ -n "$default_choice" ]]; then
      read -rp "Select wallpaper [1-${#WALLS[@]}] (Enter=$default_choice): " choice
      choice="${choice:-$default_choice}"
    else
      read -rp "Select wallpaper [1-${#WALLS[@]}]: " choice
    fi
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#WALLS[@]} )); then
    echo "Invalid selection."
    exit 1
  fi

  local wallpaper_file="${WALLS[$((choice - 1))]}"
  local wallpaper_path="$WALLPAPER_DIR/$wallpaper_file"
  echo "$wallpaper_file" > "$cache_last"

  if command -v feh >/dev/null 2>&1; then
    feh --no-xinerama --bg-fill "$wallpaper_path" || echo "feh failed; continuing without changing wallpaper."
  else
    echo "feh not found; skipping wallpaper apply."
  fi
}

choose_palette
choose_wallpaper

if [[ -x "$CORE_LAUNCHER" ]]; then
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$CORE_LAUNCHER" --suite osa >/dev/null 2>&1
  else
    nohup "$CORE_LAUNCHER" --suite osa >/dev/null 2>&1 &
    disown || true
  fi
  exit 0
fi

echo "Core launcher not found at:"
echo "  $CORE_LAUNCHER"
echo "Falling back to direct suite launch."

nohup conky -c "$SUITE_DIR/widgets/osa-main.conky.conf" >/dev/null 2>&1 &
disown || true
exit 0
