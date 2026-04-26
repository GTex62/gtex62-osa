#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_ROOT="${GTEX62_CONKY_CONFIG_DIR:-$HOME/.config/gtex62-conky}"
CACHE_ROOT="${GTEX62_CONKY_CACHE_DIR:-$HOME/.cache/gtex62-conky}"
ENGINE_REPO="${GTEX62_CONKY_ENGINE_REPO:-$HOME/.config/conky/gtex62-conky-engine}"
ENGINE_LAUNCHER="${GTEX62_CONKY_LAUNCHER:-$ENGINE_REPO/bin/gtex62-conky-launch}"
SHARED_ASSETS_ROOT="${GTEX62_CONKY_SHARED_ASSETS:-$HOME/.config/conky/gtex62-shared-assets}"
WALLPAPER_DIR="${GTEX62_CONKY_WALLPAPERS_DIR:-$SHARED_ASSETS_ROOT/wallpapers}"

export CONKY_SUITE_DIR="$SUITE_DIR"
export GTEX62_CONKY_CONFIG_DIR="$RUNTIME_ROOT"
export GTEX62_CONKY_CACHE_DIR="$CACHE_ROOT"
export GTEX62_CONKY_SUITE_ID="osa"
export GTEX62_CONKY_SHARED_ASSETS="$SHARED_ASSETS_ROOT"
export GTEX62_CONKY_WALLPAPERS_DIR="$WALLPAPER_DIR"

pkill -x conky 2>/dev/null || true

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

choose_wallpaper

if [[ -x "$ENGINE_LAUNCHER" ]]; then
  nohup "$ENGINE_LAUNCHER" --suite osa >/dev/null 2>&1 &
  disown || true
  exit 0
fi

echo "Engine launcher not found at:"
echo "  $ENGINE_LAUNCHER"
echo "Falling back to direct suite launch."

nohup conky -c "$SUITE_DIR/widgets/osa-main.conky.conf" >/dev/null 2>&1 &
disown || true
exit 0
