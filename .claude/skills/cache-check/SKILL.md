---
name: cache-check
description: Check the age and content of a gtex62-core shared cache. Usage: /cache-check <domain>  Domains: net, time, orb, weather, air, solar, env (env checks both air and solar)
allowed-tools: Bash
---

## Task

Check the shared cache for domain `$ARGUMENTS`.

Cache directory: `~/.cache/gtex62-core/shared/$ARGUMENTS/`

## Instructions

1. List the files under `~/.cache/gtex62-core/shared/$ARGUMENTS/` (check subdirectories like `home/` or `local/` if the top level only has dirs) and show each file's age in seconds.
2. Show the content of the primary cache file:
   - `state.vars` for net
   - `current.json` for time, weather, air, or solar (first 40 lines)
   - `ephemeris.vars` for orb
   - `vlan.tsv` for net VLAN rows
   - If domain is `env`, check both `air/home/` and `solar/home/` and report both
3. Report concisely:
   - Is the cache present and fresh (age within expected TTL)?
   - Key values from the content
   - Any obvious problems (missing file, stale timestamp, empty content)

Expected TTLs:
- net: 1s (VLAN/ping are fast-track meters)
- time: 1s
- orb: 60s
- weather: 300s
- air: 300s (AQI + pollution)
- solar: 300s (UV + radiation)
- env: checks both air and solar
