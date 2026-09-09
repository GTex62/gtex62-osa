# OSA Net Panel — Cache Notes

The `NET` panel reads from the shared core `net` provider cache.

For the full cache schema, file formats, key reference, and refresh model see:

- `gtex62-core/docs/net-provider-reference.md`

## OSA-Specific Notes

The `NET` panel is hybrid:

- `state.vars` and `vlan.tsv` from `shared/net/<profile>/` drive static values
  (NIC title, status, speedtest summary, node table, ping results, VLAN rows)
- Conky live expressions drive the download/upload speed bars directly
  (`live_download_kib`, `live_upload_kib`)
- The `connectivity` shared provider drives the speedtest graph independently

The net profile is bound in the suite TOML under `[profiles] net` (default `"local"`).
OSA resolves the cache path in `lua/suite/net.lua` via `net_cache_dir()`.

## View Modes

The VLAN table has three selectable render modes, set via
`theme.net.vlan_table.view` in `theme/osa-theme.lua` (default `"classic"`). Each
draws the same panel footprint and 2-column-header row differently:

| View | Header | Row set | Data source |
| --- | --- | --- | --- |
| `classic` | GATEWAY / SPEED / MS | HOME, IOT, GUEST, INFRA, CAM (gateway ping) | `shared/net/<profile>/vlan.tsv` via `M.vlan_rows()` |
| `bidir` | NAME / TRAFFIC | WAN, HOME, IOT, INFRA, CAM (interface rate, no GUEST) | `shared/pfsense/<profile>/ifaces.json` via `M.vlan_bidir_rows()` |
| `track` | NAME / TRAFFIC | Same as `bidir` | Same as `bidir` — pure alternate rendering of the same `in_pct`/`out_pct` values, no separate data path |

`classic` is a single left-to-right bar plus an MS (ping latency) column.
`bidir` drops the MS column for a center-anchored bar — IN grows left, OUT
grows right from a negative-space center split. `track` drops the filling bar
for a static dashed bracket track per row (drawn with the same glyph
technique as ORB Celestial's rise/set bracket), with one marker per direction
sliding from the center split (idle) toward each half's outer end-cap (busy).

`bidir`/`track` read a different core provider than `classic` — the
`pfsense` domain's `ifaces.json` (per-VLAN instantaneous byte rate), not
`net`'s `vlan.tsv` (gateway ping) — profile resolved from `[profiles] pfsense`
in the suite TOML, not `[profiles] net`. This is also why the row sets
differ: `ifaces.json` has a `WAN` row and no `GUEST` row, the reverse of
`vlan.tsv`.

The full knob set (geometry, EMA smoothing/scale-curve tuning for `bidir`,
track-specific glyph/marker knobs) lives as inline comments on
`theme.net.vlan_table` in `theme/osa-theme.lua` — not duplicated here, to
avoid a second copy going stale.
