---
name: cache-check
description: Check the age and content of a gtex62-core shared cache. Usage: /cache-check <domain>  Domains: net, time, orb, weather
allowed-tools: Bash
---

## Task

Check the shared cache for domain `$ARGUMENTS`.

Cache directory: `~/.cache/gtex62-core/shared/$ARGUMENTS/`

## Instructions

1. List the files under `~/.cache/gtex62-core/shared/$ARGUMENTS/` (check subdirectories like `home/` or `local/` if the top level only has dirs) and show each file's age in seconds.
2. Show the content of the primary cache file:
   - `state.vars` for net
   - `current.json` for time or weather (first 40 lines)
   - `ephemeris.vars` for orb
   - `vlan.tsv` for net VLAN rows
3. Report concisely:
   - Is the cache present and fresh (age within expected TTL)?
   - Key values from the content
   - Any obvious problems (missing file, stale timestamp, empty content)

Expected TTLs:
- net: 1s (VLAN/ping are fast-track meters)
- time: 1s
- orb: 60s
- weather: 300s
