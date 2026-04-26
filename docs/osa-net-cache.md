# Engine V1 NET Cache For OSA

## Purpose

This note documents the current suite-local `NET` cache contract used by `gtex62-osa`.

This is not a shared engine domain schema.

It is an OSA-specific cache layer used to keep `NET` rendering off the draw path while preserving fast startup and responsive updates.

---

## Core Position

`NET` is currently split into:

- fast lane:
  - live download/upload from Conky expressions
- suite cache lane:
  - NIC identity
  - online/offline status
  - speedtest snapshot summary
  - node table values
  - cached ping values
  - VLAN table rows

The suite cache is refreshed by:

- [scripts/refresh_net_cache.sh](/home/gtex62/.config/conky/gtex62-osa/scripts/refresh_net_cache.sh)

The launcher schedules that script in the background.

---

## Cache Location

For OSA:

- `~/.cache/gtex62-conky/suites/osa/net/state.vars`
- `~/.cache/gtex62-conky/suites/osa/net/vlan.tsv`

Generalized shape:

- `~/.cache/gtex62-conky/suites/<suite_id>/net/state.vars`
- `~/.cache/gtex62-conky/suites/<suite_id>/net/vlan.tsv`

---

## `state.vars`

## Format

Simple key/value text:

```text
GENERATED_AT=2026-04-22T06:58:41Z
IFACE=eno1
TITLE=Intel I219-V
STATUS=ONLINE
LIVE_PERCENT=100
SPEEDTEST_DOWN=594
WAN_IP=73.177.9.62
LAN_IP=192.168.10.3
DNS=192.168.40.7
SUBNET=255.255.255.0
GATEWAY=192.168.10.1
CF_1111_MS=14.4
GOOGLE_8888_MS=20.2
```

## Required Keys

- `GENERATED_AT`
- `IFACE`
- `TITLE`
- `STATUS`
- `LIVE_PERCENT`
- `SPEEDTEST_DOWN`
- `WAN_IP`
- `LAN_IP`
- `DNS`
- `SUBNET`
- `GATEWAY`
- `CF_1111_MS`
- `GOOGLE_8888_MS`

## Meanings

- `IFACE`
  - primary interface name used by the suite
- `TITLE`
  - user-facing NIC title shown in the NET primary box
- `STATUS`
  - expected values are currently `ONLINE` or `OFFLINE`
- `LIVE_PERCENT`
  - display-ready online meter value, currently `100` or `0`
- `SPEEDTEST_DOWN`
  - cached speedtest download Mbps summary used in the NET status line
- `WAN_IP`
  - cached WAN IP summary
- `LAN_IP`
  - current LAN IPv4 address
- `DNS`
  - primary DNS server
- `SUBNET`
  - dotted-decimal subnet mask
- `GATEWAY`
  - default gateway
- `CF_1111_MS`
  - cached ping result for `1.1.1.1`
- `GOOGLE_8888_MS`
  - cached ping result for `8.8.8.8`

---

## `vlan.tsv`

## Format

Tab-separated rows:

```text
192.168.10.1	0.546000	0.23
192.168.20.1	0.524000	0.24
192.168.30.1	0.526000	0.24
192.168.40.1	0.538000	0.23
192.168.50.1	0.518000	0.24
```

## Column Order

1. `gateway`
2. `speed_ratio`
3. `ms`

## Meanings

- `gateway`
  - VLAN gateway label shown in the first column
- `speed_ratio`
  - normalized bar-fill value used directly by the VLAN speed bar
- `ms`
  - cached ping text shown in the `MS` column

---

## OSA Consumption Model

[lua/suite/net.lua](/home/gtex62/.config/conky/gtex62-osa/lua/suite/net.lua) currently uses:

- `state.vars` for:
  - `net_box_title()`
  - `net_status_lines()`
  - `net_live_percent()`
  - `ping_1111_ms()`
  - `ping_8888_ms()`
  - `net_node_rows()`
- `vlan.tsv` for:
  - `vlan_rows()`

OSA still uses Conky live expressions for:

- `live_download_kib()`
- `live_upload_kib()`

OSA still reads the shared speedtest snapshot directly for:

- `speedtest_download_mbps()`
- `speedtest_upload_mbps()`

That means `NET` is intentionally hybrid rather than purely cache-driven.

---

## Why This Is Suite-Local

This cache should remain suite-local for now because it contains:

- OSA-shaped node labels
- OSA-shaped VLAN row expectations
- OSA-ready bar ratios
- display-oriented reductions rather than normalized shared truth

The engine may later define a normalized `network` or `connectivity` shared schema for broader reuse, but this current cache is a panel-oriented OSA projection.

---

## Refresh Model

The launcher currently schedules:

- initial background refresh at startup
- recurring background refresh every `GTEX62_OSA_NET_CACHE_TTL` seconds

Current default:

- `5` seconds

This keeps `NET` content ready without blocking first draw.
