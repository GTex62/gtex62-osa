#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:-}"
SUITE_DIR="${CONKY_SUITE_DIR:-${HOME_DIR}/.config/conky/gtex62-osa}"
CACHE_ROOT="${GTEX62_CONKY_CACHE_DIR:-${HOME_DIR}/.cache/gtex62-conky}"
SUITE_ID="${GTEX62_CONKY_SUITE_ID:-osa}"
OUT_DIR="$CACHE_ROOT/suites/$SUITE_ID/net"
TMP_DIR="$CACHE_ROOT/tmp"
HELPER="$SUITE_DIR/scripts/net_extras.sh"
SPEEDTEST="$SUITE_DIR/scripts/speedtest_snapshot.sh"
mkdir -p "$OUT_DIR" "$TMP_DIR"

STATE_TMP="$TMP_DIR/net_state_${SUITE_ID}.tmp"
STATE_OUT="$OUT_DIR/state.vars"
VLAN_TMP="$TMP_DIR/net_vlan_${SUITE_ID}.tmp"
VLAN_OUT="$OUT_DIR/vlan.tsv"

detect_iface() {
  local env_iface
  env_iface="${GTEX62_NET_PRIMARY_IFACE:-${NET_PRIMARY_IFACE:-}}"
  if [[ -n "$env_iface" ]]; then
    printf '%s\n' "$env_iface"
    return
  fi

  local route_iface
  route_iface="$(
    ip route show default 2>/dev/null \
      | awk '/default/ {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
  )"

  if [[ -n "$route_iface" ]]; then
    printf '%s\n' "$route_iface"
    return
  fi

  printf 'eno1\n'
}

normalize() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

escape_value() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

parse_ping_ms() {
  local host="$1"
  local out
  out="$(ping -n -c1 -W1 "$host" 2>/dev/null | grep -o 'time=[0-9.]*' | head -n1 | cut -d= -f2 || true)"
  printf '%s\n' "$out"
}

speed_ratio() {
  local ms="${1:-}"
  awk -v ms="${ms:-}" 'BEGIN {
    if (ms == "" || ms == "---") {
      print 0
      exit
    }
    numeric = ms + 0
    min_ms = 0
    max_ms = 0.5
    if (numeric < min_ms) numeric = min_ms
    if (numeric > max_ms) numeric = max_ms
    printf "%.6f\n", 1 - (numeric / max_ms)
  }'
}

IFACE="$(detect_iface)"
TITLE="$(normalize "$("$HELPER" nic_alias "$IFACE" 2>/dev/null || true)")"
STATUS="$(normalize "$("$HELPER" lan_status "$IFACE" 2>/dev/null || true)")"
STATUS_UPPER="$(printf '%s' "${STATUS:-OFFLINE}" | tr '[:lower:]' '[:upper:]')"
if [[ "${STATUS_UPPER}" == "ONLINE" ]]; then
  LIVE_PERCENT="100"
else
  LIVE_PERCENT="0"
fi

SPEED_PAIR="$("$SPEEDTEST" read 500 500 7 2>/dev/null || true)"
SPEEDTEST_DOWN="$(printf '%s' "$SPEED_PAIR" | awk -F'|' 'NF >= 1 {print $1; exit}')"
SPEEDTEST_DOWN="${SPEEDTEST_DOWN:-500}"

WAN_IP="$(normalize "$("$HELPER" wan_ip "$IFACE" 2>/dev/null || true)")"
LAN_IP="$(normalize "$(ip -o -4 addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)")"
DNS="$(normalize "$("$HELPER" dns1 "$IFACE" 2>/dev/null || true)")"
SUBNET="$(normalize "$("$HELPER" subnet_mask "$IFACE" 2>/dev/null || true)")"
GATEWAY="$(normalize "$("$HELPER" default_gw "$IFACE" 2>/dev/null || true)")"
CF_1111_MS="$(parse_ping_ms "1.1.1.1")"
GOOGLE_8888_MS="$(parse_ping_ms "8.8.8.8")"

{
  printf 'GENERATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'IFACE=%s\n' "$(escape_value "$IFACE")"
  printf 'TITLE=%s\n' "$(escape_value "${TITLE:-NIC UNKNOWN}")"
  printf 'STATUS=%s\n' "$(escape_value "${STATUS_UPPER:-OFFLINE}")"
  printf 'LIVE_PERCENT=%s\n' "$(escape_value "$LIVE_PERCENT")"
  printf 'SPEEDTEST_DOWN=%s\n' "$(escape_value "$SPEEDTEST_DOWN")"
  printf 'WAN_IP=%s\n' "$(escape_value "${WAN_IP:--}")"
  printf 'LAN_IP=%s\n' "$(escape_value "${LAN_IP:--}")"
  printf 'DNS=%s\n' "$(escape_value "${DNS:--}")"
  printf 'SUBNET=%s\n' "$(escape_value "${SUBNET:--}")"
  printf 'GATEWAY=%s\n' "$(escape_value "${GATEWAY:--}")"
  printf 'CF_1111_MS=%s\n' "$(escape_value "${CF_1111_MS:-}")"
  printf 'GOOGLE_8888_MS=%s\n' "$(escape_value "${GOOGLE_8888_MS:-}")"
} > "$STATE_TMP"
mv -f "$STATE_TMP" "$STATE_OUT"

: > "$VLAN_TMP"
for gateway in 192.168.10.1 192.168.20.1 192.168.30.1 192.168.40.1 192.168.50.1; do
  ms="$(parse_ping_ms "$gateway")"
  if [[ -n "${ms:-}" ]]; then
    ms_display="$(printf '%.2f' "$ms")"
    ratio="$(speed_ratio "$ms")"
  else
    ms_display="---"
    ratio="0"
  fi
  printf '%s\t%s\t%s\n' "$gateway" "$ratio" "$ms_display" >> "$VLAN_TMP"
done
mv -f "$VLAN_TMP" "$VLAN_OUT"
