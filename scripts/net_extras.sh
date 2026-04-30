#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
IFACE="${2:-${GTEX62_NET_PRIMARY_IFACE:-${NET_PRIMARY_IFACE:-}}}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_ROOT="${GTEX62_CACHE_DIR:-${GTEX62_CONKY_CACHE_DIR:-$XDG_CACHE_HOME/gtex62-core}}"
SUITE_ID="${GTEX62_SUITE_ID:-${GTEX62_CONKY_SUITE_ID:-osa}}"
CACHE_DIR="$CACHE_ROOT/suites/$SUITE_ID/net"
CACHE="$CACHE_DIR/wan_ip"

detect_iface() {
  if [[ -n "$IFACE" ]]; then
    printf '%s\n' "$IFACE"
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

alias_by_pci() {
  case "$1" in
    8086:15b8|8086:15b7|8086:15b9|8086:15fa|8086:0d4f) echo "Intel I219-V"; return ;;
    8086:15f3|8086:3100) echo "Intel I225-V"; return ;;
    8086:125b|8086:125c) echo "Intel I226-V"; return ;;
    8086:1533) echo "Intel I210"; return ;;
    8086:1521|8086:1523) echo "Intel I350"; return ;;
    10ec:8125) echo "Realtek 2.5GbE (RTL8125)"; return ;;
    10ec:8168) echo "Realtek GbE (RTL8111/8168)"; return ;;
  esac
  return 1
}

pci_id_for_iface() {
  local path vendor device
  path="$(readlink -f "/sys/class/net/$1/device" 2>/dev/null || true)"
  [[ -n "$path" ]] || return 1
  vendor="$(tr -d '\n' < "$path/vendor" 2>/dev/null | sed 's/^0x//')"
  device="$(tr -d '\n' < "$path/device" 2>/dev/null | sed 's/^0x//')"
  [[ -n "$vendor" && -n "$device" ]] || return 1
  echo "${vendor}:${device}" | tr '[:upper:]' '[:lower:]'
}

nic_model() {
  local devpath pci modaline
  devpath="$(readlink -f "/sys/class/net/$1/device" 2>/dev/null || true)"
  if [[ -n "$devpath" ]]; then
    pci="${devpath##*/}"
    modaline="$(lspci -s "$pci" 2>/dev/null | sed -E 's/^[0-9a-f:.]+[[:space:]]+[^:]+:[[:space:]]+//')"
    if [[ -n "$modaline" ]]; then
      echo "$modaline"
      return
    fi
  fi

  ethtool -i "$1" 2>/dev/null | awk -F': ' '/driver:/{print "Driver: "$2; exit}' || echo "$1"
}

nic_alias_from_model() {
  local model short
  model="$1"
  model="$(echo "$model" | sed -E 's/^[Ii]ntel [Cc]orporation /Intel /; s/[Ee]thernet (C|c)ontroller:?[[:space:]]*//; s/^[[:space:]]+//')"

  if echo "$model" | grep -Eqi 'I[0-9]{3}(-[A-Z])?'; then
    short="Intel $(echo "$model" | grep -Eio 'I[0-9]{3}(-[A-Z])?' | head -n1)"
    echo "$short"
    return
  fi

  if echo "$model" | grep -qi 'RTL8125'; then echo "Realtek 2.5GbE (RTL8125)"; return; fi
  if echo "$model" | grep -qi 'RTL8111'; then echo "Realtek GbE (RTL8111)"; return; fi

  echo "$model"
}

nic_friendly() {
  local iface pci alias model
  iface="$(detect_iface)"
  pci="$(pci_id_for_iface "$iface" 2>/dev/null || true)"
  if [[ -n "$pci" ]] && alias_by_pci "$pci" >/dev/null 2>&1; then
    alias="$(alias_by_pci "$pci")"
  fi

  if [[ -z "${alias:-}" ]]; then
    model="$(nic_model "$iface")"
    alias="$(nic_alias_from_model "$model")"
  fi

  if [[ -z "${alias:-}" ]]; then
    alias="$iface"
  fi

  printf '%s\n' "$alias"
}

lan_status() {
  local iface
  iface="$(detect_iface)"
  ip link show "$iface" 2>/dev/null | grep -q "state UP" && echo "Online" || echo "Offline"
}

mask_from_cidr() {
  local cidr m
  cidr="${1##*/}"
  m=$(( 0xffffffff << (32 - cidr) & 0xffffffff ))
  printf "%d.%d.%d.%d\n" $(( (m>>24) & 255 )) $(( (m>>16) & 255 )) $(( (m>>8) & 255 )) $(( m & 255 ))
}

cidr_for_iface() {
  ip -o -f inet addr show dev "$1" 2>/dev/null | awk '{print $4}' | head -n1
}

wan_ip() {
  if [[ -s "$CACHE" ]]; then tr -d '\r\n' < "$CACHE"; else echo "—"; fi
}

dns_primary() {
  local iface dns
  iface="$(detect_iface)"
  dns="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  if [[ "$dns" == "127.0.0.53" ]] && command -v resolvectl >/dev/null 2>&1; then
    dns="$(resolvectl dns "$iface" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)"
    if [[ -z "$dns" ]]; then
      dns="$(resolvectl status 2>/dev/null | awk '/DNS Servers:/ {print; exit}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)"
    fi
  fi
  [[ -n "$dns" ]] && echo "$dns" || echo "—"
}

subnet_mask() {
  local iface ipcidr
  iface="$(detect_iface)"
  ipcidr="$(cidr_for_iface "$iface")"
  if [[ -n "$ipcidr" ]]; then
    mask_from_cidr "$ipcidr"
  else
    echo "—"
  fi
}

default_gw() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

case "$ACTION" in
  lan_status)
    lan_status
    ;;
  wan_ip)
    wan_ip
    ;;
  dns1)
    dns_primary
    ;;
  subnet_mask)
    subnet_mask
    ;;
  default_gw)
    default_gw
    ;;
  nic_alias)
    nic_friendly
    ;;
  *)
    echo "usage: $0 {lan_status|wan_ip|dns1|subnet_mask|default_gw|nic_alias} [iface]" >&2
    exit 1
    ;;
esac
