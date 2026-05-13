# OSA Net Panel — Cache Notes

The `NET` panel reads from the shared core `net` provider cache.

For the full cache schema, file formats, key reference, and refresh model see:

- `gtex62-core/docs/net-provider.md`

## OSA-Specific Notes

The `NET` panel is hybrid:

- `state.vars` and `vlan.tsv` from `shared/net/<profile>/` drive static values
  (NIC title, status, speedtest summary, node table, ping results, VLAN rows)
- Conky live expressions drive the download/upload speed bars directly
  (`live_download_kib`, `live_upload_kib`)
- The `connectivity` shared provider drives the speedtest graph independently

The net profile is bound in the suite TOML under `[profiles] net` (default `"local"`).
OSA resolves the cache path in `lua/suite/net.lua` via `net_cache_dir()`.
