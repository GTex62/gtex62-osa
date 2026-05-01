#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:-}"
SUITE_DIR="${CONKY_SUITE_DIR:-${HOME_DIR}/.config/conky/gtex62-osa}"
CONFIG_ROOT="${GTEX62_CONFIG_DIR:-${GTEX62_CONKY_CONFIG_DIR:-${HOME_DIR}/.config/gtex62-core}}"
CACHE_ROOT="${GTEX62_CACHE_DIR:-${GTEX62_CONKY_CACHE_DIR:-${HOME_DIR}/.cache/gtex62-core}}"
CORE_DIR="${GTEX62_CORE_DIR:-${GTEX62_CONKY_ENGINE_DIR:-${HOME_DIR}/.config/conky/gtex62-core}}"
SUITE_ID="${GTEX62_SUITE_ID:-${GTEX62_CONKY_SUITE_ID:-osa}}"
OUT_DIR="$CACHE_ROOT/suites/$SUITE_ID/net"
TMP_DIR="$CACHE_ROOT/tmp"
HELPER="$SUITE_DIR/scripts/net_extras.sh"
SPEEDTEST="$CORE_DIR/providers/connectivity/speedtest_snapshot.sh"
GATE="$CORE_DIR/providers/pfsense/pf-ssh-gate.sh"
mkdir -p "$OUT_DIR" "$TMP_DIR"

STATE_TMP="$TMP_DIR/net_state_${SUITE_ID}_$$.tmp"
STATE_OUT="$OUT_DIR/state.vars"
VLAN_TMP="$TMP_DIR/net_vlan_${SUITE_ID}_$$.tmp"
VLAN_OUT="$OUT_DIR/vlan.tsv"

toml_section_value() {
  local path="$1"
  local section="$2"
  local key="$3"
  awk -F= -v section="$section" -v key="$key" '
    /^[[:space:]]*\[/ {
      in_section = ($0 == "[" section "]")
      next
    }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      v=$2
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      gsub(/^"|"$/, "", v)
      print v
      exit
    }
  ' "$path"
}

json_value() {
  local path="$1"
  local filter="$2"
  if [[ -s "$path" ]]; then
    jq -r "$filter" "$path" 2>/dev/null | awk 'NF {print; exit}'
  fi
}

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

vpn_state() {
  if command -v piactl >/dev/null 2>&1; then
    case "$(piactl get connectionstate 2>/dev/null || true)" in
      Connected) printf 'ON\n'; return ;;
      *) printf 'OFF\n'; return ;;
    esac
  fi

  if ip link show wg0 >/dev/null 2>&1 && ip addr show wg0 2>/dev/null | grep -q "inet "; then
    printf 'ON\n'
    return
  fi
  if ip link show tun0 >/dev/null 2>&1 && ip addr show tun0 2>/dev/null | grep -q "inet "; then
    printf 'ON\n'
    return
  fi

  printf 'UNKNOWN\n'
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

gate_state() {
  SSH_TRIPPED="0"
  SSH_STATUS="OK"
  SSH_REASON=""
  SSH_LEFT="0"

  if [[ ! -x "$GATE" ]]; then
    return
  fi

  SSH_STATUS="$("$GATE" status 2>/dev/null || printf 'OK')"
  if [[ "$SSH_STATUS" == TRIPPED* ]]; then
    SSH_TRIPPED="1"
    SSH_LEFT="$(printf '%s' "$SSH_STATUS" | awk -F'[=|]' '{for (i=1; i<=NF; i++) if ($i=="left") {print $(i+1); exit}}')"
    SSH_REASON="$(printf '%s' "$SSH_STATUS" | awk -F'[=|]' '{for (i=1; i<=NF; i++) if ($i=="reason") {print $(i+1); exit}}')"
    SSH_LEFT="${SSH_LEFT:-0}"
    SSH_REASON="${SSH_REASON:-PF_SSH_FAIL}"
  fi
}

SUITE_TOML="$CONFIG_ROOT/suites/$SUITE_ID.toml"
NETWORK_PROFILE="$(toml_section_value "$SUITE_TOML" profiles network || true)"
CONNECTIVITY_PROFILE="$(toml_section_value "$SUITE_TOML" profiles connectivity || true)"
PFSENSE_PROFILE="$(toml_section_value "$SUITE_TOML" profiles pfsense || true)"
NETWORK_PROFILE="${NETWORK_PROFILE:-local}"
CONNECTIVITY_PROFILE="${CONNECTIVITY_PROFILE:-default}"
PFSENSE_PROFILE="${PFSENSE_PROFILE:-main_router}"
NETWORK_JSON="$CACHE_ROOT/shared/network/$NETWORK_PROFILE/current.json"
CONNECTIVITY_JSON="$CACHE_ROOT/shared/connectivity/$CONNECTIVITY_PROFILE/current.json"
PFSENSE_STATUS_JSON="$CACHE_ROOT/shared/pfsense/$PFSENSE_PROFILE/status.json"

IFACE="$(json_value "$NETWORK_JSON" '.interface.name // empty')"
IFACE="${IFACE:-$(detect_iface)}"
gate_state
TITLE="$(normalize "$(json_value "$NETWORK_JSON" '.interface.title // empty')")"
TITLE="${TITLE:-$(normalize "$("$HELPER" nic_alias "$IFACE" 2>/dev/null || true)")}"
STATUS="$(normalize "$(json_value "$NETWORK_JSON" '.interface.state // empty')")"
STATUS="${STATUS:-$(normalize "$("$HELPER" lan_status "$IFACE" 2>/dev/null || true)")}"
STATUS_UPPER="$(printf '%s' "${STATUS:-OFFLINE}" | tr '[:lower:]' '[:upper:]')"
if [[ "${STATUS_UPPER}" == "ONLINE" ]]; then
  LIVE_PERCENT="100"
else
  LIVE_PERCENT="0"
fi

SPEEDTEST_DOWN="$(json_value "$CONNECTIVITY_JSON" '.speedtest.display_down_mbps // .speedtest.download_mbps // empty')"
SPEEDTEST_AGE="$(json_value "$CONNECTIVITY_JSON" '
  def zpad:
    tostring | if length == 1 then "0" + . else . end;
  def agefmt($s):
    ($s | tonumber | floor) as $sec
    | if $sec < 86400 then
        (($sec / 3600) | floor | zpad) + ":" +
        ((($sec % 3600) / 60) | floor | zpad)
      else
        (($sec / 86400) | floor | zpad) + "d"
      end;
  if (.speedtest.raw.timestamp // .speedtest.raw.result.timestamp // .speedtest.raw.result.date // null) != null then
    ((now - ((.speedtest.raw.timestamp // .speedtest.raw.result.timestamp // .speedtest.raw.result.date) | fromdateiso8601)) | if . < 0 then 0 else . end | agefmt(.))
  elif .speedtest.age_seconds != null then
    agefmt(.speedtest.age_seconds)
  elif .speedtest.age_label then
    .speedtest.age_label
  elif .speedtest.age_days != null then
    (.speedtest.age_days | tonumber | floor | zpad) + "d"
  else
    empty
  end
')"
SPEEDTEST_DELTA="$(json_value "$CONNECTIVITY_JSON" 'if .speedtest.download_delta_mbps == null then empty else .speedtest.download_delta_mbps | if . >= 0 then "+" + tostring else tostring end end')"
if [[ -z "$SPEEDTEST_DOWN" || -z "$SPEEDTEST_AGE" || -z "$SPEEDTEST_DELTA" ]]; then
  SPEED_PAIR="$("$SPEEDTEST" read 500 500 7 2>/dev/null || true)"
  SPEEDTEST_DOWN="${SPEEDTEST_DOWN:-$(printf '%s' "$SPEED_PAIR" | awk -F'|' 'NF >= 1 {print $1; exit}')}"
  SPEEDTEST_AGE="${SPEEDTEST_AGE:-$(printf '%s' "$SPEED_PAIR" | awk -F'|' 'NF >= 2 {print $2; exit}')}"
  SPEEDTEST_DELTA="${SPEEDTEST_DELTA:-$(printf '%s' "$SPEED_PAIR" | awk -F'|' 'NF >= 3 {print $3; exit}')}"
fi
SPEEDTEST_DOWN="${SPEEDTEST_DOWN:-500}"
SPEEDTEST_AGE="${SPEEDTEST_AGE:---:--}"
SPEEDTEST_DELTA="${SPEEDTEST_DELTA:----}"
if [[ "$SPEEDTEST_DELTA" =~ ^[+-]?[0-9]+$ ]]; then
  printf -v SPEEDTEST_DELTA "%+04d" "$SPEEDTEST_DELTA"
fi

WAN_IP="$(normalize "$(json_value "$NETWORK_JSON" '.interface.wan_ip // empty')")"
WAN_IP="${WAN_IP:-$(normalize "$("$HELPER" wan_ip "$IFACE" 2>/dev/null || true)")}"
VPN_STATE="$(normalize "$(vpn_state)")"
LAN_IP="$(normalize "$(json_value "$NETWORK_JSON" '.interface.lan_ip // empty')")"
LAN_IP="${LAN_IP:-$(normalize "$(ip -o -4 addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)")}"
DNS="$(normalize "$(json_value "$NETWORK_JSON" '.interface.dns // empty')")"
DNS="${DNS:-$(normalize "$("$HELPER" dns1 "$IFACE" 2>/dev/null || true)")}"
SUBNET="$(normalize "$(json_value "$NETWORK_JSON" '.interface.subnet // empty')")"
SUBNET="${SUBNET:-$(normalize "$("$HELPER" subnet_mask "$IFACE" 2>/dev/null || true)")}"
GATEWAY="$(normalize "$(json_value "$NETWORK_JSON" '.interface.gateway // empty')")"
GATEWAY="${GATEWAY:-$(normalize "$("$HELPER" default_gw "$IFACE" 2>/dev/null || true)")}"
PING_WORK_DIR="$TMP_DIR/net_ping_${SUITE_ID}_$$"
mkdir -p "$PING_WORK_DIR"
(
  parse_ping_ms "1.1.1.1" > "$PING_WORK_DIR/cf_1111_ms"
) &
(
  parse_ping_ms "8.8.8.8" > "$PING_WORK_DIR/google_8888_ms"
) &
wait
CF_1111_MS="$(cat "$PING_WORK_DIR/cf_1111_ms" 2>/dev/null || true)"
GOOGLE_8888_MS="$(cat "$PING_WORK_DIR/google_8888_ms" 2>/dev/null || true)"
rm -rf "$PING_WORK_DIR"
PFSENSE_TRIPPED="$(json_value "$PFSENSE_STATUS_JSON" 'if .ssh_gate.tripped then "1" else "0" end')"
PFSENSE_STATUS="$(json_value "$PFSENSE_STATUS_JSON" '.ssh_gate.status // empty')"
PFSENSE_REASON="$(json_value "$PFSENSE_STATUS_JSON" '.ssh_gate.reason // empty')"
PFSENSE_LEFT="$(json_value "$PFSENSE_STATUS_JSON" '.ssh_gate.left_seconds // empty')"
SSH_TRIPPED="${PFSENSE_TRIPPED:-$SSH_TRIPPED}"
SSH_STATUS="${PFSENSE_STATUS:-$SSH_STATUS}"
SSH_REASON="${PFSENSE_REASON:-$SSH_REASON}"
SSH_LEFT="${PFSENSE_LEFT:-$SSH_LEFT}"

{
  printf 'GENERATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'IFACE=%s\n' "$(escape_value "$IFACE")"
  printf 'TITLE=%s\n' "$(escape_value "${TITLE:-NIC UNKNOWN}")"
  printf 'STATUS=%s\n' "$(escape_value "${STATUS_UPPER:-OFFLINE}")"
  printf 'LIVE_PERCENT=%s\n' "$(escape_value "$LIVE_PERCENT")"
  printf 'SPEEDTEST_DOWN=%s\n' "$(escape_value "$SPEEDTEST_DOWN")"
  printf 'SPEEDTEST_AGE=%s\n' "$(escape_value "$SPEEDTEST_AGE")"
  printf 'SPEEDTEST_DELTA=%s\n' "$(escape_value "$SPEEDTEST_DELTA")"
  printf 'WAN_IP=%s\n' "$(escape_value "${WAN_IP:--}")"
  printf 'VPN_STATE=%s\n' "$(escape_value "${VPN_STATE:-UNKNOWN}")"
  printf 'LAN_IP=%s\n' "$(escape_value "${LAN_IP:--}")"
  printf 'DNS=%s\n' "$(escape_value "${DNS:--}")"
  printf 'SUBNET=%s\n' "$(escape_value "${SUBNET:--}")"
  printf 'GATEWAY=%s\n' "$(escape_value "${GATEWAY:--}")"
  printf 'CF_1111_MS=%s\n' "$(escape_value "${CF_1111_MS:-}")"
  printf 'GOOGLE_8888_MS=%s\n' "$(escape_value "${GOOGLE_8888_MS:-}")"
  printf 'SSH_TRIPPED=%s\n' "$(escape_value "$SSH_TRIPPED")"
  printf 'SSH_STATUS=%s\n' "$(escape_value "$SSH_STATUS")"
  printf 'SSH_REASON=%s\n' "$(escape_value "$SSH_REASON")"
  printf 'SSH_LEFT=%s\n' "$(escape_value "$SSH_LEFT")"
} > "$STATE_TMP"
mv -f "$STATE_TMP" "$STATE_OUT"

: > "$VLAN_TMP"
if [[ -s "$NETWORK_JSON" ]]; then
  mapfile -t VLAN_HOSTS < <(jq -r '.vlan_hosts[]?.host // empty' "$NETWORK_JSON" 2>/dev/null)
else
  VLAN_HOSTS=()
fi
if [[ "${#VLAN_HOSTS[@]}" -eq 0 ]]; then
  VLAN_HOSTS=(192.168.10.1 192.168.20.1 192.168.30.1 192.168.40.1 192.168.50.1)
fi

VLAN_WORK_DIR="$TMP_DIR/net_vlan_${SUITE_ID}_$$"
mkdir -p "$VLAN_WORK_DIR"
idx=0
for gateway in "${VLAN_HOSTS[@]}"; do
  [[ -n "$gateway" ]] || continue
  idx=$((idx + 1))
  (
    ms="$(parse_ping_ms "$gateway")"
    if [[ -n "${ms:-}" ]]; then
      ms_display="$(printf '%.2f' "$ms")"
      ratio="$(speed_ratio "$ms")"
    else
      ms_display="---"
      ratio="0"
    fi
    printf '%s\t%s\t%s\n' "$gateway" "$ratio" "$ms_display" > "$VLAN_WORK_DIR/$(printf '%03d' "$idx").tsv"
  ) &
done
wait
for row_file in "$VLAN_WORK_DIR"/*.tsv; do
  [[ -f "$row_file" ]] && cat "$row_file" >> "$VLAN_TMP"
done
rm -rf "$VLAN_WORK_DIR"
mv -f "$VLAN_TMP" "$VLAN_OUT"
